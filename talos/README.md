### TALOS K8S Setup on Proxmox

- [Talos K8s version mapping](https://www.talos.dev/v1.8/introduction/support-matrix/)

- Download Talos ISO from [Image factory](https://www.talos.dev/latest/talos-guides/install/boot-assets/#image-factory) for Proxmox

```
cd /var/lib/vz/template/iso
wget https://geo.mirror.pkgbuild.com/iso/2024.12.01/archlinux-2024.12.01-x86_64.iso
wget https://factory.talos.dev/image/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515/v1.8.3/nocloud-amd64.iso
mv archlinux-2024.12.01-x86_64.iso archlinux-20241201.iso
mv nocloud-amd64.iso talos-1-8-3.iso
cd
```

- Create Talos VM template 

```
qm create 6000 --name talos-183-template --ide2 local:iso/archlinux-20241201.iso,media=cdrom --boot order='scsi0;ide2;net0' \
  --cpu cputype=host --cores 2 --sockets 1 --memory 2048 --scsihw virtio-scsi-pci --bootdisk scsi0 \
  --scsi0 local-lvm:40,discard=on,ssd=1 --serial0 socket
qm start 6000
sleep 15
cd /tmp
wget https://factory.talos.dev/image/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515/v1.8.3/nocloud-amd64.raw.xz
xz -d -c nocloud-amd64.raw.xz | dd of=/dev/mapper/pve-vm--6000--disk--0
qm stop 6000
qm set 6000 --tags talos-183-template,k8s
qm set 6000 --ipconfig0 ip=dhcp
qm template 6000
cd
```

- Setup Ubuntu Host

```
qm clone 8000 107 --name ubuntu --full
qm set 107 --memory 2048 --cores 1 --cpu cputype=host
qm set 107 --ipconfig0 ip=192.168.0.107/24,gw=192.168.0.1
qm start 107
```

- Install TALOSCTL

```
wget https://github.com/talos-systems/talos/releases/download/v1.8.3/talosctl-linux-amd64
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

- Create Talos K8S VMs

```
qm clone 6000 111 --name talos-master-01 --full
qm set 111 --cpu cputype=host --cores 2 --sockets 1 --memory 2048
qm set 111 -net0 virtio=BC:24:11:99:9F:11,bridge=vmbr0
qm start 111

qm clone 6000 112 --name talos-master-02 --full
qm set 112 --cpu cputype=host --cores 2 --sockets 1 --memory 2048
qm set 112 -net0 virtio=BC:24:11:99:9F:12,bridge=vmbr0
qm start 112

qm clone 6000 113 --name talos-master-03 --full
qm set 113 --cpu cputype=host --cores 2 --sockets 1 --memory 2048
qm set 113 -net0 virtio=BC:24:11:99:9F:13,bridge=vmbr0
qm start 113

qm clone 6000 114 --name talos-infra-01 --full
qm set 114 --cpu cputype=host --cores 2 --sockets 1 --memory 2048
qm set 114 -net0 virtio=BC:24:11:99:9F:14,bridge=vmbr0
qm set 114 --scsi1 local-lvm:50
qm start 114

qm clone 6000 115 --name talos-infra-02 --full
qm set 115 --cpu cputype=host --cores 2 --sockets 1 --memory 2048
qm set 115 -net0 virtio=BC:24:11:99:9F:15,bridge=vmbr0
qm set 115 --scsi1 local-lvm:50
qm start 115

qm clone 6000 116 --name talos-worker-01 --full
qm set 116 --cpu cputype=host --cores 2 --sockets 1 --memory 2048
qm set 116 -net0 virtio=BC:24:11:99:9F:16,bridge=vmbr0
qm start 116

qm clone 6000 117 --name talos-worker-02 --full
qm set 117 --cpu cputype=host --cores 2 --sockets 1 --memory 2048
qm set 117 -net0 virtio=BC:24:11:99:9F:17,bridge=vmbr0
qm start 117
```

- Download Talos Config yaml & modify as per above VMs setup

```
mkdir talos
cd talos
wget https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talconfig.yaml
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
talosctl apply-config --insecure --nodes <master1-node ip> --file clusterconfig/talos-k8s-talos-master-01.yaml
talosctl apply-config --insecure --nodes <master2-node ip> --file clusterconfig/talos-k8s-talos-master-02.yaml
talosctl apply-config --insecure --nodes <master3-node ip> --file clusterconfig/talos-k8s-talos-master-03.yaml

talosctl apply-config --insecure --nodes <infra1-node ip> --file clusterconfig/talos-k8s-talos-infra-01.yaml
talosctl apply-config --insecure --nodes <infra2-node ip> --file clusterconfig/talos-k8s-talos-infra-02.yaml

talosctl apply-config --insecure --nodes <worker1-node ip> --file clusterconfig/talos-k8s-talos-worker-01.yaml
talosctl apply-config --insecure --nodes <worker1-node ip> --file clusterconfig/talos-k8s-talos-worker-02.yaml

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

**Cilium as a LB** 

[Ref#1](https://blog.mei-home.net/posts/k8s-migration-2-cilium-lb/) 

[Ref#2](https://blog.stonegarden.dev/articles/2023/12/migrating-from-metallb-to-cilium/)

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

[REF #1](https://www.talos.dev/v1.8/talos-guides/install/virtualized-platforms/proxmox/)

[REF #2](https://surajremanan.com/posts/automating-talos-installation-on-proxmox-with-packer-and-terraform/)

