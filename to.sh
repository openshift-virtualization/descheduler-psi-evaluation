i() { echo "i: $@"; }
x() { echo "\$ $@" ; eval "$@" ; }
die() { echo "err: $@" ; exit 1; }
_oc() { echo "$ oc $@" ; oc $@ ; }
qoc() { oc $@ > /dev/null 2>&1; }

SA=openshift-descheduler
NS=openshift-kube-descheduler-operator

apply() {
  _oc apply -f manifests/10-mc-psi-controlplane.yaml
  _oc apply -f manifests/11-mc-psi-worker.yaml
  _oc apply -f manifests/20-namespaces.yaml
  _oc apply -f manifests/30-operatorgroup.yaml
  _oc apply -f manifests/31-subscriptions.yaml
  until _oc get crd hyperconvergeds.hco.kubevirt.io 2> /dev/null ; do echo . ; sleep 6 ; done
  until _oc get crd kubedeschedulers.operator.openshift.io 2> /dev/null ; do echo . ; sleep 6 ; done
  until _oc apply -f manifests/40-cnv-operator-cr.yaml ; do sleep 6 ; done
  until _oc apply -f manifests/40-descheduler-operator-cr.yaml ; do sleep 6 ; done
}


deploy() {
  apply
  wait_for_mcp
  qoc get sa -n $NS $SA || die "Did not find descheduler ServiceAccount '$SA' in namespace '$NS'. Is it installed?"
  _oc adm policy add-cluster-role-to-user cluster-monitoring-view -z $SA -n $NS

}

destroy() {
  _oc delete -f manifests/40-descheduler-operator-cr.yaml
  _oc delete -f manifests/40-cnv-operator-cr.yaml
  _oc delete -f manifests/31-subscriptions.yaml
  _oc delete -f manifests/30-operatorgroup.yaml
  _oc delete -f manifests/20-namespaces.yaml
#  _oc delete -f manifests/11-mc-psi-worker.yaml
#  _oc delete -f manifests/10-mc-psi-controlplane.yaml
}


wait_for_mcp() {
  x "oc wait mcp worker --for condition=Updated=False --timeout=10s"
  x "oc wait mcp master --for condition=Updated=False --timeout=10s"
  x "oc wait mcp worker --for condition=Updated=True --timeout=15m"
  x "oc wait mcp master --for condition=Updated=True --timeout=15m"
}

usage() {
  grep -E -o "^.*\(\)" $0
}

eval "${@:-usage}"
