# Openshift Mirror Registry setup for disconnect environment

### Server setup

- Download OS Image

```
wget https://mirror.stream.centos.org/9-stream/BaseOS/x86_64/iso/CentOS-Stream-9-latest-x86_64-dvd1.iso
mv CentOS-Stream-9-latest-x86_64-dvd1.iso centos-9.iso
```

- Create KVM VM

```
qemu-img create -f qcow2 /home/sno/centos-9.qcow2 130G

virt-install \
  --name mirroreg \
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

- Configure OS from VNC [Download RealVNC Viewer and install in Desktop](https://downloads.realvnc.com/download/file/realvnc-connect/RealVNC-Connect-Installer-3.2.0-Windows.exe)

- Add DNS entry ( nslookup mirror-registry.pkar.tech )

- Login VM with user and password

- Install packages

```
wget https://github.com/fullstorydev/grpcurl/releases/download/v1.9.3/grpcurl_1.9.3_linux_amd64.rpm
mv grpcurl_1.9.3_linux_amd64.rpm grpcurl.rpm
yum install podman openssl jq grpcurl.rpm -y

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
REGURL=mirror-registry.pkar.tech
./mirror-registry install \
  --quayHostname $REGURL \
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

podman login -u admin -p Admin2675 $REGURL:8443

```

- Download pull secret from [Redhat Console](https://console.redhat.com) and save file as pull-secret then convert to json format 

```cat ./pull-secret | jq . > pull-secret.json```

- Convert registry username and password to base64 create config.json merge with pull-secret.json

```
mkdir /root/.docker
AUTH=`echo -n 'admin:Admin2675'|base64 -w0`

cat << EOF > config.json
"$REGURL:8443": {
   "auth": "${AUTH}",
   "email": "cloudcafe@gmail.com"
}
EOF

cat pull-secret.json |jq ".auths += {`cat config.json`}"|tr -d '[:space:]' > /root/.docker/config.json
more /root/.docker/config.json | jq .

more /root/.docker/config.json | jq '.auths | keys[]'

podman login -u admin -p Admin2675 $REGURL:8443

```

- Save Merge pull secret

> This merge pull secret require for creating clusters using mirror registry.

> TIPS: Only download pull secret from RedHat will not work, local mirror registry need to be merge else installation failed.

```
cp /root/.docker/config.json /home/cloudcafe/merge-pull-secret
chown cloudcafe:cloudcafe /home/cloudcafe/merge-pull-secret
```

### Create ImageSetConfiguration from 4.18 base images

> [To know Operators & channel version](https://github.com/cloudcafetech/homelab/blob/main/ocp/MIRROR-REGISTRY.md#to-know-name-of-the-operators-from-redhat-operator-index)

```
cat << EOF > isc-all.yaml
apiVersion: mirror.openshift.io/v2alpha1
kind: ImageSetConfiguration
mirror:
  platform:
    architectures:
    - amd64
    channels:
    - name: stable-4.20
      minVersion: 4.20.11
      maxVersion: 4.20.30
    graph: true
  operators:
  - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.20
    packages:
    - name: cluster-logging
      channels:
      - name: stable-6.4
    - name: loki-operator
      channels:
      - name: stable-6.4
    - name: metallb-operator
      channels:
      - name: stable
    - name: openshift-cert-manager-operator
      channels:
      - name: stable-v1
    - name: openshift-gitops-operator
      channels:
      - name: latest
    - name: advanced-cluster-management
      channels:
      - name: release-2.15
    - name: multicluster-engine
      channels:
      - name: stable-2.10
    - name: lvms-operator
      channels:
      - name: stable-4.18
    - name: kubernetes-nmstate-operator
      channels:
      - name: stable
    - name: kubevirt-hyperconverged
      channels:
      - name: stable
    - name: local-storage-operator
      channels:
      - name: stable
    - name: mtv-operator
      channels:
      - name: release-v2.10
    - name: cluster-observability-operator
      channels:
      - name: stable
    - name: netobserv-operator
      channels:
      - name: stable
  additionalImages:
  - name: registry.redhat.io/ubi8/ubi:latest
  - name: registry.redhat.io/ubi9/ubi:latest
  - name: registry.redhat.io/rhel8/support-tools
  - name: registry.redhat.io/rhel9/support-tools
  - name: registry.redhat.io/rhel8/rhel-guest-image:latest
  - name: registry.redhat.io/rhel9/rhel-guest-image:latest
  - name: gcr.io/k8s-staging-sig-storage/nfs-subdir-external-provisioner:v4.0.0
EOF

cat << EOF > isc-platform.yaml
apiVersion: mirror.openshift.io/v2alpha1
kind: ImageSetConfiguration
mirror:
  platform:
    architectures:
    - amd64
    channels:
    - name: stable-4.20
      minVersion: 4.20.11
      maxVersion: 4.20.11
    graph: true
  additionalImages:
  - name: registry.redhat.io/ubi8/ubi:latest
  - name: registry.redhat.io/ubi9/ubi:latest
  - name: registry.redhat.io/rhel8/support-tools
  - name: registry.redhat.io/rhel9/support-tools
  - name: registry.redhat.io/rhel8/rhel-guest-image:latest
  - name: registry.redhat.io/rhel9/rhel-guest-image:latest
  - name: gcr.io/k8s-staging-sig-storage/nfs-subdir-external-provisioner:v4.0.0
EOF

cat << EOF > isc-operator.yaml
apiVersion: mirror.openshift.io/v2alpha1
kind: ImageSetConfiguration
mirror:
  operators:
  - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.20
    packages:
    - name: cluster-logging
      channels:
      - name: stable-6.4
    - name: loki-operator
      channels:
      - name: stable-6.4
    - name: metallb-operator
      channels:
      - name: stable
    - name: openshift-cert-manager-operator
      channels:
      - name: stable-v1
    - name: openshift-gitops-operator
      channels:
      - name: latest
    - name: advanced-cluster-management
      channels:
      - name: release-2.15
    - name: multicluster-engine
      channels:
      - name: stable-2.10
    - name: lvms-operator
      channels:
      - name: stable-4.18
    - name: kubernetes-nmstate-operator
      channels:
      - name: stable
    - name: kubevirt-hyperconverged
      channels:
      - name: stable
    - name: local-storage-operator
      channels:
      - name: stable
    - name: mtv-operator
      channels:
      - name: release-v2.10
    - name: cluster-observability-operator
      channels:
      - name: stable
    - name: netobserv-operator
      channels:
      - name: stable
EOF

WORKDIR=/home/cloudcafe/work-dir
CACHEDIR=/home/cloudcafe/downloads/cache
REGURL=mirror-registry.pkar.tech

mkdir -p $WORKDIR
mkdir -p $CACHEDIR
```

### Setup Mirror Registry (Mirror 2 Mirror)

- Mirror Platform Images to Registry

```./oc-mirror --v2 -c ./isc-platform.yaml --image-timeout 30m --cache-dir $CACHEDIR --workspace file://$WORKDIR docker://$REGURL:8443/ocp```

- Mirror Operator Images to Registry   

```./oc-mirror --v2 -c ./isc-operator.yaml --image-timeout 30m --cache-dir $CACHEDIR --workspace file://$WORKDIR docker://$REGURL:8443/ocp```

### Setup Mirror Registry Images (Download & Upload)

- Mirror 2 Disk (Platform Images Download)

```./oc-mirror --v2 -c ./isc-platform.yaml --cache-dir $CACHEDIR file://$WORKDIR```

- Disk 2 Mirror (Platform Images Upload)

```./oc-mirror --v2 -c ./isc-platform.yaml --cache-dir $CACHEDIR --from file://$WORKDIR docker://$REGURL:8443/ocp```

- Mirror 2 Disk (Operator Images Download)

```./oc-mirror --v2 -c ./isc-operator.yaml --cache-dir $CACHEDIR file://$WORKDIR```

- Disk 2 Mirror (Operator Images Upload)  

```./oc-mirror --v2 -c ./isc-operator.yaml --cache-dir $CACHEDIR --from file://$WORKDIR docker://$REGURL:8443/ocp```

### Applying Mirror Configuration files in OpenShift

> Setting up mirrored operator in disconnected OCP cluster, need to apply following three files generated by oc-mirror & located in working-dir/cluster-resources of $PLATFORM & $OPERATOR.

> Make sure deployment order as follows

```
IDMS (ImageDigestMirrorSet): Responsible for where to find mirrored images based on their digests
CC (ClusterCatalog): Contains additional metadata for the mirroring configuration
CS (CatalogSource): Due to this operator visible in OperatorHub
```

- Apply all in one

```
cat << EOF > combind.yaml
apiVersion: config.openshift.io/v1
kind: ImageDigestMirrorSet
metadata:
  name: idms
spec:
  imageDigestMirrors:
  - mirrors:
    - $REGURL:8443/ocp/openshift/release
    source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
  - mirrors:
    - $REGURL:8443/ocp/openshift/release-images
    source: quay.io/openshift-release-dev/ocp-release
  - mirrors:
    - $REGURL:8443/ocp
    source: registry.redhat.io
  - mirrors:
    - $REGURL:8443/ocp/k8s-staging-sig-storage
    source: gcr.io/k8s-staging-sig-storage
---
apiVersion: olm.operatorframework.io/v1
kind: ClusterCatalog
metadata:
  name: cc-redhat-operator-index-v4-20
spec:
  priority: 0
  source:
    image:
      ref: $REGURL:8443/ocp/redhat/redhat-operator-index:v4.20
    type: Image
status: {}
---
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: cs-redhat-operator-index-v4-20
  namespace: openshift-marketplace
spec:
  image: $REGURL:8443/ocp/redhat/redhat-operator-index:v4.20
  sourceType: grpc
status: {}
EOF

oc apply -f combind.yaml

```

> Applying only the CatalogSource would result in pull failures.

> The IDMS file is particularly critical as it maps the original image references of mirror registry, as OpenShift wouldn’t know where to find the referenced images. 

- After applying combined (three files), verify that the CatalogSource becomes ready:

```oc get catalogsources -n openshift-marketplace```

#### Setup Web Server

```
yum install -y httpd
systemctl enable --now httpd
sed -i 's/Listen 80/Listen 0.0.0.0:8080/' /etc/httpd/conf/httpd.conf
mkdir /var/www/html/ocp
systemctl restart httpd
systemctl status httpd

wget https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.20/4.20.11/rhcos-4.20.11-x86_64-live-rootfs.x86_64.img -O /var/www/html/ocp/rhcos-4.20.11-x86_64-live-rootfs.x86_64.img
wget https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.20/4.20.11/rhcos-4.20.11-x86_64-live-iso.x86_64.iso -O /var/www/html/ocp/rhcos-4.20.11-x86_64-live-iso.x86_64.iso
wget https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.20/4.20.11/rhcos-installer-rootfs.x86_64.img -O /var/www/html/ocp/rhcos-installer-rootfs.x86_64.img

curl http://192.168.1.150:8080/ocp/rhcos-4.20.11-x86_64-live-rootfs.x86_64.img
curl http://192.168.1.150:8080/ocp/rhcos-4.20.11-x86_64-live-iso.x86_64.iso
curl http://192.168.1.150:8080/ocp/rhcos-installer-rootfs.x86_64.img


```

#### Extra preparation 

- Get Certificate Chain and save in file

```
echo | openssl s_client -connect mirror-registry.pkar.tech:8443 -showcerts </dev/null | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' > certificate_chain.pem
```

- Add extra 4 space in certificate chain file

> copy and paste content of file in ca-bundle.crt section

```sed -i 's/^/    /' certificate_chain.pem```

- Create AgentServiceConfig file

```
cat << EOF > mirror-registry-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: mirror-registry-config
  namespace: multicluster-engine
data:
  registries.conf: |
    unqualified-search-registries = ["registry.redhat.io", "registry.access.redhat.com", "docker.io"]

    [[registry]]
      prefix = ""
      location = "quay.io/openshift-release-dev/ocp-release"
      [[registry.mirror]]
        location = "$REGURL:8443/ocp/openshift/release-images"
        pull-from-mirror = "digest-only"

    [[registry]]
      prefix = ""
      location = "quay.io/openshift-release-dev/ocp-v4.0-art-dev"
      [[registry.mirror]]
        location = "$REGURL:8443/ocp/openshift/release"
        pull-from-mirror = "digest-only"

    [[registry]]
      prefix = ""
      location = "registry.redhat.io"
      [[registry.mirror]]
        location = "$REGURL.pkar.tech:8443/ocp"
        pull-from-mirror = "digest-only"

  ca-bundle.crt: |
    -----BEGIN CERTIFICATE-----
    MIIDpzCCAo+gAwIBAgIUMo+eBh/XOUjfjb9VTu6lOr2HDbcwDQYJKoZIhvcNAQEL
    BQAwczELMAkGA1UEBhMCVVMxCzAJBgNVBAgMAlZBMREwDwYDVQQHDAhOZXcgWW9y
    azENMAsGA1UECgwEUXVheTERMA8GA1UECwwIRGl2aXNpb24xIjAgBgNVBAMMGW1p
    cnJvci1yZWdpc3RyeS5wa2FyLnRlY2gwHhcNMjYwMTA4MTQwOTQ1WhcNMjYxMjMw
    MTQwOTQ1WjAaMRgwFgYDVQQDDA9xdWF5LWVudGVycHJpc2UwggEiMA0GCSqGSIb3
    DQEBAQUAA4IBDwAwggEKAoIBAQDcCB9hauTmHbTOSGp26tNXH/Cz3NrZ72qlko01
    LqCWkLDMRMTzo7t1R21ClEhtyKRyEJFQPer1EFauHrkymWdxB5ruUYHAnpf5lIbd
    em03brgqkuaXicXvs5gtPEayZiv0X8xLM3LVy8hrjWOnST5cD4shqieZISQfPNI8
    9+2F87U9LfnyYNjSNZ0LklxEATzrskBqCzT9BBcqcV9GTr07mpshI1tZLUCSU3pv
    cSSBy8r1k0hoNeTnQDgHlNgKttgthuoTH+cq4Za72jit2f7/wKZTzQQrEJFJfqCv
    SKig0eu6v4859vYCYn5iXXm0QE0Ck3hJRa31N3vOTy9vSgsnAgMBAAGjgYswgYgw
    CwYDVR0PBAQDAgLkMBMGA1UdJQQMMAoGCCsGAQUFBwMBMCQGA1UdEQQdMBuCGW1p
    cnJvci1yZWdpc3RyeS5wa2FyLnRlY2gwHQYDVR0OBBYEFC3T+oKBnU3rweBFbAeb
    O7xROmytMB8GA1UdIwQYMBaAFH/E3ISB2jFNsYrQO/Fih1szYuqjMA0GCSqGSIb3
    DQEBCwUAA4IBAQAziOzzPwFG9/gQOJgOvBNXi2FNi7EQ4SUwgjkWNPlwllC4bywG
    xNpFvGdQiu115okaiTibzatoPXIqRmj9QcrV68qEYGPSf8mfWCOfahO++s4g2e1b
    CYB1KKP5Wv7A1bBT0ipx3YYKkR7og2jtVQtBsLj8gDzPTGNjXtotF25+53CAJ6Wt
    JK+rn58IakUZgXr5Owg7hlz/tXlDgfUbIWT0icOrwU+rLhVtuFTcpFIcZzljznI4
    IIrBSXYyTXs+Pushk6hZOPl7pwDePrcFbgRGyXTHHWz+kcxOi0pX2eKTXIoCUrW5
    MlOlyD/xGV5pepYhPo5CkJ12UAkmo+QPaMHW
    -----END CERTIFICATE-----
    -----BEGIN CERTIFICATE-----
    MIID8TCCAtmgAwIBAgIUTtDLZ0pCIL/VqsOsNJ3Z/I0pYe8wDQYJKoZIhvcNAQEL
    BQAwczELMAkGA1UEBhMCVVMxCzAJBgNVBAgMAlZBMREwDwYDVQQHDAhOZXcgWW9y
    azENMAsGA1UECgwEUXVheTERMA8GA1UECwwIRGl2aXNpb24xIjAgBgNVBAMMGW1p
    cnJvci1yZWdpc3RyeS5wa2FyLnRlY2gwHhcNMjYwMTA4MTQwOTQzWhcNMjgxMDI4
    MTQwOTQzWjBzMQswCQYDVQQGEwJVUzELMAkGA1UECAwCVkExETAPBgNVBAcMCE5l
    dyBZb3JrMQ0wCwYDVQQKDARRdWF5MREwDwYDVQQLDAhEaXZpc2lvbjEiMCAGA1UE
    AwwZbWlycm9yLXJlZ2lzdHJ5LnBrYXIudGVjaDCCASIwDQYJKoZIhvcNAQEBBQAD
    ggEPADCCAQoCggEBAI28UiCa+Iv0WJZQ/9u/6zwEfobncWfbsxZG8bhhFHsHSrwU
    /NhjBS1QDoPDPoOoL1Lg4S712oLtMAVVOnyHLTIIoLVjZ0i4Fc2q4TRIoppE1f6z
    COGjhgL0q5IVBTL3ZtkX75B/wl4wHW9XZ+hiRXf+2jRYbUUSylcCQ3dDntE14tfl
    7WXfn1hVcoOHfuirq8PgfiVLCr1pL2s0NZnynodscgLC4uBTG84SI0CGZGckI9SR
    TAaN+f6CmHJ7UoYMeffHi9QM9ogDRcKHwTKXNGQ5dUpgbm7HSIo45xmBBGb3Oxjb
    7SUXO5aM5GzOrMqxAXEcyTe2pID7TgMXDaLO/CkCAwEAAaN9MHswCwYDVR0PBAQD
    AgLkMBMGA1UdJQQMMAoGCCsGAQUFBwMBMCQGA1UdEQQdMBuCGW1pcnJvci1yZWdp
    c3RyeS5wa2FyLnRlY2gwEgYDVR0TAQH/BAgwBgEB/wIBATAdBgNVHQ4EFgQUf8Tc
    hIHaMU2xitA78WKHWzNi6qMwDQYJKoZIhvcNAQELBQADggEBAFLj4wT7t6vtNl9c
    e1M58YOcAjjN/Pz0Aw5Rrxf36JO1ZnFT/yKVxDMhfvV4C3hGMWIiaHymap2yTZxZ
    ozAGMMiXps3+EjEAfWTlQcSosm8pkY51+oWpUo5Z/QtmwuQ7PtQ1sI8so+8rRBqH
    6qyVsmBI82RrbeMvBzARHa1Va2jov76KXLwsXnDvzQkzfW+nB0Ea/Wo1HlyKzRQC
    x4mSEOfY2Z75pBdjMnmD2cRt4JR/10aV10rot6TSXHqOIcA9XZ1A9Vr1anve5N/2
    Rzk8jcVj7c5OKWTOSXhyspsKk9JUS9PLdv+rFEuDTgzfZ6NYB6YBhZAHz9gkohgi
    TGaluAY=
    -----END CERTIFICATE-----
---
apiVersion: agent-install.openshift.io/v1beta1
kind: AgentServiceConfig
metadata:
  name: agent
  namespace: multicluster-engine
spec:
  databaseStorage:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 10Gi
  filesystemStorage:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 30Gi
  imageStorage:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 30Gi
  mirrorRegistryRef:
    name: mirror-registry-config
  osImages:
    - cpuArchitecture: x86_64
      openshiftVersion: '4.20'
      rootFSUrl: 'http://192.168.1.150:8080/ocp/rhcos-4.20.11-x86_64-live-rootfs.x86_64.img'
      url: 'http://192.168.1.150:8080/ocp/rhcos-4.20.11-x86_64-live-iso.x86_64.iso'
      version: 4.20.11
EOF
```

#### To know name of the operators from Redhat Operator Index

> Make sure grpcurl should install (wget https://github.com/fullstorydev/grpcurl/releases/download/v1.9.3/grpcurl_1.9.3_linux_amd64.rpm; yum install grpcurl_1.9.3_linux_amd64.rpm -y)

```
podman run -d --name rh-operator-index -p50051:50051 -it registry.redhat.io/redhat/redhat-operator-index:v4.18
grpcurl -plaintext localhost:50051 api.Registry/ListPackages > packages.out

> operator-list-json
for PKG in $(grpcurl -plaintext localhost:50051 api.Registry/ListPackages | jq -r .name); do
  grpcurl -plaintext -d "{\"name\":\"$PKG\"}" localhost:50051 api.Registry/GetPackage | jq -r '{"package": .name, "defaultChannel": .defaultChannelName}' >> operator-list-json
done

> operator-list-csv
grpcurl -plaintext localhost:50051 api.Registry/ListPackages | jq -r --raw-output '.name' | while read pkg; do
    grpcurl -plaintext -d "{\"name\":\"$pkg\"}" localhost:50051 api.Registry/GetPackage | jq -r --raw-output 'select(.defaultChannelName) | [.name, .defaultChannelName] | @csv' >> operator-list-csv
done
sed -i 's/"//g' operator-list-csv

while IFS=, read -r -a op; do
# echo "Name: ${op[0]}"
# echo "Channel: ${op[1]}"

cat << EOF > isc-${op[0]}.yaml
apiVersion: mirror.openshift.io/v2alpha2
kind: ImageSetConfiguration
mirror:
 operators:
 - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.18
   packages:
   - name: ${op[0]}
     channels:
     - name: ${op[1]}
EOF
done < operator-list-csv

#podman kill rh-operator-index; podman rm rh-operator-index
podman ps -a
```

#### Troubleshooting helper

- Restart process (command) if killed

> Modify PROCESS_COMMAND as per requirement 

```
cat << EOF > download-restart.sh
#!/bin/bash

PLATFORM=/home/cloudcafe/platform-images
OPERATOR=/home/cloudcafe/operator-images
CACHEDIR=/home/cloudcafe/downloads/cache
REGURL=mirror-registry.pkar.tech

PROCESS_COMMAND="/root/mirror-registry/tools/oc-mirror --v2 -c /root/mirror-registry/tools/isc-platform.yaml --cache-dir $CACHE-DIR --workspace file://$MIRROR-DIR docker://$REGURL:8443/ocp &"

echo "Starting background process monitor..."

while :
do
  $PROCESS_COMMAND
  echo "$PROCESS_COMMAND was killed. Restarting..."
  # Optional: add a short sleep to prevent a rapid respawn loop if the process crashes instantly
  sleep 2
done &

# Store the PID of the monitoring loop (the parent process of your_process_executable)
MONITOR_PID=$!
echo "Monitor running with PID: $MONITOR_PID"

# Wait for user input to stop the monitor (optional)
read -p "Press Enter to stop the monitor and exit..."

# Kill the monitor process to stop everything
kill "$MONITOR_PID"
echo "Monitor stopped."
EOF

chmod 755 download-restart.sh
```
