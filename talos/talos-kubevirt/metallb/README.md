# MetalLB


## Install

```
wget https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/metallb/values.yml
helm repo add metallb https://metallb.github.io/metallb
helm install metallb metallb/metallb -f values.yml --namespace kube-system
wget https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/metallb/metallb-ippol.yaml
kubectl create -f metallb-ippol.yaml
```
