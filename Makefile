
CLUSTER_NAME := fluid-autoscaler
KIND_CONFIG  := kind-config.yaml
 
.PHONY: up down recreate status
 
up:
	kind create cluster --name $(CLUSTER_NAME) --config $(KIND_CONFIG)
 
down:
	kind delete cluster --name $(CLUSTER_NAME)
 
recreate: down up
 
status:
	kubectl get nodes -o wide
