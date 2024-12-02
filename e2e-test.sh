#!/usr/bin/bash
#
set -e

WITH_DEPLOY=${WITH_DEPLOY:-true}
DRY=${DRY:-false}

c() { echo "# $@" ; }
n() { echo "" ; }
x() { echo "\$ $@" ; ${DRY} || eval "$@" ; }
TBD() { red c "TBD - $@"; }
red() { echo -e "\e[0;31m$@\e[0m" ; }
green() { echo -e "\e[0;32m$@\e[0m" ; }
die() { red "FATAL: $@" ; exit 1 ; }
assert() { echo "(assert:) \$ $@" ; { ${DRY} || eval $@ ; } || { echo "(assert?) FALSE" ; die "Assertion ret 0 failed: '$@'" ; } ; green "(assert?) True" ; }

c "Assumption: 'oc' is present and has access to the cluster"
assert "which oc"

if $WITH_DEPLOY;
then
  c "# Reconfigure node-exporter to export PSI"

  c "Ensure that all MCP workers are updated"
  assert "oc get mcp worker -o json | jq -e '.status.conditions[] | select(.type == \"Updated\" and .status == \"True\")'"

  n
  c "Apply MachineConfig"
  x "bash to.sh deploy"

  n
  c "Wait for MCP to pickup new MC"
  x "bash to.sh wait_for_mcp"
fi

n
c "Create workloads"
x "oc apply -f tests/00-vms-no-load.yaml -f tests/01-vms-cpu-load.yaml"
c "oc wait --for jsonpath='.status.readyReplicas'=3 vmpool no-load"
c "oc wait --for jsonpath='.status.readyReplicas'=3 vmpool cpu-load"

TBD "wait for load and rebealance"

c "Delete workloads"
x "oc delete -f tests/00-vms-no-load.yaml -f tests/01-vms-cpu-load.yaml"

if $WITH_DEPLOY;
then
  n
  c "Delete the operator"
  x "bash to.sh destroy"
  x "bash to.sh wait_for_mcp"
fi

n
c "The validation has passed! All is well."

green "PASS"
