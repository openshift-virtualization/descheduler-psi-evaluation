#!/usr/bin/bash
#
set -e

WITH_DEPLOY=${WITH_DEPLOY:-false}
DRY=${DRY:-false}

c() { echo "# $(date '+%Y-%m-%d %H:%M:%S') # $@" ; }
n() { echo "" ; }
x() { echo "\$ $@" ; ${DRY} || eval "$@" ; }
TBD() { red c "TBD - $@"; }
red() { echo -e "\e[0;31m$@\e[0m" ; }
green() { echo -e "\e[0;32m$@\e[0m" ; }
die() { red "FATAL: $@" ; exit 1 ; }
assert() { echo "(assert:) \$ $@" ; { ${DRY} || eval $@ ; } || { echo "(assert?) FALSE" ; die "Assertion ret 0 failed: '$@'" ; } ; green "(assert?) True" ; }

# https://access.redhat.com/articles/4894261
promql() { oc exec -c prometheus -n openshift-monitoring prometheus-k8s-0 -- curl -s --data-urlencode "query=$@" http://localhost:9090/api/v1/query ; }

c "Assumption: 'oc' is present and has access to the cluster"
assert "which oc"

if $WITH_DEPLOY; then x "bash to.sh deploy"; fi

TEST_SCENARIO=${TEST_SCENARIO:-1}
if [[ -f "test_scenario_${TEST_SCENARIO}.sh" ]]; then
  source "test_scenario_${TEST_SCENARIO}.sh"
else
  c "Unable to load test scenario file"
  exit 1
fi

c "Test scenario:"
echo -e $DESCRIPTION

n
c "Create workload definitions with 0 replicas (in order to scale down any existing pool)"
x "oc apply -f tests/00-vms-no-load.yaml -f tests/01-vms-cpu-load.yaml"

n
export ALL_WORKER_NODES=$(oc get nodes -l node-role.kubernetes.io/worker --no-headers -o name | sort)
export ALL_WORKER_NODE_COUNT=$(wc -l <<<$ALL_WORKER_NODES)

scale_up_pre

n
c "Ensure that we have load and see it in the PSI metrics"
c "Gather a baseline pressure and assert that it's below a threshold"
get_load() {
    promql 'avg(rate(node_pressure_cpu_waiting_seconds_total[1m]) * on(instance) group_left(node) label_replace(kube_node_role{role="worker"}, "instance", "$1", "node", "(.+)"))' \
    | jq -er '(.data.result[0].value[1]|tonumber)' ; }
AVG_BASE_LOAD=$(get_load)
assert "[[ $AVG_BASE_LOAD < $STDD_LOAD_L_TH ]]"

n
c "Gradually increase the load and measure it"
export REPLICAS=${REPLICAS_START:-$INITIAL_REPLICAS}
until x "get_load | tee /dev/stderr | jq -er '(.|tonumber) > $STDD_LOAD_H_TH'";
do
  scale_up_load_s1
done
c "Let the system settle for a bit."
x "sleep 3m"

n
scale_up_load_s2

n
c "Validate rebalance"
n
nodes_get_stddev() {
    promql 'stddev(sum by (instance) (rate(node_pressure_cpu_waiting_seconds_total[1m]) * on(instance) group_left(node) label_replace(kube_node_role{role="worker"}, "instance", "$1", "node", "(.+)")))' \
    | jq -er '(.data.result[0].value[1]|tonumber)' ; }
export PRESSURE_STDDEV_WITH_TAINT=$(nodes_get_stddev)
c "The pressure stddev is '$PRESSURE_STDDEV_WITH_TAINT'."
oc delete --all vmim
assert "[[ \$(oc get vmim | wc -l) == 0 ]]"

n
scale_up_post

n
c "Configure decsheduler for automatic mode and faster rebalancing"
x "oc patch --type=json -p '[{\"op\": \"replace\", \"path\": \"/spec/mode\", \"value\": \"Automatic\"}]' -n openshift-kube-descheduler-operator KubeDescheduler cluster"
x "oc patch --type=json -p '[{\"op\": \"replace\", \"path\": \"/spec/deschedulingIntervalSeconds\", \"value\": 20}]' -n openshift-kube-descheduler-operator KubeDescheduler cluster"

c "Let the descheduler run for a bit in order to rebalance the cluster"
c "Use the following URL in order to monitor key metrics"
c "Or the following command for watchin descheduler and taint actions:"
bash to.sh monitor

c
c "Let's give the cluster some time in order to rebelanace according to node pressure"
x "sleep 10m"
assert "[[ \$(oc get vmim | wc -l) > 0 ]]"
export PRESSURE_STDDEV_WITHOUT_TAINT=$(nodes_get_stddev)
assert "[[ $PRESSURE_STDDEV_WITHOUT_TAINT < $PRESSURE_STDDEV_WITH_TAINT ]]"

c "Wait 1h to ensure that the cluster is stable"
x "sleep 3600"

n
c "Cleaning up."
x "oc patch --type=json -p '[{\"op\": \"replace\", \"path\": \"/spec/mode\", \"value\": \"Predictive\"}]' -n openshift-kube-descheduler-operator KubeDescheduler cluster"
c "Delete workloads"
x "oc delete -f tests/00-vms-no-load.yaml -f tests/01-vms-cpu-load.yaml"

if $WITH_DEPLOY;
then
  n
  x "bash to.sh destroy"
  x "bash to.sh wait_for_mcp"
fi

n
c "The validation has passed! All is well."

green "PASS"
