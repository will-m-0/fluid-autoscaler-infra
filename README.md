# fluid-autoscaler-infra

Kubernetes infrastructure for benchmarking autoscalers against a queue-backed workload.

Everything runs in a local kind cluster. KEDA is the current baseline.
The goal is to in a custom queue based autoscaler later and compare the two under identical load.

## Architecture

```
  k6 load-test Job
        │  HTTP GET /work
        ▼
  ┌──────────────┐                               ┌───────┐
  │ load-target  │  1. handler: LPUSH jobs       │ Redis │
  │   (N pods)   │──────────────────────────────▶│       │
  │              │  2. worker:  BRPOP jobs       │       │
  │  1 handler   │◀──────────────────────────────│       │
  │  10 workers  │  3. worker:  RPUSH reply:<id> │       │
  │   per pod    │──────────────────────────────▶│       │
  │              │  4. handler: BRPOP reply:<id> │       │
  │              │◀──────────────────────────────│       │
  └──────┬───────┘                               └───┬───┘
         │ /metrics                                  │ redis_exporter
         ▼                                           ▼ (sidecar :9121)
  ┌──────────────────────────────────────────────────────┐
  │  Prometheus (kube-prometheus-stack)                  │
  └────────────────┬─────────────────────────────────────┘
                   │ sum(load_target_active_workers)
                   ▼
             ┌───────────┐   scales    ┌──────────────┐
             │   KEDA    │────────────▶│ load-target  │
             └───────────┘             └──────────────┘
                   ▲
                   └── also polls Redis jobs list length directly
```

`load-target` is a Go service ([source](https://github.com/will-m-0/load-target)).
A request to `/work` pushes a job onto the Redis `jobs` list and blocks on a reply key.
A pool of 10 workers per pod pops jobs and simulates work with an exponentially distributed service time.
This gives a queue that builds up under load, the signal the scaler reacts to.

## Namespaces

| Namespace          | Contents                                       |
| ------------------ | ---------------------------------------------- |
| `fluid-autoscaler` | load-target, Redis, load-test job, ScaledObject |
| `monitoring`       | kube-prometheus-stack, ServiceMonitors          |
| `keda`             | KEDA operator                                   |


## Usage

Both the load target and load test images are from [this repo](https://github.com/will-m-0/load-target)
```sh
# 1. Create the cluster (1 control-plane + 2 workers)
make up

# 2. Build the workload images and side-load them into kind.
#    Manifests use imagePullPolicy: Never, so they must exist in the node image store.
kind load docker-image load-target:0.0.4-ubuntu --name fluid-cluster
kind load docker-image load-test:0.0.3 --name fluid-cluster

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

```
kind-config.yaml                    3-node kind cluster
namespace.yaml                      all three namespaces
deployments/load_target.yaml        load-target Deployment + ClusterIP Service
deployments/redis.yaml              Redis StatefulSet + redis_exporter sidecar,
                                    headless + regular Service
monitoring/*_service_monitor.yaml   scrape configs for load-target and Redis
scaling/keda_scaler.yaml            KEDA ScaledObject (the thing under test)
jobs/load_test.yaml                 k6 Job that drives traffic at /work
```

## Scaling config

`scaling/keda_scaler.yaml` targets `load-target-deployment` with
`minReplicaCount: 1` / `maxReplicaCount: 50` and two triggers:

- **Prometheus** — `sum(load_target_active_workers)` with a threshold of `7`.
  Since each pod has 10 workers, this caps growth at ~1.4x per scaling step.
- **Redis** — length of the `jobs` list, target `5` per replica. No cap between
  steps, so this trigger can jump replicas aggressively.

KEDA takes the max of the two. Tuning these is the main knob when comparing scaler behaviour.

