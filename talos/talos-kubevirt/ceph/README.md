### Setup Ceph Storage in Talos (K8s)

- Download Files

```
echo - Downloading Files
mkdir $PWD/ceph; cd $PWD/ceph
kubectl create ns rook-ceph
kubectl label ns rook-ceph pod-security.kubernetes.io/enforce=privileged
wget -q https://raw.githubusercontent.com/rook/rook/refs/heads/master/deploy/examples/crds.yaml
wget -q https://raw.githubusercontent.com/rook/rook/refs/heads/master/deploy/examples/common.yaml
wget -q https://raw.githubusercontent.com/rook/rook/refs/heads/master/deploy/examples/operator.yaml
wget -q https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/ceph/cephcluster.yaml
wget -q https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/ceph/cephfs.yaml
wget -q https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/ceph/ceph-rbd-default.yaml
wget -q https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/ceph/ceph-rbd-scratch.yaml
wget -q https://raw.githubusercontent.com/rook/rook/refs/heads/master/deploy/examples/dashboard-external-https.yaml
wget -q https://raw.githubusercontent.com/rook/rook/refs/heads/master/deploy/examples/csi/cephfs/snapshotclass.yaml
```

- Install CRDs and Operators 

```
echo - Installing CRDs and Operators
kubectl create -f crds.yaml -f common.yaml -f operator.yaml
```

- Install Cluster and StorageClass

> Modify files as per environment

```
echo - Installing Cluster and StorageClass
kubectl create -f cephcluster.yaml
sleep 30
kubectl create -f cephfs.yaml -f ceph-rbd-default.yaml -f ceph-rbd-scratch.yaml -f dashboard-external-https.yaml -f snapshotclass.yaml
```

- Get Password for Dashboard

```
kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o jsonpath="{['data']['password']}" | base64 --decode
```
