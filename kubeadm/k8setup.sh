#!/bin/sh

K8S_VER=1.29.0-00
USER=cloudcafe

K8S_VER_MJ=$(echo "$K8S_VER" | cut -c 1-4)
OP=$(uname -a | grep -iE 'ubuntu|debian')

if [ "$OP" != "" ]; then
 OS=Ubuntu
fi

########################## Common Setup #######################
common() {

echo -  Installing packages
if [ "$OS" = "Ubuntu" ]; then
 systemctl stop ufw
 systemctl stop apparmor.service
 systemctl disable --now ufw
 systemctl disable --now apparmor.service

 apt update -y
 apt-get install -y apt-transport-https ca-certificates gpg nfs-common curl wget git unzip telnet apparmor ldap-utils 
else
 systemctl stop firewalld
 systemctl disable firewalld
 setenforce 0
 sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux
 yum install -y git curl wget bind-utils jq httpd-tools zip unzip nfs-utils go nmap telnet dos2unix java-1.7.0-openjdk
fi

}

###################### K8S Common Setup ########################
k8scommon() {

common
echo - Disable swap
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
swapoff -a

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
 
modprobe overlay
modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system
lsmod | grep br_netfilter
lsmod | grep overlay
sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward

## Installation based on OS

if [ "$OS" = "Ubuntu" ]; then
 mkdir -m 755 /etc/apt/keyrings
 curl -fsSL https://pkgs.k8s.io/core:/stable:/v${K8S_VER_MJ}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
 echo deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v$K8S_VER_MJ/deb/ / | sudo tee /etc/apt/sources.list.d/kubernetes.list
 curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
 sudo chmod a+r /etc/apt/keyrings/docker.gpg
 echo "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
 apt update -y
 rm -I /etc/containerd/config.toml
 apt install -y containerd.io
 apt install -y kubelet kubeadm kubectl
 apt-mark hold kubelet kubeadm kubectl
else
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v$K8S_VER_MJ/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v$K8S_VER_MJ/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

 yum config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
 yum install -y yum-utils containerd.io && rm -I /etc/containerd/config.toml
 yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
fi

mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml 
sed -i -e 's\            SystemdCgroup = false\            SystemdCgroup = true\g' /etc/containerd/config.toml

cat <<EOF | sudo tee /etc/crictl.yaml
runtime-endpoint: "unix:///run/containerd/containerd.sock"
timeout: 0
debug: false
EOF

systemctl start containerd
systemctl enable --now containerd
systemctl start kubelet
systemctl enable --now kubelet

sleep 5
systemctl restart containerd

# K8s images pull
kubeadm config images pull

}

####################### Open LDAP Setup #######################
ldapsetup() {

echo -  Open LDAP Setup on [$(hostname)]
common

if [ "$OS" = "Ubuntu" ]; then
 apt update -y
 apt install docker.io ldap-utils -y
 HIP=`ip -o -4 addr list ens4 | awk '{print $4}' | cut -d/ -f1`
else
 yum install docker-ce docker-ce-cli -y
 systemctl start docker
 systemctl enable --now docker
 HIP=`ip -o -4 addr list eth0 | awk '{print $4}' | cut -d/ -f1`
fi

echo - starting Open LDAP Service
docker run --restart=always --name ldap-server -p 389:389 -p 636:636 \
--env LDAP_TLS_VERIFY_CLIENT=try \
--env LDAP_ORGANISATION="Cloudcafe Org" \
--env LDAP_DOMAIN="cloudcafe.org" \
--env LDAP_ADMIN_PASSWORD="StrongAdminPassw0rd" \
--detach osixia/openldap:latest

echo - Check LDAP Server UP and Running
sleep 10
until [ $(docker inspect -f {{.State.Running}} ldap-server)"=="true ]; do echo "Waiting for LDAP to UP..." && sleep 1; done;

echo - Add LDAP User and Group
wget -q https://raw.githubusercontent.com/cloudcafetech/k8s-ad-integration/main/ldap-records.ldif
ldapadd -x -H ldap://$HIP -D "cn=admin,dc=cloudcafe,dc=org" -w StrongAdminPassw0rd -f ldap-records.ldif

echo - LDAP query for Verify
ldapsearch -x -H ldap://$HIP -D "cn=admin,dc=cloudcafe,dc=org" -b "dc=cloudcafe,dc=org" -w "StrongAdminPassw0rd"

}

######################### web Setup ###########################
websetup() {

echo - Web Server Setup on [$(hostname)]
common

if [ "$OS" = "Ubuntu" ]; then
 apt install apache2 -y
 sed -i 's/Listen 80/Listen 0.0.0.0:8080/' /etc/apache2/ports.conf
 sed -i 's/80/8080/' /etc/apache2/sites-enabled/000-default.conf
 systemctl start apache2
 systemctl enable --now apache2
 systemctl restart apache2
else
 yum install -y httpd
 sed -i 's/Listen 80/Listen 0.0.0.0:8080/' /etc/httpd/conf/httpd.conf
 setsebool -P httpd_read_user_content 1
 systemctl start httpd
 systemctl enable --now httpd
fi 

}

########################## LB Setup ###########################
lbsetup() {

echo - LB Setup on [$(hostname)]
common

if [ "$OS" = "Ubuntu" ]; then
 apt install -y haproxy  
else
 yum install -y haproxy 
fi

#websetup

}

######################## Master Setup #########################
master() {

echo - Setting Kubeconfig
mkdir -p $HOME/.kube
mkdir -p /home/$USER/.kube
cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
cp -f /etc/kubernetes/admin.conf /home/$USER/.kube/config
cp -f /etc/kubernetes/admin.conf /home/$USER/config
chown -R $USER:$USER /home/$USER
chown $(id -u):$(id -g) $HOME/.kube/config
echo 'export KUBECONFIG=$HOME/.kube/config' >> $HOME/.profile
echo 'alias oc=/usr/bin/kubectl' >> $HOME/.profile

}

############### K8s Eco System Setup using Argo #################
k8secoa() {

curl -#OL https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
sudo mv mc /usr/local/bin/mc

kubectl create ns minio-store
kubectl create ns cert-manager
kubectl create ns argocd
kubectl create ns monitoring
kubectl create ns logging
kubectl create ns velero
kubectl create ns argo-backup

echo - Setup K8S Networking
curl -#OL https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
kubectl create -f kube-flannel.yml

echo - Setup ArgoCD
curl -#OL https://raw.githubusercontent.com/cloudcafetech/k8s-terraform/master/argo/argo-crd.yaml
curl -#OL https://raw.githubusercontent.com/cloudcafetech/k8s-terraform/master/argo/argo-install.yaml
kubectl create -f argo-crd.yaml -n argocd
kubectl create -f argo-install.yaml -n argocd
argopo1=`kubectl get pod -n argocd | grep argocd-server | awk '{print $1}' | head -1`
argopo2=`kubectl get pod -n argocd | grep argocd-server | awk '{print $1}' | tail -1`
kubectl wait pods/$argopo1 --for=condition=Ready --timeout=2m -n argocd
kubectl wait pods/$argopo2 --for=condition=Ready --timeout=2m -n argocd
sleep 30

echo - K8s Addons
curl -#OL https://raw.githubusercontent.com/cloudcafetech/k8s-terraform/master/argo/addon-app.yaml
kubectl create -f addon-app.yaml -n argocd
sleep 10
ingpo=`kubectl get pod -n ingress-nginx | grep ingress-nginx-controller | awk '{print $1}'`
kubectl wait pods/$ingpo --for=condition=Ready --timeout=2m -n ingress-nginx

echo - Setup MinIO
curl -#OL https://raw.githubusercontent.com/cloudcafetech/k8s-terraform/master/argo/minio-app.yaml
kubectl create -f minio-app.yaml -n argocd
sleep 10
kubectl wait pods/minio-0 --for=condition=Ready --timeout=2m -n minio-store
kubectl wait pods/minio-1 --for=condition=Ready --timeout=2m -n minio-store
kubectl create -f all-ing.yaml
sleep 10
minioing=`kubectl get ing -n minio-store | grep minio-api | awk '{ print $3}'`
mc config host add k8sminio http://$minioing admin admin2675 --insecure
# mc mb k8sminio/lokik8sminio --insecure
# mc mb k8sminio/promk8sminio --insecure
# mc mb k8sminio/velero --insecure
# mc mb k8sminio/argo-backup --insecure

echo - Setup Monitoring
curl -#OL https://github.com/cloudcafetech/kubesetup/raw/master/monitoring/dashboard/pod-monitoring.json
curl -#OL https://github.com/cloudcafetech/kubesetup/raw/master/monitoring/dashboard/kube-monitoring-overview.json
kubectl create configmap grafana-dashboards -n monitoring --from-file=pod-monitoring.json --from-file=kube-monitoring-overview.json
curl -#OL https://raw.githubusercontent.com/cloudcafetech/k8s-terraform/master/argo/monitoring-app.yaml
kubectl create -f monitoring-app.yaml -n argocd

echo - Setup Thanos
curl -#OL https://raw.githubusercontent.com/cloudcafetech/k8s-terraform/master/argo/thanos-app.yaml
kubectl create -f thanos-app.yaml -n argocd

echo - Setup Logging
curl -#OL https://raw.githubusercontent.com/cloudcafetech/k8s-terraform/master/argo/logging-app.yaml
kubectl create -f logging-app.yaml -n argocd

echo - Setup Grafana
curl -#OL https://raw.githubusercontent.com/cloudcafetech/k8s-terraform/master/argo/grafana-app.yaml
kubectl create -f grafana-app.yaml -n argocd

echo - Setup CertManager
curl -#OL https://raw.githubusercontent.com/cloudcafetech/k8s-terraform/master/argo/certmanager-app.yaml
kubectl create -f certmanager-app.yaml -n argocd

echo - Setup Velero
curl -#OL https://raw.githubusercontent.com/cloudcafetech/k8s-terraform/master/argo/velero-app.yaml
kubectl create -f velero-app.yaml -n argocd

echo - Setup Argo Backup
curl -#OL https://raw.githubusercontent.com/cloudcafetech/k8s-terraform/master/argo/argo-backup-app.yaml
kubectl create -f argo-backup-app.yaml -n argocd

}

############### K8s Eco System Setup #################
k8seco() {

curl -#OL https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
sudo mv mc /usr/local/bin/mc

echo - Setup K8S Networking
curl -#OL https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
curl -#OL https://raw.githubusercontent.com/cloudcafetech/k8s-terraform/master/deploy.yaml
kubectl create -f kube-flannel.yml
kubectl create -f deploy.yaml
sleep 10
kubectl scale --replicas=2 deployment/ingress-nginx-controller -n ingress-nginx

mkdir monitoring
cd monitoring

kubectl create ns minio-store
kubectl create ns logging
kubectl create ns monitoring

echo - Setup Metric Server
curl -#OL https://raw.githubusercontent.com/cloudcafetech/rke2-airgap/main/metric-server.yaml
kubectl create -f metric-server.yaml

echo -  Setup local storage
curl -#OL https://raw.githubusercontent.com/cloudcafetech/rke2-airgap/main/local-path-storage.yaml
kubectl create -f local-path-storage.yaml

echo -  Setup reloader
curl -#OL https://raw.githubusercontent.com/cloudcafetech/k8s-ad-integration/main/reloader.yaml
kubectl create -f reloader.yaml

echo - Setup Monitoring
curl -#OL https://raw.githubusercontent.com/cloudcafetech/AI-for-K8S/main/kubemon.yaml
curl -#OL https://github.com/cloudcafetech/kubesetup/raw/master/monitoring/dashboard/pod-monitoring.json
curl -#OL https://github.com/cloudcafetech/kubesetup/raw/master/monitoring/dashboard/kube-monitoring-overview.json
kubectl create configmap grafana-dashboards -n monitoring --from-file=pod-monitoring.json --from-file=kube-monitoring-overview.json

echo - Setup Logging
curl -#OL https://raw.githubusercontent.com/cloudcafetech/kubesetup/master/logging/promtail.yaml
curl -#OL https://raw.githubusercontent.com/cloudcafetech/k8s-ad-integration/main/kubelog.yaml
curl -#OL https://raw.githubusercontent.com/cloudcafetech/k8s-ad-integration/main/loki.yaml
curl -#OL https://raw.githubusercontent.com/cloudcafetech/k8s-terraform/master/gcp-terraform-rke2/minio.yaml
kubectl create secret generic loki -n logging --from-file=loki.yaml
kubectl create -f kubelog.yaml -n logging
kubectl delete ds loki-fluent-bit-loki -n logging
kubectl wait pods/loki-0 --for=condition=Ready --timeout=2m -n logging

}

############## K8s AD/LDAP Integration #################
adauth() {

LBPUBIP=$lbpubip
LBPRIIP=$lbpriip
LDAPIP=$ldapip

mkdir adauth
cd adauth

curl -#OL https://raw.githubusercontent.com/cloudcafetech/k8s-terraform/master/all-ing.yaml
curl -#OL https://raw.githubusercontent.com/cloudcafetech/k8s-terraform/master/ad-ldap/ad-enable-ing.yaml
curl -#OL https://raw.githubusercontent.com/cloudcafetech/k8s-terraform/master/ad-ldap/dex.yaml
curl -#OL https://raw.githubusercontent.com/cloudcafetech/k8s-terraform/master/ad-ldap/dashboard-ui.yaml
curl -#OL https://raw.githubusercontent.com/cloudcafetech/k8s-terraform/master/ad-ldap/dex-ldap-cm.yaml
curl -#OL https://raw.githubusercontent.com/cloudcafetech/k8s-terraform/master/ad-ldap/argocd-cm-ldap.yaml
curl -#OL https://raw.githubusercontent.com/cloudcafetech/k8s-terraform/master/ad-ldap/oauth-proxy.yaml
curl -#OL https://raw.githubusercontent.com/cloudcafetech/k8s-terraform/master/ad-ldap/gangway.yaml
curl -#OL https://raw.githubusercontent.com/cloudcafetech/k8s-terraform/master/ad-ldap/ldap.toml
curl -#OL https://raw.githubusercontent.com/cloudcafetech/k8s-terraform/master/ad-ldap/minio-ad.yaml
curl -#OL https://raw.githubusercontent.com/cloudcafetech/k8s-terraform/master/ad-ldap/read-access.json
curl -#OL https://raw.githubusercontent.com/cloudcafetech/k8s-terraform/master/ad-ldap/admin-access.json
curl -#OL https://raw.githubusercontent.com/cloudcafetech/k8s-terraform/master/argo/grafana-ad-app.yaml

sed -i "s/ldap-ip-pri/$LDAPIP/g" *
sed -i "s/lb-ip-pub/$LBPUBIP/g" *
sed -i "s/lb-ip-pri/$LBPRIIP/g" *

kubectl create ns auth-system 
#kubectl create ns kubernetes-dashboard

echo - Delete old Ingress
kubectl delete -f all-ing.yaml

echo - Creating AD enabled Ingress
kubectl create -f ad-enable-ing.yaml

echo - Setup ArgoCD with AD and LDAP
kubectl delete cm argocd-cm argocd-cmd-params-cm argocd-rbac-cm -n argocd
kubectl create -f argocd-cm-ldap.yaml -n argocd
argopo1=`kubectl get pod -n argocd | grep argocd-server | awk '{print $1}' | head -1`
argopo2=`kubectl get pod -n argocd | grep argocd-server | awk '{print $1}' | tail -1`
argopodex1=`kubectl get pod -n argocd | grep dex-server | awk '{print $1}'`
kubectl delete po $argopo1 $argopo2 $argopodex1 -n argocd
sleep 10
argopo1=`kubectl get pod -n argocd | grep argocd-server | awk '{print $1}' | head -1`
argopo2=`kubectl get pod -n argocd | grep argocd-server | awk '{print $1}' | tail -1`
argopodex1=`kubectl get pod -n argocd | grep dex-server | awk '{print $1}'`
kubectl wait pods/$argopo1 --for=condition=Ready --timeout=2m -n argocd
kubectl wait pods/$argopo2 --for=condition=Ready --timeout=2m -n argocd
kubectl wait pods/$argopodex1 --for=condition=Ready --timeout=2m -n argocd
sleep 30

echo - Setup K8s Dashboard
#kubectl get secret dex --namespace=auth-system -oyaml | grep -v '^\s*namespace:\s' | kubectl apply --namespace=kubernetes-dashboard -f -
kubectl apply -f dashboard-ui.yaml

echo - Dex Deployment
kubectl create -f dex-ldap-cm.yaml
kubectl create -f dex.yaml

# Check for Dex POD UP
echo "Waiting for Dex POD ready .."
DEXPOD=$(kubectl get pod -n auth-system | grep dex | awk '{print $1}')
kubectl wait pods/$DEXPOD --for=condition=Ready --timeout=2m -n auth-system

echo - Oauth Deployment
kubectl create -f oauth-proxy.yaml

# Check for OAuth POD UP
echo "Waiting for OAuth POD ready .."
OAPOD=$(kubectl get pod -n auth-system | grep oauth | awk '{print $1}')
kubectl wait pods/$OAPOD --for=condition=Ready --timeout=2m -n auth-system

echo - Gangway Deployment
kubectl create secret generic gangway-key --from-literal=sesssionkey=$(openssl rand -base64 32) -n auth-system
kubectl create -f gangway.yaml

echo - Check for Gangway POD UP
echo "Waiting for Gangway POD ready .."
GWPOD=$(kubectl get pod -n auth-system | grep gangway | awk '{print $1}')
kubectl wait pods/$GWPOD --for=condition=Ready --timeout=2m -n auth-system

echo - Setup MinIO with AD and LDAP
kubectl get secret dex -n auth-system -o jsonpath="{['data']['ca\.crt']}" | base64 --decode >ca.crt
kubectl create cm dex-cert --from-file=ca.crt -n minio-store
kubectl delete app minio -n argocd
sleep 20
kubectl delete -f minio-ad.yaml -n minio-store
sleep 10
kubectl create -f minio-ad.yaml -n minio-store
sleep 10
kubectl wait pods/minio-0 --for=condition=Ready --timeout=2m -n minio-store
kubectl wait pods/minio-1 --for=condition=Ready --timeout=2m -n minio-store
sleep 10
mc admin policy create k8sminio admins admin-access.json
mc admin policy create k8sminio developers read-access.json

# Monitoring login (LDAP) enablement
kubectl delete app grafana -n argocd
sleep 20
kubectl create secret generic grafana-ldap-toml --from-file=ldap.toml=./ldap.toml -n monitoring
kubectl create -f grafana-ad-app.yaml -n argocd

# Check for Grafana POD UP and Running
echo "Waiting for Grafana POD UP and Running without Error .."
GFPOD=$(kubectl get pod -n monitoring | grep grafana | awk '{print $1}')
kubectl wait pods/$GFPOD --for=condition=Ready --timeout=2m -n monitoring

# Creating AD enable user RBAC
kubectl create clusterrolebinding debrupkar-view --clusterrole=view --user=debrupkar@cloudcafe.org 
kubectl create clusterrolebinding prasenkar-admin --clusterrole=admin --user=prasenkar@cloudcafe.org
kubectl create rolebinding titli-view-default --clusterrole=view --user=titlikar@cloudcafe.org -n default
kubectl create rolebinding rajat-admin-default --clusterrole=admin --user=rajatkar@cloudcafe.org -n default

}

####### Copy Certificate and edit the Kubernetes API configuration ##########
apialter () {

LBPUBIP=$lbpubip

echo - Copy Certificate and edit the Kubernetes API configuration for Kubeadm
kubectl get secret dex -n auth-system -o jsonpath="{['data']['ca\.crt']}" | base64 --decode >ca.crt
curl -#OL https://raw.githubusercontent.com/cloudcafetech/k8s-terraform/master/ad-ldap/add-line.txt
sed -i "s/lb-ip-pub/$LBPUBIP/g" add-line.txt
sudo cp ca.crt /etc/kubernetes/pki/dex-ca.crt
sudo sed -i '/--allow-privileged=true/r add-line.txt' /etc/kubernetes/manifests/kube-apiserver.yaml
sleep 15
}

########################### usage #############################
usage () {
  echo ""
  echo " Usage: $0 {lbsetup | websetup | master | worker | k8seco}"
  echo ""
  echo " $0 lbsetup # Setup LB (HAPROXY) Server"
  echo ""
  echo " $0 websetup # Setup Http (Apache) Server"
  echo ""
  echo " $0 master # Setup Master Node"
  echo ""
  echo " $0 worker # Setup Worker Node"
  echo ""
  echo " $0 k8seco # Setup K8s Eco System"
  echo ""
  exit 1
}

case "$1" in
        lbsetup ) lbsetup;;
        ldapsetup ) ldapsetup;;
        websetup ) websetup;;
        k8scommon ) k8scommon;;
        master ) master;;
        worker ) worker;;
        k8secoa ) k8secoa;;
        k8seco ) k8seco;;
        adauth ) adauth;;
        apialter ) apialter ;;
        *) usage;;
esac
