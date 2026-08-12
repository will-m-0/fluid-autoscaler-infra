CLUSTER_NAME          := fluid-cluster
KIND_CONFIG           := cluster/kind-config.yaml

LOAD_TARGET_NAMESPACE := fluid-autoscaler
MONITORING_NAMESPACE  := monitoring
KEDA_NAMESPACE        := keda

COMPONENTS := load-target redis
MANIFESTS := $(wildcard $(addsuffix /*.yaml,$(COMPONENTS)))
MONITORS  := $(filter %/servicemonitor.yaml,$(MANIFESTS))
WORKLOADS := $(filter-out $(MONITORS),$(MANIFESTS))

.PHONY: up down recreate certs deploy keda-scaler mmc-scaler status load-test

up:
	kind create cluster --name $(CLUSTER_NAME) --config $(KIND_CONFIG)

down:
	kind delete cluster --name $(CLUSTER_NAME)

recreate: down up

deploy:
	kubectl apply -f cluster/namespaces.yaml
	kubectl apply $(addprefix -f ,$(WORKLOADS))
	helm repo add prom-community https://prometheus-community.github.io/helm-charts
	helm repo update
	helm upgrade --install --namespace $(MONITORING_NAMESPACE) prom-monitoring prom-community/kube-prometheus-stack
	kubectl apply $(addprefix -f ,$(MONITORS))

# scalers are alternatives, not peers to run together.
keda-scaler:
	helm repo add kedacore https://kedacore.github.io/charts
	helm upgrade --install --namespace $(KEDA_NAMESPACE) keda kedacore/keda
	kubectl apply -f scalers/keda-scaledobject.yaml

# assume the mmcscaler CRD and controller already installed
mmc-scaler:
	kubectl apply -f scalers/mmc-scaler.yaml

status:
	kubectl get nodes -o wide
	kubectl get pods -n $(LOAD_TARGET_NAMESPACE) -o wide

load-test:
	kubectl delete job load-test -n $(LOAD_TARGET_NAMESPACE) --ignore-not-found
	kubectl apply -f load-test/job.yaml
	kubectl wait --for=condition=Ready pod -l job-name=load-test -n $(LOAD_TARGET_NAMESPACE) --timeout=60s
	kubectl logs -f job/load-test -n $(LOAD_TARGET_NAMESPACE)
