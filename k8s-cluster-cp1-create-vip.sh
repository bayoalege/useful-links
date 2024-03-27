#!/bin/bash
#
#########################################################################################################################
#
# Author: Bayo Alege
# Purpose: Install k8s cluster

# Function to check and load kernel modules
# References: https://blog.alexellis.io/kubernetes-in-10-minutes/
#
#########################################################################################################################

load_kernel_modules() {
    modprobe br_netfilter
    modprobe overlay
    modprobe vxlan

    #disable firewall
    systemctl disable --now ufw
}

# Function to set sysctl values
set_sysctl_values() {
    sysctl_files=("/proc/sys/net/bridge/bridge-nf-call-iptables" "/proc/sys/net/bridge/bridge-nf-call-ip6tables")

    for file in "${sysctl_files[@]}"; do
        if [ ! -e "$file" ]; then
            echo "Creating $file"
            touch "$file"
        fi
    done

    sysctl_values=("net.ipv4.ip_forward=1" "net.bridge.bridge-nf-call-iptables=1" "net.bridge.bridge-nf-call-ip6tables=1"
      "net.core.rmem_default=12582912" "net.core.wmem_default=12582912"
      "net.core.rmem_max=12582912" "net.core.wmem_max=12582912"
      "net.ipv4.tcp_rmem=10240 87380 12582912" "net.ipv4.tcp_wmem=10240 87380 12582912"
      "net.ipv4.tcp_congestion_control=westwood")

    for value in "${sysctl_values[@]}"; do
        sysctl -w "$value"
    done

    # Save sysctl settings
    sysctl --system
}

# Function to install and configure containerd
install_and_configure_containerd() {
    wget https://github.com/containerd/containerd/releases/download/v1.7.13/containerd-1.7.13-linux-amd64.tar.gz
    sudo tar Cxzvf /usr/local containerd-1.7.13-linux-amd64.tar.gz

    wget https://github.com/opencontainers/runc/releases/download/v1.1.12/runc.amd64
    sudo install -m 755 runc.amd64 /usr/local/sbin/runc

    wget https://github.com/containernetworking/plugins/releases/download/v1.4.0/cni-plugins-linux-amd64-v1.4.0.tgz
    sudo mkdir -p /opt/cni/bin
    sudo tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.4.0.tgz

    sudo mkdir /etc/containerd
    containerd config default | sudo tee /etc/containerd/config.toml
    sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
    sudo curl -L https://raw.githubusercontent.com/containerd/containerd/main/containerd.service -o /etc/systemd/system/containerd.service

    sudo systemctl daemon-reload
    sudo systemctl enable --now containerd
    sudo systemctl status containerd
}

# Function to install kubernetes packages
install_kubernetes_packages() {
    sudo apt-get update \
      && sudo apt-get install -y apt-transport-https ipcalc jq bird \
      && curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -

    echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" \
      | sudo tee -a /etc/apt/sources.list.d/kubernetes.list \
      && sudo apt-get update -qy

    sudo apt-get update \
      && sudo apt-get install -yq \
      kubelet \
      kubeadm \
      kubectl
    
    #sudo  hostnamectl set-hostname master-node
    sudo apt-mark hold kubelet kubeadm kubectl
}

# Function to disable swap
disable_swap() {
    sudo swapoff -a
    sudo sed -i '/\sswap\s/s/^/#/' /etc/fstab
}

# Function to enable necessary bridge configurations
enable_bridge_configurations() {
    sudo sysctl -w net.bridge.bridge-nf-call-iptables=1
    sudo sysctl -w net.bridge.bridge-nf-call-ip6tables=1
    sudo sysctl -w net.ipv4.ip_forward=1

    echo "net.bridge.bridge-nf-call-iptables = 1" | sudo tee -a /etc/sysctl.conf
    echo "net.bridge.bridge-nf-call-ip6tables = 1" | sudo tee -a /etc/sysctl.conf
    echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -p  # Apply the changes immediately

    lsmod | grep br_netfilter || sudo modprobe br_netfilter
}

# Function to install and initialize the Kubernetes cluster with kube-vip for HA
install_and_initialize_kubernetes() {

export VIP=10.70.249.10
export INTERFACE=lo

ctr image pull docker.io/plndr/kube-vip:0.3.1
ctr run --rm --net-host docker.io/plndr/kube-vip:0.3.1 vip \
/kube-vip manifest pod \
--interface $INTERFACE \
--vip $VIP \
--controlplane \
--services \
--arp \
--leaderElection | tee  /etc/kubernetes/manifests/kube-vip.yaml

sudo kubeadm init --apiserver-advertise-address=$VIP --pod-network-cidr=192.168.0.0/16 --kubernetes-version=1.28.2

}

#Function to install CNI and change the default alloc_ip
install_cni_and_change_alloc_ip() {
    export KUBECONFIG=/etc/kubernetes/admin.conf
    kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s-1.11.yaml
    kubectl -n kube-system set env ds/weave-net --containers=weave IPALLOC_RANGE="172.30.0.0/16"
    #POD_CIDR=$(kubectl get configmap -n kube-system kubeadm-config -o jsonpath='{.data.ClusterConfiguration}' | jq -r '.networking.podSubnet')
    #kubectl -n kube-system set env ds/weave-net --containers=weave IPALLOC_RANGE="$POD_CIDR"
    kubectl cluster-info
}

# Function to create k8s user and configure
create_k8s_user_and_configure() {
    sudo useradd k8s -G sudo -m -s /bin/bash
    sudo passwd k8s
    sudo su - k8s
}

# Main script execution
load_kernel_modules
set_sysctl_values
install_and_configure_containerd
install_kubernetes_packages
disable_swap
enable_bridge_configurations
install_and_initialize_kubernetes
install_cni_and_change_alloc_ip
create_k8s_user_and_configure