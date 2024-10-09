## Setup Container Platform on Proxmox
Setup Container (Kubeadm/RKE2/Openshift) Platform on Proxmox (Homelab)

- Create PROXMOX Host

- Login CLI ProxmoX host

- Modify subscription, Generate SSH Key using puttygen tool and create private, public & ppk key

```
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-enterprise.list
echo "deb http://download.proxmox.com/debian/ceph-quincy bookworm no-subscription" > /etc/apt/sources.list.d/ceph.list
apt-get update -y && apt-get upgrade -y
apt install putty wget vim libguestfs-tools p7zip-full -y
ssh-keygen -t rsa -N '' -f ./gcpkey -C cloudcafe -b 2048
puttygen gcpkey -O private -o gcpkey.ppk
```
- Download the ISO 

```
wget https://cloud-images.ubuntu.com/minimal/releases/jammy/release/ubuntu-22.04-minimal-cloudimg-amd64.img
wget https://cloud.centos.org/centos/8/x86_64/images/CentOS-8-GenericCloud-8.4.2105-20210603.0.x86_64.qcow2
wget https://cdimage.kali.org/kali-2024.2/kali-linux-2024.2-qemu-amd64.7z
7z x kali-linux-2024.2-qemu-amd64.7z
rm -rf kali-linux-2024.2-qemu-amd64.7z
```

- Change the file extension of the image to .qcow2

```
mv ubuntu-22.04-minimal-cloudimg-amd64.img ubuntu-22-04.qcow2
mv CentOS-8-GenericCloud-8.4.2105-20210603.0.x86_64.qcow2 centos-stream-8.qcow2
mv kali-linux-2024.2-qemu-amd64.qcow2 kali-2024.qcow2
```

- Resize the downloaded cloud image

```
qemu-img resize ubuntu-22-04.qcow2 35G
qemu-img resize centos-stream-8.qcow2 35G
qemu-img resize kali-2024.qcow2 35G
```

- Create the VM template using CLI

```
qm create 7000 --name kali-2024-template --memory 2048 --core 2 --agent enabled=1 --net0 virtio,bridge=vmbr0
qm importdisk 7000 kali-2024.qcow2 local-lvm
qm set 7000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-7000-disk-0,discard=on,ssd=1
qm set 7000 --ide2 local-lvm:cloudinit
qm set 7000 --boot c --bootdisk scsi0
qm set 7000 --serial0 socket --vga serial0

qm create 8000 --name ubuntu-2204-template --memory 1024 --core 1 --agent enabled=1 --net0 virtio,bridge=vmbr0
qm importdisk 8000 ubuntu-22-04.qcow2 local-lvm
qm set 8000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-8000-disk-0,discard=on,ssd=1
qm set 8000 --ide2 local-lvm:cloudinit
qm set 8000 --boot c --bootdisk scsi0
qm set 8000 --serial0 socket --vga serial0

qm create 9000 --name centos-8-template --memory 2048 --core 2 --agent enabled=1 --net0 virtio,bridge=vmbr0
qm importdisk 9000 centos-stream-8.qcow2 local-lvm
qm set 9000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9000-disk-0,discard=on,ssd=1
qm set 9000 --ide2 local-lvm:cloudinit
qm set 9000 --boot c --bootdisk scsi0
qm set 9000 --serial0 socket --vga serial0
```

- Configuring CloudInit

```
mkdir /var/lib/vz/snippets
cat <<EOF > /var/lib/vz/snippets/ubuntu.yaml
#cloud-config
runcmd:
  - apt update -y
  - apt install -y qemu-guest-agent vim iputils-ping apt-transport-https ca-certificates gpg nfs-common curl wget git net-tools unzip jq zip nmap telnet dos2unix
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  #- reboot
EOF

cat <<EOF > /var/lib/vz/snippets/centos.yaml
#cloud-config
runcmd:
  - cd /etc/yum.repos.d/
  - sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*
  - sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*
  - yum install -y qemu-guest-agent git curl wget bind-utils jq zip unzip go nmap telnet dos2unix net-tools nmstate
  - systemctl enable --now qemu-guest-agent
  #- reboot
EOF

cat <<EOF > /var/lib/vz/snippets/kali.yaml
#cloud-config
runcmd:
  - apt update -y
  - apt install -y qemu-guest-agent vim iputils-ping curl wget git net-tools telnet dos2unix
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  #- reboot
EOF

cat gcpkey.pub > sshkey

qm set 7000 --cicustom "vendor=local:snippets/kali.yaml"
qm set 7000 --cipassword cloudcafe2675
qm set 7000 --sshkeys ./sshkey
qm set 7000 --tags kali-template,Hack
qm set 7000 --ciuser cloudcafe
qm set 7000 --ipconfig0 ip=dhcp

qm set 8000 --cicustom "vendor=local:snippets/ubuntu.yaml"
qm set 8000 --cipassword cloudcafe2675
qm set 8000 --sshkeys ./sshkey
qm set 8000 --tags ubuntu2204-template,k8s
qm set 8000 --ciuser cloudcafe
qm set 8000 --ipconfig0 ip=dhcp

qm set 9000 --cicustom "vendor=local:snippets/centos.yaml"
qm set 9000 --cipassword cloudcafe2675
qm set 9000 --sshkeys ./sshkey
qm set 9000 --tags centos8-template,k8s
qm set 9000 --ciuser cloudcafe
qm set 9000 --ipconfig0 ip=dhcp
```
- Converting to template

```
qm template 7000
qm template 8000
qm template 9000
```

### Kubeadm Setup

- Create VM from Template by Login ProxmoX host

```
qm clone 8000 501 --name ubuntu --full
qm set 501 --memory 1024 --cores 1
qm start 501
```

- Login ubuntu host

- Installing Terraform & Ansible

```
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
add-apt-repository --yes --update ppa:ansible/ansible
apt update
apt install terraform ansible git -y
terraform version
ansible --version
```
- Download repo, edit and modify tf files as per environment

```
git clone https://github.com/cloudcafetech/homelab
cd homelab/kubeadm
```
- Copy sshkey files (gcpkey & gcpkey.pub) from proxmox

```scp root@<proxmox-host>:/root/gcp* .```

- Start K8s Setup using Kubeadm

```
terraform init
terraform plan 
terraform apply -auto-approve
```

### RKE2 Setup

- Create VM from Template by Login ProxmoX host

```
qm clone 8000 502 --name ubuntu-rke2 --full
qm set 502 --memory 1024 --cores 1
qm start 502
```

- Login ubuntu-rke2 host

- Installing Terraform & Ansible

```
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
add-apt-repository --yes --update ppa:ansible/ansible
apt update
apt install terraform ansible git -y
terraform version
ansible --version
```

- Download repo, edit and modify tf files as per environment

```
git clone https://github.com/cloudcafetech/homelab
cd homelab/rke2
```

- Copy sshkey files (gcpkey & gcpkey.pub) from proxmox

```scp root@<proxmox-host>:/root/gcp* .```

- Start K8s Setup using RKE2

```
terraform init
terraform plan 
terraform apply -auto-approve
```

### Openshift Setup

- Create VM from Template by Login ProxmoX host

```
qm clone 9000 214 --name jumphost --full
qm set 214 --memory 2048 --cores 2
qm set 214 --ipconfig0 ip=192.168.29.214/24,gw=192.168.29.1
qm start 214
```

- Login jumphost host

- Installing Terraform & Ansible

```
sudo yum install -y yum-utils python3 python3-pip
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo yum -y install terraform git net-tools nmstate bind-utils
python3 -m pip install ansible==4.10.0
```

- Download repo, prepare Jumphost for DNSMASQ,TFTP,WEB & OCP deplyoment (Modify files based as per requirement)

```
git clone https://github.com/cloudcafetech/homelab
cd homelab/ocp
chmod 755 ocp-jumphost.sh
#./ocp-jumphost.sh
sed -i '1s/^/nameserver 192.168.29.214\n/' /etc/resolv.conf
```

- Download pullsecret & put it in ocp-jumphost.sh

- Create VMs

##### Bootstrap first, make sure Bootstrap process complete

```
qm create 216 --name bootstrap --ide2 none,media=cdrom --ostype l26 --boot order='scsi0;ide2;net0' \
  --cpu cputype=max --cores 4 --sockets 1 --memory 10240 --scsihw virtio-scsi-pci --bootdisk scsi0 \
  --net0 bridge=vmbr0,virtio=BC:24:11:11:22:88 --scsi0 local-lvm:40,discard=on,ssd=1 \
  --serial0 socket --onboot yes

qm start 216

openshift-install --dir ~/ocp-install wait-for bootstrap-complete --log-level=debug

ssh -i /root/.ssh/id_rsa core@192.168.29.216

sudo su -

journalctl -b -f -u release-image.service -u bootkube.service
```

##### Start Master1, Master2 &  Master3 then rest of VMs

```
qm create 217 --name ocpmaster1 --ide2 none,media=cdrom --ostype l26 --boot order='scsi0;ide2;net0' \
  --cpu cputype=max --cores 4 --sockets 1 --memory 8192 --scsihw virtio-scsi-pci --bootdisk scsi0 \
  --net0 bridge=vmbr0,virtio=BC:24:11:11:22:11 --scsi0 local-lvm:40,discard=on,ssd=1 \
  --serial0 socket --onboot yes

qm start 217

qm create 218 --name ocpmaster2 --ide2 none,media=cdrom --ostype l26 --boot order='scsi0;ide2;net0' \
  --cpu cputype=max --cores 4 --sockets 1 --memory 8192 --scsihw virtio-scsi-pci --bootdisk scsi0 \
  --net0 bridge=vmbr0,virtio=BC:24:11:11:22:22 --scsi0 local-lvm:40,discard=on,ssd=1 \
  --serial0 socket --onboot yes

qm start 218

qm create 219 --name ocpmaster3 --ide2 none,media=cdrom --ostype l26 --boot order='scsi0;ide2;net0' \
  --cpu cputype=max --cores 4 --sockets 1 --memory 8192 --scsihw virtio-scsi-pci --bootdisk scsi0 \
  --net0 bridge=vmbr0,virtio=BC:24:11:11:22:33 --scsi0 local-lvm:40,discard=on,ssd=1 \
  --serial0 socket --onboot yes

qm start 219

qm create 220 --name ocpinfra1 --ide2 none,media=cdrom --ostype l26 --boot order='scsi0;ide2;net0' \
  --cpu cputype=max --cores 4 --sockets 1 --memory 8192 --scsihw virtio-scsi-pci --bootdisk scsi0 \
  --net0 bridge=vmbr0,virtio=BC:24:11:11:22:44 --scsi0 local-lvm:40,discard=on,ssd=1 \
  --serial0 socket --onboot yes

qm start 220

qm create 221 --name ocpinfra2 --ide2 none,media=cdrom --ostype l26 --boot order='scsi0;ide2;net0' \
  --cpu cputype=max --cores 4 --sockets 1 --memory 8192 --scsihw virtio-scsi-pci --bootdisk scsi0 \
  --net0 bridge=vmbr0,virtio=BC:24:11:11:22:55 --scsi0 local-lvm:40,discard=on,ssd=1 \
  --serial0 socket --onboot yes

qm start 221

qm create 222 --name ocpworker1 --ide2 none,media=cdrom --ostype l26 --boot order='scsi0;ide2;net0' \
  --cpu cputype=max --cores 4 --sockets 1 --memory 8192 --scsihw virtio-scsi-pci --bootdisk scsi0 \
  --net0 bridge=vmbr0,virtio=BC:24:11:11:22:66 --scsi0 local-lvm:40,discard=on,ssd=1 \
  --serial0 socket --onboot yes

qm start 222

qm create 223 --name ocpworker2 --ide2 none,media=cdrom --ostype l26 --boot order='scsi0;ide2;net0' \
  --cpu cputype=max --cores 4 --sockets 1 --memory 8192 --scsihw virtio-scsi-pci --bootdisk scsi0 \
  --net0 bridge=vmbr0,virtio=BC:24:11:11:22:77 --scsi0 local-lvm:40,discard=on,ssd=1 \
  --serial0 socket --onboot yes

qm start 223
```

#### OR 

- Start Openshift using Terraform

```
terraform init
terraform plan 
terraform apply -auto-approve
```

### Destroy Setup 

```terraform destroy -auto-approve```

### Hacking Setup

- Create VM from Template by Login ProxmoX host

```
qm clone 7000 100 --name kali --full
qm set 100 --memory 2048 --cores 3
qm set 100 --ipconfig0 ip=192.168.29.100/24,gw=192.168.29.1
qm start 100
```

- Login kali host
