## Talos with Kubevirt on Proxmox & Baremetal

KubeVirt on Talos Linux. 

This 3 config based on 1 master (VM on Proxmox) 1 worker (Baremetal) with default Flannel CNI & No (cilium) CNI including Longhorn

### Master (Talos VM) on Proxmox

- [Talos K8s version mapping](https://www.talos.dev/v1.8/introduction/support-matrix/)

- Download Talos ISO from [Image factory](https://www.talos.dev/latest/talos-guides/install/boot-assets/#image-factory) for Proxmox

```
cd /var/lib/vz/template/iso
wget https://geo.mirror.pkgbuild.com/iso/2024.12.01/archlinux-2024.12.01-x86_64.iso
wget https://factory.talos.dev/image/f8c7004f900329b6c00fe7a7e2458cb31e494a54f0cf1c3f1101d403a0a60af1/v1.9.1/nocloud-amd64.iso
mv archlinux-2024.12.01-x86_64.iso archlinux-20241201.iso
mv nocloud-amd64.iso talos-1-8-3.iso
cd
```

- Create Talos VM template 

```
qm create 6000 --name talos-191-template --ide2 local:iso/archlinux-20241201.iso,media=cdrom --boot order='scsi0;ide2;net0' \
  --cpu cputype=host --cores 2 --sockets 1 --memory 2048 --scsihw virtio-scsi-pci --bootdisk scsi0 \
  --scsi0 local-lvm:40,discard=on,ssd=1 --serial0 socket
qm start 6000
sleep 15
cd /tmp
wget https://factory.talos.dev/image/f8c7004f900329b6c00fe7a7e2458cb31e494a54f0cf1c3f1101d403a0a60af1/v1.9.1/nocloud-amd64.raw.xz
xz -d -c nocloud-amd64.raw.xz | dd of=/dev/mapper/pve-vm--6000--disk--0
qm stop 6000
qm set 6000 --tags talos-191-template,k8s
qm set 6000 --ipconfig0 ip=dhcp
qm template 6000
cd
```

- Create VM (Master)

```
qm clone 6000 108 --name talos-master --full
qm set 108 --cpu cputype=host --cores 4 --sockets 1 --memory 6144
qm set 108 -net0 virtio=BC:24:11:99:9F:11,bridge=vmbr0
qm set 108 --ipconfig0 ip=192.168.0.108/24,gw=192.168.0.1
qm start 108
```

### Jumphost setup

- Deploy Ubuntu VM

```
qm clone 8000 107 --name ubuntu --full
qm set 107 --memory 2048 --cores 1 --cpu cputype=host
qm set 107 --ipconfig0 ip=192.168.0.107/24,gw=192.168.0.1
qm start 107
```

- Install TALOSCTL

```
wget https://github.com/talos-systems/talos/releases/download/v1.9.1/talosctl-linux-amd64
chmod 755 talosctl-linux-amd64
mv talosctl-linux-amd64 /usr/local/bin/talosctl 
```

- Install TALOS Helper

```
curl https://i.jpillora.com/budimanjojo/talhelper! | sudo bash
```

- Install KUBECTL

```
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod 755 kubectl
mv kubectl /usr/local/bin/
```

- Install SOPS

```
curl -LO https://github.com/getsops/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64
mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops
chmod +x /usr/local/bin/sops
```

- Install AGE

```
apt install age
age -version
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

### Preparation network booting for Baremetal setup

- Set Env

```
TALOS_VER=v1.9.1
NIC=`ip -o -4 route show to default | awk '{print $5}'`
HIP=`ip -o -4 addr list $NIC | awk '{print $4}' | cut -d/ -f1`

DHCPS=192.168.0.30
DHCPE=192.168.0.50
GW=192.168.0.1
```

- Download kernel & setup matchbox

```
mkdir -p /var/lib/matchbox/{assets,groups,profiles}
wget -q https://factory.talos.dev/image/8b43d8668ab19b5aed93b9aa9bb8fca512c16be7d259483e58f702bb461fd9dc/v1.9.1/kernel-amd64
wget -q https://factory.talos.dev/image/8b43d8668ab19b5aed93b9aa9bb8fca512c16be7d259483e58f702bb461fd9dc/v1.9.1/initramfs-amd64.xz
mv kernel-amd64 /var/lib/matchbox/assets/vmlinuz
mv initramfs-amd64.xz /var/lib/matchbox/assets/initramfs.xz

cat <<EOF > /var/lib/matchbox/groups/default.json
{
  "id": "default",
  "name": "default",
  "profile": "default"
}
EOF

cat <<EOF > /var/lib/matchbox/profiles/default.json
{
  "id": "default",
  "name": "default",
  "boot": {
    "kernel": "/assets/vmlinuz",
    "initrd": ["/assets/initramfs.xz"],
    "args": [
      "initrd=initramfs.xz",
      "init_on_alloc=1",
      "slab_nomerge",
      "pti=on",
      "console=tty0",
      "console=ttyS0",
      "printk.devkmsg=on",
      "talos.platform=metal"
    ]
  }
}
EOF
```

- Start Matchbox

```
docker run --name=matchbox -d --net=host -v /var/lib/matchbox:/var/lib/matchbox:Z \
 quay.io/poseidon/matchbox:v0.10.0 -address=:8080 -log-level=debug
```

- Start DHCP Server

```
docker run --name=dnsmasq -d --cap-add=NET_ADMIN --net=host quay.io/poseidon/dnsmasq:v0.5.0-32-g4327d60-amd64 \
  -d -q -p0 --enable-tftp --tftp-root=/var/lib/tftpboot \
  --dhcp-range=$DHCPS,$DHCPE --dhcp-option=option:router,$GW \
  --dhcp-match=set:bios,option:client-arch,0 --dhcp-boot=tag:bios,undionly.kpxe \
  --dhcp-match=set:efi32,option:client-arch,6 --dhcp-boot=tag:efi32,ipxe.efi \
  --dhcp-match=set:efibc,option:client-arch,7 --dhcp-boot=tag:efibc,ipxe.efi \
  --dhcp-match=set:efi64,option:client-arch,9 --dhcp-boot=tag:efi64,ipxe.efi \
  --dhcp-userclass=set:ipxe,iPXE --dhcp-boot=tag:ipxe,http://$HIP:8080/boot.ipxe \
  --log-queries --log-dhcp
```

- Start baremetal host

Wait for system boot with Talos OS using pxeboot

### Kubernetes Cluster Setup

- Download Talos Config yaml, modify (IP & hostname) as per Proxmox VM (master) and Baremetal (worker) configuration.

```
mkdir talos
cd talos
wget https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/talconfig.yaml-longhorn-no-cni
mv talconfig.yaml-longhorn-no-cni talconfig.yaml
```

- Generating Talos Configuration using Talhelper

```
talhelper gensecret > talsecret.sops.yaml
mkdir -p $HOME/.config/sops/age/
age-keygen -o $HOME/.config/sops/age/keys.txt
KEY=`cat $HOME/.config/sops/age/keys.txt | grep public | cut -d : -f2 | tr -d ' '`

cat << EOF > .sops.yaml
---
creation_rules:
  - age: >-
      $KEY
EOF

sops -e -i talsecret.sops.yaml
talhelper genconfig
```

- Bootsrap Talos

```
talosctl apply-config --insecure -n <master1-node ip> -f clusterconfig/talos-k8s-talos-master.yaml
talosctl apply-config --insecure -n <worker1-node ip> -f clusterconfig/talos-k8s-talos-worker-01.yaml
cp clusterconfig/talos-k8s-talos-worker-01.yaml /var/lib/matchbox/assets/

mkdir -p $HOME/.talos
cp clusterconfig/talosconfig $HOME/.talos/config
talosctl bootstrap -n <master-node ip> # **Bootstrap should run ONCE on ANY master node**
```

- Set Kubeconfig

```
mkdir -p $HOME/.kube
talosctl -n <master1-node ip> kubeconfig $HOME/.kube/config
kubectl get no
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
  --helm-set=k8sServicePort=7445 \
  --helm-set=devices='{eth0,eth1,eth2,eno1,eno2,br0}'
```

- Cilium LB IP POOL

```
kubectl create -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/00-cilium/cilium-lb-pool.yaml
```

## Next deploy rest of tools

- CSI NFS Storage

```
wget https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/00-nfs-provisioner/values.yaml
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
wget https://raw.githubusercontent.com/cloudcafetech/k8sdemo/refs/heads/main/minio/snd/minio.yaml
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

- Whereabouts

```
kubectl create -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/04-multus/00-ns.yaml
kubectl create -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/04-multus/01-whereabouts.cni.cncf.io_ippools.yaml
kubectl create -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/04-multus/02-whereabouts.cni.cncf.io_overlappingrangeipreservations.yaml
kubectl create -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/04-multus/03-whereabouts-install.yaml
kubectl create -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/04-multus/04-networkattachmentconfig.yml
```

- Monitoring Logging and dashboard

```
kubectl create -f https://raw.githubusercontent.com/cloudcafetech/k8s-terraform/refs/heads/main/addon/metric-server.yaml
kubectl create ns monitoring
kubectl create -f https://raw.githubusercontent.com/cloudcafetech/kubesetup/master/monitoring/kubemon.yaml -n monitoring
kubectl create ns logging
rm -rf loki.yaml
wget -q https://raw.githubusercontent.com/cloudcafetech/kubesetup/master/logging/loki.yaml
kubectl create secret generic loki -n logging --from-file=loki.yaml
kubectl create -f https://raw.githubusercontent.com/cloudcafetech/kubesetup/master/logging/kubelog.yaml -n logging
kubectl delete ds loki-fluent-bit-loki -n logging
kubectl create -f https://raw.githubusercontent.com/cloudcafetech/kubesetup/master/logging/promtail.yaml -n logging
kubectl delete deployment cost-model -n monitoring
kubectl delete statefulset kubemon-grafana -n monitoring
kubectl create -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/06-console/ocp-console.yaml
```

### HCO [Hyperconverged Cluster Operator](https://github.com/kubevirt/hyperconverged-cluster-operator?tab=readme-ov-file#using-the-hco-without-olm-or-marketplace)

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

- Create an HCO CustomResource, which creates the KubeVirt CR, launching KubeVirt

```
kubectl apply ${LABEL_SELECTOR_ARG} -n $HCONS -f https://raw.githubusercontent.com/kubevirt/hyperconverged-cluster-operator/main/deploy/hco.cr.yaml
```

## OR Kubevirt CDI and Multus

- Kubevirt

```
export RELEASE=$(curl https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)
kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/${RELEASE}/kubevirt-operator.yaml
kubectl apply -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/02-kubevirt-operator/01-kubevirt-cr.yaml
```

- CDI

```
export TAG=$(curl -s -w %{redirect_url} https://github.com/kubevirt/containerized-data-importer/releases/latest)
export VERSION=$(echo ${TAG##*/})
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/$VERSION/cdi-operator.yaml
kubectl create -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/03-cdi-operator/01-cdi-cr.yaml
```

- Multus

```
kubectl create -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/04-multus/00-multus-daemonset-thick.yml
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

## [Migration](https://github.com/cloudcafetech/homelab/blob/main/talos/talos-kubevirt/migration/README.md)

### Reference

[Ref #1](https://github.com/MichaelTrip/taloscon2024)  [REF #2](https://surajremanan.com/posts/automating-talos-installation-on-proxmox-with-packer-and-terraform/)  [REF #3](https://cozystack.io/docs/talos/installation/pxe/)  [REF #4](https://github.com/dellathefella/talos-baremetal-install/tree/master) [Ref #5](https://www.talos.dev/v1.9/advanced/install-kubevirt/)

[Youtube](https://youtu.be/2sXQGnx5Apw?si=jWvRLVlSF69pmKkI)
