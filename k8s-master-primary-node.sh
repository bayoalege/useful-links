#!/bin/bash

# Function to install and initialize the Kubernetes cluster
install_and_initialize_kubernetes() {
    APISERVER_ENDPOINT="lb-server-01:6443"
    #MASTER_INTERFACE_IP="139.178.84.9"
    POD_NETWORK_CIDR="192.168.0.0/16"
    sudo kubeadm init --control-plane-endpoint=$APISERVER_ENDPOINT --upload-certs --pod-network-cidr=$POD_NETWORK_CIDR 
    #\ --apiserver-advertise-address=$MASTER_INTERFACE_IP 
}

# Function to install CNI (choice: Weave) and change the default alloc_ip
install_cni_choice() {
    export KUBECONFIG=/etc/kubernetes/admin.conf
    WEAVE_NET_RANGE="172.30.0.0/16"
    kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s-1.11.yaml
    kubectl -n kube-system set env ds/weave-net --containers=weave IPALLOC_RANGE=$WEAVE_NET_RANGE
    kubectl cluster-info

    # Deploy Calico network (uncomment the line below if switching to Calico)
    # kubectl --kubeconfig=/etc/kubernetes/admin.conf create -f https://docs.projectcalico.org/v3.18/manifests/calico.yaml
}

# Function to create k8s user and configure
create_k8s_regular_user() {
    sudo useradd k8suser -G sudo -m -s /bin/bash
    echo -e "k8suser123\nk8suser123" | passwd k8suser >/dev/null 2>&1
}

# Function to install Helm
install_helm() {
    cd /tmp
    sudo wget https://get.helm.sh/helm-v3.7.1-linux-amd64.tar.gz
    sudo tar -zxvf helm-v3.7.1-linux-amd64.tar.gz
    sudo mv linux-amd64/helm /usr/local/bin/helm
    helm version
}

# Function to install NGINX Ingress
install_ingress_nginx() {
    export KUBECONFIG=/etc/kubernetes/admin.conf

    MASTER_NODE=$(kubectl get nodes -o custom-columns=NAME:.metadata.name --no-headers)
    kubectl taint nodes "${MASTER_NODE}" node-role.kubernetes.io/control-plane-

    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update

    cat >> $HOME/ingrex-nginx-values.yaml <<EOF
controller:
  extraArgs:
    update-status: "false"
EOF

    helm upgrade --install ingress-nginx ingress-nginx --repo https://kubernetes.github.io/ingress-nginx \
    --namespace ingress-nginx --create-namespace -f $HOME/ingrex-nginx-values.yaml
    ##--set controller.extraArgs.update-status=false

    kubectl create deployment demo --image=httpd
    kubectl expose deployment demo --port=80
    kubectl create ingress demo-localhost --class=nginx \
  --rule="demo.localdev.me/*=demo:80"
}

# Master script
install_and_initialize_kubernetes
install_cni_choice
create_k8s_regular_user
install_helm
#install_ingress_nginx
