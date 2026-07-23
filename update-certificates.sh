#!/usr/bin/env bash

containers=(fluid-cluster-control-plane fluid-cluster-worker fluid-cluster-worker2)

for container in "${containers[@]}"; do
    docker cp /usr/local/share/ca-certificates/dorsetsoftware-root-ca.crt $container:/usr/local/share/ca-certificates/corporate-ca.crt
    docker exec $container update-ca-certificates
    docker exec $container systemctl restart containerd
done
