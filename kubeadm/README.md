# Kubernetes on HOME Lab using Proxmox, Kubeadm and Terraform

## Installing tools

### Installing Terraform & Ansible

- Ubuntu
```
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
add-apt-repository --yes --update ppa:ansible/ansible
apt update
apt install terraform ansible -y
terraform version
ansible --version
```
- Amazon Linux
```
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo yum -y install terraform
pip3 install ansible
```
### Installing Git
```yum install git -y```

### Configure gcloud CLI
```
wget -q https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-470.0.0-linux-x86_64.tar.gz
tar -xf google-cloud-cli-470.0.0-linux-x86_64.tar.gz
./google-cloud-sdk/install.sh
./google-cloud-sdk/bin/gcloud init
```

### Download repo, edit provider.tf and modify ```credentials``` part
```
git clone https://github.com/cloudcafetech/homelab
cd homelab/kubeadm
```

### Start K8s Setup using Kubeadm
```
ssh-keygen -t rsa -N '' -f ./gcpkey -C k8sgcp -b 2048
terraform init
terraform plan 
terraform apply -auto-approve
```

### Destroy Setup 
```terraform destroy -auto-approve```
