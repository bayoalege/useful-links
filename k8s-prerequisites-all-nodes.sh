#!/bin/bash

function disable_swap() {
  swapoff -a
  sed -i '/swap/d' /etc/fstab
}

function disable_firewall() {
  systemctl disable --now ufw
}

function load_kernel_modules() {
  cat >> /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF

  modprobe overlay
  modprobe br_netfilter
}

function add_kernel_settings() {
  cat >> /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
EOF

  sysctl --system
}

function install_containerd() {
  apt update
  apt install -y containerd apt-transport-https jq \
  gnupg-agent software-properties-common

  mkdir -p /etc/containerd
  containerd config default > /etc/containerd/config.toml

  systemctl restart containerd
  systemctl enable containerd
}

function add_and_install_kubernetes_repo() {
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

  # Update package lists and install Kubernetes components
  sudo apt-get update -qy
  sudo apt-cache madison kudeadm
  sudo apt-get install -y kubelet kubeadm kubectl
}

function enable_ssh_pwd_auth_and_root_passwd() {
  # Enable ssh password authentication
  echo "[TASK 1] Enable ssh password authentication"
  sed -i 's/^PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
  echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
  systemctl reload sshd

  # Set Root password
  echo "[TASK 2] Set root password"
  echo -e "kubeadmin\nkubeadmin" | passwd root >/dev/null 2>&1
}

# Main script

# Enable passwd auth and change root password
enable_ssh_pwd_auth_and_root_passwd

# Disable Swap
disable_swap

# Disable Firewall
disable_firewall

# Load Kernel Modules
load_kernel_modules

# Add Kernel Settings
add_kernel_settings

# Install Containerd
install_containerd

# Add Kubernetes Repository and install components
add_and_install_kubernetes_repo

#NEXT IF YOU DON'T WANT TO USE SCRIPT FOR CONTROLPLANE SINGLE NODE RUN BELOW MANUALLY
#kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-cert-extra-sans=controlplane --apiserver-advertise-address=192.168.1.31
#node controlplane node-role.kubernetes.io/control-plane:NoSchedule-
#kubectl -n kube-system set env ds/weave-net --containers=weave IPALLOC_RANGE="10.244.0.0/16"
#kubeadm join 192.168.1.31:6443 --token txsgms.1gg89vv8gqcfe0xt \
#        --discovery-token-ca-cert-hash sha256:2ad12c5fd26b4b75f63dd29430a8b5fd66086d11df84a3a4a291373cdefae876
