CLUSTER_NAME 		  := fluid-cluster
KIND_CONFIG  		  := kind-config.yaml
LOAD_TARGET_NAMESPACE := fluid-autoscaler
MONITORING_NAMESPACE  := monitoring

.PHONY: up down recreate deploy status

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
	
status:
	@echo "── Nodes ────────────────────────────────"
	kubectl get nodes -o wide
	@echo ""
	@echo "── Pods ─────────────────────────────────"
	kubectl get pods -n $(LOAD_TARGET_NAMESPACE) -o wide