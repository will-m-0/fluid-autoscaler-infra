CLUSTER_NAME 		  := fluid-cluster
KIND_CONFIG  		  := kind-config.yaml

LOAD_TEST_IMAGE       := load-test:0.1.0

LOAD_TARGET_NAMESPACE := fluid-autoscaler
MONITORING_NAMESPACE  := monitoring
KEDA_NAMESPACE := keda

.PHONY: up down recreate deploy status load-test-image load-test

up:
	kind create cluster --name $(CLUSTER_NAME) --config $(KIND_CONFIG)

down:
	kind delete cluster --name $(CLUSTER_NAME)

recreate: down up

deploy:
	kubectl apply -f namespace.yaml
	kubectl apply -f deployments/
	helm repo add prom-community https://prometheus-community.github.io/helm-charts
	helm repo update
	helm upgrade --install --namespace $(MONITORING_NAMESPACE) prom-monitoring prom-community/kube-prometheus-stack
	kubectl apply -f monitoring/

keda-scaler:
	helm repo add kedacore https://kedacore.github.io/charts
	helm upgrade --install --namespace $(KEDA_NAMESPACE) keda kedacore/keda 
	kubectl apply -f scaling/keda_scaler.yaml
	
status:
	@echo "── Nodes ────────────────────────────────"
	kubectl get nodes -o wide
	@echo ""
	@echo "── Pods ─────────────────────────────────"
	kubectl get pods -n $(LOAD_TARGET_NAMESPACE) -o wide

load-test:
	kubectl delete job load-test -n $(LOAD_TARGET_NAMESPACE) --ignore-not-found
	kubectl apply -f jobs/load_test.yaml
	kubectl wait --for=condition=Ready pod -l job-name=load-test -n $(LOAD_TARGET_NAMESPACE) --timeout=60s
	kubectl logs -f job/load-test -n $(LOAD_TARGET_NAMESPACE)
