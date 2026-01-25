## Openshift HA Cluster using Mirror Registry

- Download tools

```
dnf install /usr/bin/nmstatectl -y
wget https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/4.18.30/openshift-install-linux.tar.gz
wget https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/4.18.30/openshift-client-linux.tar.gz
tar zxvf openshift-install-linux.tar.gz
tar zxvf openshift-client-linux.tar.gz
mv oc /usr/local/bin/
mv kubectl /usr/local/bin/
rm openshift-install-linux.tar.gz openshift-client-linux.tar.gz README.md
```

- Transfer merged-pull-secret file (/home/cloudcafe/merge-pull-secret) from Mirror Registry server

> TIPS: Cluster Build in disconnected network from Mirror Registry, pull secret should contains credentials for both Mirror Registry and official Red Hat Registries.

```
scp cloudcafe@192.168.1.150:/home/cloudcafe/merge-pull-secret .
cp merge-pull-secret pull-secret
```

- DNS Setup

> Modify script as per requirement

```
wget https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/ocp/ocp-env-setup.sh
chmod 755 ocp-env-setup.sh
vi ocp-env-setup.sh
```
  
- Generate Agent and Install Config

```
REGURL=mirror-registry.pkar.tech
CLUSTER=ocp-ha

ssh-keygen -t rsa -N '' -f id_rsa
PULLSECRET=`cat /root/pull-secret` 
SSHKEY=`cat id_rsa.pub`

MAS1IP=192.168.1.151
MAS1MAC=52:54:00:42:a4:51

MAS2IP=192.168.1.152
MAS2MAC=52:54:00:42:a4:52

MAS3IP=192.168.1.153
MAS3MAC=52:54:00:42:a4:53

DNS=192.168.1.159
DOMAIN=pkar.tech
GW=192.168.1.1

mkdir ocp418
mkdir ocp418-backup

cat << EOF > agent-config.yaml
apiVersion: v1beta1
kind: AgentConfig
metadata:
  name: $CLUSTER
rendezvousIP: $MAS1IP
hosts:
- hostname: ocp-m1
  interfaces:
  - name: enp1s0
    macAddress: $MAS1MAC
  rootDeviceHints:
    deviceName: /dev/vda
  networkConfig:
    interfaces:
    - name: enp1s0
      type: ethernet
      state: up
      mac-address: $MAS1MAC
      ipv4:
        enabled: true
        address:
        - ip: $MAS1IP
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
- hostname: ocp-m2
  interfaces:
  - name: enp1s0
    macAddress: $MAS2MAC
  rootDeviceHints:
    deviceName: /dev/vda
  networkConfig:
    interfaces:
    - name: enp1s0
      type: ethernet
      state: up
      mac-address: $MAS2MAC
      ipv4:
        enabled: true
        address:
        - ip: $MAS2IP
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
- hostname: ocp-m3
  interfaces:
  - name: enp1s0
    macAddress: $MAS3MAC
  rootDeviceHints:
    deviceName: /dev/vda
  networkConfig:
    interfaces:
    - name: enp1s0
      type: ethernet
      state: up
      mac-address: $MAS3MAC
      ipv4:
        enabled: true
        address:
        - ip: $MAS3IP
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
  replicas: 3
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

echo | openssl s_client -connect $REGURL:8443 -showcerts </dev/null | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' > certificate_chain.pem
sed -i 's/^/  /' certificate_chain.pem
cat certificate_chain.pem >> install-config.yaml

cp *-config.yaml ocp418-backup/
cp *-config.yaml ocp418/
rm -rf certificate_chain.pem
```

- Create iso

```
./openshift-install --dir=ocp418 agent create image --log-level=debug 
```

- Prapare ISO to other host boot

```
cp ocp418/agent.x86_64.iso /home/cloudcafe/
chown cloudcafe:cloudcafe /home/cloudcafe/agent.x86_64.iso
ll /home/cloudcafe/
````

- Create VM using ISO on Host-01

```
MAS1MAC=52:54:00:42:a4:51

mkdir -p /home/sno/ocp-ha
cd /home/sno/ocp-ha
scp cloudcafe@192.168.1.159:/home/cloudcafe/agent.x86_64.iso .
chown root:root agent.x86_64.iso
qemu-img create -f qcow2 /home/sno/ocp-ha/ocp-m1-os-disk.qcow2 100G

virt-install \
  --name=ocp-m1 \
  --ram=16384 \
  --vcpus=10 \
  --cpu host-passthrough \
  --os-variant=rhel8.0 \
  --noreboot \
  --events on_reboot=restart \
  --noautoconsole \
  --import \
  --cdrom /home/sno/ocp-ha/ocp418/agent.x86_64.iso \
  --disk path=/home/sno/ocp-ha/ocp-m1-os-disk.qcow2,size=100 \
  --network network=host-bridge,mac=$MAS1MAC \
  --graphics vnc,listen=0.0.0.0,port=5951,password=pkar2675

sleep 10
virsh list --all
```

- Create VM using ISO on Host-02

```
MAS2MAC=52:54:00:42:a4:52

mkdir -p /home/sno/ocp-ha
cd /home/sno/ocp-ha
scp cloudcafe@192.168.1.159:/home/cloudcafe/agent.x86_64.iso .
chown root:root agent.x86_64.iso
qemu-img create -f qcow2 /home/sno/ocp-ha/ocp-m2-os-disk.qcow2 100G

virt-install \
  --name=ocp-m2 \
  --ram=16384 \
  --vcpus=10 \
  --cpu host-passthrough \
  --os-variant=rhel8.0 \
  --noreboot \
  --events on_reboot=restart \
  --noautoconsole \
  --import \
  --cdrom /home/sno/ocp-ha/agent.x86_64.iso \
  --disk path=/home/sno/ocp-ha/ocp-m2-os-disk.qcow2,size=100 \
  --network network=host-bridge,mac=$MAS2MAC \
  --graphics vnc,listen=0.0.0.0,port=5952,password=pkar2675

sleep 10
virsh list --all
```

- Create VM using ISO on Host-03

```
MAS3MAC=52:54:00:42:a4:53

mkdir -p /home/sno/ocp-ha
cd /home/sno/ocp-ha
scp cloudcafe@192.168.1.159:/home/cloudcafe/agent.x86_64.iso .
chown root:root agent.x86_64.iso
qemu-img create -f qcow2 /home/sno/ocp-ha/ocp-m3-os-disk.qcow2 100G

virt-install \
  --name=ocp-m3 \
  --ram=16384 \
  --vcpus=10 \
  --cpu host-passthrough \
  --os-variant=rhel8.0 \
  --noreboot \
  --events on_reboot=restart \
  --noautoconsole \
  --import \
  --cdrom /home/sno/ocp-ha/agent.x86_64.iso \
  --disk path=/home/sno/ocp-ha/ocp-m3-os-disk.qcow2,size=100 \
  --network network=host-bridge,mac=$MAS3MAC \
  --graphics vnc,listen=0.0.0.0,port=5953,password=pkar2675

sleep 10
virsh list --all
```

### POST Installation

- Monitor install boostrapping

```openshift-install --dir=ocp418 agent wait-for bootstrap-complete --log-level=debug```

- Verify install complete

```openshift-install --dir=ocp418 agent wait-for install-complete --log-level=debug```

- Login Cluster

```
export KUBECONFIG=/home/sno/tools/ocp418/auth/kubeconfig
oc get no
oc get co
oc get po -A | grep -Ev "Running|Completed"
```

- Disable default OperatorHub Catalog Sources and create disconnected Operator Catalog

```
oc patch OperatorHub cluster --type merge --patch '{"spec":{"disableAllDefaultSources":true}}'

oc get catalogsource --all-namespaces

REGURL=mirror-registry.pkar.tech

cat << EOF > redhat-operator-cs.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: redhat-operators
  namespace: openshift-marketplace
spec:
  image: $REGURL:8443/ocp/redhat/redhat-operator-index:v4.18
  sourceType: grpc
status: {}
EOF

oc apply -f redhat-operator-cs.yaml
```
