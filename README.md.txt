1. mkdir monitoring
2. mkdir grafana-data prometheus-data
3. Install kind
curl.exe -Lo kind-windows-amd64.exe https://kind.sigs.k8s.io/dl/v0.20.0/kind-windows-amd64
Move-Item .\kind-windows-amd64.exe C:\Kind\kind.exe 
Update System Environment variable to include C:\Kind
Hint:  create Kubernetes cluster on top of Docker containers.
4. Create the kind.yaml file with following content.
# This config file contains all config fields with comments
# NOTE: this is not a particularly useful config file
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
# 1 control plane node and 3 workers
nodes:
# the control plane node config
- role: control-plane
# the three workers
- role: worker
- role: worker
- role: worker
5. Create the cluster using the kind.yaml file with kind command
kind create cluster --config kind.yaml --name monitoring-cluster

