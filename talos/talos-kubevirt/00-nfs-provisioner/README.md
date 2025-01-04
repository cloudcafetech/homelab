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

- NFS CSI (Modify values.yaml as per setup)

```
wget https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/00-nfs-provisioner/values.yaml
helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
helm install csi-driver-nfs csi-driver-nfs/csi-driver-nfs \
  --create-namespace \
  --namespace csi-nfs \
  --version v0.0.0 \
  --values values.yaml

kubectl apply -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/talos/talos-kubevirt/00-nfs-provisioner/volumesnapshotclass.yaml
```
