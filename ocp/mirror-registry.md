## Openshift Mirror Registry setup for diconnect environment

- Download OS Image

```
wget https://mirror.stream.centos.org/9-stream/BaseOS/x86_64/iso/CentOS-Stream-9-latest-x86_64-dvd1.iso
mv CentOS-Stream-9-latest-x86_64-dvd1.iso centos-9.iso
```

- Create KVM VM

```
qemu-img create -f qcow2 /home/sno/centos-9.qcow2 130G

virt-install \
  --name registry \
  --memory 8192 \
  --vcpus=6 \
  --cpu host-passthrough \
  --os-variant centos-stream9 \
  --noreboot \
  --events on_reboot=restart \
  --noautoconsole \
  --import \
  --cdrom /home/sno/centos-9.iso \
  --disk path=/home/sno/centos-9.qcow2,size=20 \
  --network network=host-bridge \
  --graphics vnc,listen=0.0.0.0,port=5975,password=pkar2675
```

- Configure OS from VNC

- Add DNS entry ( nslookup mirror-registry.pkar.tech )

- Login VM with user and password

- Install packages

```
yum install podman openssl jq -y

mkdir -p mirror-registry/tools
cd mirror-registry/tools

wget https://mirror.openshift.com/pub/cgw/mirror-registry/latest/mirror-registry-amd64.tar.gz
wget https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/latest/oc-mirror.rhel9.tar.gz
wget https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-linux-amd64-rhel9.tar.gz

tar xvzpf mirror-registry-amd64.tar.gz
tar xvzpf oc-mirror.rhel9.tar.gz
tar xvzpf openshift-client-linux-amd64-rhel9.tar.gz
chmod 755 oc-mirror
rm -rf *.tar.gz README.md

```

- Install Mirror Registry

```
./mirror-registry install \
  --quayHostname mirror-registry.pkar.tech \
  --quayRoot /root/mirror-registry/quay-config \
  --quayStorage /root/mirror-registry/storage \
  --sqliteStorage /root/mirror-registry/sqlite-storage \
  --initUser admin --initPassword "Admin2675"
```

- Trust the root certificate of Quay registry

```
systemctl stop firewalld; systemctl disable firewalld

cp /root/mirror-registry/quay-config/quay-rootCA/rootCA.pem /etc/pki/ca-trust/source/anchors/
update-ca-trust extract

podman login -u admin -p Admin2675 mirror-registry.pkar.tech:8443

```

- Download pull secret (https://console.redhat.com) and save file as pull-secret then convert to json format 

```cat ./pull-secret | jq . > pull-secret.json```

- Convert registry username and password to base64 create config.json merge with pull-secret.json

```
mkdir /root/.docker

mkdir /etc/docker
cat << EOF > /etc/docker/daemon.json
{
  "insecure-registries" : ["$REGURL:8443"]
}
EOF

AUTH=`echo -n 'admin:Admin2675'|base64 -w0`
REGURL=mirror-registry.pkar.tech

cat << EOF > config.json
"$REGURL:8443": {
   "auth": "${AUTH}",
   "email": "cloudcafe@gmail.com"
}
EOF

cat pull-secret.json |jq ".auths += {`cat config.json`}"|tr -d '[:space:]' > /root/.docker/config.json
more /root/.docker/config.json | jq .

more /root/.docker/config.json | jq '.auths | keys[]'

podman login -u admin -p Admin2675 mirror-registry.pkar.tech:8443

```

- Create ImageSetConfiguration and start mirror 4.18 base images

> Take reference Operators & channel version (https://myopenshiftblog.com/disconnected-registry-mirroring/) search "Disconnected Operators"

```
cat << EOF > imageset.yaml
apiVersion: mirror.openshift.io/v2alpha2
kind: ImageSetConfiguration
mirror:
 platform:
   channels:
   - name: stable-4.18
     minVersion: 4.18.9
     maxVersion: 4.18.9
     type: ocp
   graph: true
 operators:
 - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.18
   packages:
   - name: advanced-cluster-management
     channels:
     - name: release-2.15
   - name: multicluster-engine
   - name: lvms-operator
     channels:
     - name: stable-4.18
   - name: metallb-operator
     channels:
     - name: stable
   - name: openshift-gitops-operator
     channels:
     - name: latest
 additionalImages:
 - name: registry.redhat.io/ubi9/ubi:latest
 - name: registry.redhat.io/ubi8/ubi:latest
 - name: registry.redhat.io/rhel8/support-tools
 - name: registry.redhat.io/rhel9/support-tools
 - name: registry.redhat.io/rhel8/rhel-guest-image:latest
 - name: registry.redhat.io/rhel9/rhel-guest-image:latest
EOF

nohup ./oc-mirror --config imageset.yaml --workspace file:///root/mirror-registry/base-images-418 docker://mirror-registry.pkar.tech:8443/ocp --v2 &

```
