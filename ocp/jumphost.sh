#!/usr/bin/env bash
# Openshift Jumphost (DNSMASQ,TFTP,LB,NFS,WEB) host setup script

DOMAIN=cloudcafe.tech
CTX=ocp414
OCPVERM=4.14
OCPVER=4.14.34

PULLSECRET=$pull_secret

HIP=`ip -o -4 addr list eth0 | grep -v secondary | awk '{print $4}' | cut -d/ -f1`
SUBNET=`echo $HIP | cut -d. -f1-3`
REV=`echo $SUBNET | awk -F . '{print $3"."$2"."$1".in-addr.arpa"}'`

# Change IP, MAC, Hostname & GW

GW=$jio_gw # JIO Router Gateway

#BASEMAC=AA:BB:CC

HIPT=`echo $HIP | awk -F . '{print $4}'`
JIP=$ocp_jump_ip
if [[ "$HIPT" != "$JIP" ]]; then JIP=$HIPT; fi
JIP2=$ocp_jump2_ip
BIP=$ocp_bootstrap_ip
M1IP=$ocp_master01_ip
M2IP=$ocp_master02_ip
M3IP=$ocp_master03_ip
I1IP=$ocp_infra01_ip
I2IP=$ocp_infra02_ip
W1IP=$ocp_worker01_ip
W2IP=$ocp_worker02_ip

BOOT=$bootstrap_hn
MAS1=$ocpmaster01_hn
MAS2=$ocpmaster02_hn
MAS3=$ocpmaster03_hn
INF1=$ocpinfra01_hn
INF2=$ocpinfra02_hn
WOR1=$ocpworker01_hn
WOR2=$ocpworker02_hn
JUMP=`hostname`

BOOTMAC=$ocp_bootstrap_mac
MAS1MAC=$ocp_master01_mac
MAS2MAC=$ocp_master02_mac
MAS3MAC=$ocp_master03_mac
INF1MAC=$ocp_infra01_mac
INF2MAC=$ocp_infra02_mac
WOR1MAC=$ocp_worker01_mac
WOR2MAC=$ocp_worker02_mac

#########################
## DO NOT MODIFY BELOW ##
#########################

JUMPIP=$SUBNET.$JIP
JUMPIP2=$SUBNET.$JIP2
BOOTIP=$SUBNET.$BIP
MAS1IP=$SUBNET.$M1IP
MAS2IP=$SUBNET.$M2IP
MAS3IP=$SUBNET.$M3IP
INF1IP=$SUBNET.$I1IP
INF2IP=$SUBNET.$I2IP
WOR1IP=$SUBNET.$W1IP
WOR2IP=$SUBNET.$W2IP

red=$(tput setaf 1)
grn=$(tput setaf 2)
yel=$(tput setaf 3)
blu=$(tput setaf 4)
bld=$(tput bold)
nor=$(tput sgr0)

# Download Openshift Software from Red Hat portal
toolsetup() {

echo "$bld$grn Downloading & Installing Openshift binary $nor"
curl -s -o openshift-install-linux.tar.gz https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/$OCPVER/openshift-install-linux.tar.gz
tar xpvf openshift-install-linux.tar.gz
rm -rf openshift-install-linux.tar.gz
sudo mv openshift-install /usr/local/bin

curl -s -o openshift-client-linux.tar.gz https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/$OCPVER/openshift-client-linux.tar.gz
tar xvf openshift-client-linux.tar.gz
rm -rf openshift-client-linux.tar.gz
sudo mv oc kubectl /usr/local/bin

echo "$bld$grn Downloading Openshift ISO ... $nor"
curl -s -o rhcos-live.x86_64.iso https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/$OCPVERM/$OCPVER/rhcos-live.x86_64.iso

echo "$bld$grn Downloading Openshift Initramfs Images ... $nor"
curl -s -o rhcos-initramfs.img https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/$OCPVERM/$OCPVER/rhcos-$OCPVER-x86_64-live-initramfs.x86_64.img

echo "$bld$grn Downloading Openshift Kernel ... $nor"
curl -s -o rhcos-kernel https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/$OCPVERM/$OCPVER/rhcos-$OCPVER-x86_64-live-kernel-x86_64

echo "$bld$grn Downloading Openshift Rootfs Image ... $nor"
curl -s -o rhcos-rootfs.img https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/$OCPVERM/$OCPVER/rhcos-$OCPVER-x86_64-live-rootfs.x86_64.img

}

# Configure DNSMASQ, TFTP with PXE Server
tftpsetup() {

HNM=`hostname`
echo "$bld$grn Configuring DNSMASQ, TFTP with PXE Server $nor"

sudo yum install net-tools nmstate dnsmasq syslinux tftp-server bind-utils -y
sudo ifconfig eth0:0 $SUBNET.$JIP2 netmask 255.255.255.0
echo "PEERDNS=no" >> /etc/sysconfig/network-scripts/ifcfg-eth0

sudo cp -r /usr/share/syslinux/* /var/lib/tftpboot
sudo mkdir /var/lib/tftpboot/rhcos
sudo mkdir /var/lib/tftpboot/pxelinux.cfg

sudo mv /etc/dnsmasq.conf  /etc/dnsmasq.conf.backup

cat <<EOF > dnsmasq.conf
interface=eth0
bind-interfaces
domain=$DOMAIN

# DHCP range-leases
dhcp-range=eth0,$SUBNET.$BIP,$SUBNET.225,255.255.255.0,1h

# PXE
dhcp-boot=pxelinux.0,$HNM,$HIP

# Gateway
dhcp-option=3,$GW

# DNS
dhcp-option=6,$JUMPIP, $GW, 8.8.8.8
server=8.8.4.4

# Broadcast Address
dhcp-option=28,$SUBNET.255

# NTP Server
dhcp-option=42,0.0.0.0

###### OpenShift #######

# Hosts MAC & Static IP
dhcp-host=$BOOTMAC,$BOOT,$BOOTIP,86400
dhcp-host=$MAS1MAC,$MAS1,$MAS1IP,86400
dhcp-host=$MAS2MAC,$MAS2,$MAS2IP,86400
dhcp-host=$MAS3MAC,$MAS3,$MAS3IP,86400
dhcp-host=$INF1MAC,$INF1,$INF1IP,86400
dhcp-host=$INF2MAC,$INF2,$INF2IP,86400
dhcp-host=$WOR1MAC,$WOR1,$WOR1IP,86400
dhcp-host=$WOR2MAC,$WOR2,$WOR2IP,86400

# DNS Records
address=/api.$CTX.$DOMAIN/$JUMPIP
address=/api-int.$CTX.$DOMAIN/$JUMPIP
address=/apps.$CTX.$DOMAIN/$JUMPIP2

address=/$JUMP/$JUMPIP
address=/$BOOT/$BOOTIP
address=/$MAS1/$MAS1IP
address=/$MAS2/$MAS2IP
address=/$MAS3/$MAS3IP
address=/$INF1/$INF1IP
address=/$INF2/$INF2IP
address=/$WOR1/$WOR1IP
address=/$WOR2/$WOR2IP
address=/etcd-0.$CTX.$DOMAIN/$MAS1IP
address=/etcd-1.$CTX.$DOMAIN/$MAS2IP
address=/etcd-2.$CTX.$DOMAIN/$MAS3IP

# PTR Records
ptr-record=$JIP.$REV.,"$JUMP"
ptr-record=$JIP2.$REV.,"$JUMP"
ptr-record=$BIP.$REV.,"$BOOT"
ptr-record=$M1IP.$REV.,"$MAS1IP"
ptr-record=$M2IP.$REV.,"$MAS2IP"
ptr-record=$M3IP.$REV.,"$MAS3IP"
ptr-record=$I1IP.$REV.,"$INF1IP"
ptr-record=$I2IP.$REV.,"$INF2IP"
ptr-record=$W1IP.$REV.,"$WOR1IP"
ptr-record=$W2IP.$REV.,"$WOR2IP"
ptr-record=$JIP.$REV.,"api-int.$CTX.$DOMAIN"
ptr-record=$JIP.$REV.,"api.$CTX.$DOMAIN"
###### OpenShift #######

# TFTP
pxe-prompt="Press F8 for menu.", 5
pxe-service=x86PC, "Install COREOS from network server", pxelinux
enable-tftp
tftp-root=/var/lib/tftpboot
EOF

sudo mv dnsmasq.conf /etc/dnsmasq.conf
sudo chown root:root /etc/dnsmasq.conf

cat <<EOF > bootstrap
DEFAULT pxeboot
TIMEOUT 5
PROMPT 0
LABEL pxeboot
 KERNEL http://$HIP:8080/ocp4/rhcos-kernel
 APPEND ip=dhcp rd.neednet=1 initrd=http://$HIP:8080/ocp4/rhcos-initramfs.img coreos.inst.install_dev=sda coreos.live.rootfs_url=http://$HIP:8080/ocp4/rhcos-rootfs.img coreos.inst.ignition_url=http://$HIP:8080/ocp4/bootstrap.ign
EOF

cat <<EOF > master
DEFAULT pxeboot
TIMEOUT 5
PROMPT 0
LABEL pxeboot
 KERNEL http://$HIP:8080/ocp4/rhcos-kernel
 APPEND ip=dhcp rd.neednet=1 initrd=http://$HIP:8080/ocp4/rhcos-initramfs.img coreos.inst.install_dev=sda coreos.live.rootfs_url=http://$HIP:8080/ocp4/rhcos-rootfs.img coreos.inst.ignition_url=http://$HIP:8080/ocp4/master.ign
EOF

cat <<EOF > worker
DEFAULT pxeboot
TIMEOUT 5
PROMPT 0
LABEL pxeboot
 KERNEL http://$HIP:8080/ocp4/rhcos-kernel
 APPEND ip=dhcp rd.neednet=1 initrd=http://$HIP:8080/ocp4/rhcos-initramfs.img coreos.inst.install_dev=sda coreos.live.rootfs_url=http://$HIP:8080/ocp4/rhcos-rootfs.img coreos.inst.ignition_url=http://$HIP:8080/ocp4/worker.ign
EOF

sudo mv bootstrap /var/lib/tftpboot/pxelinux.cfg/
sudo mv master /var/lib/tftpboot/pxelinux.cfg/ 
sudo mv worker /var/lib/tftpboot/pxelinux.cfg/

# Link the MAC
sudo ln -s /var/lib/tftpboot/pxelinux.cfg/bootstrap /var/lib/tftpboot/pxelinux.cfg/$(echo $BOOTMAC | awk '{print tolower($0)}' | sed 's/^/01-/g' | sed 's/:/-/g')
sudo ln -s /var/lib/tftpboot/pxelinux.cfg/master /var/lib/tftpboot/pxelinux.cfg/$(echo $MAS1MAC | awk '{print tolower($0)}' | sed 's/^/01-/g' | sed 's/:/-/g')
sudo ln -s /var/lib/tftpboot/pxelinux.cfg/master /var/lib/tftpboot/pxelinux.cfg/$(echo $MAS2MAC | awk '{print tolower($0)}' | sed 's/^/01-/g' | sed 's/:/-/g')
sudo ln -s /var/lib/tftpboot/pxelinux.cfg/master /var/lib/tftpboot/pxelinux.cfg/$(echo $MAS3MAC | awk '{print tolower($0)}' | sed 's/^/01-/g' | sed 's/:/-/g')
sudo ln -s /var/lib/tftpboot/pxelinux.cfg/worker /var/lib/tftpboot/pxelinux.cfg/$(echo $INF1MAC | awk '{print tolower($0)}' | sed 's/^/01-/g' | sed 's/:/-/g')
sudo ln -s /var/lib/tftpboot/pxelinux.cfg/worker /var/lib/tftpboot/pxelinux.cfg/$(echo $INF2MAC | awk '{print tolower($0)}' | sed 's/^/01-/g' | sed 's/:/-/g')
sudo ln -s /var/lib/tftpboot/pxelinux.cfg/worker /var/lib/tftpboot/pxelinux.cfg/$(echo $WOR1MAC | awk '{print tolower($0)}' | sed 's/^/01-/g' | sed 's/:/-/g')
sudo ln -s /var/lib/tftpboot/pxelinux.cfg/worker /var/lib/tftpboot/pxelinux.cfg/$(echo $WOR2MAC | awk '{print tolower($0)}' | sed 's/^/01-/g' | sed 's/:/-/g')

sudo chown root:root /var/lib/tftpboot/pxelinux.cfg/* 

sudo systemctl start dnsmasq;sudo systemctl enable --now dnsmasq
sudo systemctl start tftp;sudo systemctl enable --now tftp
#firewall-cmd --add-service=tftp --permanent 
#firewall-cmd --reload

}

# Configure Apache Web Server
websetup() {

echo "$bld$grn Configuring Apache Web Server $nor"
sudo yum install -y httpd
sudo sed -i 's/Listen 80/Listen 0.0.0.0:8080/' /etc/httpd/conf/httpd.conf
sudo setsebool -P httpd_read_user_content 1
sudo systemctl start httpd;sudo systemctl enable --now httpd
#firewall-cmd --add-port=8080/tcp --permanent
#firewall-cmd --reload
}

# Configure HAProxy
lbsetup() {

echo "$bld$grn Configuring HAProxy Server $nor"
sudo yum install net-tools nmstate haproxy -y

# As apiVIPs & ingressVIPs need different ip, create secondary IP in same server (Haproxy)
sudo ifconfig eth0:0 $SUBNET.$JIP2 netmask 255.255.255.0
cat <<EOF > ifcfg-eth0:0
DEVICE=eth0:0
BOOTPROTO=static
IPADDR=$SUBNET.$JIP2
NETMASK=255.255.255.0
ONBOOT=yes
PEERDNS=no
EOF

sudo mv ifcfg-eth0:0 /etc/sysconfig/network-scripts/ifcfg-eth0:0
sudo chown root:root /etc/sysconfig/network-scripts/ifcfg-eth0:0

cat <<EOF > haproxy.cfg
# Global settings
#---------------------------------------------------------------------
global
    maxconn     20000
    log         /dev/log local0 info
    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    user        haproxy
    group       haproxy
    daemon
    # turn on stats unix socket
    stats socket /var/lib/haproxy/stats
#---------------------------------------------------------------------
# common defaults that all the 'listen' and 'backend' sections will
# use if not designated in their block
#---------------------------------------------------------------------
defaults
    log                     global
    mode                    http
    option                  httplog
    option                  dontlognull
    option http-server-close
    option redispatch
    option forwardfor       except 127.0.0.0/8
    retries                 3
    maxconn                 20000
    timeout http-request    10000ms
    timeout http-keep-alive 10000ms
    timeout check           10000ms
    timeout connect         40000ms
    timeout client          300000ms
    timeout server          300000ms
    timeout queue           50000ms

# Enable HAProxy stats
listen stats
    bind :9000
    stats uri /stats
    stats refresh 10000ms

# Kube API Server
frontend k8s_api_frontend
    bind :6443
    default_backend k8s_api_backend
    mode tcp

backend k8s_api_backend
    mode tcp
    balance source
    server      $BOOT $BOOTIP:6443 check
    server      $MAS1 $MAS1IP:6443 check
    server      $MAS2 $MAS2IP:6443 check
    server      $MAS3 $MAS3IP:6443 check

# OCP Machine Config Server
frontend ocp_machine_config_server_frontend
    mode tcp
    bind :22623
    default_backend ocp_machine_config_server_backend

backend ocp_machine_config_server_backend
    mode tcp
    balance source
    server      $BOOT $BOOTIP:22623 check
    server      $MAS1 $MAS1IP:22623 check
    server      $MAS2 $MAS2IP:22623 check
    server      $MAS3 $MAS3IP:22623 check

# OCP Ingress - layer 4 tcp mode for each. Ingress Controller will handle layer 7.
frontend ocp_http_ingress_frontend
    bind :80
    default_backend ocp_http_ingress_backend
    mode tcp

backend ocp_http_ingress_backend
    balance source
    mode tcp
    server $MAS1 $MAS1IP:80 check
    server $MAS2 $MAS2IP:80 check
    server $MAS3 $MAS3IP:80 check
    server $INF1 $INF1IP:80 check
    server $INF2 $INF2IP:80 check

frontend ocp_https_ingress_frontend
    bind *:443
    default_backend ocp_https_ingress_backend
    mode tcp

backend ocp_https_ingress_backend
    mode tcp
    balance source
    server $MAS1 $MAS1IP:443 check
    server $MAS2 $MAS2IP:443 check
    server $MAS3 $MAS3IP:443 check
    server $INF1 $INF1IP:443 check
    server $INF2 $INF2IP:443 check

EOF

sudo mv haproxy.cfg /etc/haproxy/haproxy.cfg
sudo chown root:root /etc/haproxy/haproxy.cfg
sudo setsebool -P haproxy_connect_any 1
sudo systemctl start haproxy;sudo systemctl enable --now haproxy

#firewall-cmd --add-port=6443/tcp --permanent
#firewall-cmd --add-port=6443/tcp --permanent
#firewall-cmd --add-port=22623/tcp --permanent
#firewall-cmd --add-service=http --permanent
#firewall-cmd --add-service=https --permanent
#firewall-cmd --add-port=9000/tcp --permanent
#firewall-cmd --reload
}

# Configure NFS Server
nfssetup() {

echo "$bld$grn Configuring NFS Server $nor"
sudo yum install nfs-utils -y
sudo mkdir -p /shares/registry
sudo chown -R nobody:nobody /shares/registry
sudo chmod -R 777 /shares/registry

cat <<EOF > exports
/shares/registry  *(rw,sync,no_subtree_check,no_root_squash,no_all_squash,insecure,no_wdelay)
EOF

sudo mv exports /etc/exports
sudo chown root:root /etc/exports

sudo setsebool -P nfs_export_all_rw 1
sudo systemctl start nfs-server rpcbind nfs-mountd;sudo systemctl enable --now nfs-server rpcbind
sud exportfs -rav
sudo exportfs -v

#firewall-cmd --add-service mountd --permanent
#firewall-cmd --add-service rpc-bind --permanent
#firewall-cmd --add-service nfs --permanent
#firewall-cmd --reload

}

# Generate Manifests and Ignition files
manifes() {

echo "$bld$grn Generating Manifests and Ignition files $nor"
# Generate SSH Key
ssh-keygen -q -t rsa -N '' -f ~/.ssh/id_rsa <<<y >/dev/null 2>&1
PUBKEY=`cat ~/.ssh/id_rsa.pub`
echo $PUBKEY

sudo rm -rf /var/www/html/ocp4
sudo rm -rf ~/ocp-install
sudo mkdir /var/www/html/ocp4
mkdir ~/ocp-install

cat <<EOF > ~/ocp-install/install-config.yaml
apiVersion: v1
baseDomain: $DOMAIN
compute:
  - hyperthreading: Enabled
    name: worker
    replicas: 4
controlPlane:
  hyperthreading: Enabled
  name: master
  replicas: 3
metadata:
  name: $CTX # Cluster name
networking:
  machineNetwork:
    - cidr: $SUBNET.0/24
  clusterNetwork:
    - cidr: 10.128.0.0/14
      hostPrefix: 23
  networkType: OVNKubernetes
  serviceNetwork:
    - 172.30.0.0/16
platform:
  none: {}
#  baremetal:
#    apiVIPs:
#      - "$JUMPIP"
#    ingressVIPs:
#      - "$JUMPIP2"
fips: false
pullSecret: 'PULL_SECRET'  
sshKey: "ssh-rsa PUBLIC_SSH_KEY"  

EOF

sed -i "s%PULL_SECRET%$PULLSECRET%" ~/ocp-install/install-config.yaml
sed -i "s%ssh-rsa PUBLIC_SSH_KEY%$PUBKEY%" ~/ocp-install/install-config.yaml
cp ~/ocp-install/install-config.yaml ~/ocp-install/install-config.yaml-bak
cp ~/ocp-install/install-config.yaml install-config.yaml

sudo cp rhcos-live.x86_64.iso /var/www/html/ocp4/rhcos-live.x86_64.iso
sudo cp rhcos-kernel /var/www/html/ocp4/rhcos-kernel
sudo cp rhcos-initramfs.img /var/www/html/ocp4/rhcos-initramfs.img
sudo cp rhcos-rootfs.img /var/www/html/ocp4/rhcos-rootfs.img

sudo openshift-install create manifests --dir ~/ocp-install/
sed -i 's/mastersSchedulable: true/mastersSchedulable: false/' ~/ocp-install/manifests/cluster-scheduler-02-config.yml
sudo openshift-install create ignition-configs --dir ~/ocp-install/
sudo cp -R ~/ocp-install/*.ign /var/www/html/ocp4

sudo chcon -R -t httpd_sys_content_t /var/www/html/ocp4/
sudo chown -R apache: /var/www/html/ocp4/
sudo chmod 755 /var/www/html/ocp4/

curl localhost:8080/ocp4/
}

# Install ALL
setupall () {

toolsetup
tftpsetup
websetup
lbsetup
nfssetup
manifes
}

case "$1" in
    'toolsetup')
            toolsetup
            ;;
    'tftpsetup')
            tftpsetup
            ;;
    'websetup')
            websetup
            ;;
    'lbsetup')
            lbsetup
            ;;
    'nfssetup')
            nfssetup
            ;;
    'manifes')
            manifes
            ;;
    'setupall')
            setupall
            ;;
    *)
            clear
            echo
            echo "$bld$blu Openshift Jumphost (LB,NFS,TFTP,WEB) host setup script $nor"
            echo
            echo "$bld$grn Usage: $0 { toolsetup | tftpsetup | websetup | lbsetup | nfssetup | manifes | setupall } $nor"
            echo
            exit 1
            ;;
esac

exit 0
