#!/usr/bin/bash
#
set -e

export DESCRIPTION="1. Cordon half of the worker nodes\n2. Create cpu VMs till we detect significant pressure\n3. Flip the partitions of cordoned and uncordoned nodes\n4. Create the same amount of no-load VMs on the other set of nodes\n5. Uncordon all and rebalance"
export STDD_LOAD_L_TH=0.2
export STDD_LOAD_H_TH=0.3

scale_up_pre() {
  CPUL_COUNT=$(( ALL_WORKER_NODE_COUNT / 2 ))
  NOLOAD_COUNT=$(( ALL_WORKER_NODE_COUNT - CPUL_COUNT  ))
  export CPUL_WORKER_NODES=$(head -n$CPUL_COUNT <<<$ALL_WORKER_NODES)
  export NOLOAD_WORKER_NODES=$(tail -n$NOLOAD_COUNT <<<$ALL_WORKER_NODES )

  n
  c "Uncordon all the workers nodes in order to have a clean environment"
  for N in $ALL_WORKER_NODES ; do x "oc adm uncordon $N" ; done

  n
  c "Initially cordon noload nodes in order to create an inbalance"
  c "Going to cordon node(s) '$NOLOAD_WORKER_NODES' in order to rebalance workloads later"
  for N in $NOLOAD_WORKER_NODES ; do x "oc adm cordon $N" ; done

  export INITIAL_REPLICAS=$CPUL_COUNT
}

scale_up_load_s1() {
  c "Scale up the deployments to generate more load"
  x "oc patch --type=json -p '[{\"op\": \"replace\", \"path\": \"/spec/replicas\", \"value\": $REPLICAS}]' vmpool cpu-load"
  export REPLICAS=$(( REPLICAS + CPUL_COUNT ))

  c "Give it some time to generate load"
  x "sleep 30s"
}

scale_up_load_s2() {
  n
  c "Switch cordoned and uncordoned worker node partitions"
  for N in $NOLOAD_WORKER_NODES ; do x "oc adm uncordon $N" ; done
  for N in $CPUL_WORKER_NODES ; do x "oc adm cordon $N" ; done

  n
  c "Scale up no load VMs to match # loading one"
  x "oc patch --type=json -p '[{\"op\": \"replace\", \"path\": \"/spec/replicas\", \"value\": $REPLICAS}]' vmpool no-load"
  n
  c "Let the system settle for a bit."
  x "sleep 3m"
}

scale_up_post() {
  c "Uncordon all the workers nodes in order to rebalance the VMs"
  for N in $ALL_WORKER_NODES ; do x "oc adm uncordon $N" ; done
}
