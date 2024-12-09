#!/usr/bin/bash
#
set -e

WITH_DEPLOY=${WITH_DEPLOY:-false}
DRY=${DRY:-false}

c() { echo "# $@" ; }
n() { echo "" ; }
x() { echo "\$ $@" ; ${DRY} || eval "$@" ; }
TBD() { red c "TBD - $@"; }
red() { echo -e "\e[0;31m$@\e[0m" ; }
green() { echo -e "\e[0;32m$@\e[0m" ; }
die() { red "FATAL: $@" ; exit 1 ; }
assert() { echo "(assert:) \$ $@" ; { ${DRY} || eval $@ ; } || { echo "(assert?) FALSE" ; die "Assertion ret 0 failed: '$@'" ; } ; green "(assert?) True" ; }

# https://access.redhat.com/articles/4894261
promql() { oc exec -c prometheus -n openshift-monitoring prometheus-k8s-0 -- curl -s --data-urlencode "query=$@" http://localhost:9090/api/v1/query | tee /dev/stderr ; }
get_load() { promql "sum(rate(node_pressure_cpu_waiting_seconds_total{instance=~\".*worker.*\"}[1m]))" | jq -er '(.data.result[0].value[1]|tonumber)' ; }

c "Assumption: 'oc' is present and has access to the cluster"
assert "which oc"

if $WITH_DEPLOY; then x "bash to.sh deploy"; fi

n
c "Taint node for in-balance"
ALL_WORKER_NODES=$(oc get nodes -l node-role.kubernetes.io/worker --no-headers -o name | sort)
ALL_WORKER_NODE_COUNT=$(wc -l <<<$ALL_WORKER_NODES)
TAINTED_WORKER_NODE=$(head -n1 <<<$ALL_WORKER_NODES)
c "Going to taint node '$TAINTED_WORKER_NODE' in order to rebalance workloads later"
x "oc adm taint node --all rebalance:NoSchedule- || :"
x "oc adm taint --overwrite node $TAINTED_WORKER_NODE rebalance:NoSchedule"

n
c "Create workloads"
x "oc apply -f tests/00-vms-no-load.yaml -f tests/01-vms-cpu-load.yaml"
x "sleep 30s"

n
c "Validate pressure generation and metrics"
n

n
c "Ensure that we have load and see it in the PSI metrics"
c "Wait for the pressure to be low"
BASE_LOAD=$(get_load)

n
c "Gradually increase the load and measure it"
export REPLICAS=20
#until x "get_load | jq -er '(.|tonumber) > ($BASE_LOAD + 1)'";
until x "[[ \$(oc get vm | grep ErrorUnschedulable | wc -l) > 0 ]]"
do
  c "Scale up the deployments to generate more load"
  x "oc patch --type=json -p '[{\"op\": \"replace\", \"path\": \"/spec/replicas\", \"value\": $REPLICAS}]' vmpool cpu-load"
  x "oc patch --type=json -p '[{\"op\": \"replace\", \"path\": \"/spec/replicas\", \"value\": $REPLICAS}]' vmpool no-load"
  REPLICAS=$((REPLICAS + 4))

  c "Give it some time to generate load"
  x "sleep 15s"
done
c "We saw the load increasing."
x "sleep 1m"

n
c "Validate rebalance"
n
nodes_get_stddev() { promql "stddev(sum by (instance) (rate(node_pressure_cpu_waiting_seconds_total{instance=~\".*worker.*\"}[1m])))" | jq -er '(.data.result[0].value[1]|tonumber)' ; }
nodes_with_vms() { promql "count(count by (node) (kubevirt_vmi_info{node=~\".+\"}) > 0)" | jq -r ".data.result[0].value[1]" ; }
export NODE_COUNT_WITH_TAINT=$(nodes_with_vms)
export PRESSURE_STDDEV_WITH_TAINT=$(nodes_get_stddev)
c "With node '$TAINTED_WORKER_NODE' tainted, the VMs are spread accross '$NODE_COUNT_WITH_TAINT' nodes. The pressure stddev is '$PRESSURE_STDDEV_WITH_TAINT'."
assert "[[ $NODE_COUNT_WITH_TAINT < $ALL_WORKER_NODE_COUNT ]]"
assert "[[ \$(oc get vmim | wc -l) == 0 ]]"

n
c "Remove the taint from node '$TAINTED_WORKER_NODE' in order to rebalance the VMs"
x "oc adm taint node $TAINTED_WORKER_NODE rebalance:NoSchedule-"

n
c "Configure decsheduler for automatic mode and faster rebalancing"
x "oc patch --type=json -p '[{\"op\": \"replace\", \"path\": \"/spec/mode\", \"value\": \"Automatic\"}]' -n openshift-kube-descheduler-operator KubeDescheduler cluster"
x "oc patch --type=json -p '[{\"op\": \"replace\", \"path\": \"/spec/deschedulingIntervalSeconds\", \"value\": 12}]' -n openshift-kube-descheduler-operator KubeDescheduler cluster"
#c "Spawn tainter"
#x "sleep 10s"
#bash contrib/desched-taint.sh &

x "sleep 5m"
assert "[[ \$(oc get vmim | wc -l) > 0 ]]"
export NODE_COUNT_WITHOUT_TAINT=$(nodes_with_vms)
export PRESSURE_STDDEV_WITHOUT_TAINT=$(nodes_get_stddev)
assert "[[ $NODE_COUNT_WITH_TAINT < $NODE_COUNT_WITHOUT_TAINT ]]"
assert "[[ $PRESSURE_STDDEV_WITH_TAINT > $PRESSURE_STDDEV_WITHOUT_TAINT ]]"


n
c "Cleaning up."
c "Delete workloads"
#x "oc delete -f tests/00-vms-no-load.yaml -f tests/01-vms-cpu-load.yaml"

if $WITH_DEPLOY;
then
  n
  x "bash to.sh destroy"
  x "bash to.sh wait_for_mcp"
fi

n
c "The validation has passed! All is well."

green "PASS"
