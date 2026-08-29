# fluid-autoscaler-infra

Kubernetes infrastructure for comparing autoscalers against a queue-backed workload.

Everything runs in a local kind cluster. KEDA is the current baseline.
The goal is to create a queue based autoscaler later and compare the two under identical load.

## Architecture

```
  ┌────────────────┐
  │  k6 load-test  │
  └───┬────────▲───┘
      │        │
      │ GET    │ 200 OK, immediately. The handler
      │ /work  │ does not wait for the job to run.
      ▼        │
  ┌──────────────┐                               ┌───────┐
  │ load-target  │  1. handler: LPUSH jobs       │ Redis │
  │   (N pods)   │──────────────────────────────▶│       │
  │              │                               │ jobs  │
  │  1 handler   │  2. worker:  BRPOP jobs       │ list  │
  │  10 workers  │◀──────────────────────────────│       │
  │   per pod    │                               │       │
  │              │  3. worker simulates work,    │       │
  │              │     writes nothing back       │       │
  └──────────────┘                               └───────┘
         ▲                                           ▲
         │ scrape /metrics                           │ scrape :9121
         │                                           │
  ┌──────┴───────────────────────────────────────────┴───┐
  │  Prometheus (kube-prometheus-stack)                  │
  └────────────────▲─────────────────────────────────────┘
                   │ queries sum(load_target_active_workers)
             ┌─────┴─────┐   scales    ┌──────────────┐
             │   KEDA    │────────────▶│ load-target  │
             └─────┬─────┘             └──────────────┘
                   │
                   └── also polls the Redis jobs list length directly
```


`load-target` is a Go service ([source](https://github.com/will-m-0/load-target)).
A request to `/work` pushes a job onto the Redis `jobs` list and returns 200 immediately without waiting for job to be processed.
A pool of 10 workers per pod pops jobs off the list in the background and simulates work with an exponentially distributed service time.


## Namespaces

| Namespace          | Contents                                             |
| ------------------ | ---------------------------------------------------- |
| `fluid-autoscaler` | load-target, Redis, load-test job, the active scaler |
| `monitoring`       | kube-prometheus-stack, ServiceMonitors               |
| `keda`             | KEDA operator                                        |


## Usage

Both the load target and load test images are from [this repo](https://github.com/will-m-0/load-target)
```sh
# 1. Create the cluster (1 control-plane + 2 workers)
make up

# 2. Build images and load into kind.
kind load docker-image load-target:0.0.6-ubuntu --name fluid-cluster
kind load docker-image load-test:0.0.5 --name fluid-cluster

# 3. Namespaces, workloads, Prometheus stack, ServiceMonitors
make deploy

# 4. Install KEDA and apply the ScaledObject
make keda-scaler

# 5. Run the load test (follows logs; re-runnable)
make load-test
```

`make status` prints nodes and pods. `make down` deletes the cluster;
`make recreate` is down + up.

## Layout

Manifests are grouped by component i.e. everything that makes up `load-target` lives in one directory.

```
cluster/
  kind-config.yaml          
  namespaces.yaml           
load-target/                the service under test
  configmap.yaml            worker count, queue key, Redis address
  deployment.yaml
  service.yaml              ClusterIP
  servicemonitor.yaml       scrape /metrics
redis/                      the queue
  statefulset.yaml          Redis + redis_exporter sidecar
  service.yaml              ClusterIP, 6379 plus 9121 for metrics
  service-headless.yaml     governing Service for the StatefulSet
  servicemonitor.yaml       scrape the exporter
scalers/                    scalers
  keda-scaledobject.yaml    KEDA baseline
  mmc-scaler.yaml           custom M/M/c controller
load-test/
  job.yaml                  k6 Job that drives traffic at /work
```

`make deploy` applies the ServiceMonitors after the Prometheus stack.
Both manifest lists in the Makefile are globbed, so a new file in a component directory is picked up

## Scaling config

`scalers/keda-scaledobject.yaml` targets `load-target-deployment` with
`minReplicaCount: 1` / `maxReplicaCount: 50` and two triggers:

- **Prometheus** — `sum(load_target_active_workers)` with a threshold of `7`.
  Since each pod has 10 workers, this caps growth at ~1.4x per scaling step.
- **Redis** — length of the `jobs` list, target `5` per replica. No cap between
  steps, so this trigger can jump replicas aggressively.

KEDA takes the max of the two.

`scalers/mmc-scaler.yaml` is the custom alternative, applied with `make mmc-scaler`.

