#!/bin/bash
# Author: Bayo Alege
# Purpose: Install k8s cluster
#
#1. Install and download containerd
wget https://github.com/containerd/containerd/releases/download/v1.7.13/containerd-1.7.13-linux-amd64.tar.gz
sudo tar Cxzvf /usr/local containerd-1.7.13-linux-amd64.tar.gz

wget https://github.com/opencontainers/runc/releases/download/v1.1.12/runc.amd64
sudo install -m 755 runc.amd64 /usr/local/sbin/runc

#Now, we need the Container Network Interface, which is used to provide the necessary networking functionality. Download CNI with:
wget https://github.com/containernetworking/plugins/releases/download/v1.4.0/cni-plugins-linux-amd64-v1.4.0.tgz
sudo mkdir -p /opt/cni/bin
sudo tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.4.0.tgz

# How to configure Containerd
sudo mkdir /etc/containerd

containerd config default | sudo tee /etc/containerd/config.toml
#Enable SystemdCgroup with the command:

sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
sudo curl -L https://raw.githubusercontent.com/containerd/containerd/main/containerd.service -o /etc/systemd/system/containerd.service

#Reload the systemd daemon with:
sudo systemctl daemon-reload
sudo systemctl enable --now containerd
sudo systemctl status containerd

#2. adds the package repository where kubeadm, kubectl and
 sudo apt-get update \
  && sudo apt-get install -y apt-transport-https \
  && curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -

#3. perform a packages update
echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" \
  | sudo tee -a /etc/apt/sources.list.d/kubernetes.list \
  && sudo apt-get update -qy

#4. install kubeadm, kubectl etc
sudo apt-get update \
  && sudo apt-get install -yq \
  kubelet \
  kubeadm \
  kubectl

#5. hold the package versions
sudo apt-mark hold kubelet kubeadm kubectl

#6. disable swap
sudo swapoff $(cat /proc/swaps|grep ^/dev|awk '{print $1}')
sudo sed -i '/\sswap\s/s/^/#/' /etc/fstab

#7. bridge enabling
# Enable bridge-nf-call-iptables
sudo sysctl -w net.bridge.bridge-nf-call-iptables=1
sudo sysctl -w net.bridge.bridge-nf-call-ip6tables=1

# Enable IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1

# To make these changes persistent across reboots, you can add them to /etc/sysctl.conf
echo "net.bridge.bridge-nf-call-iptables = 1" | sudo tee -a /etc/sysctl.conf
echo "net.bridge.bridge-nf-call-ip6tables = 1" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p  # Apply the changes immediately

# Load br_netfilter module
lsmod | grep br_netfilter
sudo modprobe br_netfilter

#8. install cluster
 sudo kubeadm init \
 --apiserver-advertise-address=$(ifconfig bond0:0 | grep inet | awk '{print $2}') \
 --pod-network-cidr=192.168.0.0/16 \
 --kubernetes-version=1.28.2

#9. create k8s user and configure
sudo useradd k8s -G sudo -m -s /bin/bash
sudo passwd k8s
sudo su - k8s