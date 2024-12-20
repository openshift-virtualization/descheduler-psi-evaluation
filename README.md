
> [!IMPORTANT]
> This repository is not inteded to be used in production environments.
> This repository is containing files to evaluate the PSI integration into the descheduler only.
> For a production level integration please monitor the OpenShift Documentation in order to understand when this feature GAs.


# Using the descheduler with PSI metrics

PSI metrics expose node level pressure (or even cgroup). These metrics can be leveraged by the descheduler in order
to rebalance workloads according to the real node usage.

## User stories

- As a cluster administrator I want to ensure that all my nodes are equally utilized in order to avoid pressure for the individual workloads

## Scope & Limitations

- Limited to Virtual Machines run with OpenShift Virtualization
- Limited to worker machine pools (PSI metrics are needed also for master nodes)

## Usage

> [!NOTE]
> - Use a cluster with at least 6 worker nodes
> - The cluster should have no other workloads running

> [!NOTE]
> Two alternative test scenarios are available, replace `TEST_SCENARIO=1` with `TEST_SCENARIO=2` to switch to the second one.


```console
$ bash to.sh deploy
...
$ bash to.sh apply
...
$ TEST_SCENARIO=1 bash e2e-test.sh
...
$
```

### Deployment walk through

Running `bash to.sh deploy` will deploy all necessary parts.
In this section we are looking what exactly is getting deployed.

1. Reconfiguration of the machine pools to enable PSI metrics at Kernel level and expose them via the `node_exporter`

       oc apply -f manifests/10-mc-psi-controlplane.yaml
       oc apply -f manifests/11-mc-psi-worker.yaml
       oc apply -f manifests/12-mc-schedstats-worker.yaml

2. Deploy the Descheduler Operator and OpenShift Virtualization

       oc apply -f manifests/20-namespaces.yaml
       oc apply -f manifests/30-operatorgroup.yaml
       oc apply -f manifests/31-subscriptions.yaml

       until _oc apply -f manifests/40-cnv-operator-cr.yaml ; do echo -n . sleep 6 ; done
       until _oc apply -f manifests/41-descheduler-operator-cr.yaml ; do echo -n . sleep 6 ; done

       oc adm policy add-cluster-role-to-user cluster-monitoring-view -z $SA -n $NS  # for desched metrics

3. Deploy the node tainting component

       oc create -n $NS configmap desched-taint --from-file contrib/desched-taint.sh
       oc apply -n $NS -f manifests/50-desched-taint.yaml
       oc adm policy add-cluster-role-to-user system:controller:node-controller -z $SA -n $NS" # for tainter
