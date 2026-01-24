# Setup Advance Cluster Management on SNO

### Base Setup on CentOS host

- Update and basic tools

```
yum update -y
dnf groupinstall "Virtualization Host" -y
systemctl enable --now libvirtd
yum -y install virt-install virt-top libguestfs-tools virt-manager guestfs-tools
wget https://github.com/fullstorydev/grpcurl/releases/download/v1.9.3/grpcurl_1.9.3_linux_amd64.rpm
mv grpcurl_1.9.3_linux_amd64.rpm grpcurl.rpm
yum install podman openssl jq grpcurl.rpm -y
dnf install /usr/bin/nmstatectl -y
dnf install epel-release -y
dnf -y install xrdp
systemctl enable xrdp --now
systemctl stop firewalld
systemctl disable firewalld
rm -rf grpcurl.rpm
```

- Default storage pool

```
virsh pool-list
mkdir -p /kvm_pool/default
virsh pool-define-as --name default --type dir --target /kvm_pool/default
virsh pool-autostart default
virsh pool-start default
virsh pool-list
```

- Create Bridge Interface

```
INTERFACE=eno2
nmcli connection add type bridge autoconnect yes con-name br0 ifname br0
nmcli connection modify br0 ipv4.addresses 192.168.1.160/24 ipv4.gateway 192.168.1.1 ipv4.dns 192.168.1.161,192.168.1.1,8.8.8.8 ipv4.method manual
nmcli connection add type ethernet slave-type bridge autoconnect yes con-name bridge-port-eth0 ifname $INTERFACE master br0
nmcli connection down $INTERFACE && nmcli connection up br0

ip addr show br0
ping google.com
```

- Add Bridge network on KVM

```
cat << EOF > host-bridge.xml
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

### SSH KEYGEN Setup

```ssh-keygen -f ./id_rsa -t rsa -N ''```

### DNS Setup

- Install BIND and tools

```yum install bind bind-utils -y```

- Verify nslookup should resolve from network 

>         allow-query     { localhost; 192.168.1.0/24;};  section in /etc/named.conf file.

- Create a new zone file

```
cat << EOF > /var/named/pkar.tech.zone

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
  verbs: ["create", "get", "list", "update", "delete", "watch", "patch"]
- apiGroups: ["policy.open-cluster-management.io"]
  resources: ["policies", "policysets", "placementbindings"]
  verbs: ["create", "get", "list", "update", "delete", "watch", "patch"]
- apiGroups: ["apps.open-cluster-management.io"]
  resources: ["placementrules"]
  verbs: ["create", "get", "list", "update", "delete", "watch", "patch"]
- apiGroups: ["cluster.open-cluster-management.io"]
  resources: ["managedclustersets", "managedclustersetbindings", "managedclustersets/bind", "managedclustersets/join", "placements", "placements/status", "placementdecisions", "placementdecisions/status"]
  verbs: ["create", "get", "list", "update", "delete", "watch", "patch"]
- apiGroups: ["cluster.open-cluster-management.io"]
  resources: ["managedclusters"]
  verbs: ["get", "list", "update", "watch", "patch"]
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
  kustomizeBuildOptions: --enable-alpha-plugins
  repo:
    env:
    - name: KUSTOMIZE_PLUGIN_HOME
      value: /etc/kustomize/plugin
    initContainers:
    - args:
      - -c
      - cp /policy-generator/PolicyGenerator-not-fips-compliant /policy-generator-tmp/PolicyGenerator
      command:
      - /bin/bash
      image: registry.redhat.io/rhacm2/multicluster-operators-subscription-rhel9:v2.11.7-13
      name: policy-generator-install
      volumeMounts:
      - mountPath: /policy-generator-tmp
        name: policy-generator
    volumeMounts:
    - mountPath: /etc/kustomize/plugin/policy.open-cluster-management.io/v1/policygenerator
      name: policy-generator
    volumes:
    - emptyDir: {}
      name: policy-generator
EOF

oc patch argocd openshift-gitops -n openshift-gitops --type merge --patch-file argocd-patch.yaml
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
yum -y install virt-top libguestfs-tools virt-install virt-manager virt-customize
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

cat << EOF > metallb-config.yaml
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

- Setup Oauth using htpasswd

```
yum install httpd-tools -y

htpasswd -c -B -b ./htpasswd pkar pkar2675
htpasswd -B -b ./htpasswd dkar dkar2675

oc create secret generic htpasswd-secret --from-file=htpasswd=./htpasswd -n openshift-config

oc extract secret/htpasswd-secret -n openshift-config  --to /tmp/ --confirm
more /tmp/htpasswd

cat << EOF > oauth.yaml
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: htpasswd
    mappingMethod: claim
    type: HTPasswd
    htpasswd:
      fileData:
        name: htpasswd-secret
EOF

oc replace -f oauth.yaml

oc adm policy add-cluster-role-to-user cluster-admin pkar 
oc adm policy add-cluster-role-to-user cluster-admin dkar
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

- Disable Openshift Monitoring using CVO (cluster-version-operator)

> Cluster Monitoring Operator (CMO) is managed by the Cluster Version Operator (CVO), disable CVO then scale down the CMO and Prometheus statefulset.

```
oc get pods -n openshift-cluster-version
oc scale deployment/cluster-version-operator --replicas=0 -n openshift-cluster-version
oc get pods -n openshift-cluster-version
oc get deployment -n openshift-monitoring
oc scale deployment cluster-monitoring-operator --replicas=0 -n openshift-monitoring
oc scale deployment prometheus-operator --replicas=0 -n openshift-monitoring

cat << EOF > cluster-monitoring-config
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    enableUserWorkload: false
    alertmanagerMain:
      enabled: false
    kubeStateMetrics:
      enabled: false
    nodeExporter:
      enabled: false
    prometheusK8s:
      enabled: false
EOF

oc apply -f cluster-monitoring-config

oc scale deployment cluster-monitoring-operator --replicas=0 -n openshift-monitoring
oc scale deployment prometheus-operator --replicas=0 -n openshift-monitoring
oc scale deployment thanos-querier --replicas=0 -n openshift-monitoring
oc scale deployment telemeter-client --replicas=0 -n openshift-monitoring
oc scale deployment openshift-state-metrics --replicas=0 -n openshift-monitoring
oc scale deployment kube-state-metrics --replicas=0 -n openshift-monitoring
oc scale deployment monitoring-plugin --replicas=0 -n openshift-monitoring
oc scale deployment.apps/metrics-server --replicas=0 -n openshift-monitoring
oc scale deployment.apps/prometheus-operator-admission-webhook --replicas=0 -n openshift-monitoring
oc scale statefulset.apps/prometheus-k8s --replicas=0 -n openshift-monitoring
oc scale statefulset.apps/alertmanager-main --replicas=0 -n openshift-monitoring
oc patch ds node-exporter -p '{"spec": {"template": {"spec": {"nodeSelector": {"non-existing": "true"}}}}}' -n openshift-monitoring
oc get po -n openshift-monitoring
```

- Disable community-operators redhat-marketplace and certified-operators

```
oc patch operatorhubs/cluster --type merge --patch '{"spec":{"sources":[{"disabled": true,"name": "community-operators"},{"disabled": true,"name": "certified-operators"},{"disabled": true,"name": "redhat-marketplace"}]}}'

oc get catsrc -n openshift-marketplace
```

- Kubeadmin user password change

```
PASS=g9GVb-I92co-kU379-IHjB5
ASD=`htpasswd -bnBC 10 "" $PASS | tr -d ':\n'`
EPASS=`echo "$ASD" | base64 -w0`
oc patch secret/kubeadmin -n kube-system -p '{"data":{"kubeadmin": "'$EPASS'"}}'
```

- Remove Exited containers

``` 
crictl rm `crictl ps -a | grep Exited | awk '{ print $1}'`
```

- Remove stuck resource

```
oc patch apps sno-ztp-cluster-app -n openshift-gitops --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]'

oc patch <object> <resource name> -p '{"metadata":{"finalizers":null}}'

```
- Remove Terminating namespace

```
NS=sno-ztp
kubectl get ns $NS -o json | tr -d "\\n" | sed "s/\"finalizers\": \[[^]]\+]/\"finalizers\": []/" | kubectl replace --raw /api/v1/namespaces/$NS/finalize -f -
```

- Merge multiple kubeconfig

```
export KUBECONFIG=/home/sno/ocp-acm/sno-acm-kubeconfig:/home/sno/ocp-acm/sno-ztp-kubeconfig
kubectl config view --flatten > all-clusters-kubeconfig
cp all-clusters-kubeconfig ~/.kube/config
```

- Labeling Managed Clusters

```
oc label managedcluster ztp-sno cluster.open-cluster-management.io/clusterset=ocp-ztp-gitops  --overwrite
oc label managedcluster local-cluster cluster.open-cluster-management.io/clusterset=ocp-ztp-gitops  --overwrite
```

- Unlabeled

```oc label managedcluster local-cluster cluster.open-cluster-management.io/clusterset-```

- Restart process (command) if killed

> Modify PROCESS_COMMAND as per requirement 

```
cat << EOF > download-restart.sh
#!/bin/bash

PROCESS_COMMAND="/root/mirror-registry/tools/oc-mirror --config /root/mirror-registry/tools/imageset.yaml --workspace file://root/mirror-registry/base-images-418 docker://mirror-registry.pkar.tech:8443/ocp --v2 &"

echo "Starting background process monitor..."

while :
do
  $PROCESS_COMMAND
  echo "$PROCESS_COMMAND was killed. Restarting..."
  # Optional: add a short sleep to prevent a rapid respawn loop if the process crashes instantly
  sleep 2
done &

# Store the PID of the monitoring loop (the parent process of your_process_executable)
MONITOR_PID=$!
echo "Monitor running with PID: $MONITOR_PID"

# Wait for user input to stop the monitor (optional)
read -p "Press Enter to stop the monitor and exit..."

# Kill the monitor process to stop everything
kill "$MONITOR_PID"
echo "Monitor stopped."
EOF

chmod 755 download-restart.sh
```

#### Modify or add DNS in Openshift

> To add a general upstream DNS server for all non-cluster queries, use the upstreamResolvers field: as follows


```
spec:
  # ... other spec fields
  upstreamResolvers:
    policy: Sequential
    protocolStrategy: ""
    transportConfig: {}
    upstreams:
    - address: 192.168.1.161
      port: 53
      type: Network
    - port: 53
      type: SystemResolvConf # Keeps the original fallback
```

- Edit DNS Operator

```
oc edit dns.operator/default
```

- Delete DNS pod 

```
oc get po -n openshift-dns
oc delete po `oc get po -n openshift-dns | grep dns-default | awk '{ print $1 }'` -n openshift-dns  --force
oc get po -n openshift-dns
```

- Verify

```
oc get configmap/dns-default -n openshift-dns -o yaml
```

#### Configure IP, GW & DNS

```
nmcli con mod "System eth0" ipv4.addresses 192.168.1.15/24
nmcli con mod "System eth0" ipv4.method manual
nmcli con mod "System eth0" ipv4.gateway 192.168.1.1
nmcli con mod "System eth0" ipv4.dns "192.168.1.161 192.168.1.1"
nmcli con up "System eth0"
nmcli connection show "System eth0"
```

## Lesson learned

### To recover the cluster, please try to reimport the cluster (https://access.redhat.com/solutions/6988100)

> clusters unknown status in ACM, seems Klusterlet Registration Degraded and expired bootstrap secret

- Delete the klusterlet on the each managed cluster

```oc delete klusterlets klusterlet```

- Delete the import secret from each managed cluster namespace on the hub

```
oc delete secrets sno-ztp-import -n sno-ztp
sleep 10
```

- After import secret is recreated, expose the import resources from the import secret on the hub

```
oc get secrets sno-ztp-import -n sno-ztp -o=jsonpath='{.data.crds\.yaml}' | base64 -d > klusterlet-crds-sno-ztp.yaml
oc get secrets sno-ztp-import -n sno-ztp -o=jsonpath='{.data.import\.yaml}' | base64 -d > import-sno-ztp.yaml
```
- Apply yamls on the managed cluster

```
oc apply -f klusterlet-crds-sno-ztp.yaml
oc apply -f import-sno-ztp.yaml
```

#### openshift argocd "user" as cluster-admin not able to create apps or view

> Even with cluster-admin privileges in OpenShift, a user might not have automatic permissions within the Argo CD application itself because Argo CD manages its own internal Role-Based Access Control (RBAC)

- Edit the ArgoCD CR in the openshift-gitops namespace

```oc edit argocd openshift-gitops -n openshift-gitops```

- Add or modify the following lines to the spec section

```
spec:
  rbac:
    defaultPolicy: ""
    policy: |
      g, system:cluster-admins, role:admin
      g, cluster-admins, role:admin
      g, cluster-admin, role:admin
    scopes: '[groups]'
```

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

- Ubuntu VM

> Download images and rename

```
wget wget https://releases.ubuntu.com/jammy/ubuntu-22.04.5-desktop-amd64.iso
mv ubuntu-22.04.5-desktop-amd64.iso ubuntu-2204.iso
```

- After create VM Configure OS from VNC (Install RealVNC in Laptop/Desktop)

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
  --graphics vnc,listen=0.0.0.0,port=5977,password=pkar2675
```

- CentOS VM

> Download images and rename

```
wget https://mirror.stream.centos.org/9-stream/BaseOS/x86_64/iso/CentOS-Stream-9-latest-x86_64-dvd1.iso
mv CentOS-Stream-9-latest-x86_64-dvd1.iso centos-9.iso
```

- After create VM Configure OS from VNC (Install RealVNC in Laptop/Desktop)

```
qemu-img create -f qcow2 /home/sno/centos-9.qcow2 130G

virt-install \
  --name centos9 \
  --memory 8192 \
  --vcpus=6 \
  --cpu host-passthrough \
  --os-variant centos-stream9 \
  --noreboot \
  --events on_reboot=restart \
  --noautoconsole \
  --import \
  --cdrom /home/sno/centos-9.iso \
  --disk path=/home/sno/centos-9.qcow2,size=20 \
  --network network=host-bridge \
  --graphics vnc,listen=0.0.0.0,port=5975,password=pkar2675
```
