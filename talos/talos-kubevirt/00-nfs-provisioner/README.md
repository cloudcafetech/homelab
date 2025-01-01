# NFS provisioner

- Setup NFS Server

```
NIC=`ip -o -4 route show to default | awk '{print $5}'`
HIP=`ip -o -4 addr list $NIC | awk '{print $4}' | cut -d/ -f1`
apt update -y
apt install nfs-kernel-server -y
systemctl start nfs-kernel-server
systemctl enable nfs-kernel-server
systemctl status nfs-kernel-server

mkdir -p /root/nfs/kubedata
chown nobody:nogroup /root/nfs/kubedata
echo "/root/nfs/kubedata *(rw,sync,no_root_squash,no_subtree_check,insecure)" >> /etc/exports
exportfs -a
systemctl restart nfs-kernel-server
showmount -e $HIP
```

- Deploy in K8S

```
NFSRV=192.168.0.100
NFSMOUNT=/root/nfs/kubedata

mkdir nfsstorage
cd nfsstorage

wget https://raw.githubusercontent.com/cloudcafetech/kubesetup/master/nfs-storage/nfs-rbac.yaml
wget https://raw.githubusercontent.com/cloudcafetech/kubesetup/master/nfs-storage/nfs-deployment.yaml
wget https://raw.githubusercontent.com/cloudcafetech/kubesetup/master/nfs-storage/kubenfs-storage-class.yaml

sed -i "s/10.128.0.9/$NFSRV/g" nfs-deployment.yaml
sed -i "s|/root/nfs/kubedata|$NFSMOUNT|g" nfs-deployment.yaml

kubectl create ns kubenfs
kubectl create -f nfs-rbac.yaml -f nfs-deployment.yaml -f kubenfs-storage-class.yaml -n kubenfs
```

- NFS CSI

```
curl -skSL https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/v4.9.0/deploy/install-driver.sh | bash -s v4.9.0 --

kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/release-8.2/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/release-8.2/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/release-5.0/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml
kubectl apply -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/00-nfs-provisioner/nfs-csi-sc.yaml

```
