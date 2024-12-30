## Kubevirt

```
export RELEASE=$(curl https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)
kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/${RELEASE}/kubevirt-operator.yaml
kubectl apply -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/02-kubevirt-operator/01-kubevirt-cr.yaml
```
