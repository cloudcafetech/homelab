## Image Based Single Node OpenShift (SNO) Cluster Setup

#### Limitation

- Seed image should prepare from same single-node OpenShift cluster that uses the same hardware as your target bare-metal host. 

- The seed cluster must reflect your target cluster configuration for the following items:

> CPU topology

> CPU architecture

> Number of CPU cores

- IP version

- Disconnected registry (If the target cluster uses a disconnected registry, seed cluster must use a disconnected registry. Only the registries do not have to be the same.

- FIPS configuration


#### Preparation

- Create SNO Cluster

```
mkdir -p /home/ocp/sno-sa
cd /home/ocp/sno-sa
wget http://192.168.0.159:8080/ocp/sno-sa.iso
qemu-img create -f qcow2 /home/ocp/sno-sa/sno-sa-os-disk.qcow2 100G
qemu-img create -f qcow2 /home/ocp/sno-sa/sno-sa-var-disk2.qcow2 120G

virt-install \
  --name=sno-sa \
  --ram=16384 \
  --vcpus=12 \
  --cpu host-passthrough \
  --os-variant=rhel8.0 \
  --noreboot \
  --events on_reboot=restart \
  --noautoconsole \
  --import \
  --cdrom /home/ocp/sno-sa/sno-sa.iso \
  --disk path=/home/ocp/sno-sa/sno-sa-os-disk.qcow2,size=100 \
  --network network=host-bridge,mac=52:54:00:42:a4:20 \
  --graphics vnc,listen=0.0.0.0,port=5920,password=pkar2675


virsh attach-disk --domain sno-sa --source /home/ocp/sno-sa/sno-sa-var-disk2.qcow2 --target vdb --persistent --config --subdriver qcow2
sleep 10
virsh list --all

```

- Disable All Default Sources and install RedHat Operator catalogue source

```
oc get no
oc get co
oc get po -A | grep -Ev "Running|Completed"
oc patch OperatorHub cluster --type merge --patch '{"spec":{"disableAllDefaultSources":true}}'
oc get catalogsource --all-namespaces
oc create -f ../common/00-redhat-operator-cs.yaml
```

- [Create separate partition](https://access.redhat.com/solutions/4952011) for sharing /var/lib/containers partition 

```
cat << EOF > 98-var-lib-containers-partitioned.yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 98-var-lib-containers
spec:
  config:
    ignition:
      version: 3.4.0
    storage:
      files:
        - path: /etc/find-secondary-device
          mode: 0755
          contents:
            source: data:text/plain;charset=utf-8;base64,IyEvYmluL2Jhc2gKc2V0IC11byBwaXBlZmFpbAoKZm9yIGRldmljZSBpbiAvZGV2L3ZkKjsgZG8gCi91c3Ivc2Jpbi9ibGtpZCAiJHtkZXZpY2V9IiAmPiAvZGV2L251bGwKIGlmIFsgJD8gPT0gMiAgXTsgdGhlbgogICAgZWNobyAic2Vjb25kYXJ5IGRldmljZSBmb3VuZCAke2RldmljZX0iCiAgICBlY2hvICJjcmVhdGluZyBmaWxlc3lzdGVtIGZvciBjb250YWluZXJzIG1vdW50IgogICAgbWtmcy54ZnMgLUwgdmFyLWxpYi1jb250IC1mICIke2RldmljZX0iICY+IC9kZXYvbnVsbAogICAgdWRldmFkbSBzZXR0bGUKICAgIHRvdWNoIC9ldGMvdmFyLWxpYi1jb250YWluZXJzLW1vdW50CiAgICBleGl0CiBmaQpkb25lCmVjaG8gIkNvdWxkbid0IGZpbmQgc2Vjb25kYXJ5IGJsb2NrIGRldmljZSEiID4mMgpleGl0IDc3Cg==
    systemd:
      units:
        - name: find-secondary-device.service
          enabled: true
          contents: |
            [Unit]
            Description=Find secondary device
            DefaultDependencies=false
            After=systemd-udev-settle.service
            Before=local-fs-pre.target
            ConditionPathExists=!/etc/var-lib-containers-mount

            [Service]
            RemainAfterExit=yes
            ExecStart=/etc/find-secondary-device

            RestartForceExitStatus=77

            [Install]
            WantedBy=multi-user.target
        - name: var-lib-containers.mount
          enabled: true
          contents: |
            [Unit]
            Description=Mount /var/lib/containers
            Before=local-fs.target

            [Mount]
            What=/dev/disk/by-label/var-lib-cont
            Where=/var/lib/containers
            Type=xfs
            TimeoutSec=120s

            [Install]
            RequiredBy=local-fs.target
        - name: restorecon-var-lib-containers.service
          enabled: true
          contents: |
            [Unit]
            Description=Restore recursive SELinux security contexts
            DefaultDependencies=no
            After=var-lib-containers.mount
            Before=crio.service

            [Service]
            Type=oneshot
            RemainAfterExit=yes
            ExecStart=/sbin/restorecon -R /var/lib/containers/
            TimeoutSec=0

            [Install]
            WantedBy=multi-user.target graphical.target
EOF

oc apply -f 98-var-lib-containers-partitioned.yaml
```

- Wait for restart

- Verify Host file system after reboot

> Login SNO host and run lsblk, if new /dev/vdb mounted in /var/lib/containers then edit the same machineConfig and disable the restorecon-var-lib-containers.service 

> - name: restorecon-var-lib-containers.service

>   enabled: false --> change this to false so the service is disabled by systemd.

```
oc edit mc/98-var-lib-containers

```

- Install Lifecycle Agent Operator

```
cat << EOF > lca-operator.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-lifecycle-agent
  annotations:
    workload.openshift.io/allowed: management
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-lifecycle-agent
  namespace: openshift-lifecycle-agent
spec:
  targetNamespaces:
  - openshift-lifecycle-agent 
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-lifecycle-agent-subscription
  namespace: openshift-lifecycle-agent
spec:
  channel: stable
  name: lifecycle-agent
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

oc create -f  lca-operator.yaml
sleep 40
oc get deploy -n openshift-lifecycle-agent
```

- Create secret and for push seed image to registry.

> In Secret name should be "seedgen" and SeedGenerator name should be "seedimage" 

```
cat << EOF > secret-and-seedgen.yaml
apiVersion: v1
kind: Secret
metadata:
  name: seedgen
  namespace: openshift-lifecycle-agent
type: Opaque
data:
  seedAuth: ewogICJhdXRocyI6IHsKICAgICJtaXJyb3ItcmVnaXN0cnkucGthci50ZWNoOjg0NDMiOiB7CiAgICAgICJhdXRoIjogIllXUnRhVzQ2UVdSdGFXNHlOamMxIiwKICAgICAgImVtYWlsIjogImNsb3VkY2FmZUBnbWFpbC5jb20iCiAgICB9CiAgfQp9Cg==
---
apiVersion: lca.openshift.io/v1
kind: SeedGenerator
metadata:
  name: seedimage
spec:
  seedImage: mirror-registry.pkar.tech:8443/ocp/sno-seed-img:4.20.0
EOF

oc create -f secret-and-seedgen.yaml

```

- Verify

```
oc get seedgenerator -o yaml
oc get seedgenerators
```

- Enable Image-Based Install Operator in ACM

```
oc patch multiclusterengines.multicluster.openshift.io multiclusterengine --type json --patch '[{"op": "add", "path":"/spec/overrides/components/-", "value": {"name":"image-based-install-operator","enabled": true}}]'
oc get pods -n multicluster-engine | grep image-based
```

- Create ClusterImageSet

```
cat << EOF > clusterimageset.yaml
apiVersion: hive.openshift.io/v1
kind: ClusterImageSet
metadata:
  name: img4.20.0-x86-64-appsub-ibi
spec:
  releaseImage: mirror-registry.pkar.tech:8443/ocp/sno-seed-img:4.20.0
EOF

oc create -f clusterimageset.yaml
```

- Extract IBI seed image from existing Single Node OpenShift (SNO) Cluster

> Mainly --recert-image flag (optional) used for disconnected environments, if not mentioned then tool will use quay.io/edge-infrastructure/recert:v0 as a default recert image.

> For a disconnected environment, first mirror the lca-cli and recert container images to mirror registry using skopeo or a similar tool.

```
REG_URL=mirror-registry.pkar.tech
export KUBECONFIG=/etc/kubernetes/static-pod-resources/kube-apiserver-certs/secrets/node-kubeconfigs/lb-ext.kubeconfig

LCA_IMG=$(oc get deployment -n openshift-lifecycle-agent lifecycle-agent-controller-manager -o jsonpath='{.spec.template.spec.containers[?(@.name=="manager")].image}')

PULL_SEC=/root/pull-secret

mkdir /root/.docker
cat $PULL_SEC > /root/.docker/config.json
SEED_IMG=$REG_URL:8443/ocp/sno-sa:4.20.0
RECERT_IMG=quay.io/edge-infrastructure/recert:v0

podman run --privileged --pid=host --rm --net=host \
 -v /etc:/etc \
 -v /var:/var \
 -v /var/run:/var/run \
 -v /run/systemd/journal/socket:/run/systemd/journal/socket \
 -v ${PULL_SEC}:${PULL_SEC} \
 --entrypoint lca-cli ${LCA_IMG} create -a ${PULL_SEC} -i ${SEED_IMG} --recert-image ${RECERT_IMG} --skip-cleanup
```

- Create Image Build and Push

```
REG_URL=mirror-registry.pkar.tech
SEED_IMG=$REG_URL:8443/ocp/sno-sa:4.20.0

cat << EOF > dockerfile
FROM scratch
COPY . /
EOF

podman build --file dockerfile --tag $SEED_IMG /var/tmp/backup
podman push $SEED_IMG

```
