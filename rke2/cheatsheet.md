# Cheatsheet

- Enable Wifi

```
dnf install NetworkManager-wifi
systemctl restart NetworkManager
reboot
```
- Resource/object delete terminating

```kubectl patch apps/velero -n argocd --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' ```

- Delete terminating namespace

```
NS=`kubectl get ns |grep Terminating | awk 'NR==1 {print $1}'` && kubectl get namespace "$NS" -o json   | tr -d "\n" | sed "s/\"finalizers\": \[[^]]\+\]/\"finalizers\": []/"   | kubectl replace --raw /api/v1/namespaces/$NS/finalize -f -
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
