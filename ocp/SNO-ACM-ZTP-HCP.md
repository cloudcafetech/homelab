# Setup SNO ACM ZTP HCP


### SSH KEYGEN Setup

```ssh-keygen -f ./id_rsa -t rsa -N ''```

### kubeadmin user password change

```
PASS=463yz-I2tzq-DZe9f-7GfuK
ASD=`htpasswd -bnBC 10 "" $PASS | tr -d ':\n'`
EPASS=`echo "$ASD" | base64 -w0`
oc patch secret/kubeadmin -n kube-system -p '{"data":{"kubeadmin": "'$EPASS'"}}'
```

### DNS setup using DNSMASQ

```
yum install dnsmasq -y
cp /etc/dnsmasq.conf /etc/dnsmasq.conf.orig

systemctl start dnsmasq
systemctl enable dnsmasq
systemctl status dnsmasq

cat << "EOF" > /etc/dnsmasq.conf
listen-address=127.0.0.1,192.168.1.2
interface=eth0

# Google nameservers
server=8.8.8.8
server=8.8.4.4

# Airtel nameservers
server=192.168.1.1

# DOMAIN
domain=pkar.tech

# Cluster SNO ACM (sno-acm-ts) records
address=/*.apps.sno-acm-ts.pkar.tech/192.168.1.14
host-record=api.sno-acm-ts.pkar.tech,192.168.1.14
host-record=api-int.sno-acm-ts.pkar.tech,192.168.1.14

# Cluster SNO ZTP (sno-ztp-tc) records
address=/*.apps.sno-ztp-tc.pkar.tech/192.168.1.15
host-record=api.sno-ztp-tc.pkar.tech,192.168.1.15
host-record=api-int.sno-ztp-tc.pkar.tech,192.168.1.15
EOF

dnsmasq --test
systemctl restart dnsmasq
```

### Create Bridge network on CentOS host

- Create Bridge Interface

```
nmcli connection add type bridge autoconnect yes con-name br0 ifname br0
nmcli connection modify br0 ipv4.addresses 192.168.1.160/24 ipv4.gateway 192.168.1.1 ipv4.dns 8.8.8.8 ipv4.method manual
nmcli connection add type ethernet slave-type bridge autoconnect yes con-name bridge-port-eth0 ifname eno2 master br0
nmcli connection down eno2 && nmcli connection up br0

ip addr show br0
ping google.com
```

- Add Bridge network on KVM

```
cat << "EOF" > host-bridge.xml
<network>
  <name>host-bridge</name>
  <forward mode="bridge"/>
  <bridge name="br0"/>
</network>
EOF
virsh net-define host-bridge.xml
virsh net-start host-bridge
virsh net-autostart host-bridge
```

### Install XRDP

```
dnf install epel-release -y
dnf -y install xrdp
systemctl enable xrdp --now

# How to allow RDP through Firewalld
#firewall-cmd --add-port=3389/tcp
#firewall-cmd --runtime-to-permanent
```

### Download oc tools

```
mkdir ocp-tools
cd ocp-tools
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable-4.19/openshift-client-linux.tar.gz
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable-4.19/openshift-install-linux.tar.gz
chmod 777 *
tar xvf openshift-install-linux.tar.gz openshift-install
tar xvf openshift-client-linux.tar.gz oc kubectl
cp oc kubectl /usr/local/bin
```

### KVM VM create for SNO

```
qemu-img create -f qcow2 /home/sno/ocp-acm/sno-acm-ts.qcow2 120G

virt-install \
  --name=sno-acm-ts \
  --ram=28384 \
  --vcpus=12 \
  --cpu host-passthrough \
  --os-type linux \
  --os-variant=rhel8.0 \
  --noreboot \
  --events on_reboot=restart \
  --noautoconsole \
  --import \
  --cdrom /home/sno/ocp-acm/sno-acm-ts.iso \
  --disk path=/home/sno/ocp-acm/sno-acm-ts.qcow2,size=120 \
  --network network=host-bridge \
  --graphics vnc,listen=0.0.0.0,port=5975,password=pkar2675
```

### KVM Commands

```
virsh net-list
virsh list --all
virsh shutdown sno-acm-ts
virsh destroy sno-acm-ts
virsh domifaddr sno-acm-ts
virsh dominfo sno-acm-ts
virsh setmem sno-acm-ts 27G --config
virsh undefine sno-acm-ts --remove-all-storage
virsh domifaddr sno-acm-ts --source arp
```

### NFS setup

```
yum install -y nfs-utils
systemctl enable rpcbind
systemctl enable nfs-server
systemctl start rpcbind
systemctl start nfs-server
mkdir /home/sno/ocp-acm/nfsshare
chmod -R 755 /home/sno/ocp-acm/nfsshare

echo "/home/sno/ocp-acm/nfsshare *(rw,sync,no_root_squash,no_subtree_check,insecure)" >> /etc/exports

systemctl restart nfs-server
```

### NFS Storage Setup for OCP

```
NFSRV=192.168.1.160
NFSMOUNT=/home/sno/ocp-acm/nfsshare

mkdir nfsstorage
cd nfsstorage

wget https://raw.githubusercontent.com/cloudcafetech/kubesetup/master/nfs-storage/nfs-rbac.yaml
wget https://raw.githubusercontent.com/cloudcafetech/kubesetup/master/nfs-storage/nfs-deployment.yaml
wget https://raw.githubusercontent.com/cloudcafetech/kubesetup/master/nfs-storage/kubenfs-storage-class.yaml

sed -i "s/10.128.0.9/$NFSRV/g" nfs-deployment.yaml
sed -i "s|/root/nfs/kubedata|$NFSMOUNT|g" nfs-deployment.yaml

oc new-project kubenfs
oc create -f nfs-rbac.yaml
oc adm policy add-scc-to-user hostmount-anyuid system:serviceaccount:kubenfs:nfs-client-provisioner
oc create -f nfs-deployment.yaml -f kubenfs-storage-class.yaml -n kubenfs
#oc patch storageclass managed-nfs-storage -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

```

### Setup ZTP in OCP ACM

- Enable SiteConfig Operator

```
oc get multiclusterhubs.operator.open-cluster-management.io multiclusterhub -n open-cluster-management -o yaml | grep siteconfig -B2 -A2```
oc patch multiclusterhubs.operator.open-cluster-management.io multiclusterhub -n open-cluster-management --type json --patch '[{"op": "add", "path":"/spec/overrides/components/-", "value": {"name":"siteconfig","enabled": true}}]'
```

- Verify the operator pod is running

```oc get po -n open-cluster-management | grep siteconfig```

- Check for default install template

```oc get cm -n open-cluster-management | grep templates```

- Check for the baremetalhost CRD

```oc get crd | grep baremetalhost```

- Check for the Provisioning Resource

```oc get provisioning```

- If it exists then patch it with

```oc patch provisioning provisioning-configuration --type merge -p '{"spec":{"watchAllNamespaces": true }}'```

- If it does not exist then create

```
cat << "EOF" > provisioning.yaml
apiVersion: metal3.io/v1alpha1
kind: Provisioning
metadata:
  name: provisioning-configuration
spec:
  provisioningNetwork: "Disabled"
  watchAllNamespaces: true
EOF

oc create -f provisioning.yaml
oc get provisioning
```

- Create AgentServiceConfig

```
cat << "EOF" > agentserviceconfig.yaml
apiVersion: agent-install.openshift.io/v1beta1
kind: AgentServiceConfig
metadata:
  name: agent
spec:
  databaseStorage:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 10Gi
  filesystemStorage:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 30Gi
  imageStorage:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 30Gi
  osImages:
    - cpuArchitecture: x86_64
      openshiftVersion: '4.17'
      rootFSUrl: 'https://mirror.openshift.com/pub/openshift-v4/x86_64/dependencies/rhcos/pre-release/latest-4.17/rhcos-4.17.0-ec.3-x86_64-live-rootfs.x86_64.img'
      url: 'https://mirror.openshift.com/pub/openshift-v4/x86_64/dependencies/rhcos/pre-release/latest-4.17/rhcos-4.17.0-ec.3-x86_64-live.x86_64.iso'
      version: 417.94.202410090854-0
    - cpuArchitecture: x86_64
      openshiftVersion: '4.18'
      rootFSUrl: 'https://mirror.openshift.com/pub/openshift-v4/x86_64/dependencies/rhcos/pre-release/4.18.0-rc.2/rhcos-4.18.0-rc.2-x86_64-live-rootfs.x86_64.img'
      url: 'https://mirror.openshift.com/pub/openshift-v4/x86_64/dependencies/rhcos/pre-release/4.18.0-rc.2/rhcos-4.18.0-rc.2-x86_64-live.x86_64.iso'
      version: 418.94.202411221729-0
EOF

oc apply -f agentserviceconfig.yaml
```

- Verify pod running

```oc get po -n multicluster-engine | grep assisted```

### Verify Hypershift enable 

```
oc get mce multiclusterengine -oyaml | grep hypershift -B2 -A2
oc get po -A | grep hypershift
```

### Setup MetalLB using yamls

- Download yamls

```
wget https://raw.githubusercontent.com/metallb/metallb/v0.10.2/manifests/namespace.yaml
wget https://raw.githubusercontent.com/metallb/metallb/v0.10.2/manifests/metallb.yaml
```

- Edit file metallb.yaml and remove spec.template.spec.securityContext from controller Deployment and the speaker DaemonSet.

```
Lines to be deleted:

securityContext:
  runAsNonRoot: true
  runAsUser: 65534
```

- Deploy MetalLB

```
oc create -f namespace.yaml
oc create -f metallb.yaml

oc adm policy add-scc-to-user privileged -n metallb-system -z speaker 

cat << "EOF" > metallb-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - 192.168.1.170-192.168.1.180
EOF
oc create -f metallb-config.yaml
```

### Using MetalLB operator

- First Install MetalLB Operator from Operator HUB

- Create a single instance of a MetalLB custom resource

```
cat << EOF | oc apply -f -
apiVersion: metallb.io/v1beta1
kind: MetalLB
metadata:
  name: metallb
  namespace: metallb-system
EOF
```

- Verify

``oc get po -n metallb-system```

- Configuring MetalLB address pools 

```
cat << "EOF" > metallb-ip-pool.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: ocp-hcp-ip-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.1.170-192.168.1.180
  autoAssign: true
  avoidBuggyIPs: false
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: ocp-hcp-l2-adv
  namespace: metallb-system
spec:
  ipAddressPools:
    - ocp-hcp-ip-pool
EOF

oc create -f metallb-ip-pool.yaml
```

- Verify address pool

```oc get ipaddresspool -A```

- Patch the RHACM Hub Application ingress controller to allow wildcard DNS routes

```
oc get ingresscontroller default -n openshift-ingress-operator | grep wildcardPolicy
oc patch ingresscontroller -n openshift-ingress-operator default --type=json -p '[{ "op": "add", "path": "/spec/routeAdmission", "value": {wildcardPolicy: "WildcardsAllowed"}}]'
```

- Download HCP CLI

```
oc get ConsoleCLIDownload hcp-cli-download -o json | jq -r ".spec" | grep amd64 | grep linux
wget --no-check-certificat `oc get ConsoleCLIDownload hcp-cli-download -o json | jq -r ".spec" | grep amd64 | grep linux | cut -d '"' -f4`
tar -zxvf hcp.tar.gz
mv hcp /usr/local/bin/
```

### Check Utilizations

```
kubectl top pods -n metallb-system --sum
oc adm top pods -n openshift-monitoring --sum
oc adm top pods -n multicluster-engine --sum
oc adm top pods -n open-cluster-management --sum
```
