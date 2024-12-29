## CNI (Cilium) Setup

- Tool download

```

```

- CNI deployment

Due to cilium with other CNI (**Multus**) integration needed to add helm config **cni.exclusive=false** to prevent cilium change multus config file name to ```*.cilium_bak``` in ```/etc/cni/net.d``` [FIX](https://github.com/siderolabs/talos/discussions/7914#discussioncomment-7457510)

```
cilium install \
  --helm-set=ipam.mode=kubernetes \
  --helm-set=kubeProxyReplacement=true \
  --helm-set=securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
  --helm-set=securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
  --helm-set=cgroup.autoMount.enabled=false \
  --helm-set=cgroup.hostRoot=/sys/fs/cgroup \
  --helm-set=cni.exclusive=false \
  --helm-set=l2announcements.enabled=true \
  --helm-set=externalIPs.enabled=true \
  --helm-set=socketLB.hostNamespaceOnly=true \
  --helm-set=k8sServiceHost=localhost \
  --helm-set=k8sServicePort=7445 \
  --helm-set=devices='{eth0,eth1,eth2,eno1,eno2,br0}'
```
