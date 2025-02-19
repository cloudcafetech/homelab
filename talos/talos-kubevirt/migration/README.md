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
  feature_must_gather_api: true
  feature_ui: true
  feature_validation: true
  inventory_tls_enabled: false
  must_gather_api_tls_enabled: false
  ui_tls_enabled: false
  validation_tls_enabled: false
EOF
```

- Deploy Forklift Console Plugins and Dashboard

```
kubectl create -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/migration/forklift-console-plugins.yaml
kubectl create -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/migration/ocp-console.yaml
```

### Migration from VMware to Kubevirt

Migrate from VMware make sure VMware-tool should be installed.

>Ubuntu: ```sudo apt-get install open-vm-tools-desktop -y```

>Windows step1: ```Mount VMware image mount in windows VM and run setup.exe```

>Windows step2: [Change Block Tracking (CBT) is enable] ```Edit settings of VM > VM Options > Advanced > Configuration Parameters  >> EDIT CONFIGURATION >> add parameter ctkEnabled = "TRUE"```

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

- Download Resource mapping file modify (VM name, Datastore & Network)

```
wget https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/migration/resource-mapping-windows.yaml
wget https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/migration/resource-mapping-linux.yaml
```

- Deploy Resource mapping

```
kubectl create -f resource-mapping-windows.yaml
kubectl create -f resource-mapping-linux.yaml
```
