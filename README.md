## Setup Container Platform on Proxmox
Setup Container (Kubeadm/RKE2/Openshift) Platform on Proxmox (Homelab)

- Create PROXMOX Host

- Create VM from GUI

- Login VM
  
- Download the ISO 

```
wget https://cloud-images.ubuntu.com/minimal/releases/jammy/release/ubuntu-22.04-minimal-cloudimg-amd64.img
wget https://cloud.centos.org/centos/8/x86_64/images/CentOS-8-GenericCloud-8.4.2105-20210603.0.x86_64.qcow2
```

- Change the file extension of the image to .qcow2

```
mv ubuntu-22.04-minimal-cloudimg-amd64.img ubuntu-22-04.qcow2
mv CentOS-8-GenericCloud-8.4.2105-20210603.0.x86_64.qcow2 centos-stream-8.qcow2
```

- Resize the downloaded cloud image

```
qemu-img resize ubuntu-22-04.qcow2 35G
qemu-img resize centos-stream-9.qcow2 35G
```

- Create the VM template using CLI

```
qm create 8000 --name ubuntu-2204-template --memory 1024 --core 1 --agent enabled=1 --net0 virtio,bridge=vmbr0
qm importdisk 8000 ubuntu-22-04.qcow2 local-lvm
qm set 8000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-8000-disk-0,discard=on,ssd=1
qm set 8000 --ide2 local-lvm:cloudinit
qm set 8000 --boot c --bootdisk scsi0
qm set 8000 --serial0 socket --vga serial0

qm create 9000 --name centos-9-template --memory 2048 --core 2 --agent enabled=1 --net0 virtio,bridge=vmbr0
qm importdisk 9000 centos-stream-9.qcow2 local-lvm
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
  - apt install -y qemu-guest-agent vim iputils-ping apt-transport-https ca-certificates gpg nfs-common curl wget git net-tools unzip jq zip nmap telnet dos2unix apparmor ldap-utils
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - reboot
EOF

cat <<EOF > /var/lib/vz/snippets/centos.yaml
#cloud-config
runcmd:
  - cd /etc/yum.repos.d/
  - sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*
  - sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*
  - yum update -y
  - yum install -y qemu-guest-agent git curl wget bind-utils jq httpd-tools zip unzip nfs-utils go nmap telnet dos2unix java-1.7.0-openjdk 
  - systemctl enable --now qemu-guest-agent
  - reboot
EOF

cat <<EOF > sshkey
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC7wP/7YbVIrlJArfj9xA12VVQufXVW3Zjhf99Dl9j6mI0m3aVT1/EXWDOAGPjRa0kx/kX6UjtDqtpVpMGyVsMWqxm6oKFqt/fkf8CWpK3xNVn1yOKU9GvSJxeRRvNEFsFXWws2w9qLbE/fD15gLJTOwRk8OhlZ66sNhVPq+y2JutWlbR/Uwl0CWCY0yGWnkkoHClkGmq8EnAvY7Tf6SqZVVLXC3R40qU16DqQNR2WSTuFq1td+PFJN/1N70VcfYZuD6GMkrVxVx54iLNWt1/pCpn+ekwARDjPeHeWSO5907Yat9URvyhwLZM/9oi4hM0W1MuUHm+nyUWWj3islVk3V cloudcafe
EOF

qm set 8000 --cicustom "vendor=local:snippets/ubuntu.yaml"
qm set 8000 --cipassword cloudcafe2675
qm set 8000 --sshkeys ./sshkey
qm set 8000 --tags ubuntu2204-template,k8s
qm set 8000 --ciuser cloudcafe
qm set 8000 --ipconfig0 ip=dhcp

qm set 9000 --cicustom "vendor=local:snippets/centos.yaml"
qm set 9000 --cipassword cloudcafe2675
qm set 9000 --sshkeys ./sshkey
qm set 9000 --tags centos9-template,k8s
qm set 9000 --ciuser cloudcafe
qm set 9000 --ipconfig0 ip=dhcp
```

- Converting to template

```
qm template 9000
qm template 8000
```

### Kubeadm Setup

- Create VM from Template

```
qm clone 8000 501 --name ubuntu--full
qm set 501 --memory 1024 --cores 1
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
- Download repo, edit provider.tf and modify ```credentials``` part

```
git clone https://github.com/cloudcafetech/homelab
cd homelab/kubeadm
```

- Start K8s Setup using Kubeadm

```
ssh-keygen -t rsa -N '' -f ./gcpkey -C cloudcafe -b 2048
terraform init
terraform plan 
terraform apply -auto-approve
```

- Destroy Setup 
```terraform destroy -auto-approve```

### RKE2 Setup

```

```

### Openshift Setup

- Create VM from Template

```
qm clone 9000 501 --name centos--full
qm set 601 --memory 1024 --cores 1
```

- Login ubuntu host

- Installing Terraform & Ansible

```
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo yum -y install terraform git net-tools nmstate syslinux bind-utils
pip3 install ansible
```

- Download repo, edit provider.tf and modify ```credentials``` part

```
git clone https://github.com/cloudcafetech/homelab
cd homelab/ocp
```

- Download pullsecret

- Start Openshift

```
terraform init
terraform plan 
terraform apply -auto-approve
```

### Destroy Setup 

```terraform destroy -auto-approve```
