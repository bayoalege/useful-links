#After VIP creation
#configure Load Balancer or DNS:
#If you have a load balancer, configure it to forward traffic to the VIP (192.168.0.100) and distribute it among your control plane nodes.
#Alternatively, you can use DNS to point a hostname (e.g., bayo-controlplane-vip.localdev.me) to the VIP.

install_keepalived() {
    # Variables
    VIP="$1"
    AUTH_PASS="$2"
    ROLE="$3"

    # Install Keepalived
    sudo apt-get update
    sudo apt-get install -y keepalived

    # Determine priority based on role
    if [ "$ROLE" = "MASTER" ]; then
        PRIORITY=101
    elif [ "$ROLE" = "BACKUP" ]; then
        PRIORITY=100
    else
        echo "Invalid role. Please specify 'MASTER' or 'BACKUP'."
        exit 1
    fi

    # Configure Keepalived
    sudo cat <<EOF | sudo tee /etc/keepalived/keepalived.conf
vrrp_script check_kube {
    script "/usr/bin/systemctl is-active kubelet"
    interval 2
    weight 2
}

vrrp_instance VI_1 {
    state $ROLE
    interface bond0
    virtual_router_id 51
    priority $PRIORITY
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass $AUTH_PASS
    }

    unicast_src_ip 139.178.86.87     # The IP address of this machine
    unicast_peer {
       147.28.141.71                 # The IP address of peer machines
    }
    virtual_ipaddress {
        $VIP
    }
    track_script {
        check_kube
    }
}
EOF

    # Start Keepalived
    sudo systemctl stop keepalived
    sudo systemctl enable keepalived
    sudo systemctl start keepalived
}

# Example usage
MY_VIP="147.75.51.178"
KEEPALIVED_PASSWD="abrakada-abra"
ROLE="MASTER"
install_keepalived $MY_VIP $KEEPALIVED_PASSWD $ROLE