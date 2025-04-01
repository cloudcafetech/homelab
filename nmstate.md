## NMstate setup


- Deploy Operator

```
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/v0.83.0/nmstate.io_nmstates.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/v0.83.0/namespace.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/v0.83.0/service_account.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/v0.83.0/role.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/v0.83.0/role_binding.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/v0.83.0/operator.yaml
```

- Deploy NMstate handler

```
cat <<EOF | kubectl create -f -
apiVersion: nmstate.io/v1
kind: NMState
metadata:
  name: nmstate
EOF
```

- Deploy Bridge

```
cat << EOF > bridge.yaml
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: hp-ed-w1-br0-eno1
spec:
  nodeSelector:
    kubernetes.io/hostname: hp-ed-w1
  desiredState:
    dns-resolver:
      config:
        server:
          - 192.168.29.1
        search:
          - cloudcafe.tech

    routes:
      config:
        - destination: 0.0.0.0/0
          next-hop-address: 192.168.0.254
          next-hop-interface: br0

    interfaces:
      - name: br0
        description: Bridge to cloudcafe.tech network (192.168.0.0/24) and default router (internet)
        state: up
        type: linux-bridge
        bridge:
          options:
            stp:
              enabled: false
          port:
            - name: eno1
        ipv4:
          enabled: true
          dhcp: false
          address:
            - ip: 192.168.0.122
              prefix-length: 24

      - name: eno1
        description: Bridge member (br0)
        state: up
        type: ethernet
        lldp:
          enabled: true
---
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: lenevo-ts-w2-br0-eno2
spec:
  nodeSelector:
    kubernetes.io/hostname: lenevo-ts-w2
  desiredState:
    dns-resolver:
      config:
        server:
          - 192.168.29.1
        search:
          - cloudcafe.tech

    routes:
      config:
        - destination: 0.0.0.0/0
          next-hop-address: 192.168.0.254
          next-hop-interface: br0

    interfaces:
      - name: br0
        description: Bridge to cloudcafe.tech network (192.168.0.0/24) and default router (internet)
        state: up
        type: linux-bridge
        bridge:
          options:
            stp:
              enabled: false
          port:
            - name: eno2
        ipv4:
          enabled: true
          dhcp: false
          address:
            - ip: 192.168.0.119
              prefix-length: 24

      - name: eno2
        description: Bridge member (br0)
        state: up
        type: ethernet
        lldp:
          enabled: true
EOF

kubectl create -f bridge.yaml
```
