#!/usr/bin/bash
#
set -e

export DESCRIPTION="1. Taint 1/2 of the nodes\n2. Create cpu and no-load VMs till we detect significant utilization\n3. Remove taints and rebalance"
export STDD_LOAD_TARGET=0.10
export LOAD_L_TH=0.10
export LOAD_H_TH=0.25

scale_up_pre() {
  TAINT_COUNT=$(( ALL_WORKER_NODE_COUNT / 2 ))
  TAINTED_WORKER_NODES=$(head -n$TAINT_COUNT <<<$ALL_WORKER_NODES)

  oc label --all rebalance_tainted- > /dev/null 2>&1 || :
  for N in $TAINTED_WORKER_NODES ; do x "oc label --overwrite $N rebalance_tainted=true" ; done

  c "Taint node in order to create an inbalance"
  c "Going to taint node(s) '$TAINTED_WORKER_NODES' in order to rebalance workloads later"
  oc adm taint node --all rebalance:NoSchedule- > /dev/null 2>&1 || :
  x "oc adm taint --overwrite node -l rebalance_tainted=true rebalance:NoSchedule"

  export INITIAL_REPLICAS=$ALL_WORKER_NODE_COUNT
}

scale_up_load_s1() {
  c "Scale up the deployments to generate more load"
  x "oc patch --type=json -p '[{\"op\": \"replace\", \"path\": \"/spec/replicas\", \"value\": $REPLICAS_S}]' vmpool cpu-load-s"
  x "oc patch --type=json -p '[{\"op\": \"replace\", \"path\": \"/spec/replicas\", \"value\": $REPLICAS_M}]' vmpool cpu-load-m"
  x "oc patch --type=json -p '[{\"op\": \"replace\", \"path\": \"/spec/replicas\", \"value\": $REPLICAS_L}]' vmpool cpu-load-l"
  x "oc patch --type=json -p '[{\"op\": \"replace\", \"path\": \"/spec/replicas\", \"value\": $REPLICAS_S}]' vmpool no-load"
  export REPLICAS_S=$(( REPLICAS_S + ALL_WORKER_NODE_COUNT ))
  export REPLICAS_M=$(( REPLICAS_M + ALL_WORKER_NODE_COUNT / 2 ))
  export REPLICAS_L=$(( REPLICAS_L + ALL_WORKER_NODE_COUNT / 4 ))

  c "Give it some time to generate load"
  x "sleep 30s"
}

scale_up_load_s2() { n ; }

scale_up_post() {
  c "Remove the taint from node(s) '$TAINTED_WORKER_NODES' in order to rebalance the VMs"
  x "oc adm taint --overwrite node -l rebalance_tainted=true rebalance:NoSchedule-"
  oc label nodes --all rebalance_tainted- > /dev/null 2>&1 || :
}
