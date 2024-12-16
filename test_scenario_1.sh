#!/usr/bin/bash
#
set -e

export DESCRIPTION="1. Taint 1/3 of the nodes\n2. Create cpu and no-load VMs till we detect significant pressure\n3. Remove taints and rebalance"
export STDD_LOAD_L_TH=0.2
export STDD_LOAD_H_TH=0.5

scale_up_pre() {
  TAINT_COUNT=$(( ALL_WORKER_NODE_COUNT / 3 ))
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
  x "oc patch --type=json -p '[{\"op\": \"replace\", \"path\": \"/spec/replicas\", \"value\": $REPLICAS}]' vmpool cpu-load"
  x "oc patch --type=json -p '[{\"op\": \"replace\", \"path\": \"/spec/replicas\", \"value\": $REPLICAS}]' vmpool no-load"
  export REPLICAS=$(( REPLICAS + ALL_WORKER_NODE_COUNT ))

  c "Give it some time to generate load"
  x "sleep 30s"
}

scale_up_load_s2() { n ; }

scale_up_post() {
  c "Remove the taint from node(s) '$TAINTED_WORKER_NODES' in order to rebalance the VMs"
  x "oc adm taint --overwrite node -l rebalance_tainted=true rebalance:NoSchedule-"
  oc label --all rebalance_tainted- > /dev/null 2>&1 || :
}
