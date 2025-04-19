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
wget -q https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/ceph/rook-ceph-system-clusterrole-endpointslices.yaml
```

- Install CRDs and Operators 

```
echo - Installing CRDs and Operators
kubectl create -f crds.yaml -f common.yaml -f operator.yaml
kubectl apply -f rook-ceph-system-clusterrole-endpointslices.yaml
```

- Install Cluster and StorageClass

> Modify files as per environment

```
echo - Installing Cluster and StorageClass
kubectl create -f cephcluster.yaml
sleep 30
kubectl create -f cephfs.yaml -f ceph-rbd-default.yaml -f ceph-rbd-scratch.yaml -f dashboard-external-https.yaml -f snapshotclass.yaml
```

### Note: If CSI NFS Storage deployed then DO NOT Deploy VolumeSnapshot CRDs and snapshot controller (Next section)

- Deploy VolumeSnapshot CRDs and snapshot controller

```
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/release-8.2/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/release-8.2/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/release-8.2/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml
sleep 10
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/release-8.2/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/release-8.2/deploy/kubernetes/snapshot-controller/setup-snapshot-controller.yaml
```

- Deploy Snapshotclass

```
kubectl create -f snapshotclass.yaml
```

- Get Password for Dashboard

```
kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o jsonpath="{['data']['password']}" | base64 --decode
```

### Ceph Cluster cleanup

- Step #1 (**Do below in K8s Cluster**)

```
crictl rm `crictl ps -a | grep Exited | awk '{ print $1 }'`
kubectl  delete -f cephcluster.yaml
kubectl delete -f operator.yaml
kubectl patch cephcluster/rook-ceph -n rook-ceph --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]'
kubectl -n rook-ceph patch cephcluster rook-ceph --type merge -p '{"spec":{"cleanupPolicy":{"confirmation":"yes-really-destroy-data"}}}'
for CRD in $(kubectl get crd -n rook-ceph | awk '/ceph.rook.io/ {print $1}'); do kubectl get -n rook-ceph "$CRD" -o name | xargs -I {} kubectl patch -n rook-ceph {} --type merge -p '{"metadata":{"finalizers": []}}'; done
```

- Step #2 (**Do below in ALL Nodes**)

```
crictl rm `crictl ps -a | grep Exited | awk '{ print $1 }'`
rm -rf /var/lib/rook
```
