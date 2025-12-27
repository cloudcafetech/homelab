# Setup SNO ACM ZTP HCP

### SSH KEYGEN Setup

```ssh-keygen -f ./id_rsa -t rsa -N ''```

### DNS Setup

- Install BIND and tools

```yum install bind bind-utils -y```

- Verify nslookup should resolve from network 

>         allow-query     { localhost; 192.168.1.0/24;};  section in /etc/named.conf file.

- Create a new zone file

```
cat << "EOF" > /var/named/pkar.tech.zone

$TTL 86400
@   IN  SOA ns1.pkar.tech. admin.pkar.tech. (
        2025040301 3600 1800 1209600 86400 )

    IN NS ns1.pkar.tech.

; DNS Server
ns1.pkar.tech.           	IN A 192.168.1.161

; SNO ACM cluster
api.sno-acm.pkar.tech.    	IN A 192.168.1.18
api-int.sno-acm.pkar.tech.	IN A 192.168.1.18
*.apps.sno-acm.pkar.tech. 	IN A 192.168.1.18

; SNO ZTP cluster
api.sno-ztp.pkar.tech.    	IN A 192.168.1.21
api-int.sno-ztp.pkar.tech.	IN A 192.168.1.21
*.apps.sno-ztp.pkar.tech. 	IN A 192.168.1.21
EOF
```

- Update (add below text) /etc/named.conf to load new zone

```
zone "pkar.tech" IN {
    type master;
    file "pkar.tech.zone";
};
```

- Restart DNS

```systemctl restart named```

### Setup Bridge network on CentOS host

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

## Setup SNO ACM Cluster

- Create SNO Cluster in RedHAt portal (https://console.redhat.com/)

- Create VM for SNO ACM Cluster

```
mkdir -p /home/sno/ocp-acm
cd /home/sno/ocp-acm/
qemu-img create -f qcow2 /home/sno/ocp-acm/sno-acm.qcow2 120G

virt-install \
  --name=sno-acm \
  --ram=28384 \
  --vcpus=12 \
  --cpu host-passthrough \
  --os-variant=rhel8.0 \
  --noreboot \
  --events on_reboot=restart \
  --noautoconsole \
  --import \
  --cdrom /home/sno/ocp-acm/sno-acm.iso \
  --disk path=/home/sno/ocp-acm/sno-acm.qcow2,size=120 \
  --network network=host-bridge \
  --graphics vnc,listen=0.0.0.0,port=5975,password=pkar2675

sleep 10
virsh list --all
```

- Download Kubeconfig from Redhat Portal (https://console.redhat.com/)

- Verify Cluster

```
oc get no
oc get co
oc get po -A | grep -Ev "Running|Completed"
```

### Setup ACM

- Install ACM Operator

```
cat << EOF > acm-operator.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: open-cluster-management
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: open-cluster-management
  namespace: open-cluster-management
spec:
  targetNamespaces:
  - open-cluster-management  
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: advanced-cluster-management
  namespace: open-cluster-management
spec:
  channel: release-2.15
  installPlanApproval: Automatic
  name: advanced-cluster-management
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

oc create -f  acm-operator.yaml
sleep 20
```

- Install ACM Multi Cluster Hub

```
cat << EOF > acm-mch.yaml
apiVersion: operator.open-cluster-management.io/v1
kind: MultiClusterHub
metadata:
  name: multiclusterhub
  namespace: open-cluster-management
spec: {}
EOF

oc create -f acm-mch.yaml
```
- Check ACM Deployment

```
oc get po -n open-cluster-management
oc get po -n multicluster-engine
```

### Setup NFS Storage in ACM cluster

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

### Setup OCP GitOps

- Install GitOps Operator

```
oc create ns openshift-gitops-operator

cat << EOF > gitops-operator.yaml
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-gitops-operator
  namespace: openshift-gitops-operator
spec:
  upgradeStrategy: Default
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-gitops-operator
  namespace: openshift-gitops-operator
spec:
  channel: latest
  installPlanApproval: Automatic
  name: openshift-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

oc create -f  gitops-operator.yaml
sleep 40
```
- Check GitOps Deployment

```
oc get pods -n openshift-gitops-operator
oc get pods -n openshift-gitops
```
- Openshift Gitops RBAC for clusterinstance and policy

```
cat << EOF > openshift-gitops-acm-rbac.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: openshift-gitops-acm-clusterrole
rules:
- apiGroups: ["siteconfig.open-cluster-management.io"]
  resources: ["clusterinstances"]
  verbs: ["create", "get", "list", "update", "delete", "watch"]
- apiGroups: ["policy.open-cluster-management.io"]
  resources: ["policies", "placementbindings"]
  verbs: ["create", "get", "list", "update", "delete", "watch", "patch"]
- apiGroups: ["apps.open-cluster-management.io"]
  resources: ["placementrules"]
  verbs: ["create", "get", "list", "update", "delete", "watch", "patch"]
- apiGroups: ["cluster.open-cluster-management.io"]
  resources: ["placements", "placements/status", "placementdecisions", "placementdecisions/status"]
  verbs: ["create", "get", "list", "update", "delete", "watch", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: openshift-gitops-acm-clusterrolebinding
subjects:
- kind: ServiceAccount
  name: openshift-gitops-argocd-application-controller
  namespace: openshift-gitops
roleRef:
  kind: ClusterRole
  name: openshift-gitops-acm-clusterrole
  apiGroup: rbac.authorization.k8s.io
EOF

oc create -f openshift-gitops-acm-rbac.yaml
```

- Integrate Kustomize plugin with OpenShift GitOps

```
cat << EOF > argocd-patch.yaml
apiVersion: argoproj.io/v1beta1
kind: ArgoCD
metadata:
  name: openshift-gitops
  namespace: openshift-gitops
spec:
  repo:
    env:
    - name: KUSTOMIZE_PLUGIN_HOME
      value: /etc/kustomize/plugin
    initContainers:
    - args:
      - -c
      - cp /etc/kustomize/plugin/policy.open-cluster-management.io/v1/policygenerator/PolicyGenerator
        /policy-generator/PolicyGenerator
      command:
      - /bin/bash
      image: registry.redhat.io/rhacm2/multicluster-operators-subscription-rhel9:v2.11.7-13
      #image: registry.redhat.io/rhacm2/multicluster-operators-subscription-rhel8:v2.5
      name: policy-generator-install
      volumeMounts:
      - mountPath: /policy-generator
        name: policy-generator
    volumeMounts:
    - mountPath: /etc/kustomize/plugin/policy.open-cluster-management.io/v1/policygenerator
      name: policy-generator
    volumes:
    - emptyDir: {}
      name: policy-generator
  kustomizeBuildOptions: --enable-alpha-plugins
EOF

oc -n openshift-gitops patch argocd openshift-gitops --type merge --patch -f argocd-patch.yaml
```

### Setup MetalLB

- Install MetalLB Operator

```
cat << EOF > metallb-operator.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: metallb-system
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: metallb-operator
  namespace: metallb-system
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: metallb-operator-sub
  namespace: metallb-system
spec:
  channel: stable
  name: metallb-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

oc create -f  metallb-operator.yaml
sleep 40
```
- Confirm install plan

```oc get installplan -n metallb-system```

- Verify Operator is installed

```oc get clusterserviceversion -n metallb-system -o custom-columns=Name:.metadata.name,Phase:.status.phase```

- Create MetalLB instance

```
cat << EOF > metallb-system.yaml
apiVersion: metallb.io/v1beta1
kind: MetalLB
metadata:
  name: metallb
  namespace: metallb-system
EOF

oc create -f metallb-system.yaml
```

- Check Metallb Deployment

```oc get pods -n metallb-system```

- Define IP Pool

```
cat << EOF > metallb-ip-pool.yaml
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

- Verify

```oc get ipaddresspool -n metallb-system```

### Setup ZTP in ACM

> Without Storage Setup DO NOT run following steps

- Enable SiteConfig Operator

```
oc get multiclusterhubs.operator.open-cluster-management.io multiclusterhub -n open-cluster-management -o yaml | grep siteconfig -B2 -A2
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

### Setup Sushy Emulator

```
sudo mkdir -p /etc/sushy/
cat << "EOF" | sudo tee /etc/sushy/sushy-emulator.conf
SUSHY_EMULATOR_LISTEN_IP = u'0.0.0.0'
SUSHY_EMULATOR_LISTEN_PORT = 8000
SUSHY_EMULATOR_SSL_CERT = None
SUSHY_EMULATOR_SSL_KEY = None
SUSHY_EMULATOR_OS_CLOUD = None
SUSHY_EMULATOR_LIBVIRT_URI = u'qemu:///system'
SUSHY_EMULATOR_IGNORE_BOOT_DEVICE = True
SUSHY_EMULATOR_BOOT_LOADER_MAP = {
    u'UEFI': {
        u'x86_64': u'/usr/share/OVMF/OVMF_CODE.secboot.fd'
    },
    u'Legacy': {
        u'x86_64': None
    }
}
EOF

export SUSHY_TOOLS_IMAGE=${SUSHY_TOOLS_IMAGE:-"quay.io/metal3-io/sushy-tools"}
sudo podman create --net host --privileged --name sushy-emulator -v "/etc/sushy":/etc/sushy -v "/var/run/libvirt":/var/run/libvirt "${SUSHY_TOOLS_IMAGE}" sushy-emulator -i :: -p 8000 --config /etc/sushy/sushy-emulator.conf
sudo podman start sushy-emulator
sudo firewall-cmd --add-port=8000/tcp

# First, use Podman to create a systemd unit
sudo sh -c 'podman generate systemd --restart-policy=always -t 1 sushy-emulator > /etc/systemd/system/sushy-emulator.service'
sudo systemctl daemon-reload

# Next, use systemd to start and enable the Sushy-Emulator
sudo systemctl restart sushy-emulator.service
sudo systemctl enable sushy-emulator.service
sudo systemctl status sushy-emulator.service

```

### Create VM for new Cluster (ZTP)

```
qemu-img create -f qcow2 /home/sno/sno-ztp.qcow2 120G

virt-install \
  --name=sno-ztp \
  --uuid=d54f3990-12c9-4749-8b89-a1242e6af101 \
  --ram=16536 \
  --vcpus=12 \
  --cpu host-passthrough \
  --os-variant rhel8.0 \
  --noreboot \
  --events on_reboot=restart \
  --noautoconsole \
  --boot hd,cdrom \
  --import \
  --disk path=/home/sno/sno-ztp.qcow2,size=20 \
  --network type=direct,source=br0,mac=52:54:00:42:a4:10,source_mode=bridge,model=virtio \
  --graphics vnc,listen=0.0.0.0,port=5976,password=pkar2675
```

### Create Clusterinstance 

- Create Namespace

```oc create ns sno-ztp```

- Create Pull Secret (First login Redhat console url then download section)

```oc create secret generic pull-secret -n sno-ztp --from-file=.dockerconfigjson=pull-secret.json --type=kubernetes.io/dockerconfigjson```

- Create BMC Credentials Secret

```oc create secret generic bmc-secret -n sno-ztp --from-literal=username=admin --from-literal=password=password```

- Create Cluster Instance

```
cat << "EOF" > sno-ztp-clusterinstance.yaml
apiVersion: siteconfig.open-cluster-management.io/v1alpha1
kind: ClusterInstance
metadata:
  name: sno-ztp
  namespace: sno-ztp
spec:
  clusterName: sno-ztp
  clusterImageSetNameRef: img4.18.5-x86-64-appsub
  baseDomain: pkar.tech
  cpuArchitecture: x86_64
  holdInstallation: false
  cpuPartitioningMode: None
  networkType: OVNKubernetes
  machineNetwork:
    - cidr: 192.168.1.0/24
  pullSecretRef:
    name: pull-secret
  templateRefs:
    - name: ai-cluster-templates-v1
      namespace: open-cluster-management
  sshPublicKey: ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDFoML+fLuVqwcWbtH6TGiq9VxIUi0umNaJAEVixhTLhiAnHEk8OT8p06fFxYAM+1B+oMPfU5u/36+gWIrTPUD+jgzdEZksZ8BoHveDOrrJBEGWD4xsVGj7szV4bXBEHbxgD4WeILIAtYy/QMaH+Nxkdj/eUoD7KYSelNkwKPJpJkbTIzQs6r76VYYxQkeGbraRJ5EnGQWjeAVqXXlCvzssJxGbEagub3cmv99niCa3EfUd6fPS4OjqYI7SkYSdJezRHJ5Q+eLuqTG5oicD8MWbWMsEvPC97n9bmqLsrfh1g+K69eE92a2Gu6kSwZIMcdbktEBeEeUDz/lgVG1+y/z4JFB57dSVxtdYrawxFMvVNVmX1XXydkQzOJU7WQ3Wm55qS8Zv9vCEmu9hEdZ0AC3+5pFktprNj861ETiKs969HG/xIZxUqvmWVJQI9c9eIo1KF7wxEav5VvCxV4yZq7ulUjkuMOZIPvqyWIbjz1kwFmXU9k1Ihi4gUsnKA94eKpU= root@lenevo-ts-w2
  nodes:
    - role: master
      hostName: sno-ztp
      ironicInspect: ''
      bootMACAddress: '52:54:00:42:a4:10'
      bootMode: UEFI
      automatedCleaningMode: disabled
      cpuArchitecture: x86_64
      templateRefs:
        - name: ai-node-templates-v1
          namespace: open-cluster-management
      bmcAddress: 'redfish-virtualmedia+http://192.168.1.161:8000/redfish/v1/Systems/d54f3990-12c9-4749-8b89-a1242e6af101'
      bmcCredentialsName:
        name: bmc-secret
      nodeNetwork:
        interfaces:
          - macAddress: '52:54:00:42:a4:10'
            name: enp1s0
        config:
          interfaces:
            - name: enp1s0
              type: ethernet
              state: up
              ipv4:
                enabled: true
                dhcp: false
                address:
                  - ip: 192.168.1.21
                    prefix-length: 24
              ipv6:
                enabled: false
          dns-resolver:
            config:
              search:
                - pkar.tech
              server:
                - 192.168.1.18
                - 192.168.1.21
                - 192.168.1.1
          routes:
            config:
              - destination: 0.0.0.0/0
                next-hop-address: 192.168.1.1
                next-hop-interface: enp1s0
EOF

oc apply -f sno-ztp-clusterinstance.yaml
sleep 20
oc get clusterinstance sno-ztp -n sno-ztp

```

# HCP (Hosted Control Plane) using Hypershift

- Verify Hypershift enable 

```
oc get mce multiclusterengine -oyaml | grep hypershift -B2 -A2
oc get po -A | grep hypershift
```
- Patch the RHACM Hub Application ingress controller to allow wildcard DNS routes

```
oc get ingresscontroller default -n openshift-ingress-operator | grep wildcardPolicy
oc patch ingresscontroller -n openshift-ingress-operator default --type=json -p '[{ "op": "add", "path": "/spec/routeAdmission", "value": {wildcardPolicy: "WildcardsAllowed"}}]'
```
## HCP Cluster setup

- Create Worker VM for HCP Cluster (hcp-ztp)

```
qemu-img create -f qcow2 /home/sno/hcp-ztp-worker1.qcow2 70G

virt-install \
  --name=hcp-ztp-worker1 \
  --uuid=d54f3990-12c9-4749-8b89-a1242e6af111 \
  --ram=8192 \
  --vcpus=8 \
  --cpu host-passthrough \
  --os-variant rhel8.0 \
  --noreboot \
  --events on_reboot=restart \
  --noautoconsole \
  --boot hd,cdrom \
  --import \
  --disk path=/home/sno/hcp-ztp-worker1.qcow2,size=20 \
  --network type=direct,source=br0,mac=52:54:00:42:a4:12,source_mode=bridge,model=virtio \
  --graphics vnc,listen=0.0.0.0,port=5978,password=pkar2675
```

- Create HCP cluster namespace

```oc create ns hcp-ztp```

- Create Pull Secret (First login Redhat console url then download section)

```oc create secret generic pull-secret -n hcp-ztp --from-file=.dockerconfigjson=pull-secret.json --type=kubernetes.io/dockerconfigjson```

- Create BMC Credentials Secret

```oc create secret generic bmc-secret -n hcp-ztp --from-literal=username=admin --from-literal=password=password```

- Create SSHKEY Credentials Secret

```
cat << EOF > sshkey-hcp-ztp.yaml
apiVersion: v1
kind: Secret
metadata:
  name: sshkey
  namespace: hcp-ztp
stringData:
  id_rsa.pub: ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDFoML+fLuVqwcWbtH6TGiq9VxIUi0umNaJAEVixhTLhiAnHEk8OT8p06fFxYAM+1B+oMPfU5u/36+gWIrTPUD+jgzdEZksZ8BoHveDOrrJBEGWD4xsVGj7szV4bXBEHbxgD4WeILIAtYy/QMaH+Nxkdj/eUoD7KYSelNkwKPJpJkbTIzQs6r76VYYxQkeGbraRJ5EnGQWjeAVqXXlCvzssJxGbEagub3cmv99niCa3EfUd6fPS4OjqYI7SkYSdJezRHJ5Q+eLuqTG5oicD8MWbWMsEvPC97n9bmqLsrfh1g+K69eE92a2Gu6kSwZIMcdbktEBeEeUDz/lgVG1+y/z4JFB57dSVxtdYrawxFMvVNVmX1XXydkQzOJU7WQ3Wm55qS8Zv9vCEmu9hEdZ0AC3+5pFktprNj861ETiKs969HG/xIZxUqvmWVJQI9c9eIo1KF7wxEav5VvCxV4yZq7ulUjkuMOZIPvqyWIbjz1kwFmXU9k1Ihi4gUsnKA94eKpU= root@lenevo-ts-w2
EOF

oc create -f sshkey-hcp-ztp.yaml
```

- Creating an InfraEnv

> An InfraEnv is a enviroment where worker hosts starting boot and join as Agents.

```
export SSH_PUB_KEY=`cat id_rsa.pub`
cat << EOF > kvm-infra.yaml
apiVersion: agent-install.openshift.io/v1beta1
kind: NMStateConfig
metadata:
  name: hcp-ztp-nmstate-config
  namespace: hcp-ztp
  labels:
    cluster: hcp-ztp
spec:
  interfaces:
    - name: enp1s0
      macAddress: '52:54:00:42:a4:12'
  config:
    interfaces:
      - name: enp1s0
        type: ethernet
        state: up
        ipv4:
          enabled: true
          dhcp: true
        ipv6:
          enabled: false
    dns-resolver:
      config:
        search:
          - pkar.tech
        server:
          - 192.168.1.18
          - 192.168.1.1
    routes:
      config:
        - destination: 0.0.0.0/0
          next-hop-address: 192.168.1.1
          next-hop-interface: enp1s0
---
apiVersion: agent-install.openshift.io/v1beta1
kind: InfraEnv
metadata:
  name: hcp-ztp
  namespace: hcp-ztp
spec:
  nmStateConfigLabelSelector:
    matchLabels:
      cluster: hcp-ztp
  additionalNTPSources:
  - 192.168.1.1
  pullSecretRef:
    name: pull-secret
  sshAuthorizedKey: ${SSH_PUB_KEY}
EOF

oc create -f kvm-infra.yaml
```

- Create baremetahost yaml file for first worker

```
cat << EOF > hcp-ztp-worker1.yaml
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: hcp-ztp-worker1
  namespace: hcp-ztp
  labels:
    infraenvs.agent-install.openshift.io: hcp-ztp
  annotations:
    inspect.metal3.io: disabled
    bmac.agent-install.openshift.io/hostname: hcp-ztp-worker1
spec:
  automatedCleaningMode: disabled
  bmc:
    disableCertificateVerification: True
    address: 'redfish-virtualmedia+http://192.168.1.161:8000/redfish/v1/Systems/d54f3990-12c9-4749-8b89-a1242e6af111'
    credentialsName: bmc-secret
  bootMACAddress: 52:54:00:42:a4:12
  online: true
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: capi-provider-role
  namespace: hcp-ztp
rules:
- apiGroups:
  - agent-install.openshift.io
  resources:
  - agents
  verbs:
  - '*'
EOF
```

- Create the baremetalhost for the first worker on the hub cluster SNO-ACM:

```oc create -f hcp-ztp-worker1.yaml```

- Create and deploy Hosted Cluster

```
cat << EOF > hcp-ztp-hosted.yaml
apiVersion: hypershift.openshift.io/v1beta1
kind: HostedCluster
metadata:
  name: hcp-ztp
  namespace: hcp-ztp
  labels:
spec:
  release:
    image: quay.io/openshift-release-dev/ocp-release:4.18.5-multi
  pullSecret:
    name: pull-secret
  sshKey:
    name: sshkey
  networking:
    clusterNetwork:
      - cidr: 10.132.0.0/14
    serviceNetwork:
      - cidr: 172.31.0.0/16
    networkType: OVNKubernetes
  controllerAvailabilityPolicy: SingleReplica
  infrastructureAvailabilityPolicy: SingleReplica
  platform:
    type: Agent
    agent:
      agentNamespace: hcp-ztp
  infraID: hcp-ztp
  dns:
    baseDomain: pkar.tech
  services:
  - service: APIServer
    servicePublishingStrategy:
      type: LoadBalancer
  - service: OAuthServer
    servicePublishingStrategy:
      type: Route
  - service: OIDC
    servicePublishingStrategy:
      type: Route
  - service: Konnectivity
    servicePublishingStrategy:
      type: Route
  - service: Ignition
    servicePublishingStrategy:
      type: Route
---
apiVersion: hypershift.openshift.io/v1beta1
kind: NodePool
metadata:
  name: nodepool-hcp-ztp-1
  namespace: hcp-ztp
spec:
  clusterName: hcp-ztp
  replicas: 1
  management:
    autoRepair: false
    upgradeType: InPlace
  platform:
    type: Agent
    agent:
      agentLabelSelector:
        matchLabels: {}
  release:
    image: quay.io/openshift-release-dev/ocp-release:4.18.5-multi
---
apiVersion: cluster.open-cluster-management.io/v1
kind: ManagedCluster
metadata:
  name: hcp-ztp
  annotations:
    import.open-cluster-management.io/hosting-cluster-name: local-cluster 
    import.open-cluster-management.io/klusterlet-deploy-mode: Hosted
    open-cluster-management/created-via: hypershift
  labels:
    cloud: BareMetal
    vendor: OpenShift
    name: hcp-ztp
spec:
  hubAcceptsClient: true
EOF

oc create -f hcp-ztp-hosted.yaml
```

- Verify pods are running

```
oc get hostedcluster -n hcp-ztp
oc get po,svc -n hcp-ztp-hcp-ztp
```

- Download Hosted cluster Kubeconfig and check status 

```
oc get secret admin-kubeconfig -n hcp-ztp-hcp-ztp -o jsonpath='{.data.kubeconfig}' |base64 -d > hcp-ztp-kubeconfig
export KUBECONFIG=hcp-ztp-kubeconfig
oc get clusterversion,no,co
```

- After we have created the first worker baremetalhost we should watch the agent until the worker appears. 

> We can do this with a until loop on oc get agent.

```
until oc get agent -n hcp-ztp ${UUID} >/dev/null 2>&1 ; do sleep 1 ; done
echo $?
```

- When the loop exits check that agent is listed.

```oc get agent -n hcp-ztp ${UUID}```

## Tools setup

- Install XRDP

```
dnf install epel-release -y
dnf -y install xrdp
systemctl enable xrdp --now

# How to allow RDP through Firewalld
#firewall-cmd --add-port=3389/tcp
#firewall-cmd --runtime-to-permanent
```

- NFS setup

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

- Download oc tools

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

- Download HCP CLI

```
oc get ConsoleCLIDownload hcp-cli-download -o json | jq -r ".spec" | grep amd64 | grep linux
wget --no-check-certificat `oc get ConsoleCLIDownload hcp-cli-download -o json | jq -r ".spec" | grep amd64 | grep linux | cut -d '"' -f4`
tar -zxvf hcp.tar.gz
mv hcp /usr/local/bin/
```

- KVM Install

```
yum update -y
dnf groupinstall "Virtualization Host" -y
systemctl enable --now libvirtd
yum -y install virt-top libguestfs-tools virt-install virt-manager
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

## Troubleshooting

- KVM Commands

```
virsh net-list
virsh list --all
virsh shutdown sno-acm-ts
virsh destroy sno-acm-ts
virsh domifaddr sno-acm-ts
virsh dominfo sno-acm-ts
virsh setmem sno-acm-ts 27G --config
virsh setmaxmem sno-ztp 24G --config
virsh undefine sno-acm-ts --remove-all-storage
virsh undefine sno-ztp --remove-all-storage --nvram
virsh domifaddr sno-acm-ts --source arp
```

- Check Utilizations

```
kubectl top pods -n metallb-system --sum
oc adm top pods -n openshift-monitoring --sum
oc adm top pods -n multicluster-engine --sum
oc adm top pods -n open-cluster-management --sum
for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do echo "Namespace: $ns"; kubectl top po -n $ns --sum ; sleep 3; done
```

- Disable CVO (cluster-version-operator)

> Cluster Monitoring Operator (CMO) is managed by the Cluster Version Operator (CVO), disable CVO then scale down the CMO and Prometheus statefulset.

```
oc get pods -n openshift-cluster-version
oc get deployments -n openshift-cluster-version
oc scale --replicas=0 deployment/cluster-version-operator -n openshift-cluster-version
oc get pods -n openshift-cluster-version

oc get deployment -n openshift-monitoring
oc scale --replicas=0 deployment prometheus-operator -n openshift-monitoring

```

- Kubeadmin user password change

```
PASS=g9GVb-I92co-kU379-IHjB5
ASD=`htpasswd -bnBC 10 "" $PASS | tr -d ':\n'`
EPASS=`echo "$ASD" | base64 -w0`
oc patch secret/kubeadmin -n kube-system -p '{"data":{"kubeadmin": "'$EPASS'"}}'
```

- Remove Exited containers

```crictl rm `crictl ps -a | grep Exited | awk '{ print $1}'```

- Remove stuck resource

```oc patch <object> <resource name> -p '{"metadata":{"finalizers":null}}'```

## Lesson learned

#### default Storage Pool issue from KVM [libvirt](https://serverfault.com/questions/840519/how-to-change-the-default-storage-pool-from-libvirt/840520#840520)

> error: Storage pool not found: no storage pool with matching name 'default'

- Listing current pools

```virsh pool-list```

- Remove existing storage pool

```
virsh pool-destroy sno
virsh pool-destroy images
```

- Undefine pool

```virsh pool-undefine default```

- Defining a new pool with name default

```virsh pool-define-as --name default --type dir --target /home/sno```

- Set pool to be started when libvirt daemons starts

```virsh pool-autostart default```

- Start pool

```virsh pool-start default```

- Checking pool state

```virsh pool-list```


### DNS resolve issue (Not able to pull intrim images from ACM Cluster)

- Modify clusterinstance dns-resolver section and put both SNO cluster host IPs and router GW

```
          dns-resolver:
            config:
              search:
                - pkar.tech
              server:
                - 192.168.1.18
                - 192.168.1.21
                - 192.168.1.1
```

### Cluster Image not found

- Find proper image based on AgentServiceConfig download version

```oc get clusterimagesets```

- Modify clusterinstance below section

> clusterImageSetNameRef: img4.18.5-x86-64-appsub

### If POD not start in HCP due to memory issue (preemption: not eligible due to preemptionPolicy=Never)

> Not recommended for production

- Check priorityclasses

```oc get priorityclasses```

- Save below priorityclasses then delete and edit save file (modify Never to PreemptLowerPriority) and deploy again

> hypershift-api-critical    100001000    false            133m    Never
> hypershift-control-plane   100000000    false            133m    Never
> hypershift-etcd            100002000    false            139m    Never
> hypershift-operator        100003000    false            6d8h    Never

- Verify

```oc get priorityclasses```

> Should be as below

```
oc get priorityclasses
NAME                       VALUE        GLOBAL-DEFAULT   AGE     PREEMPTIONPOLICY
hypershift-api-critical    100001000    false            133m    PreemptLowerPriority
hypershift-control-plane   100000000    false            133m    PreemptLowerPriority
hypershift-etcd            100002000    false            139m    PreemptLowerPriority
hypershift-operator        100003000    false            6d8h    PreemptLowerPriority
klusterlet-critical        1000000      false            6d9h    PreemptLowerPriority
openshift-user-critical    1000000000   false            6d15h   PreemptLowerPriority
system-cluster-critical    2000000000   false            6d15h   PreemptLowerPriority
system-node-critical       2000001000   false            6d15h   PreemptLowerPriority
```

### Test VM Creation

> Download images (wget https://releases.ubuntu.com/jammy/ubuntu-22.04.5-desktop-amd64.iso) and rename ubuntu-2204.iso

```
qemu-img create -f qcow2 /home/sno/ubuntu-2204.qcow2 30G

virt-install \
  --name ubuntu-2204 \
  --memory 2048 \
  --vcpus=12 \
  --cpu host-passthrough \
  --os-type linux \
  --os-variant ubuntu22.04 \
  --noreboot \
  --events on_reboot=restart \
  --noautoconsole \
  --import \
  --cdrom /home/kvm/images/ubuntu-2204.iso \
  --disk path=/home/sno/ubuntu-2204.qcow2,size=20 \
  --network network=host-bridge \
  --graphics vnc,listen=0.0.0.0,port=5975,password=pkar2675
```
