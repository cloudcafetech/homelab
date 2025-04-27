## RKE2 with Kubevirt on Proxmox & Baremetal

KubeVirt on RKE2 based on 1 master (VM on Proxmox) 2 worker (Baremetal) with Canal/Cilium Whereabouts CNI and Ceph Storage

[Cheatsheet](https://github.com/cloudcafetech/homelab/blob/main/rke2/cheatsheet.md#cheatsheet)

### Jumphost setup

- Deploy Ubuntu VM

```
qm clone 8000 110 --name jumphost --full
qm set 110 --memory 2048 --cores 2 --cpu cputype=host
qm set 110 --ipconfig0 ip=192.168.0.110/24,gw=192.168.0.1
qm start 110
```

- Deploy CentOS Master VM

```
qm clone 9000 126 --name rke2-centos-m1 --full
qm set 126 --memory 7168 --cores 4 --cpu cputype=host
qm set 126 --ipconfig0 ip=192.168.0.126/24,gw=192.168.0.1
qm start 126
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
rm -rf helm-setup.sh
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
cat << EOF > config.yaml
token: pkar-rke2
write-kubeconfig-mode: "0644"
cluster-cidr: 10.244.0.0/16
service-cidr: 10.96.0.0/12
cluster-domain: cloudcafe.tech
node-label:
- "region=master"
tls-san:
  - "rke2-centos-m1"
  - "192.168.0.126"
cni:
  - multus
  - canal
#  - cilium
#disable-kube-proxy: true
disable:
  - rke2-snapshot-controller
  - rke2-snapshot-controller-crd
  - rke2-snapshot-validation-webhook
#  - rke2-ingress-nginx
#node-taint:
#  - "CriticalAddonsOnly=true:NoExecute"
EOF

cat << EOF > rke2-cilium-config.yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-cilium
  namespace: kube-system
spec:
  valuesContent: |-
    operator:
      replicas: 2
      image:
        #tag: v1.17.3
        tag: v1.16.6
    kubeProxyReplacement: true
    k8sServiceHost: "localhost"
    k8sServicePort: "6443"
    ipam:
      mode: kubernetes
    cni:
      exclusive: false
    l2announcements:
      enabled: true
    externalIPs:
      enabled: true
    socketLB:
      hostNamespaceOnly: true
    ingressController:
      enabled: true
    gatewayAPI:
      enabled: false
EOF

cat << EOF > rke2-multus-config.yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-multus
  namespace: kube-system
spec:
  valuesContent: |-
    rke2-whereabouts:
      enabled: true
EOF

curl -sfL https://get.rke2.io | INSTALL_RKE2_CHANNEL=v1.31 sh -
mkdir -p /etc/rancher/rke2/
mkdir -p /var/lib/rancher/rke2/server/manifests
cp config.yaml /etc/rancher/rke2/
#cp rke2-cilium-config.yaml /var/lib/rancher/rke2/server/manifests/
cp rke2-multus-config.yaml /var/lib/rancher/rke2/server/manifests/

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
server: https://192.168.0.126:9345
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

- Ceph Storage [Install](https://github.com/cloudcafetech/homelab/blob/main/talos/talos-kubevirt/ceph/README.md)

```
echo - Downloading Files
mkdir $PWD/ceph; cd $PWD/ceph
kubectl create ns rook-ceph
kubectl label ns rook-ceph pod-security.kubernetes.io/enforce=privileged
wget -q https://raw.githubusercontent.com/rook/rook/refs/heads/master/deploy/examples/crds.yaml
wget -q https://raw.githubusercontent.com/rook/rook/refs/heads/master/deploy/examples/common.yaml
wget -q https://raw.githubusercontent.com/rook/rook/refs/heads/master/deploy/examples/operator.yaml
wget -q https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/ceph/cephcluster.yaml
wget -q https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/ceph/cephfs.yaml
wget -q https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/ceph/ceph-rbd-default.yaml
wget -q https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/ceph/ceph-rbd-scratch.yaml
wget -q https://raw.githubusercontent.com/rook/rook/refs/heads/master/deploy/examples/dashboard-external-https.yaml
wget -q https://raw.githubusercontent.com/rook/rook/refs/heads/master/deploy/examples/csi/cephfs/snapshotclass.yaml
wget -q https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/ceph/rook-ceph-system-clusterrole-endpointslices.yaml

echo - Installing CRDs and Operators
kubectl create -f crds.yaml -f common.yaml -f operator.yaml
kubectl apply -f rook-ceph-system-clusterrole-endpointslices.yaml
sleep 10
kubectl -n rook-ceph wait deployment/rook-ceph-operator --for=condition=Available --timeout 300s

echo - Installing Cluster
kubectl create -f cephcluster.yaml
sleep 30
kubectl create -f cephfs.yaml -f ceph-rbd-default.yaml -f ceph-rbd-scratch.yaml -f dashboard-external-https.yaml

echo - Installing Snapshot Controller and StorageClass
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/release-8.2/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/release-8.2/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/release-8.2/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml
sleep 10
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/release-8.2/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/release-8.2/deploy/kubernetes/snapshot-controller/setup-snapshot-controller.yaml

kubectl create -f snapshotclass.yaml

echo - Patch storageprofile
kubectl get storageprofile 
kubectl patch storageprofile ceph --type=merge -p '{"spec": {"claimPropertySets": [{"accessModes": ["ReadWriteMany"], "volumeMode": "Filesystem"}]}}'
kubectl patch storageprofile ceph-rbd --type=merge -p '{"spec": {"claimPropertySets": [{"accessModes": ["ReadWriteOnce"], "volumeMode": "Block"}]}}'

echo - Get Password for Dashboard
kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o jsonpath="{['data']['password']}" | base64 --decode
```

### Virtualization

**KUBEVIRT & CDI** 

- Create namespaces 

```
for ns in openshift konveyor-forklift virtualmachines olm; do  kubectl create ns $ns; done
for ns in openshift konveyor-forklift virtualmachines olm; do  kubectl label ns $ns pod-security.kubernetes.io/enforce=privileged ; done
```

- Cert Manager 

```
LABEL_SELECTOR_ARG="-l name!=ssp-operator,name!=hyperconverged-cluster-cli-download"
kubectl apply ${LABEL_SELECTOR_ARG} -f https://raw.githubusercontent.com/kubevirt/hyperconverged-cluster-operator/main/deploy/cert-manager.yaml
kubectl -n cert-manager wait deployment/cert-manager --for=condition=Available --timeout="300s"
kubectl -n cert-manager wait deployment/cert-manager-webhook --for=condition=Available --timeout="300s"
```

- KUBEVIRT

```
export RELEASE=$(curl https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)
kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/${RELEASE}/kubevirt-operator.yaml
wget https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/02-kubevirt-operator/kubevirt-cr.yaml
sed -i '/HostDisk/s/^/#/' kubevirt-cr.yaml
sed -i '/VMExport/s/^/#/' kubevirt-cr.yaml
kubectl apply -f kubevirt-cr.yaml
```

- CDI

```
export TAG=$(curl -s -w %{redirect_url} https://github.com/kubevirt/containerized-data-importer/releases/latest)
export VERSION=$(echo ${TAG##*/})
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/$VERSION/cdi-operator.yaml
kubectl create -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/03-cdi-operator/01-cdi-cr.yaml
sleep 30
#kubectl patch cdi cdi --patch '{"spec": {"config": {"podResourceRequirements": {"limits": {"memory": "5G"}}}}}' --type merge
```

- Enable KubeSecondaryDNS

```
wget https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/metallb/values.yml
wget https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/metallb/metallb-ippol.yaml
wget https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/hco/secondary-dns.yaml
sed -i 's/kubevirt-hyperconverged/kubevirt/g' secondary-dns.yaml
helm repo add metallb https://metallb.github.io/metallb
helm install metallb metallb/metallb -f values.yml --namespace kube-system
sleep 30
kubectl -n kube-system wait deployment/metallb-controller --for=condition=Available --timeout 300s
kubectl -n kube-system rollout status ds/metallb-speaker --timeout 300s
kubectl create -f metallb-ippol.yaml 
kubectl create -f secondary-dns.yaml
```

- [Addon Network](https://github.com/kubevirt/cluster-network-addons-operator?tab=readme-ov-file#cluster-network-addons-operator)

```
kubectl apply -f https://github.com/kubevirt/cluster-network-addons-operator/releases/download/v0.98.2/namespace.yaml
kubectl apply -f https://github.com/kubevirt/cluster-network-addons-operator/releases/download/v0.98.2/network-addons-config.crd.yaml
kubectl apply -f https://github.com/kubevirt/cluster-network-addons-operator/releases/download/v0.98.2/operator.yaml
wget https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/hco/network-addons-config-example.cr.yaml
#wget https://github.com/kubevirt/cluster-network-addons-operator/releases/download/v0.98.2/network-addons-config-example.cr.yaml
#sed -i '/kubeSecondaryDNS/s/^/#/' network-addons-config-example.cr.yaml
#sed -i '/macvtap/s/^/#/' network-addons-config-example.cr.yaml
#sed -i '/ovs/s/^/#/' network-addons-config-example.cr.yaml
#sed -i '/multus/s/^/#/' network-addons-config-example.cr.yaml
kubectl apply -f network-addons-config-example.cr.yaml
kubectl wait networkaddonsconfig cluster --for condition=Available
kubectl get networkaddonsconfig cluster -o yaml
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

- NMstate Setup

```
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/v0.83.0/nmstate.io_nmstates.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/v0.83.0/namespace.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/v0.83.0/service_account.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/v0.83.0/role.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/v0.83.0/role_binding.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/v0.83.0/operator.yaml
sleep 30

cat <<EOF | kubectl create -f -
apiVersion: nmstate.io/v1
kind: NMState
metadata:
  name: nmstate
EOF

wget https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/nmstate/bridge.yaml
kubectl create -f bridge.yaml
```

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
sed -i 's/kubevirt-hyperconverged/kubevirt/g' servicemonitor-kubevirt.yaml
kubectl create -f ocp-console.yaml
kubectl create -f ocp-console-custom-rule.yaml -n monitoring
kubectl create -f servicemonitor-kubevirt.yaml

# Get Grafana 'admin' user password by running:
kubectl --namespace monitoring get secrets kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 -d ; echo
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

cat << EOF > velero-snapclass.yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: velero-snapclass
  labels:
    velero.io/csi-volumesnapshot-class: "true"
deletionPolicy: Delete
driver: rook-ceph.cephfs.csi.ceph.com
parameters:
  force-create: "true"
EOF

kubectl create -f velero-snapclass.yaml
```

- Backup

```
alias vel='kubectl -n velero exec deployment/velero -c velero -it -- ./velero'
vel backup create virtualmachines-vm-backup --include-namespaces virtualmachines --wait

```

- Restore

```
alias vel='kubectl -n velero exec deployment/velero -c velero -it -- ./velero'
vel restore create --from-backup virtualmachines-vm-backup --restore-volumes=true --exclude-resources=dv --wait
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

- [Windows](https://github.com/dockur/windows)

[Windows Host device](https://github.com/kubevirt/kubevirt/issues/10878)

[Ref](https://github.com/dockur/windows/pull/304#discussion_r1637455331)

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
