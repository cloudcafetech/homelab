## Longhorn 

-  Deploy longhorn (**NOTE: It take time to install, be patient** )
  
```
helm repo add longhorn https://charts.longhorn.io
helm repo update
helm install longhorn longhorn/longhorn --namespace longhorn-system --create-namespace --version 1.6.1 --set defaultSettings.defaultDataPath="/var/mnt/longhorn"
kubectl label ns longhorn-system pod-security.kubernetes.io/enforce=privileged
```

 - Storageclass ( `storageclass` that is used to configure `ReadWriteMany` for Longhorn )

```kubectl create -f storageclass-rwx.yml```

- VolumeSnapshotClass (Basic configurion of a `VolumeSnapshotClass` which can be used to create snapshots of your virtual machines)

```kubectl create -f volumesnapshotclass-default.yml```

### External-snapshotter directory

This directory contains manifests to deploy a external-snapshotter. This is the basic external-snapshotter that coms from the Kubernetes SIG storage group. This is a prerequiste for Snapshots and KubeVirt to work properly
