## WBE notes

#### [Network](https://access.redhat.com/solutions/6972064)

> With the VLAN filtering feature, need one bridge interface and no VLAN interfaces.
 
> By default, VLAN filtering will be enabled on the bridge and bridge  will handle the VLAN filtering.

> Create the bridge interface over physical nic, enable VLAN filter, and attach the interface to the bridge directly.


```
       ---------
       | ens4f0 |
       ---------
          | 
       ------
       | br1 | 
       ------
          |
          |
    ------------------
    |                |
 ---------          ---------
| VM1 NIC |        | VM2 NIC | 
 ---------          ---------
```

- Create NNCP (NodeNetworkConfigurationPolicy) using LinuxBridge

```
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: br1-ens4f0-policy 
spec:
  desiredState:
    interfaces:
      - name: br1 
        description: Linux bridge with ens4f0 port 
        type: linux-bridge 
        state: up 
        ipv4:
          enabled: false 
        bridge:
          options:
            stp:
              enabled: false 
          port:
            - name: ens4f0 
```

- Create NAD (NetworkAttachmentDefinition) with the required VLAN for the VM with "br1" interface defined in NNCP

> Multiple Network Attachment Definition can be created over the same bridge for different VLANs.

```
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: vlan-1223 
  annotations:
    k8s.v1.cni.cncf.io/resourceName: bridge.network.kubevirt.io/br1
spec:
  config: '{
    "cniVersion": "0.3.1",
    "name": "vlan-1223",  
    "type": "cnv-bridge", 
    "bridge": "br1 ", 
    "macspoofchk": true, 
    "vlan": 1223
  }'
```


