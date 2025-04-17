## RKE2 with Kubevirt on Proxmox & Baremetal

KubeVirt on RKE2 based on 1 master (VM on Proxmox) 2 worker (Baremetal) with Cilium CNI including Ceph

### Jumphost setup

- Deploy Ubuntu VM

```
qm clone 8000 107 --name ubuntu --full
qm set 107 --memory 2048 --cores 1 --cpu cputype=host
qm set 107 --ipconfig0 ip=192.168.0.107/24,gw=192.168.0.1
qm start 107
```

- Install [Cilium CLI](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-the-cilium-cli)

```
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
```

- Install Kubectl

```
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod 755 kubectl
mv kubectl /usr/local/bin/
```

- Setup Helm Chart

```
wget https://raw.githubusercontent.com/cloudcafetech/kubesetup/master/misc/helm-setup.sh
chmod +x ./helm-setup.sh
./helm-setup.sh
```

- Velero 

```
curl -L -k -o /tmp/velero.tar.gz https://github.com/vmware-tanzu/velero/releases/download/v1.16.0/velero-v1.16.0-linux-amd64.tar.gz
tar -C /tmp -xvf /tmp/velero.tar.gz
mv /tmp/velero-v1.16.0-linux-amd64/velero /usr/local/bin/velero
chmod +x /usr/local/bin/velero
```

- Install Krew

```
set -x; cd "$(mktemp -d)" &&
OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
KREW="krew-${OS}_${ARCH}" &&
curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
tar zxvf "${KREW}.tar.gz" &&
./"${KREW}" install krew
  
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

# Install kubectl plugins using krew
kubectl krew install modify-secret
kubectl krew install ctx
kubectl krew install ns
kubectl krew install rook-ceph
kubectl krew install virt

echo 'export PATH="${PATH}:${HOME}/.krew/bin"' >> /root/.bash_profile
```

### Cluster (RKE2) Setup 

- Common setup for all hosts

```
systemctl stop firewalld
systemctl disable firewalld

cat << EOF > /etc/NetworkManager/conf.d/rke2-canal.conf
[keyfile]
unmanaged-devices=interface-name:cali*;interface-name:flannel*
EOF
systemctl reload NetworkManager
setenforce 0
sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux

yum install -y git curl wget nc sshpass jq bind-utils zip unzip nfs-utils telnet dos2unix net-tools

swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

modprobe br_netfilter
modprobe overlay
cat <<EOF | tee /etc/modules-load.d/k8s.conf
br_netfilter
overlay
EOF

cat <<EOF | tee /etc/sysctl.conf
net.ipv4.ip_forward=1
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.send_redirects=0
net.ipv4.conf.default.accept_source_route=0
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.all.log_martians=1
net.ipv4.conf.default.log_martians=1
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1
net.ipv6.conf.all.accept_ra=0
net.ipv6.conf.default.accept_ra=0
net.ipv6.conf.all.accept_redirects=0
net.ipv6.conf.default.accept_redirects=0
kernel.keys.root_maxbytes=25000000
kernel.keys.root_maxkeys=1000000
kernel.panic=10
kernel.panic_on_oops=1
vm.overcommit_memory=1
vm.panic_on_oom=0
net.ipv4.ip_local_reserved_ports=30000-32767
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-arptables=1
net.bridge.bridge-nf-call-ip6tables=1
fs.inotify.max_user_watches = 11524288
fs.inotify.max_user_instances = 512
EOF

sysctl --system
sysctl -p
```

- Master Setup on Proxmox

```
cat << EOF >  config.yaml
token: pkar-rke2
write-kubeconfig-mode: "0644"
cluster-cidr: 10.244.0.0/16
service-cidr: 10.96.0.0/12
cluster-domain: cloudcafe.tech
node-label:
- "region=master"
tls-san:
  - "rke2-master-01"
  - "192.168.0.124"
cni: none
disable-kube-proxy: true
disable-cloud-controller: true
disable:
  - disable-cloud-controller
  - rke2-snapshot-controller
  - rke2-snapshot-controller-crd
  - rke2-snapshot-validation-webhook
#node-taint:
#  - "CriticalAddonsOnly=true:NoExecute"
EOF

curl -sfL https://get.rke2.io | INSTALL_RKE2_CHANNEL=v1.31 sh -
mkdir -p /etc/rancher/rke2/
cp config.yaml /etc/rancher/rke2/

systemctl disable rke2-agent && systemctl mask rke2-agent
systemctl enable --now rke2-server

mkdir -p /root/.kube
cp /etc/rancher/rke2/rke2.yaml /root/.kube/config
chmod 600 /root/.kube/config
echo 'export PATH=/var/lib/rancher/rke2/bin:$PATH' >> /root/.bash_profile
echo 'alias oc=/var/lib/rancher/rke2/bin/kubectl' >> /root/.bash_profile
cp /var/lib/rancher/rke2/agent/etc/crictl.yaml /etc/crictl.yaml

#journalctl -b -u rke2-server -f
```

- Worker Setup on Baremetal

```
cat << EOF > config.yaml
server: https://192.168.0.124:9345
token: pkar-rke2
selinux: false
node-label:
- "region=worker"
EOF

curl -sfL https://get.rke2.io | INSTALL_RKE2_CHANNEL=v1.31 sh -
mkdir -p /etc/rancher/rke2/
cp config.yaml /etc/rancher/rke2/

yum install rke2-agent -y
systemctl disable rke2-server && systemctl mask rke2-server
systemctl enable --now rke2-agent

echo 'export PATH=/var/lib/rancher/rke2/bin:$PATH' >> /root/.bash_profile
cp /var/lib/rancher/rke2/agent/etc/crictl.yaml /etc/crictl.yaml
```

- Deploy CNI

If use multiple hosts with deffierence interfaces, you may face crashloopback error (**level=fatal msg="failed to start: daemon creation failed: failed to detect devices: unable to determine direct routing device. Use --direct-routing-device to specify it" subsys=daemon** ) [FIX](https://github.com/cilium/cilium/issues/33527#issuecomment-2203382474)

Below special helm options (Multus + Kubevirt)

> ```cni.exclusive=false```  **Cilium with Multus integration** [Ref](https://github.com/siderolabs/talos/discussions/7914#discussioncomment-7457510)

> ```l2announcements.enabled=true``` & ```externalIPs.enabled=true```  **No extrat tool (metallb) for LB**

> ```socketLB.hostNamespaceOnly=true```  **For Kubevirt**

**Cilium as a CNI & L4 LB**  [Ref#1](https://blog.mei-home.net/posts/k8s-migration-2-cilium-lb/)  [Ref#2](https://blog.stonegarden.dev/articles/2023/12/migrating-from-metallb-to-cilium/)

```
cilium install \
  --helm-set=ipam.mode=kubernetes \
  --helm-set=kubeProxyReplacement=true \
  --helm-set=securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
  --helm-set=securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
  --helm-set=cgroup.autoMount.enabled=false \
  --helm-set=cgroup.hostRoot=/sys/fs/cgroup \
  --helm-set=cni.exclusive=false \
  --helm-set=l2announcements.enabled=true \
  --helm-set=externalIPs.enabled=true \
  --helm-set=socketLB.hostNamespaceOnly=true \
  --helm-set=k8sServiceHost=localhost \
  --helm-set=k8sServicePort=6443 \
  --helm-set=devices='{eth0,eth1,eth2,eno1,eno2,br0,enp0s18,ens18}'
```

- Cilium LB IP POOL

```
kubectl create -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/00-cilium/cilium-lb-pool.yaml
```

## Deploy Eco-system tools

### Storage

[Setup NFS Server](https://github.com/cloudcafetech/homelab/tree/main/talos/talos-kubevirt/00-nfs-provisioner#nfs-provisioner)

- NFS Storage (Provisioner), fast but does NOT support Snapshot

```
NFSRV=192.168.0.108
NFSMOUNT=/root/nfs/kubedata

mkdir nfsstorage
cd nfsstorage

wget https://raw.githubusercontent.com/cloudcafetech/kubesetup/master/nfs-storage/nfs-rbac.yaml
wget https://raw.githubusercontent.com/cloudcafetech/kubesetup/master/nfs-storage/nfs-deployment.yaml
wget https://raw.githubusercontent.com/cloudcafetech/kubesetup/master/nfs-storage/kubenfs-storage-class.yaml

sed -i "s/10.128.0.9/$NFSRV/g" nfs-deployment.yaml
sed -i "s|/root/nfs/kubedata|$NFSMOUNT|g" nfs-deployment.yaml

kubectl create ns kubenfs
kubectl create -f nfs-rbac.yaml -f nfs-deployment.yaml -f kubenfs-storage-class.yaml -n kubenfs
```

**OR**

- NFS Storage (CSI), Support Snapshot

```
NFSRV=192.168.0.108
NFSMOUNT=/root/nfs/kubedata
wget https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/00-nfs-provisioner/values.yaml
sed -i "s/192.168.0.100/$NFSRV/g" values.yaml
sed -i "s|/root/nfs/kubedata|$NFSMOUNT|g" values.yaml
helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
helm install csi-driver-nfs csi-driver-nfs/csi-driver-nfs \
  --create-namespace \
  --namespace csi-nfs \
  --version v0.0.0 \
  --values values.yaml

kubectl label ns csi-nfs pod-security.kubernetes.io/enforce=privileged
kubectl apply -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/00-nfs-provisioner/volumesnapshotclass.yaml
```

- Local Path Storage

```
kubectl create -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/01-local-path-provisioner/local-path-storage.yaml
kubectl label ns local-path-storage pod-security.kubernetes.io/enforce=privileged
```

- MinIO object storage

```
kubectl create ns minio-store
kubectl label ns minio-store pod-security.kubernetes.io/enforce=privileged
wget https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/backup/minio.yaml
sed -i 's/local-path/kubenfs-storage/g' minio.yaml
sed -i 's/5Gi/15Gi/g' minio.yaml
kubectl create -f minio.yaml
```

- Longhorn Storage

```
helm repo add longhorn https://charts.longhorn.io
helm repo update
helm install longhorn longhorn/longhorn --namespace longhorn-system --create-namespace --version 1.6.1 --set defaultSettings.defaultDataPath="/var/mnt/longhorn"
kubectl label ns longhorn-system pod-security.kubernetes.io/enforce=privileged
kubectl create -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/longhorn/storageclass-rwx.yml
kubectl patch svc longhorn-frontend -n longhorn-system --type='json' -p '[{"op":"replace","path":"/spec/type","value":"NodePort"}]'
```

**OR**

- Ceph Storage

[Install](https://github.com/cloudcafetech/homelab/blob/main/talos/talos-kubevirt/ceph/README.md)

### Virtualization

**HCO** [Hyperconverged Cluster Operator](https://github.com/kubevirt/hyperconverged-cluster-operator?tab=readme-ov-file#using-the-hco-without-olm-or-marketplace)

- Create namespaces 

```
HCONS=kubevirt-hyperconverged
for ns in $HCONS openshift konveyor-forklift virtualmachines olm; do  kubectl create ns $ns; done
for ns in $HCONS openshift konveyor-forklift virtualmachines olm; do  kubectl label ns $ns pod-security.kubernetes.io/enforce=privileged ; done
```

- Deploy CRDs

```
LABEL_SELECTOR_ARG="-l name!=ssp-operator,name!=hyperconverged-cluster-cli-download"
kubectl apply ${LABEL_SELECTOR_ARG} -f https://raw.githubusercontent.com/kubevirt/hyperconverged-cluster-operator/main/deploy/crds/cluster-network-addons00.crd.yaml
kubectl apply ${LABEL_SELECTOR_ARG} -f https://raw.githubusercontent.com/kubevirt/hyperconverged-cluster-operator/main/deploy/crds/containerized-data-importer00.crd.yaml
kubectl apply ${LABEL_SELECTOR_ARG} -f https://raw.githubusercontent.com/kubevirt/hyperconverged-cluster-operator/main/deploy/crds/hco00.crd.yaml
kubectl apply ${LABEL_SELECTOR_ARG} -f https://raw.githubusercontent.com/kubevirt/hyperconverged-cluster-operator/main/deploy/crds/kubevirt00.crd.yaml
kubectl apply ${LABEL_SELECTOR_ARG} -f https://raw.githubusercontent.com/kubevirt/hyperconverged-cluster-operator/main/deploy/crds/hostpath-provisioner00.crd.yaml
kubectl apply ${LABEL_SELECTOR_ARG} -f https://raw.githubusercontent.com/kubevirt/hyperconverged-cluster-operator/main/deploy/crds/scheduling-scale-performance00.crd.yaml
kubectl apply ${LABEL_SELECTOR_ARG} -f https://raw.githubusercontent.com/kubevirt/hyperconverged-cluster-operator/main/deploy/crds/application-aware-quota00.crd.yaml
```

- Deploy Cert Manager for webhook certificates

```
kubectl apply ${LABEL_SELECTOR_ARG} -f https://raw.githubusercontent.com/kubevirt/hyperconverged-cluster-operator/main/deploy/cert-manager.yaml
kubectl -n cert-manager wait deployment/cert-manager --for=condition=Available --timeout="300s"
kubectl -n cert-manager wait deployment/cert-manager-webhook --for=condition=Available --timeout="300s"
```

- Deploy Service Accounts, Cluster Role(Binding)s and Operators

```
kubectl apply ${LABEL_SELECTOR_ARG} -n $HCONS -f https://raw.githubusercontent.com/kubevirt/hyperconverged-cluster-operator/main/deploy/cluster_role.yaml
kubectl apply ${LABEL_SELECTOR_ARG} -n $HCONS -f https://raw.githubusercontent.com/kubevirt/hyperconverged-cluster-operator/main/deploy/service_account.yaml
kubectl apply ${LABEL_SELECTOR_ARG} -n $HCONS -f https://raw.githubusercontent.com/kubevirt/hyperconverged-cluster-operator/main/deploy/cluster_role_binding.yaml
kubectl apply ${LABEL_SELECTOR_ARG} -n $HCONS -f https://raw.githubusercontent.com/kubevirt/hyperconverged-cluster-operator/main/deploy/webhooks.yaml
kubectl apply ${LABEL_SELECTOR_ARG} -n $HCONS -f https://raw.githubusercontent.com/kubevirt/hyperconverged-cluster-operator/main/deploy/operator.yaml

kubectl -n $HCONS wait deployment/hyperconverged-cluster-webhook --for=condition=Available --timeout="300s"
```

- Create an HCO CustomResource, which creates the KubeVirt CR, launching KubeVirt [Ref Config](https://github.com/kubevirt/hyperconverged-cluster-operator/blob/main/docs/cluster-configuration.md)

```
#wget https://raw.githubusercontent.com/kubevirt/hyperconverged-cluster-operator/main/deploy/hco.cr.yaml
wget https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/hco/hco.cr.yaml
# Change Hostpath Storage Class as per environment
#echo "  scratchSpaceStorageClass: hostpath-csi" >> hco.cr.yaml
#echo "  scratchSpaceStorageClass: ceph-rbd-scratch" >> hco.cr.yaml
kubectl apply ${LABEL_SELECTOR_ARG} -n $HCONS -f hco.cr.yaml
```

- Enable KubeSecondaryDNS

```
wget https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/metallb/values.yml
helm repo add metallb https://metallb.github.io/metallb
helm install metallb metallb/metallb -f values.yml --namespace kube-system
wget https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/metallb/metallb-ippol.yaml
kubectl create -f metallb-ippol.yaml
kubectl create -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/hco/secondary-dns.yaml
```

- [ISSUE Hostpath Provisioner CSI not started](https://github.com/kubevirt/hostpath-provisioner-operator/tree/main?tab=readme-ov-file#hostpath-provisioner-operator)

```
kubectl apply -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/hco/hostpath-provisioner-operator-webhook.yaml
kubectl apply -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/hco/hostpath-provisioner-csi.yaml
kubectl get po -n kubevirt-hyperconverged | grep hostpath-provisioner-csi
```

### Networking

- Whereabouts and NAD

```
kubectl create -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/04-multus/01-whereabouts.cni.cncf.io_ippools.yaml
kubectl create -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/04-multus/02-whereabouts.cni.cncf.io_overlappingrangeipreservations.yaml
kubectl create -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/04-multus/03-whereabouts-install.yaml
kubectl create -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/04-multus/04-networkattachmentconfig.yml
kubectl create -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/04-multus/nad-4-migration-vm.yaml
```

- Multi Network Policy

```
kubectl create -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multi-networkpolicy/refs/heads/master/scheme.yml
kubectl create -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/04-multus/deploy.yml
#kubectl create -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multi-networkpolicy-iptables/refs/heads/master/deploy.yml
```

- [NMstate Setup](https://github.com/cloudcafetech/homelab/blob/main/nmstate.md)

### Observability

- Monitoring

```
mkdir monitoring
cd monitoring
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
wget https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/05-monitoring/prom-values.yaml
wget https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/05-monitoring/ocp-console-custom-rule.yaml
wget https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/06-console/ocp-console.yaml
wget https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/05-monitoring/servicemonitor-kubevirt.yaml
helm install kube-prometheus-stack --create-namespace -n monitoring -f prom-values.yaml prometheus-community/kube-prometheus-stack
sed -i 's/kubemon-/kube-prometheus-stack-/g' ocp-console.yaml
kubectl create -f ocp-console.yaml
kubectl create -f ocp-console-custom-rule.yaml -n monitoring
kubectl create -f servicemonitor-kubevirt.yam

# Get Grafana 'admin' user password by running:
kubectl --namespace monitoring get secrets kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 -d ; echol
```

- Logging

```
kubectl create ns logging
rm -rf loki.yaml
wget -q https://raw.githubusercontent.com/cloudcafetech/kubesetup/master/logging/loki.yaml
kubectl create secret generic loki -n logging --from-file=loki.yaml
kubectl create -f https://raw.githubusercontent.com/cloudcafetech/kubesetup/master/logging/kubelog.yaml -n logging
kubectl delete ds loki-fluent-bit-loki -n logging
kubectl create -f https://raw.githubusercontent.com/cloudcafetech/kubesetup/master/logging/promtail.yaml -n logging
```

### Backup & Restore

- Velero Setup

**MinIO should Install**

```
cat << EOF > credentials-velero
[default]
aws_access_key_id = admin
aws_secret_access_key = admin2675
EOF

velero install \
    --features=EnableCSI \
    --provider aws \
    --use-node-agent --privileged-node-agent \
    --plugins velero/velero-plugin-for-aws:v1.10.1,quay.io/kubevirt/kubevirt-velero-plugin:v0.7.1 \
    --bucket velero \
    --secret-file credentials-velero \
    --use-volume-snapshots=true \
    --velero-pod-mem-request 512Mi \
    --velero-pod-mem-limit 1Gi \
    --backup-location-config region=minio,s3ForcePathStyle="true",insecureSkipTLSVerify=true,s3Url=http://minio.minio-store.svc:9000 \
    --snapshot-location-config region=minio,insecureSkipTLSVerify=true,enableSharedConfig=true

sleep 30

# If node agent not required in master node
kubectl patch ds node-agent -n velero --patch '{"spec":{"template":{"spec":{"nodeSelector":{"region":"worker"}}}}}'
```

- Backup

```
alias vel='kubectl -n velero exec deployment/velero -c velero -it -- ./velero'

```

- Restore

```
alias vel='kubectl -n velero exec deployment/velero -c velero -it -- ./velero'
velero restore create --from-backup testvm-backup
```

### VM Deploy

[BUG](https://github.com/kubevirt/kubevirt/issues/13607) [FIX](https://github.com/kubevirt/kubevirt/issues/13607#issuecomment-2568972586)

```
kubectl create ns virtualmachines
kubectl label ns virtualmachines pod-security.kubernetes.io/enforce=privileged
kubectl create -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/vm-manifests/disable-selinux.yaml
```

- Ubuntu 2204 (Using multus cni)

>Image pull ( ```kubectl create -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/vm-manifests/import-dv-ubuntu.yml``` )

>Create VM Disks ( ```kubectl create -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/vm-manifests/ubuntu-external-dv-pvc.yaml``` )

>Deploy VM ( ```kubectl create -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/vm-manifests/ubuntu-external-vm.yaml``` )

- Debian 12 Webserver (Using POD network)

>Image pull ( ```kubectl create -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/vm-manifests/import-dv-debian.yml``` )

>Create VM Disks ( ```kubectl create -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/vm-manifests/debian-dv-pvc.yaml``` )

>Deploy VM ( ```kubectl create -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/vm-manifests/debian-webserver-vm.yaml``` )

- Fedora 40 (Using POD network)

>Image pull ( ```kubectl create -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/vm-manifests/import-dv-fedora.yml``` )

>Create VM Disks ( ```kubectl create -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/vm-manifests/fedora-dv-pvc.yaml``` )

>Deploy VM ( ```kubectl create -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/vm-manifests/fedora-vm.yaml``` )

### Manage VNC for windows 

- Deploy
  
```
wget -q https://raw.githubusercontent.com/cloudcafetech/nestedk8s/refs/heads/main/vncviewer.yaml
kubectl create -f vncviewer.yaml
```

- Usage

Get node port of virtvnc service ```kubectl get svc -n kubevirt virtvnc```

Manage virtual machines in namespace.

http://NODEIP:NODEPORT/?namespace=test
