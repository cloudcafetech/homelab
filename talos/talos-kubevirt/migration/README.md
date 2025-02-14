### Migration Tools [Forklift](https://github.com/kubev2v/forklift/blob/main/operator/docs/k8s.md) Setup

- Install OLM

```
kubectl apply -f https://raw.githubusercontent.com/operator-framework/operator-lifecycle-manager/master/deploy/upstream/quickstart/crds.yaml
kubectl apply -f https://raw.githubusercontent.com/operator-framework/operator-lifecycle-manager/master/deploy/upstream/quickstart/olm.yaml
```

- Wait for olm operator to start

```
while ! kubectl get deployment -n olm olm-operator; do sleep 10; done
kubectl wait deployment -n olm olm-operator --for condition=Available=True --timeout=180s
```

- Deploy operator

```
wget https://raw.githubusercontent.com/kubev2v/forklift/main/operator/forklift-k8s.yaml
sed -i 's/latest/release-2.7/g' forklift-k8s.yaml
kubectl apply -f forklift-k8s.yaml
```

- Wait for forklift operator to start and create a controller instance

```
while ! kubectl get deployment -n konveyor-forklift forklift-operator; do sleep 10; done
kubectl wait deployment -n konveyor-forklift forklift-operator --for condition=Available=True --timeout=180s
```

- Create Forklift Controller

```
cat << EOF | kubectl -n konveyor-forklift apply -f -
apiVersion: forklift.konveyor.io/v1beta1
kind: ForkliftController
metadata:
  name: forklift-controller
  namespace: konveyor-forklift
spec:
  feature_ui: true
  feature_validation: true
  inventory_tls_enabled: false
  must_gather_api_tls_enabled: false
  ui_tls_enabled: false
  validation_tls_enabled: false
EOF
```

- Deploy Forklift Console Plugins

```
kubectl create -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/migration/forklift-console-plugins.yaml
```

### Migration from VMware to Kubevirt

- Create Secret & Provider

```
VCURL=192.168.0.122
VCUSER=`echo -n administrator@vsphere.local | base64`
VCPASS=`echo -n Admin@2675 | base64`
INSEC=`echo -n true | base64`
TPTEMP=`openssl s_client -connect $VCURL:443 </dev/null | openssl x509 -in /dev/stdin -fingerprint -sha1  | grep Fingerprint | cut -d "=" -f2`
TP=`echo -n $TPTEMP | base64 -w 0`

cat <<EOF > vsphere-provider.yaml
apiVersion: v1
kind: Secret
metadata:
  name: vsphere-provider-secret
  namespace: konveyor-forklift
type: Opaque
data:
  user: $VCUSER
  password: $VCPASS
  thumbprint: $TP
  insecureSkipVerify: $INSEC
---
apiVersion: forklift.konveyor.io/v1beta1
kind: Provider
metadata:
  name: vsphere-provider
  namespace: konveyor-forklift
spec:
  secret:
    name: vsphere-provider-secret
    namespace: konveyor-forklift
  settings:
    vddkInitImage: 'docker.io/prasenforu/vddk:7'
  type: vsphere
  url: 'https://$VCURL/sdk'
EOF

kubectl create -f vsphere-provider.yaml
```

- Create Resource mapping

```
cat <<EOF > resource-mapping.yaml
apiVersion: forklift.konveyor.io/v1beta1
kind: StorageMap
metadata:
  name: vmware-storage-map
  namespace: konveyor-forklift
spec:
  map:
    - destination:
        storageClass: longhorn-rwx
        accessMode: ReadWriteMany
      source:
        name: datastore1
  provider:
    destination:
      name: host
      namespace: konveyor-forklift
    source:
      name: vsphere-provider
      namespace: konveyor-forklift
---
apiVersion: forklift.konveyor.io/v1beta1
kind: NetworkMap
metadata:
  name: vmware-network-map
  namespace: konveyor-forklift
spec:
  map:
    - destination:
        type: pod
      source:
        name: pk-lan
  provider:
    destination:
      name: host
      namespace: konveyor-forklift
    source:
      name: vsphere-provider
      namespace: konveyor-forklift
---
apiVersion: forklift.konveyor.io/v1beta1
kind: Plan
metadata:
  name: vm-mig-plan
  namespace: konveyor-forklift
spec:
  archived: false
  description: ''
  map:
    network:
      name: vmware-network-map
      namespace: konveyor-forklift
    storage:
      name: vmware-storage-map
      namespace: konveyor-forklift
  provider:
    destination:
      name: host
      namespace: konveyor-forklift
    source:
      name: vsphere-provider
      namespace: konveyor-forklift
  targetNamespace: virtualmachines
  vms:
    - hooks: []
      name: vw-jumphost
  warm: false
---
apiVersion: forklift.konveyor.io/v1beta1
kind: Migration
metadata:
  name: v2kv-migration
  namespace: konveyor-forklift
spec:
  plan:
    name: vm-mig-plan
    namespace: konveyor-forklift
EOF

kubectl create -f resource-mapping.yaml
