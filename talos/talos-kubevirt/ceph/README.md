### Setup Ceph Storage in Talos (K8s)

- Download Files

```
echo - Downloading Files
mkdir $PWD/ceph; cd $PWD/ceph
kubectl create ns rook-ceph
kubectl label ns rook-ceph pod-security.kubernetes.io/enforce=privileged
wget https://raw.githubusercontent.com/rook/rook/refs/heads/master/deploy/examples/crds.yaml
wget https://raw.githubusercontent.com/rook/rook/refs/heads/master/deploy/examples/common.yaml
wget https://raw.githubusercontent.com/rook/rook/refs/heads/master/deploy/examples/operator.yaml
wget https://raw.githubusercontent.com/rook/rook/refs/heads/master/deploy/examples/cluster.yaml
wget https://raw.githubusercontent.com/rook/rook/refs/heads/master/deploy/examples/dashboard-external-https.yaml
```

- Install CRDs, Operators and Cluster

```
echo - Installing CRDs and Operators
kubectl create -f crds.yaml -f common.yaml -f operator.yaml
kubectl create -f cephcluster.yaml
```

- Get Password for Dashboard

```
kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o jsonpath="{['data']['password']}" | base64 --decode
```
