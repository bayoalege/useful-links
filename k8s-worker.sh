#!/bin/bash
# Author: Bayo Alege
# Purpose: Install k8s cluster

# Function to check and load kernel modules
load_kernel_modules() {
    modprobe br_netfilter
    modprobe overlay
    modprobe vxlan
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
      && sudo apt-get install -y apt-transport-https \
      && curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -

    echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" \
      | sudo tee -a /etc/apt/sources.list.d/kubernetes.list \
      && sudo apt-get update -qy

    sudo apt-get update \
      && sudo apt-get install -yq \
      kubelet \
      kubeadm \
      kubectl

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

# Function to install and initialize the Kubernetes cluster
install_and_initialize_kubernetes() {
        kubeadm join 10.70.249.3:6443 --token cfxb70.nfdm5gyx7y3arj85 \
        --discovery-token-ca-cert-hash sha256:6d20f676def20e31d6c33ee045b7ceefc1ffc6a9859c0a542b397b85718e9c73
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
create_k8s_user_and_configure