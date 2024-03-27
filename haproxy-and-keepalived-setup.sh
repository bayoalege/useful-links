#!/bin/bash
#
# Author: Bayo Alege
# Purpose: Configure HA Proxy and KeepAlived daemon
# Changes: Update the VIP and backend hostname, and IP addresses as needed
#

errorExit() {
  echo "*** " 1>&2
  exit 1
}

installBinaries() {
    apt update && apt install -y keepalived haproxy psmisc
}

configureKeepalived() {
  # Create check_apiserver.sh
  cat > /etc/keepalived/check_apiserver.sh <<EOF
#!/bin/sh

errorExit() {
  echo "*** " 1>&2
  exit 1
}

curl --silent --max-time 2 --insecure https://localhost:6443/ -o /dev/null || errorExit "Error GET https://localhost:6443/"
if ip addr | grep -q 192.168.0.240; then
  curl --silent --max-time 2 --insecure https://192.168.0.240:6443/ -o /dev/null || errorExit "Error GET https://192.168.0.240:6443/"
fi
EOF


  # Create keepalived.conf
  cat > /etc/keepalived/keepalived.conf <<EOF
global_defs {
  notification_email {
      # Leave this empty for now
  }
  router_id LVS_DEVEL
  vrrp_skip_check_adv_addr
  vrrp_garp_interval 0
  vrrp_gna_interval 0
  script_security
}

vrrp_script chk_haproxy {
    script "/etc/keepalived/check_apiserver.sh"
    interval 3
    weight -5
}

vrrp_instance haproxy-vip {
    state MASTER
    priority 150   # set BACKUP at 100 for preferred MASTER node
    interface bond0
    virtual_router_id 1
    advert_int 5
    authentication {
        auth_type PASS
        auth_pass mysecret
    }
  
  unicast_src_ip 147.28.196.119     # The IP address of this machine
  unicast_peer {
    147.28.196.181                  # The IP address of peer machines
  }
    virtual_ipaddress {
        192.168.0.240
    }
    track_script {
        chk_haproxy
    }
}
EOF

  # Check if group and user exist
  if ! getent group keepalived_script; then
    sudo groupadd -r keepalived_script
  fi

  if ! getent passwd keepalived_script; then
    sudo useradd -r -g keepalived_script -s /sbin/nologin -M -c "Keepalived Script User" keepalived_script
  fi

  # Restart service if it exists
  if systemctl cat keepalived &>/dev/null; then
    sudo systemctl restart keepalived
  else
    echo "Warning: keepalived.service not found."
  fi

  journalctl -u keepalived
  journalctl -xe | grep keepalived
  ip addr show dev bond0  # show the VIP is bounded to interface bond0
  sudo chmod +x /etc/keepalived/check_apiserver.sh
  sudo -u keepalived_script /etc/keepalived/check_apiserver.sh
  sudo systemctl restart keepalived
}

configureHaproxy() {
  # Create haproxy.cfg
  cat > /etc/haproxy/haproxy.cfg <<EOF
global
    log /dev/log  local0 warning
    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    maxconn     4000
    user        haproxy
    group       haproxy
    daemon

   stats socket /var/lib/haproxy/stats

defaults
  log global
  option  httplog
  option  dontlognull
        timeout connect 5000
        timeout client 50000
        timeout server 50000

frontend kube-apiserver
    bind *:6443
    mode tcp
    option tcplog
    default_backend kube-apiserver

backend kube-apiserver
    mode tcp
    option tcplog
    option tcp-check
    balance roundrobin
    default-server inter 10s downinter 5s rise 2 fall 2 slowstart 60s maxconn 250 maxqueue 256 weight 100
    server k8s-master-01 139.178.80.97:6443 check fall 3 rise 2
    server k8s-master-02 139.178.80.185:6443 check fall 3 rise 2
EOF

  # Enable and restart haproxy if it exists
  if systemctl cat haproxy &>/dev/null; then
    sudo systemctl enable haproxy && sudo systemctl restart haproxy
    nc -v localhost 6443
  else
    echo "Warning: haproxy.service not found."
  fi
}

# Execute functions
installBinaries
configureKeepalived
configureHaproxy