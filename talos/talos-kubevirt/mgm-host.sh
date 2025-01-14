#!/bin/bash
## ReF: https://blog.aenix.io/installing-a-kubernetes-cluster-managed-by-cozystack-a-detailed-guide-by-gohost-and-%C3%A6nix-2b2d2e0ddbdb

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

apt update
apt upgrade -y
apt -y install ntp bind9 curl jq nload

service ntp restart
#service ntp status
sed -i -r 's/listen-on-v6/listen-on/g'  /etc/bind/named.conf.options 
sed -i '/listen-on/a \\tallow-query { any; };'  /etc/bind/named.conf.options 
apt -y  install apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update
apt install  -y docker-ce snapd make dialog nmap 
#systemctl status docker
#curl -sL https://talos.dev/install | sh

releases=$(curl -s https://api.github.com/repos/siderolabs/talos/releases | jq -r '.[].tag_name' | head -n 10)
echo -e "${YELLOW}Select version to download:${NC}"
select version in $releases; do
    if [[ -n "$version" ]]; then
        echo "You have selected a version $version"
        break
    else
        echo -e "${RED}Incorrect selection. Please try again. ${NC}"
    fi
done
url="https://github.com/siderolabs/talos/releases/download/$version/talosctl-linux-amd64"
wget $url -O talosctl
chmod +x talosctl
sudo mv talosctl /usr/local/bin/
#kubectl
releases=$(curl -s https://api.github.com/repos/kubernetes/kubernetes/releases | jq -r '.[].tag_name' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n 10)
echo -e "${YELLOW}Select kubectl version to download:${NC}"
select version in $releases; do
    if [[ -n "$version" ]]; then
        echo  "You have selected a version $version"
        break
    else
        echo -e "${RED}Incorrect selection. Please try again. ${NC}"
    fi
done
url="https://storage.googleapis.com/kubernetes-release/release/$version/bin/linux/amd64/kubectl"
wget $url -O kubectl
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

curl -LO https://github.com/kvaps/kubectl-node-shell/raw/master/kubectl-node_shell
chmod +x ./kubectl-node_shell
sudo mv ./kubectl-node_shell /usr/local/bin/kubectl-node_shell

curl -LO https://github.com/aenix-io/talm/releases/download/v0.5.7/talm-linux-amd64
chmod +x ./talm-linux-amd64
sudo mv ./talm-linux-amd64 /usr/local/bin/talm


echo "Specify the directory name for the configuration files,"
echo -e "the directory will be located in the catalog ${GREEN}/opt/${NC}. By default: ${GREEN}/opt/cozystack${NC}"
echo -e "${YELLOW}"
read -p "Enter the directory name: " cozystack
echo -e "${NC}"
if [ -z "$cozystack" ]; then    
  cozystack="cozystack" 
fi
mkdir -p /opt/$cozystack
curl -LO https://github.com/aenix-io/talos-bootstrap/raw/master/talos-bootstrap
mv talos-bootstrap /opt/$cozystack
chmod +x /opt/$cozystack/talos-bootstrap
snap install  yq
echo -e "${YELLOW}Specify IP network for etcd and kubelet${NC}"
echo -e "Default: ${GREEN} 192.168.100.0/24 ${NC}"
read -p "IP network (network/mask): " IPEK 
if [ -z "$IPEK" ]; then    
  IPEK="192.168.100.0/24" 
fi
#ADD FORWARD (RELATED,ESTABLISHED)
rule1="-d $IPEK -m state --state RELATED,ESTABLISHED -m comment --comment $cozystack -j ACCEPT"
if ! iptables-save | grep -q -- "-A FORWARD $rule1"; then
    iptables -I FORWARD -d $IPEK -m state --state RELATED,ESTABLISHED -m comment --comment $cozystack -j ACCEPT
fi
# ADD FORWARD
rule2="-s $IPEK -m comment --comment $cozystack -j ACCEPT"
if ! iptables-save | grep -q -- "-A FORWARD $rule2"; then
    iptables -I FORWARD -s $IPEK -m comment --comment $cozystack -j ACCEPT
fi
# ADD NAT
rule3="-s $IPEK -m comment --comment $cozystack -j MASQUERADE"
if ! iptables-save | grep -q -- "-A POSTROUTING $rule3"; then
    iptables -t nat -I POSTROUTING -s $IPEK -m comment --comment $cozystack -j MASQUERADE
fi
#sysctl -w net.ipv4.ip_forward=1
if ! grep -qF "$REQUIRED_SETTING" "$FILE"; then
  echo "net.ipv4.ip_forward = 1" | sudo tee -a "/etc/sysctl.conf" > /dev/null 
fi
sysctl -p
apt -y install iptables-persistent 

cat > /opt/$cozystack/patch.yaml <<EOT
machine:
  kubelet:
    nodeIP:
      validSubnets:
      - $IPEK
    extraConfig:
      maxPods: 512
  kernel:
    modules:
    - name: openvswitch
    - name: drbd
      parameters:
        - usermode_helper=disabled
    - name: zfs
    - name: spl
  install:
    image: ghcr.io/aenix-io/cozystack/talos:v1.7.1
  files:
  - content: |
      [plugins]
        [plugins."io.containerd.grpc.v1.cri"]
          device_ownership_from_security_context = true      
    path: /etc/cri/conf.d/20-customization.part
    op: create
cluster:
  network:
    cni:
      name: none
    dnsDomain: cozy.local
    podSubnets:
    - 10.244.0.0/16
    serviceSubnets:
    - 10.96.0.0/16
EOT

cat > /opt/$cozystack/patch-controlplane.yaml <<EOT
cluster:
  allowSchedulingOnControlPlanes: true
  controllerManager:
    extraArgs:
      bind-address: 0.0.0.0
  scheduler:
    extraArgs:
      bind-address: 0.0.0.0
  apiServer:
    certSANs:
    - 127.0.0.1
  proxy:
    disabled: true
  discovery:
    enabled: false
  etcd:
    advertisedSubnets:
    - $IPEK
EOT

echo -e "${YELLOW}========== Installed binary ===========${NC}"
echo "helm       in folder" $(which helm)
echo "yq         in folder" $(which yq)
echo "kubectl    in folder" $(which kubectl)
echo "docker     in folder" $(which  docker)
echo "talosctl   in folder" $(which  talosctl)
echo "dialog     in folder" $(which  dialog)
echo "nmap       in folder" $(which  nmap)
echo "talm       in folder" $(which  talm)
echo "node_shell       in folder" $(which  kubectl-node_shell)
echo -e "${YELLOW}========== services runing ===========${NC}"
echo "DNS Bind9"; systemctl is-active bind9 
echo "NTP"; systemctl is-active ntp
echo -e "${YELLOW}========== ADD Iptables Rule ===========${NC}"
iptables -S | grep $cozystack
iptables -t nat -S | grep $cozystack
echo -e "${RED}!!!  Please change the catalog to work with talos-bootstrap !!!${NC}"
echo -e "${GREEN}cd  /opt/$cozystack ${NC}"
