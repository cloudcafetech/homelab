## KIND Cluster Setup

- Install kind

```
[ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.33.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
```

- Cluster Config

```
apiVersion: kind.x-k8s.io/v1alpha4
kind: Cluster
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 80
        hostPort: 9080
        protocol: TCP
      - containerPort: 443
        hostPort: 8443
        protocol: TCP
      - containerPort: 30000
        hostPort: 30000
        protocol: TCP
  - role: worker
networking:
  apiServerAddress: "192.168.0.159" 
  apiServerPort: 6443
```

- Deploy

```
export KIND_EXPERIMENTAL_PROVIDER=podman
kind create cluster --name multi-node --config kind-config.yaml
kind export kubeconfig --name=multi-node --kubeconfig=./kind-kubeconfig.yaml
```

