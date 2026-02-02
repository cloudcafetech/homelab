### Setup Zero Touch Provisioning (ZTP) on Single Node Openshift (SNO) 

Setup Zero Touch Provisioning (ZTP) on Single Node Openshift (SNO) from Advance Cluster Management (ACM)

> Without Storage Setup DO NOT run following steps

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

> IF ZTP in disconnected network from Mirror registry follow instruction for [AgentServiceConfig file creation](https://github.com/cloudcafetech/homelab/blob/main/ocp/MIRROR-REGISTRY.md#extra-preparation)

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

### Setup Sushy Emulator

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

- Create Namespace and set label

```
oc create ns sno-ztp
oc label namespace sno-ztp argocd.argoproj.io/managed-by=openshift-gitops
```

- Create Pull Secret (First login Redhat console url then download pull secret from download section)

> #### Zero Touch Provisioning (ZTP) with Mirror Registry integration, pull secret should contains credentials for both Mirror Registry and official Red Hat Registries.

> Transfer merged-pull-secret file (/home/cloudcafe/merge-pull-secret) from Mirror Registry server

```
scp cloudcafe@192.168.1.150:/home/cloudcafe/merge-pull-secret .
cp merge-pull-secret pull-secret.json
```

```oc create secret generic pull-secret -n sno-ztp --from-file=.dockerconfigjson=pull-secret.json --type=kubernetes.io/dockerconfigjson```

- Create BMC Credentials Secret

```oc create secret generic bmc-secret -n sno-ztp --from-literal=username=admin --from-literal=password=password```

- Create Cluster Instance [Ref Sample](https://github.com/stolostron/siteconfig/tree/main/config/samples)

> Verify BMC address IP should match with Where Sushy Emulator deployed

```
cat << EOF > sno-ztp-clusterinstance.yaml
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
    - cidr: 192.168.0.0/24
  pullSecretRef:
    name: pull-secret
  templateRefs:
    - name: ai-cluster-templates-v1
      namespace: open-cluster-management
  sshPublicKey: ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCWoz7bEt/HTXoRCJFCP310RlzDc6rtlguDoBqCMz+Em4DiY7F6b/+DUwdzGm6KHoHLsPxCV5RdtJ0D++SoFYZHy1J3rl3ASDKtiwWb4ifTcdUZxKHGU48N5j0qYtGB0nAK/BEJn3MI3BTqnuWWcutuDo6xH2aJ7HBUCpqaAaxXsrmp+AQjwpdYIyiKyMUexgByo1MPwU806oxJPiZwgIks6TR+Y0hE/zPfkfTHFTvMpOLu5YfuzgksTJhNxjNxPa4CNZzzRRqDWflWxVSI93iz5Atw/x5Q8sjxzCONfKIjPiRkky6sP2hpwB0cVr/p+U3n6UAYC5lmkqvdr/eh0EY2ZaQ4QsBhtxgTHrWW2l1xFDxVK8FxNfBZMyvSG8K8jingo3hE2udIIG43MpX4HM9Kg75SQTuDIZ4HxHQiSlYrcaNWVOckcZHYrs1AAMLUKtx5InhYa6YpC98WT1/MmP+45vA00UbU8Eh36CeorcC1MpGXmOnj00NYsVZoronPoic= root@lenevo-tci57
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
      bmcAddress: 'redfish-virtualmedia+http://192.168.0.161:8000/redfish/v1/Systems/d54f3990-12c9-4749-8b89-a1242e6af101'
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
                  - ip: 192.168.0.21
                    prefix-length: 24
              ipv6:
                enabled: false
          dns-resolver:
            config:
              search:
                - pkar.tech
              server:
                - 192.168.0.18
                - 192.168.0.21
                - 192.168.0.1
          routes:
            config:
              - destination: 0.0.0.0/0
                next-hop-address: 192.168.0.1
                next-hop-interface: enp1s0
EOF

oc apply -f sno-ztp-clusterinstance.yaml
sleep 20
oc get clusterinstance sno-ztp -n sno-ztp
oc get clusterinstance,AgentClusterInstall,ClusterDeployment,InfraEnv,BareMetalHost,NMStateConfig -n sno-ztp
```

- Verify

```
oc describe clusterinstance sno-ztp -n sno-ztp
oc describe AgentClusterInstall sno-ztp -n sno-ztp
oc describe ClusterDeployment sno-ztp -n sno-ztp
oc describe InfraEnv sno-ztp -n sno-ztp
oc describe BareMetalHost sno-ztp -n sno-ztp
oc describe NMStateConfig sno-ztp -n sno-ztp
```

- Download Kubeconfig & Kubeadmin Password

> Make sure RHACM logged in and Managed Cluster Ready

```
wget https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/ocp/get-ocp-cred.sh
chmod 755 get-ocp-cred.sh
# ./get-ocp-cred.sh <Cluster Name>
./get-ocp-cred.sh sno-ztp
```
