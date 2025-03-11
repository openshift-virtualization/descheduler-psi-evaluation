
# https://downloads-openshift-console.apps.ci-ln-278xfb2-1d09d.ci.azure.devcluster.openshift.com/amd64/linux/oc.tar
test -d /app && { cd /var/tmp && curl -L http://downloads.openshift-console.svc.cluster.local/amd64/linux/oc.tar | tar xf - ; } && { cd /var/tmp && curl -L https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64 -o jq && chmod +x /var/tmp/jq ; }
export PATH=/var/tmp/:$PATH

promql() { oc exec -c prometheus -n openshift-monitoring prometheus-k8s-0 -- curl -s --data-urlencode "query=$@" http://localhost:9090/api/v1/query ; }

get_load() {
	promql 'round(100 * avg(1 - rate(node_cpu_seconds_total{mode="idle"}[1m]) * on(instance) group_left(node) label_replace(kube_node_role{role="worker"}, "instance", "$1", "node", "(.+)")))' \
    | jq -er '(.data.result[0].value[1]|tonumber)' ; }

execute() {
  while true
  do
    echo "updating dynamic thresholds"
    AVG_LOAD=$(get_load)
    TARGETTHRESHOLDS=$((AVG_LOAD + 10))
    if [[ ${TARGETTHRESHOLDS} -gt 99 ]]; then
      TARGETTHRESHOLDS=99
    fi
    if [[ ${TARGETTHRESHOLDS} -lt 21 ]]; then
      TARGETTHRESHOLDS=21
    fi
    THRESHOLDS=$((TARGETTHRESHOLDS - 20))
    echo "AVG Load: $AVG_LOAD"
    echo "TARGETTHRESHOLDS Load: $TARGETTHRESHOLDS"
    echo "THRESHOLDS Load: $THRESHOLDS"
    oc get configmap -n openshift-kube-descheduler-operator cluster -o json | jq -r '.data["policy.yaml"]' > /var/tmp/policy.yaml
    sed -z "s/      targetThresholds:\n        MetricResource: [0-9]*\n/      targetThresholds:\n        MetricResource: ${TARGETTHRESHOLDS}\n/" -i /var/tmp/policy.yaml
    sed -z "s/      thresholds:\n        MetricResource: [0-9]*\n/      thresholds:\n        MetricResource: ${THRESHOLDS}\n/" -i /var/tmp/policy.yaml
    cat /var/tmp/policy.yaml
    if grep -q "targetThresholds" /var/tmp/policy.yaml ; then
      oc delete configmap -n openshift-kube-descheduler-operator cluster
      oc create configmap -n openshift-kube-descheduler-operator cluster --from-file=/var/tmp/policy.yaml
      oc delete pods -n openshift-kube-descheduler-operator -l=app=descheduler
    else
      print "broken file, skipping"
    fi
    sleep 90
  done
}

${@:-execute}
