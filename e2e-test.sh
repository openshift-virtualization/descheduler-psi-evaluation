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
get_load() { promql "sum(rate(node_pressure_cpu_waiting_seconds_total[1m]))" ; }

c "Assumption: 'oc' is present and has access to the cluster"
assert "which oc"

if $WITH_DEPLOY; then x "bash to.sh deploy"; fi

n
TAINTED_NODE=$(oc get nodes -l node-role.kubernetes.io/worker -o name | head -n 1)
c "Going to taint node '$TAINTED_NODE' in order to rebalance workloads later"
x "oc adm taint --overwrite node $TAINTED_NODE rebalance:NoSchedule"

n
c "Create workloads"
x "oc apply -f tests/00-vms-no-load.yaml -f tests/01-vms-cpu-load.yaml"

n
c "Ensure that we have load and see it in the PSI metrics"
c "Wait for the pressure to be low"
until x "get_load | jq -er '(.data.result[0].value[1]|tonumber) < 0.5'"; do sleep 6 ; done

n
c "Gradually increase the load and measure it"
export REPLICAS=1
until x "get_load | jq -er '(.data.result[0].value[1]|tonumber) > 1.0'";
do
  c "Scale up the deployments to generate more load"
  x "oc patch --type=json -p '[{\"op\": \"replace\", \"path\": \"/spec/replicas\", \"value\": $REPLICAS}]' vmpool no-load"
  x "oc patch --type=json -p '[{\"op\": \"replace\", \"path\": \"/spec/replicas\", \"value\": $REPLICAS}]' vmpool cpu-load"
  REPLICAS=$((REPLICAS + 1))

  c "Give it some time to generate load"
  x "sleep 15s"

  assert "[[ \$(oc get vm | grep ErrorUnschedulable | wc -l) == 0 ]]"
done
c "We saw the load increasing."

n
TBD "The whole section needs to be reworked"
nodes_with_vms() { promql "count(count by (node) (kubevirt_vmi_info) > 0)" ; }
NODE_COUNT_WITH_TAINT=$(nodes_with_vms)
c "With node '$TAINTED_NODE' tainted, the VMs are spread accross '$NODE_COUNT_WITH_TAINT' nodes"

n
c "Remove the taint from node '$TAINTED_NODE' in order to rebalance the VMs"
x "oc adm taint node $TAINTED_NODE rebalance:NoSchedule-"
x "sleep 3m"
x "nodes_with_vms"


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
