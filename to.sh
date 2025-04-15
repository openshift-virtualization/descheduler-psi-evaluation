i() { echo "i: $@"; }
c() { echo "# $@"; }
x() { echo "\$ $@" ; eval "$@" ; }
die() { echo "err: $@" ; exit 1; }
_oc() { echo "$ oc $@" ; oc $@ ; }
qoc() { oc $@ > /dev/null 2>&1; }

SA=openshift-descheduler
NS=openshift-kube-descheduler-operator

#tainter() {
#  x "oc delete -n $NS configmap desched-taint || :"
#  x "oc delete -n $NS -f manifests/50-desched-taint.yaml || :"
#  x "oc adm policy remove-cluster-role-from-user system:controller:node-controller -z $SA -n $NS || :"
#  if [[ "$1" != "del" ]]; then
#    x "oc create -n $NS configmap desched-taint --from-file contrib/desched-taint.sh"
#    x "oc apply -n $NS -f manifests/50-desched-taint.yaml"
#    x "oc adm policy add-cluster-role-to-user system:controller:node-controller -z $SA -n $NS" # for tainter
#  fi
#}

apply_mc() {
  c "Reconfigure node-exporter to export PSI"
  _oc apply -f manifests/10-mc-psi-controlplane.yaml
  _oc apply -f manifests/11-mc-psi-worker.yaml
  _oc apply -f manifests/12-mc-schedstats-worker.yaml
}

apply_operators() {
  c "Deploy operators"
  _oc apply -f manifests/20-namespaces.yaml
  _oc apply -f manifests/30-operatorgroup.yaml
  _oc apply -f manifests/31-subscriptions.yaml
  _oc scale --replicas=1 deployment -n openshift-kube-descheduler-operator descheduler-operator
  x "until qoc get crd hyperconvergeds.hco.kubevirt.io kubedeschedulers.operator.openshift.io ; do echo -n . ; sleep 6 ; done"
  x "until _oc apply -f manifests/40-cnv-operator-cr.yaml ; do echo -n . sleep 6 ; done"
  x "until _oc apply -f manifests/41-descheduler-operator-cr.yaml ; do echo -n . sleep 6 ; done"
  #_oc scale --replicas=0 deployment -n openshift-kube-descheduler-operator descheduler-operator
  #_oc get configmap -n openshift-kube-descheduler-operator cluster -o json | jq -r '.data["policy.yaml"]' > policy.yaml
  #export TARGETTHRESHOLDS=60
  #export THRESHOLDS=40
  #export QUERY="avg by (instance) (1 - rate(node_cpu_seconds_total{mode='idle'}[1m]))"
  #x "sed \"s/          query: .*$/          query: ${QUERY}/g\" -i policy.yaml"
  #x "sed -z \"s/      targetThresholds:\n        MetricResource: [0-9]*\n/      targetThresholds:\n        MetricResource: ${TARGETTHRESHOLDS}\n/\" -i policy.yaml"
  #x "sed -z \"s/      thresholds:\n        MetricResource: [0-9]*\n/      thresholds:\n        MetricResource: ${THRESHOLDS}\n/\" -i policy.yaml"
  #if grep -q "targetThresholds" policy.yaml ; then
  #  _oc delete configmap -n openshift-kube-descheduler-operator cluster
  #  _oc create configmap -n openshift-kube-descheduler-operator cluster --from-file=policy.yaml
  #  _oc delete pods -n openshift-kube-descheduler-operator -l=app=descheduler
  #else
  #  print "broken file, skipping"
  #fi
}

#apply_node_tainter() {
#  tainter
#}

apply() {
  apply_mc
#  apply_operators
#  apply_node_tainter
}

deploy() {
  apply
  wait_for_mcp
  qoc get sa -n $NS $SA || die "Did not find descheduler ServiceAccount '$SA' in namespace '$NS'. Is it installed?"
  _oc adm policy add-cluster-role-to-user cluster-monitoring-view -z $SA -n $NS  # for desched metrics
}

monitor() {
  baseURL=$(oc get console cluster -o=jsonpath='{@.status.consoleURL}')
  echo "## CPU utilization metrics"
  echo -n "${baseURL}"
  echo '/monitoring/query-browser?query0=stddev%28descheduler%3Anodeutilization%3Acpu%3Aavg1m+*+on%28instance%29+group_left%28node%29+label_replace%28kube_node_role%7Brole%3D%22worker%22%7D%2C+%27instance%27%2C+%22%241%22%2C+%27node%27%2C+%27%28.%2B%29%27%29%29&query1=descheduler%3Aaverageworkersutilization%3Acpu%3Aavg1m&query2=descheduler%3Anodeutilization%3Acpu%3Aavg1m+*+on%28instance%29+group_left%28node%29+label_replace%28kube_node_role%7Brole%3D%22worker%22%7D%2C+%27instance%27%2C+%22%241%22%2C+%27node%27%2C+%27%28.%2B%29%27%29'
  echo
  echo "## CPU pressure metrics"
  echo -n "${baseURL}"
  echo '/monitoring/query-browser?query0=descheduler%3Aaverageworkersutilization%3Acpu%3Aavg1m&query1=stddev%28descheduler%3Anodepressure%3Acpu%3Aavg1m+*+on%28instance%29+group_left%28node%29+label_replace%28kube_node_role%7Brole%3D%22worker%22%7D%2C+%27instance%27%2C+%22%241%22%2C+%27node%27%2C+%27%28.%2B%29%27%29%29&query2=avg%28descheduler%3Anodepressure%3Acpu%3Aavg1m+*+on%28instance%29+group_left%28node%29+label_replace%28kube_node_role%7Brole%3D%22worker%22%7D%2C+%27instance%27%2C+%22%241%22%2C+%27node%27%2C+%27%28.%2B%29%27%29%29&query3=descheduler%3Anodepressure%3Acpu%3Aavg1m+*+on%28instance%29+group_left%28node%29+label_replace%28kube_node_role%7Brole%3D%22worker%22%7D%2C+%27instance%27%2C+%22%241%22%2C+%27node%27%2C+%27%28.%2B%29%27%29'
  echo
  echo "## CPU intensive VMs"
  echo -n "${baseURL}"
  echo '/monitoring/query-browser?query0=count+by+%28node%29+%28kubevirt_vmi_info%7Bname%3D%7E%22.*cpu.*%22%2C+phase%3D%22running%22%7D%29'
  echo
  echo "## idle VMs"
  echo -n "${baseURL}"
  echo '/monitoring/query-browser?query0=count+by+%28node%29+%28kubevirt_vmi_info%7Bname%3D~".*no.*"%2C+phase%3D"running"%7D%29'
  echo
  echo "## Live Migrations"
  echo -n "${baseURL}"
  echo '/monitoring/query-browser?query0=count%28kubevirt_vmi_migration_succeeded%29'
  echo
  echo "$ oc logs -n openshift-kube-descheduler-operator -l app=desched-taint -f"
}

destroy() {
  c "Delete the operators"
  _oc delete -f manifests/50-desched-taint.yaml
  _oc delete -f manifests/41-descheduler-operator-cr.yaml
  _oc delete -f manifests/40-cnv-operator-cr.yaml
  _oc delete -f manifests/31-subscriptions.yaml
  _oc delete -f manifests/30-operatorgroup.yaml
  _oc delete -f manifests/20-namespaces.yaml
  #tainter del
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
