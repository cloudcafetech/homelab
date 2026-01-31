#!/bin/bash
# Single Node OpenShift (SNO) in KVM

### Variable

VM_CREATE=Y
REGURL=mirror-registry.pkar.tech
PULLSECPATH=/root/pull-secret
VER=4.18.30
DNS=192.168.0.159
DOMAIN=pkar.tech
GW=192.168.1.1

# ACM
CLUSTER=sno-acm
MEM=28384
IP=192.168.0.135
MAC=52:54:00:42:a4:35
VNCPORT=5935

# Standalone
#CLUSTER=sno-sa
#MEM=16384
#IP=192.168.0.120
#MAC=52:54:00:42:a4:20
#VNCPORT=5920

echo - Install necessary packages and create ssh key

if [ ! -f /root/pull-secret ]; then
 echo "pull-secret file not found under /root folder, PLEASE download pull secret from RedHat Console & save in /root folder"
 exit
fi

INSTDIR=/home/sno/$CLUSTER
rm -rf $INSTDIR
mkdir $INSTDIR
cd $INSTDIR
mkdir ocp$VER
mkdir ocp$VER-backup
ssh-keygen -t rsa -N '' -f id_rsa
PULLSECRET=`cat $PULLSECPATH`
SSHKEY=`cat id_rsa.pub`

command -v podman >/dev/null 2>&1 || { echo - podman was not found; yum install -y podman > /dev/null 2>&1; }
command -v nc >/dev/null 2>&1 || { echo - nc was not found; yum install -y nc > /dev/null 2>&1; }
command -v nmstatectl >/dev/null 2>&1 || { echo - nmstatectl was not found; dnf install /usr/bin/nmstatectl -y > /dev/null 2>&1; }

if ! command -v openshift-install &>/dev/null; then
    wget https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/$VER/openshift-install-linux.tar.gz
    tar zxvf openshift-install-linux.tar.gz
    mv openshift-install /usr/local/bin/
    rm -rf openshift-install-linux.tar.gz README.md LICENSE
fi

if ! command -v oc &>/dev/null; then
    wget https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/$VER/openshift-client-linux.tar.gz
    tar zxvf openshift-client-linux.tar.gz
    mv oc /usr/local/bin/
    mv kubectl /usr/local/bin/
    rm -rf openshift-client-linux.tar.gz README.md LICENSE
fi

echo - Create Agent config

cat << EOF > agent-config.yaml
apiVersion: v1beta1
kind: AgentConfig
metadata:
  name: $CLUSTER
rendezvousIP: $IP
hosts:
  - hostname: $CLUSTER
    interfaces:
      - name: enp1s0
        macAddress: $MAC
    rootDeviceHints:
      deviceName: /dev/vda
    networkConfig:
      interfaces:
        - name: enp1s0
          type: ethernet
          state: up
          mac-address: $MAC
          ipv4:
            enabled: true
            address:
              - ip: $IP
                prefix-length: 24
            dhcp: false
      dns-resolver:
        config:
          search:
            - $DOMAIN
          server:
            - $DNS
            - $GW
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: $GW
            next-hop-interface: enp1s0
            table-id: 254
EOF

echo - Create Install config

cat << EOF > install-config.yaml
apiVersion: v1
baseDomain: $DOMAIN
compute:
- architecture: amd64
  name: worker
  replicas: 0
controlPlane:
  architecture: amd64
  name: master
  platform:
  replicas: 1
metadata:
  name: $CLUSTER
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 192.168.1.0/24
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  none: {}
pullSecret: '$PULLSECRET'
sshKey: $SSHKEY

EOF

cat << EOF > ids.txt
imageDigestSources:
- mirrors:
  - $REGURL:8443/ocp/openshift/release
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
- mirrors:
  - $REGURL:8443/ocp/openshift/release-images
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - $REGURL:8443/ocp
  source: registry.redhat.io
- mirrors:
  - $REGURL:8443/ocp/k8s-staging-sig-storage
  source: gcr.io/k8s-staging-sig-storage
additionalTrustBundle: |

EOF

echo - Checking Mirror Registry

if [[ ! -z "$REGURL" ]]; then
  if nc -z -w5 $REGURL 8443; then
    echo - Genrating Certificate Chain and merge with install-config
    echo | openssl s_client -connect $REGURL:8443 -showcerts </dev/null | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' > certificate_chain.pem
    sed -i 's/^/  /' certificate_chain.pem
    cat ids.txt >> install-config.yaml
    cat certificate_chain.pem >> install-config.yaml
  else
    echo "Mirror registry not responding, building cluster without it!"
  fi
fi

cp *-config.yaml ocp$VER-backup/
cp *-config.yaml ocp$VER/

echo - Generating ISO .. it will take time !!

openshift-install --dir=ocp$VER agent create image --log-level=debug

# Checking if VM Launch
[[ "$VM_CREATE" != "Y" ]] && exit

echo - Create VM using ISO

qemu-img create -f qcow2 $INSTDIR/$CLUSTER-os-disk.qcow2 100G

virt-install \
  --name=$CLUSTER \
  --ram=$MEM \
  --vcpus=12 \
  --cpu host-passthrough \
  --os-variant=rhel8.0 \
  --noreboot \
  --events on_reboot=restart \
  --noautoconsole \
  --import \
  --cdrom $INSTDIR/ocp$VER/agent.x86_64.iso \
  --disk path=$INSTDIR/$CLUSTER-os-disk.qcow2,size=100 \
  --network network=host-bridge,mac=$MAC \
  --graphics vnc,listen=0.0.0.0,port=$VNCPORT,password=pkar2675

sleep 10
virsh list --all

echo "Post Install follow!! ( https://github.com/cloudcafetech/homelab/blob/main/ocp/SNO-from-MirrorRegistry.md#post-installation )"
