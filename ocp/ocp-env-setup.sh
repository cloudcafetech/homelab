#! /bin/bash
# Openshift Jumphost (Mirror Registry,DNS,WEB,LB,NFS,Sushy) setup script

HIP=`ip -o -4 addr list br0 | grep -v secondary | awk '{print $4}' | cut -d/ -f1`
systemctl stop firewalld; systemctl disable firewalld

PULLSECPATH=/root/pull-secret
DOMAIN=pkar.tech

SNO_ACM=192.168.1.135
SNO_ZTP=192.168.1.110
SNO_SA=192.168.1.120
SNO_HCP=192.168.1.130

MAS1=ocp-m1
MAS2=ocp-m2
MAS3=ocp-m3
MAS1IP=192.168.1.151
MAS2IP=192.168.1.152
MAS3IP=192.168.1.153

NFSLOCATION=/home/sno/nfsshare

REGPASS=Admin2675
REGURL=registry.$DOMAIN
AUTH=`echo -n 'admin:$REGPASS'|base64 -w0`

if [ ! -f /root/config.json ]; then
cat << EOF > /root/config.json
"$REGURL:8443": {
   "auth": "$AUTH",
   "email": "cloudcafe@gmail.com"
}
EOF
fi

if [ ! -f /etc/named.conf ]; then
cat << EOF > /etc/named.conf
options {
        listen-on port 53 { $HIP;127.0.0.1; };
        listen-on-v6 port 53 { ::1; };
        directory       "/var/named";
        dump-file       "/var/named/data/cache_dump.db";
        statistics-file "/var/named/data/named_stats.txt";
        memstatistics-file "/var/named/data/named_mem_stats.txt";
        secroots-file   "/var/named/data/named.secroots";
        recursing-file  "/var/named/data/named.recursing";
        allow-query     { localhost; 192.168.1.0/24;};

        /*
         - If you are building an AUTHORITATIVE DNS server, do NOT enable recursion.
         - If you are building a RECURSIVE (caching) DNS server, you need to enable
           recursion.
         - If your recursive DNS server has a public IP address, you MUST enable access
           control to limit queries to your legitimate users. Failing to do so will
           cause your server to become part of large scale DNS amplification
           attacks. Implementing BCP38 within your network would greatly
           reduce such attack surface
        */
        recursion yes;

        dnssec-validation yes;

        managed-keys-directory "/var/named/dynamic";
        geoip-directory "/usr/share/GeoIP";

        pid-file "/run/named/named.pid";
        session-keyfile "/run/named/session.key";

        /* https://fedoraproject.org/wiki/Changes/CryptoPolicy */
        include "/etc/crypto-policies/back-ends/bind.config";
};

logging {
        channel default_debug {
                file "data/named.run";
                severity dynamic;
        };
};

zone "." IN {
        type hint;
        file "named.ca";
};

zone "$DOMAIN" IN {
    type master;
    file "/var/named/$DOMAIN.zone";
};

include "/etc/named.rfc1912.zones";
include "/etc/named.root.key";
EOF
fi

#### ALL Functions ####

# Setup Mirror Registry
mirrorreg() {

 # Check pull-secret
 if [ ! -f /root/pull-secret ]; then
   echo "pull-secret file not found under /root folder, PLEASE download pull secret from RedHat Console & save in /root folder"
   exit
 fi

 # Install required packages
 wget https://github.com/fullstorydev/grpcurl/releases/download/v1.9.3/grpcurl_1.9.3_linux_amd64.rpm
 mv grpcurl_1.9.3_linux_amd64.rpm grpcurl.rpm
 yum install podman openssl jq grpcurl.rpm -y
 rm grpcurl.rpm
 
 echo "Setup Mirror Registry ..."

 if [ ! -d "/root/mirror-registry" ]; then
 mkdir -p /root/mirror-registry/tools
 mkdir /root/.docker
 cd /root/mirror-registry/tools

 wget https://mirror.openshift.com/pub/cgw/mirror-registry/latest/mirror-registry-amd64.tar.gz
 wget https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/latest/oc-mirror.rhel9.tar.gz
 wget https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-linux-amd64-rhel9.tar.gz

 tar xvzpf mirror-registry-amd64.tar.gz
 tar xvzpf oc-mirror.rhel9.tar.gz
 tar xvzpf openshift-client-linux-amd64-rhel9.tar.gz
 chmod 755 oc-mirror
 cp oc kubectl oc-mirror /usr/local/bin
 rm -rf *.tar.gz README.md
fi

 ./mirror-registry install \
  --quayHostname $REGURL \
  --quayRoot /root/mirror-registry/quay-config \
  --quayStorage /root/mirror-registry/storage \
  --sqliteStorage /root/mirror-registry/sqlite-storage \
  --initUser admin --initPassword $REGPASS

 # Trust root certificate of Quay registry
 cp /root/mirror-registry/quay-config/quay-rootCA/rootCA.pem /etc/pki/ca-trust/source/anchors/
 update-ca-trust extract

 cat $PULLSECPATH | jq . > pull-secret.json
 cat pull-secret.json |jq ".auths += {`cat /root/config.json`}"|tr -d '[:space:]' > /root/.docker/config.json

 # Verify
 more /root/.docker/config.json | jq '.auths | keys[]'
 podman login -u admin -p $REGPASS $REGURL:8443

 # Merge
 cp /root/.docker/config.json /home/cloudcafe/merge-pull-secret
 chown cloudcafe:cloudcafe /home/cloudcafe/merge-pull-secret

 # Get Certificate chain
 echo | openssl s_client -connect $REGURL:8443 -showcerts </dev/null | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' > certificate_chain.pem
}

# Setup DNS
dnssetup() {
 if [[ -n $(netstat -tunpl | grep 53) ]]; then echo "DNS Port (53) used, DO NOT RUN dnssetup"; exit; fi
 yum install bind bind-utils -y

cat << EOF > /var/named/$DOMAIN.zone

$TTL 86400
@   IN  SOA ns1.$DOMAIN. admin.$DOMAIN. (
        2025040301 3600 1800 1209600 86400 )

    IN NS ns1.$DOMAIN.

; DNS Server
ns1.$DOMAIN.           	IN A $HIP

; SNO ACM cluster
api.sno-acm.$DOMAIN.    	IN A $SNO_ACM
api-int.sno-acm.$DOMAIN.	IN A $SNO_ACM
*.apps.sno-acm.$DOMAIN. 	IN A $SNO_ACM

; SNO ZTP cluster
api.sno-ztp.$DOMAIN.    	IN A $SNO_ZTP
api-int.sno-ztp.$DOMAIN.	IN A $SNO_ZTP
*.apps.sno-ztp.$DOMAIN. 	IN A $SNO_ZTP

; SNO Stand Alone cluster
api.sno-sa.$DOMAIN.    	IN A $SNO_SA
api-int.sno-sa.$DOMAIN.	IN A $SNO_SA
*.apps.sno-sa.$DOMAIN. 	IN A $SNO_SA

; SNO HCP cluster
api.sno-hcp.$DOMAIN.    	IN A $SNO_HCP
api-int.sno-hcp.$DOMAIN.	IN A $SNO_HCP
*.apps.sno-hcp.$DOMAIN. 	IN A $SNO_HCP

; OCP HA cluster entries
api.ocp-ha.$DOMAIN.            IN A 192.168.1.159
api-int.ocp-ha.$DOMAIN.        IN A 192.168.1.159
*.apps.ocp-ha.$DOMAIN.         IN A 192.168.1.159

ocp-m1.$DOMAIN.                IN A 192.168.1.151
ocp-m2.$DOMAIN.                IN A 192.168.1.152
ocp-m3.$DOMAIN.                IN A 192.168.1.153
EOF

systemctl start named;systemctl enable --now named
systemctl restart named

}

# Setup Web Server
websetup() {
 yum install -y httpd
 systemctl enable --now httpd
 sed -i 's/Listen 80/Listen 0.0.0.0:8080/' /etc/httpd/conf/httpd.conf
 mkdir /var/www/html/ocp
 systemctl restart httpd
 #systemctl status httpd

 curl https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.18/4.18.30/rhcos-4.18.30-x86_64-live-rootfs.x86_64.img -o /var/www/html/ocp/rhcos-4.18.30-x86_64-live-rootfs.x86_64.img
 curl https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.18/4.18.30/rhcos-4.18.30-x86_64-live.x86_64.iso -o /var/www/html/ocp/rhcos-4.18.30-x86_64-live.x86_64.iso

 # Verify
 curl http://$HIP:8080/ocp/rhcos-4.18.30-x86_64-live-rootfs.x86_64.img
 curl http://$HIP:8080/ocp/rhcos-4.18.30-x86_64-live.x86_64.iso
}

# Setup Load Balancer
lbsetup() {
yum install net-tools nmstate haproxy -y

cat <<EOF > /etc/haproxy/haproxy.cfg
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

EOF

setsebool -P haproxy_connect_any 1
systemctl start haproxy;systemctl enable --now haproxy
}

# Setup NFS Server
nfssetup() {
 yum install nfs-utils -y
 mkdir -p $NFSLOCATION
 chown -R nobody:nobody $NFSLOCATION
 chmod -R 777 $NFSLOCATION
 echo "$$NFSLOCATION *(rw,sync,no_subtree_check,no_root_squash,no_all_squash,insecure,no_wdelay)" >> /etc/exports
 setsebool -P nfs_export_all_rw 1
 systemctl start nfs-server rpcbind nfs-mountd;systemctl enable --now nfs-server rpcbind
 exportfs -rav
 exportfs -v
}

# Setup Sushy Emulator
sushysetup()
{
 yum install podman -y
 mkdir -p /etc/sushy/
cat << EOF > /etc/sushy/sushy-emulator.conf
SUSHY_EMULATOR_LISTEN_IP = u'0.0.0.0'
SUSHY_EMULATOR_LISTEN_PORT = 8000
SUSHY_EMULATOR_SSL_CERT = None
SUSHY_EMULATOR_SSL_KEY = None
SUSHY_EMULATOR_OS_CLOUD = None
SUSHY_EMULATOR_LIBVIRT_URI = u'qemu:///system'
SUSHY_EMULATOR_IGNORE_BOOT_DEVICE = True
SUSHY_EMULATOR_BOOT_LOADER_MAP = {
    u'UEFI': {
        u'x86_64': u'/usr/share/OVMF/OVMF_CODE.secboot.fd'
    },
    u'Legacy': {
        u'x86_64': None
    }
}
EOF

 export SUSHY_TOOLS_IMAGE=${SUSHY_TOOLS_IMAGE:-"quay.io/metal3-io/sushy-tools"}
 podman create --net host --privileged --name sushy-emulator -v "/etc/sushy":/etc/sushy -v "/var/run/libvirt":/var/run/libvirt "${SUSHY_TOOLS_IMAGE}" sushy-emulator -i :: -p 8000 --config /etc/sushy/sushy-emulator.conf
 podman start sushy-emulator
 firewall-cmd --add-port=8000/tcp

 # First, use Podman to create a systemd unit
 sh -c 'podman generate systemd --restart-policy=always -t 1 sushy-emulator > /etc/systemd/system/sushy-emulator.service'
 systemctl daemon-reload

 # Next, use systemd to start and enable the Sushy-Emulator
 systemctl restart sushy-emulator.service
 systemctl enable sushy-emulator.service
 systemctl status sushy-emulator.service
}

case "$1" in
    'mirrorreg')
            mirrorreg
            ;;
    'dnssetup')
            dnssetup
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
    'sushysetup')
            sushysetup
            ;;
    *)
            clear
            echo
            echo "Openshift Jumphost (Mirror Registry,DNS,WEB,LB,NFS,Sushy) setup script"
            echo
            echo "Usage: $0 { mirrorreg | dnssetup | websetup | lbsetup | nfssetup | sushysetup } $nor"
            echo
            exit 1
            ;;
esac

exit 0
