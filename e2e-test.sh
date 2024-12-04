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

promql() { oc exec -c prometheus -n openshift-monitoring prometheus-k8s-0 -- curl -s --data-urlencode "query=$@" http://localhost:9090/api/v1/query | tee /dev/stderr ; }

c "Assumption: 'oc' is present and has access to the cluster"
assert "which oc"

if $WITH_DEPLOY;
then
  x "bash to.sh deploy"
fi

n
c "Create workloads"
x "oc apply -f tests/00-vms-no-load.yaml -f tests/01-vms-cpu-load.yaml"
#c "oc wait --for jsonpath='.status.readyReplicas'=5 vmpool no-load"
#c "oc wait --for jsonpath='.status.readyReplicas'=5 vmpool cpu-load"

n
c "Ensure that we have load and see it in the PSI metrics"
export REPLICAS=1
# https://access.redhat.com/articles/4894261
export PROMQUERY="sum(irate(node_pressure_cpu_waiting_seconds_total[1m]))"
c "Wait for the pressure to be low"
until x "promql '$PROMQUERY' | jq -er '(.data.result[0].value[1]|tonumber) < 0.4'"; do sleep 6 ; done

c "Gradually increase the load and measure it"
until x "promql '$PROMQUERY' | jq -er '(.data.result[0].value[1]|tonumber) > 1.0'";
do
  c "Scale up the deployments to generate more load"
  x "oc patch --type=json -p '[{\"op\": \"replace\", \"path\": \"/spec/replicas\", \"value\": $REPLICAS}]' vmpool no-load"
  x "oc patch --type=json -p '[{\"op\": \"replace\", \"path\": \"/spec/replicas\", \"value\": $REPLICAS}]' vmpool cpu-load"
  REPLICAS=$((REPLICAS + 1))

  c "Give it some time to generate load"
  x "sleep 15s"
done
c "We saw the load increasing."

# Alerts
# https://access.redhat.com/solutions/4250221
#x "export ALERT_MANAGER=\$(oc get route alertmanager-main -n openshift-monitoring -o jsonpath='{@.spec.host}')"
#assert "curl -s -k -H \"Authorization: Bearer \$(oc create token prometheus-k8s -n openshift-monitoring)\"  https://\$ALERT_MANAGER/api/v1/alerts | jq -e \".data | map(select(.labels.alertname == \\\"NodeSwapping\\\")) | .[0]\""

TBD "rebealance"

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
