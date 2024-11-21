# Using the descheduler with PSI metrics

PSI metrics expose node level pressure (or even cgroup). These metrics can be leveraged by the descheduler in order
to rebalance workloads according to the real node usage.

## User stories

- As a cluster administrator I want to ensure that all my nodes are equally utilized in order to avoid pressure for the individual workloads

## Scope & Limitations

- Limited to Virtual Machines run with OpenShift Virtualization
- Limited to woker machine pools

## Usage

### Installation

> **Note**
> You can also just simply run `bash to.sh deploy`

1. [Reconfigure the worker machine pool](manifests/mc-psi.yaml) to enable PSI metrics at Kernel level and expose them via the `node_exporter`

       $ oc apply -f manifests/mc-psi.yaml

2. Deploy Descheduler Operator

   1. Install the descheduler operator as [documented here](TBD)
   2. Create the [descheduler operator CR with proper eviciton and load awareness configured](manifests/descheduler-operator-cr.yaml)
      
          $ oc apply -f manifests/descheduler-operator-cr.yaml

### Uninstallation

TBD
