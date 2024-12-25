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

```
