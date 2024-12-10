# Using the descheduler with PSI metrics

PSI metrics expose node level pressure (or even cgroup). These metrics can be leveraged by the descheduler in order
to rebalance workloads according to the real node usage.

## User stories

- As a cluster administrator I want to ensure that all my nodes are equally utilized in order to avoid pressure for the individual workloads

## Scope & Limitations

- Limited to Virtual Machines run with OpenShift Virtualization
- Limited to worker machine pools (PSI metrics are needed also for master nodes)

## Usage

```console
$ bash to.sh deploy
...
$ bash to..sh apply ; WITH_DEPLOY=false bash e2e-test.sh 
...
$
```

### Installation

> **Note**
> You can also just simply run `bash to.sh deploy`

1. [Reconfigure the worker machine pool](manifests/mc-psi.yaml) to enable PSI metrics at Kernel level and expose them via the `node_exporter`

```bash
       $ oc apply -f manifests/mc-psi-worker.yaml
       $ oc apply -f manifests/mc-psi-controlplane.yaml
```

2. Deploy Descheduler Operator

   1. Install the descheduler operator as [documented here](https://docs.openshift.com/container-platform/4.17/nodes/scheduling/descheduler/index.html)
   2. Bind 'cluster-monitoring-view' cluster role to the service account used by the descheduler.

```bash
          $ oc adm policy add-cluster-role-to-user cluster-monitoring-view -z openshift-descheduler -n openshift-kube-descheduler-operator
```
 
   3. Create the [descheduler operator CR with proper eviciton and load awareness configured](manifests/descheduler-operator-cr.yaml)
      
```bash
          $ oc apply -f manifests/descheduler-operator-cr.yaml
```

### Uninstallation

TBD
