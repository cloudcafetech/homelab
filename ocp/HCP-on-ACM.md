# HCP (Hosted Control Plane) using Hypershift managed from ACM

> Without Storage Setup in ACM DO NOT run following steps

- Verify Storage Class

```oc get sc```

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
cat << EOF > provisioning.yaml
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
cat << EOF > agentserviceconfig.yaml
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

- Verify Hypershift enable in ACM

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

- Setup Sushy Emulator

```
sudo mkdir -p /etc/sushy/
cat << EOF | sudo tee /etc/sushy/sushy-emulator.conf
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

> Verify BMC address IP should match with where Sushy Emulator deployed

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
