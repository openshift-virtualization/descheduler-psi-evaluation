
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

## Monitoring

Two dashboards are available for monitoring the descheduler behaviour.

### Load Aware ReBalancing (Grafana)

A Grafana dashboard for the PSI-based load-aware rebalancing profile.
See [monitoring/README.md](monitoring/README.md) for deployment instructions.

### Memory Aware Rebalancing (Perses — local)

A [Perses](https://perses.dev) dashboard focused on the memory-aware aspects:
synthetic utilization values, dynamic thresholds, PSI pressure, node classification
over time, and evictions.

The stack runs **locally** in containers and proxies to the remote cluster's Thanos
querier, so no cluster-side deployment is required.

**Prerequisites:** `podman` (or `docker`) with compose support, and an active `oc` login
to the target cluster.

```console
$ cd monitoring/perses
$ KUBECONFIG=/path/to/kubeconfig ./start.sh
```

Open **http://localhost:8080** and navigate to
`Projects → descheduler → Dashboards → memory-aware-rebalancing`.

To stop the stack:

```console
$ ./start.sh stop
```

To refresh an expired token (tokens are short-lived), simply re-run `./start.sh` —
it regenerates `nginx.conf` with the new token and restarts the proxy container.

#### What the dashboard shows

| Section | Panels |
| --- | --- |
| Utilization | CPU utilization per node + fleet average (★); Memory utilization per node + fleet average |
| Pressure | CPU PSI pressure per node + fleet average; Memory PSI pressure per node + fleet average |
| Synthetic utilization value & thresholds | Per-node descheduler score with dynamic high (red dashed) and low (orange dashed) threshold bands |
| Node classification | `StatusHistoryChart` — Underutilized / Normal / Overutilized per node over time |
| Evictions | Total counter + per-node time series for `KubeVirtRelieveAndMigrate` |
| Detailed metrics *(collapsed)* | CPU & memory pressure and utilization, each per node with fleet average overlaid |

All panels are filterable by node via the **Node** variable at the top of the dashboard.
