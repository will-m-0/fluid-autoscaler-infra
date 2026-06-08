CLUSTER_NAME := fluid-autoscaler
KIND_CONFIG  := kind-config.yaml
NAMESPACE    := fluid-autoscaler

.PHONY: up down recreate deploy status

up:
	kind create cluster --name $(CLUSTER_NAME) --config $(KIND_CONFIG)

down:
	kind delete cluster --name $(CLUSTER_NAME)

recreate: down up

deploy:
	kubectl apply -f namespace.yaml
	kubectl apply -f deployments/

status:
	@echo "── Nodes ────────────────────────────────"
	kubectl get nodes -o wide
	@echo ""
	@echo "── Pods ─────────────────────────────────"
	kubectl get pods -n $(NAMESPACE) -o wide