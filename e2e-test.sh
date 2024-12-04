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

promql() { ( set -x ; oc exec -c prometheus -n openshift-monitoring prometheus-k8s-0 -- curl -s --data-urlencode "query=$@" http://localhost:9090/api/v1/query ; ) | tee /dev/stderr ; }

c "Assumption: 'oc' is present and has access to the cluster"
assert "which oc"

if $WITH_DEPLOY;
then
  x "bash to.sh deploy"
fi

TAINTED_NODE=$(oc get nodes -l node-role.kubernetes.io/worker -o name | head -n 1)
n
c "Going to taint node '$TAINTED_NODE' in order to rebalance workloads later"
x "oc adm taint --overwrite node $TAINTED_NODE rebalance:NoSchedule"

n
c "Create workloads"
x "oc apply -f tests/00-vms-no-load.yaml -f tests/01-vms-cpu-load.yaml"
#c "oc wait --for jsonpath='.status.readyReplicas'=5 vmpool no-load"
#c "oc wait --for jsonpath='.status.readyReplicas'=5 vmpool cpu-load"

n
c "Ensure that we have load and see it in the PSI metrics"
export REPLICAS=1
# https://access.redhat.com/articles/4894261
get_load() { promql "sum(rate(node_pressure_cpu_waiting_seconds_total[1m]))" ; }

c "Wait for the pressure to be low"
until x "get_load | jq -er '(.data.result[0].value[1]|tonumber) < 2'"; do sleep 6 ; done

c "Gradually increase the load and measure it"
until x "get_load | jq -er '(.data.result[0].value[1]|tonumber) > 3'";
do
  c "Scale up the deployments to generate more load"
  x "oc patch --type=json -p '[{\"op\": \"replace\", \"path\": \"/spec/replicas\", \"value\": $REPLICAS}]' vmpool no-load"
  x "oc patch --type=json -p '[{\"op\": \"replace\", \"path\": \"/spec/replicas\", \"value\": $REPLICAS}]' vmpool cpu-load"
  REPLICAS=$((REPLICAS + 1))

  c "Give it some time to generate load"
  x "sleep 15s"
done
c "We saw the load increasing."

TBD "The whole section needs to be reworked"
n
nodes_with_vms() { promql "count(count by (node) (kubevirt_vmi_info) > 0)" ; }
NODE_COUNT_WITH_TAINT=$(nodes_with_vms)
c "With node '$TAINTED_NODE' tainted, the VMs are spread accross '$NODE_COUNT_WITH_TAINT' nodes"

n
c "Remove the taint from node '$TAINTED_NODE' in order to rebalance the VMs"
x "oc adm taint node $TAINTED_NODE rebalance:NoSchedule-"
sleep 3m
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
