
# https://downloads-openshift-console.apps.ci-ln-278xfb2-1d09d.ci.azure.devcluster.openshift.com/amd64/linux/oc.tar
test -d /app && { cd /var/tmp && curl -L http://downloads.openshift-console.svc.cluster.local/amd64/linux/oc.tar | tar xf - ; }
export PATH=/var/tmp/:$PATH

handle() {
  TAINT="kubevirt.io/rebalance:PreferNoSchedule"
  oc_taint="echo oc adm taint node --overwrite"
  CYCLE_DONE=true
  tr -d '"' | while read LINE; do
#    if $CYCLE_DONE && grep -qE "Processing node" <<<$LINE
#    then $oc_taint --all ${TAINT}- ; CYCLE_DONE=false; fi


    if grep -qE "nodeutilization.*Node is overutilized.*" <<<$LINE ;
    then NODE=$(echo "$LINE" | grep -E -o "node=[^ ]+" | cut -d= -f2-) ;  $oc_taint $NODE ${TAINT} ; CYCLE_DONE=true ;
    elif grep -qE "nodeutilization.*Node is (under|appr).*" <<<$LINE ;
    then NODE=$(echo "$LINE" | grep -E -o "node=[^ ]+" | cut -d= -f2-) ;  $oc_taint $NODE ${TAINT}- ; CYCLE_DONE=true ; fi
  done
  sleep 2
}


verify() {
  testdata() { cat <<EOF
  I1209 11:33:20.308217       1 descheduler.go:354] "Number of evictions/requests" totalEvicted=0 evictionRequests=0
  I1209 11:33:32.294373       1 toomanyrestarts.go:116] "Processing node" node="ci-ln-gi479l2-1d09d-g4n22-master-0"
  I1209 11:33:32.294450       1 toomanyrestarts.go:116] "Processing node" node="ci-ln-gi479l2-1d09d-g4n22-master-1"
  I1209 11:33:32.294478       1 toomanyrestarts.go:116] "Processing node" node="ci-ln-gi479l2-1d09d-g4n22-master-2"
  I1209 11:33:32.294518       1 toomanyrestarts.go:116] "Processing node" node="ci-ln-gi479l2-1d09d-g4n22-worker-centralus1-d9xt5"
  I1209 11:33:32.294551       1 toomanyrestarts.go:116] "Processing node" node="ci-ln-gi479l2-1d09d-g4n22-worker-centralus2-xwfw7"
  I1209 11:33:32.294582       1 toomanyrestarts.go:116] "Processing node" node="ci-ln-gi479l2-1d09d-g4n22-worker-centralus3-tdzxf"
  I1209 11:33:32.294609       1 profile.go:347] "Total number of evictions/requests" extension point="Deschedule" evictedPods=0 evictionRequests=0
  I1209 11:33:32.297747       1 nodeutilization.go:208] "Node is appropriately utilized" node="ci-ln-gi479l2-1d09d-g4n22-master-0" usage={"MetricResource":"45"} usagePercentage={"MetricResource":45}
  I1209 11:33:32.297777       1 nodeutilization.go:208] "Node is appropriately utilized" node="ci-ln-gi479l2-1d09d-g4n22-master-1" usage={"MetricResource":"45"} usagePercentage={"MetricResource":45}
  I1209 11:33:32.297785       1 nodeutilization.go:208] "Node is appropriately utilized" node="ci-ln-gi479l2-1d09d-g4n22-master-2" usage={"MetricResource":"38"} usagePercentage={"MetricResource":38}
  I1209 11:33:32.297792       1 nodeutilization.go:205] "Node is overutilized" node="ci-ln-gi479l2-1d09d-g4n22-worker-centralus1-d9xt5" usage={"MetricResource":"54"} usagePercentage={"MetricResource":54}
  I1209 11:33:32.297799       1 nodeutilization.go:205] "Node is overutilized" node="ci-ln-gi479l2-1d09d-g4n22-worker-centralus2-xwfw7" usage={"MetricResource":"62"} usagePercentage={"MetricResource":62}
  I1209 11:33:32.297806       1 nodeutilization.go:205] "Node is overutilized" node="ci-ln-gi479l2-1d09d-g4n22-worker-centralus3-tdzxf" usage={"MetricResource":"56"} usagePercentage={"MetricResource":56}
  I1209 11:33:32.297812       1 lownodeutilization.go:159] "Criteria for a node under utilization" CPU=0 Mem=0 Pods=0 MetricResource=20
  I1209 11:33:32.297819       1 lownodeutilization.go:160] "Number of underutilized nodes" totalNumber=0
  I1209 11:33:32.297825       1 lownodeutilization.go:163] "Criteria for a node above target utilization" CPU=0 Mem=0 Pods=0 MetricResource=50
  I1209 11:33:32.297831       1 lownodeutilization.go:164] "Number of overutilized nodes" totalNumber=3
  I1209 11:33:32.297837       1 lownodeutilization.go:167] "No node is underutilized, nothing to do here, you might tune your thresholds further"
  I1209 11:33:32.297852       1 profile.go:376] "Total number of evictions/requests" extension point="Balance" evictedPods=0 evictionRequests=0
  I1209 11:33:32.297867       1 descheduler.go:354] "Number of evictions/requests" totalEvicted=0 evictionRequests=0
  I1209 13:53:17.090426       1 toomanyrestarts.go:116] "Processing node" node="ci-ln-4pvhhbt-1d09d-vzrdd-worker-centralus3-9svn5"
  I1209 13:53:17.090591       1 toomanyrestarts.go:116] "Processing node" node="ci-ln-4pvhhbt-1d09d-vzrdd-master-0"
  I1209 13:53:17.090630       1 toomanyrestarts.go:116] "Processing node" node="ci-ln-4pvhhbt-1d09d-vzrdd-master-1"
  I1209 13:53:17.090674       1 toomanyrestarts.go:116] "Processing node" node="ci-ln-4pvhhbt-1d09d-vzrdd-master-2"
  I1209 13:53:17.090741       1 toomanyrestarts.go:116] "Processing node" node="ci-ln-4pvhhbt-1d09d-vzrdd-worker-centralus1-zfrlm"
  I1209 13:53:17.090832       1 toomanyrestarts.go:116] "Processing node" node="ci-ln-4pvhhbt-1d09d-vzrdd-worker-centralus2-xs4kw"
  I1209 13:53:17.090982       1 profile.go:347] "Total number of evictions/requests" extension point="Deschedule" evictedPods=0 evictionRequests=0
  I1209 13:53:17.140976       1 nodeutilization.go:202] "Node is underutilized" node="ci-ln-4pvhhbt-1d09d-vzrdd-worker-centralus3-9svn5" usage={"MetricResource":"2"} usagePercentage={"MetricResource":2}
  I1209 13:53:17.142259       1 nodeutilization.go:202] "Node is underutilized" node="ci-ln-4pvhhbt-1d09d-vzrdd-master-0" usage={"MetricResource":"1"} usagePercentage={"MetricResource":1}
  I1209 13:53:17.143138       1 nodeutilization.go:202] "Node is underutilized" node="ci-ln-4pvhhbt-1d09d-vzrdd-master-1" usage={"MetricResource":"1"} usagePercentage={"MetricResource":1}
  I1209 13:53:17.143908       1 nodeutilization.go:202] "Node is underutilized" node="ci-ln-4pvhhbt-1d09d-vzrdd-master-2" usage={"MetricResource":"3"} usagePercentage={"MetricResource":3}
  I1209 13:53:17.144641       1 nodeutilization.go:208] "Node is appropriately utilized" node="ci-ln-4pvhhbt-1d09d-vzrdd-worker-centralus1-zfrlm" usage={"MetricResource":"49"} usagePercentage={"MetricResource":49}
  I1209 13:53:17.145341       1 nodeutilization.go:202] "Node is underutilized" node="ci-ln-4pvhhbt-1d09d-vzrdd-worker-centralus2-xs4kw" usage={"MetricResource":"1"} usagePercentage={"MetricResource":1}
  I1209 13:53:17.146110       1 lownodeutilization.go:159] "Criteria for a node under utilization" CPU=0 Mem=0 Pods=0 MetricResource=20
  I1209 13:53:17.146962       1 lownodeutilization.go:160] "Number of underutilized nodes" totalNumber=5
  I1209 13:53:17.148026       1 lownodeutilization.go:163] "Criteria for a node above target utilization" CPU=0 Mem=0 Pods=0 MetricResource=50
  I1209 13:53:17.148435       1 lownodeutilization.go:164] "Number of overutilized nodes" totalNumber=0
  I1209 13:53:17.149366       1 lownodeutilization.go:182] "All nodes are under target utilization, nothing to do here"
  I1209 13:53:17.150076       1 profile.go:376] "Total number of evictions/requests" extension point="Balance" evictedPods=0 evictionRequests=0
  I1209 13:53:17.150820       1 descheduler.go:354] "Number of evictions/requests" totalEvicted=0 evictionRequests=0
EOF
  }

  EXPECTED="oc adm taint node --all kubevirt.io/rebalance:PreferNoSchedule-
oc adm taint node ci-ln-gi479l2-1d09d-g4n22-worker-centralus1-d9xt5 kubevirt.io/rebalance:PreferNoSchedule
oc adm taint node ci-ln-gi479l2-1d09d-g4n22-worker-centralus2-xwfw7 kubevirt.io/rebalance:PreferNoSchedule
oc adm taint node ci-ln-gi479l2-1d09d-g4n22-worker-centralus3-tdzxf kubevirt.io/rebalance:PreferNoSchedule
oc adm taint node --all kubevirt.io/rebalance:PreferNoSchedule-"

  STDOUT="$(testdata | handle)"
  [[ "$EXPECTED" == "$STDOUT" ]] && echo PASS || { echo FAIL ; echo -e "expected\n$EXPECTED" ; echo -e "stdout\n$STDOUT" ; }
}


pilot() {
    oc logs -f -n openshift-kube-descheduler-operator -l app=descheduler | tee /dev/stderr | handle
}


${@:-pilot}
