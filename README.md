# Using the descheduler with PSI metrics

## User stories

- As a cluster administrator I want to ensure that all my nodes are equally utilized in order to avoid pressure for the individual workloads

## Scope & Limitations

- Limited to Virtual Machines run with OpenShift Virtualization
- Limited to woker machine pools

## Usage

### Installation

1. Reconfigure the `node_exporter` 

    $ oc apply -f [manifests/mc-psi.yaml](mc-psi.yaml)

2. Deploy `descheduler operator`
   a. Install the descheduler operator as [documented here](TBD)
   b. Create the descheduler operator CR

    $ oc apply -f [manifests/descheduler-operator-cr.yaml](descheduler-operator-cr.yaml)

### Uninstallation
