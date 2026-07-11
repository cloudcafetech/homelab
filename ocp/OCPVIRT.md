# Openshift Virtualization

### Virtualization

- Install Virtualization Operator CLI or GUI

```
cat << EOF > ocp-virt-operator.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-cnv
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: kubevirt-hyperconverged-group
  namespace: openshift-cnv
spec:
  targetNamespaces:
  - openshift-cnv
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: kubevirt-hyperconverged
  namespace: openshift-cnv
spec:
  channel: stable
  installPlanApproval: Automatic
  name: kubevirt-hyperconverged
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

oc create -f ocp-virt-operator.yaml
```

- Install Instance CLI or GUI

```
oc apply -f - <<EOF
kind: HyperConverged
apiVersion: hco.kubevirt.io/v1beta1
metadata:
  annotations:
    deployOVS: 'false'
  name: kubevirt-hyperconverged
  namespace: openshift-cnv
spec: {}
EOF

oc get po -n openshift-cnv
```

### Storage

> FOR SNO with one disk, for Storage Virtualization Operator by default install Host Path Provisioner Operator

- Install HostPathProvisioner CRD

```
cat << EOF > hpp.yaml
apiVersion: hostpathprovisioner.kubevirt.io/v1beta1
kind: HostPathProvisioner
metadata:
  name: hostpath-provisioner
spec:
  imagePullPolicy: IfNotPresent
  storagePools: 
  - name: vm-storage-pool
    path: "/var/vm-volumes" 
EOF

oc create -f hpp.yaml
```

- Install Storage Class

```
cat << EOF > hpp-sc.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: hostpath-csi
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: kubevirt.io.hostpath-provisioner
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
parameters:
  storagePool: vm-storage-pool 
EOF

oc create -f hpp-sc.yaml
```

### [Networking](https://www.redhat.com/en/blog/access-external-networks-with-openshift-virtualization)

- Install NMState Operator

```
cat << EOF > nmstate-operator.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-nmstate
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-nmstate
  namespace: openshift-nmstate
spec:
  targetNamespaces:
    - openshift-nmstate
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: kubernetes-nmstate-operator
  namespace: openshift-nmstate
spec:
  channel: stable
  name: kubernetes-nmstate-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

oc apply -f nmstate-operator.yaml
```

- Install NMState Operator

```
oc apply -f - <<EOF
apiVersion: nmstate.io/v1
kind: NMState
metadata:
  name: nmstate
EOF
oc get pods -n openshift-nmstate
```

> The SNO cluster build with single NIC (eno1), which is already configured during the cluster installation using the bridge br-ex.
> As OpenShift nodes only have a single NIC for networking, then only option for connecting VM to the external network is to reuse the br-ex bridge that is the default on all nodes running in an OVN-Kubernetes cluster. FYI, this option may not be available older Openshift-SDN.

- Install NNCP

```
cat << EOF > nncp-sno-bm1.yaml
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: sno-bm1-br-ex
spec:
  nodeSelector:
    kubernetes.io/hostname: sno-bm1
  desiredState:
    ovn:
      bridge-mappings:
      - localnet: br-ex-network # should match in NAD
        bridge: br-ex 
        state: present
EOF

oc create -f nncp-sno-bm1.yaml
oc get nncp
oc get nnce
```

> Note: Value is used for the localnet is needed for CUDN or NAD

- Deploy VM NS

```
cat << EOF > ns-lin-winvm.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: linvm
---
apiVersion: v1
kind: Namespace
metadata:
  name: winvm
EOF

oc create -f ns-lin-winvm.yaml
```

> OpenShift provides advanced multi-networking features to segment and isolate traffic using ClusterUserDefinedNetwork (CUDN) or UserDefinedNetwork (UDN) overlays per namespace. 

- [CUDN](https://www.redhat.com/en/blog/user-defined-networks-red-hat-openshift-virtualization)

```
cat << EOF > cudn-localnet-lin-winvm.yaml
apiVersion: k8s.ovn.org/v1
kind: ClusterUserDefinedNetwork
metadata:
  name: cudn-localnet
spec:
  namespaceSelector:
    matchExpressions:
    - key: kubernetes.io/metadata.name
      operator: In
      values: ["linvm", "winvm"]
  network:
    topology: Localnet
    localnet:
      physicalNetworkName: br-ex-network	# should match in NNCP
      role: Secondary
      ipam:
        mode: Disabled
EOF

oc create -f cudn-localnet-lin-winvm.yaml
oc get net-attach-def -A
```

> NOTE : Using CUDN or UDN, NAD automatically created in namespace.


#### OR 

- Create NAD 

```
cat << EOF > br-ex-network-nad.yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: br-ex-network
  namespace: default
spec:
  config: '{
            "name":"br-ex-network",	# should match in NNCP
            "type":"ovn-k8s-cni-overlay",
            "cniVersion":"0.4.0",
            "topology":"localnet",
            "netAttachDefName":"default/br-ex-network"
          }'
EOF

oc apply -f br-ex-network-nad.yaml
```

### Load Balance (LB)

- Install MetalLB Operator

- Deploy IPAddressPool and L2Advertisement

```
cat << EOF > vm-ip-pool.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: vm-ip-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.0.90-192.168.0.100
EOF

cat << EOF > vm-l2-adv.yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: vm-l2-adv
  namespace: metallb-system
spec:
  ipAddressPools:
  - vm-ip-pool
EOF

oc create -f vm-ip-pool.yaml
```

- Create VM

```
cat << EOF > vm-centos9.yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: centos9
  namespace: default
  finalizers:
    - kubevirt.io/virtualMachineControllerFinalize
  labels:
    app: centos9
spec:
  dataVolumeTemplates:
    - apiVersion: cdi.kubevirt.io/v1beta1
      kind: DataVolume
      metadata:
        name: centos9
      spec:
        sourceRef:
          kind: DataSource
          name: centos-stream9
          namespace: openshift-virtualization-os-images
        storage:
          resources:
            requests:
              storage: 30Gi
  runStrategy: RerunOnFailure
  template:
    metadata:
      labels:
        kubevirt.io/domain: centos9
    spec:
      accessCredentials:
        - sshPublicKey:
            propagationMethod:
              noCloud: {}
            source:
              secret:
                secretName: common-ssh
      architecture: amd64
      domain:
        cpu:
          cores: 2
          sockets: 1
          threads: 1
        devices:
          disks:
            - bootOrder: 1
              disk:
                bus: virtio
              name: rootdisk
            - disk:
                bus: virtio
              name: cloudinitdisk
          interfaces:
            - macAddress: '02:55:c3:fb:7c:b5'
              masquerade: {}
              model: virtio
              name: default
            - bridge: {}
              macAddress: '02:55:c3:fb:7c:b6'
              model: virtio
              name: ext-nic
              state: up
          rng: {}
        machine:
          type: pc-q35-rhel9.6.0
        memory:
          guest: 2Gi
        resources: {}
      networks:
        - name: default
          pod: {}
        - multus:
            networkName: nad-centos-vm
          name: ext-nic
      subdomain: headless
      terminationGracePeriodSeconds: 180
      volumes:
        - dataVolume:
            name: centos9
          name: rootdisk
        - cloudInitNoCloud:
            userData: |-
              #cloud-config
              user: centos
              password: cloudcafe2675
              chpasswd: { expire: False }
          name: cloudinitdisk
EOF
```

- Create Service for VM 

```
cat << EOF > vm-svc.yaml
apiVersion: v1
kind: Service
metadata:
  name: vm-loadbalancer
  namespace: linvm 
spec:
  type: LoadBalancer
  selector:
    kubevirt.io/domain: my-virtual-machine-name # Matches your VM's autogenerated name label
  ports:
  - name: http
    protocol: TCP
    port: 80         # Port exposed externally
    targetPort: 80   # Port the application is listening on inside the VM
EOF

oc create -f vm-svc.yaml
```
