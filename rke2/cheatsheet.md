### Cheatsheet

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
