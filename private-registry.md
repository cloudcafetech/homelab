## Private Registry Setup in K8s

- Deploy Private registry

```
DOMAIN=apps.k8s.cloudcafe.tech
NODE=`kubectl get no | grep -v control-plane | grep -v NAME | awk '{ print $1 }'`
wget https://raw.githubusercontent.com/cloudcafetech/k8s-ad-integration/refs/heads/main/private-registry.yaml
sed -i "s|apps.k8s.cloudcafe.tech|$DOMAIN|g" private-registry.yaml
sed -i "s|node-01|$NODE|g" private-registry.yaml
kubectl create ns registry
kubectl create -f private-registry.yaml
```

- Add insecure registry

```
cat <<EOF > /etc/docker/daemon.json
{
    "insecure-registries" : [ "registry.$DOMAIN:80" ]
}
EOF
systemctl restart docker
```

- Registry login

```
docker login -u admin -p admin2675 http://registry.$DOMAIN
```

- View Images

```
curl -s --user admin:admin2675 http://registry.$DOMAIN/v2/_catalog | jq .repositories | sed -n 's/[ ",]//gp' | xargs -IIMAGE \
 curl -s --user admin:admin2675 http://registry.$DOMAIN/v2/IMAGE/tags/list | jq '. as $parent | .tags[] | $parent.name + ":" + . '
```
