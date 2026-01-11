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

- Save Merge pull secret

> This merge pull secret require for creating clusters using mirror registry.
> TIPS: Only download pull secret from RedHat will not work, local mirror registry need to be merge else installation failed.

```
cp /root/.docker/config.json /home/cloudcafe/merge-pull-secret
chown cloudcafe:cloudcafe /home/cloudcafe/merge-pull-secret
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

nohup ./oc-mirror --config imageset.yaml --workspace file://root/mirror-registry/base-images-418 docker://mirror-registry.pkar.tech:8443/ocp --v2 &

```

- Setup Web Server

```
yum install -y httpd
systemctl enable --now httpd
sed -i 's/Listen 80/Listen 0.0.0.0:8080/' /etc/httpd/conf/httpd.conf
mkdir /var/www/html/ocp418
systemctl restart httpd
systemctl status httpd

wget https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.18/4.18.30/rhcos-4.18.30-x86_64-live-rootfs.x86_64.img -O /var/www/html/ocp418/rhcos-4.18.30-x86_64-live-rootfs.x86_64.img

wget https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.18/4.18.30/rhcos-4.18.30-x86_64-live.x86_64.iso -O /var/www/html/ocp418/rhcos-4.18.30-x86_64-live.x86_64.iso

curl http://192.168.1.150:8080/ocp418/rhcos-4.18.30-x86_64-live-rootfs.x86_64.img
curl http://192.168.1.150:8080/ocp418/rhcos-4.18.30-x86_64-live.x86_64.iso
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
cat << EOF > agentserviceconfig-mirror.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: assisted-installer-mirror-config
  namespace: multicluster-engine
  labels:
    app: assisted-service
data:
  registries.conf: |
    unqualified-search-registries = ["registry.access.redhat.com", "docker.io"]

    [[registry]]
      prefix = ""
      location = "registry.redhat.io/cert-manager"
      mirror-by-digest-only = true
      [[registry.mirror]]
        location = "mirror-registry.pkar.tech:8443/ocp/cert-manager"

    [[registry]]
      prefix = ""
      location = "registry.redhat.io/lvms4"
      mirror-by-digest-only = true
      [[registry.mirror]]
        location = "mirror-registry.pkar.tech:8443/ocp/lvms4"

    [[registry]]
      prefix = ""
      location = "registry.redhat.io/openshift4"
      mirror-by-digest-only = true
      [[registry.mirror]]
        location = "mirror-registry.pkar.tech:8443/ocp/openshift4"

    [[registry]]
      prefix = ""
      location = "registry.redhat.io/ubi8"
      mirror-by-digest-only = true
      [[registry.mirror]]
        location = "mirror-registry.pkar.tech:8443/ocp/ubi8"

    [[registry]]
      prefix = ""
      location = "registry.redhat.io/ubi9"
      mirror-by-digest-only = true
      [[registry.mirror]]
        location = "mirror-registry.pkar.tech:8443/ocp/ubi9"

    [[registry]]
      prefix = ""
      location = "quay.io/openshift-release-dev/ocp-release"
      mirror-by-digest-only = true
      [[registry.mirror]]
        location = "mirror-registry.pkar.tech:8443/ocp/openshift/release-images"

    [[registry]]
      prefix = ""
      location = "quay.io/openshift-release-dev/ocp-v4.0-art-dev"
      mirror-by-digest-only = true
      [[registry.mirror]]
        location = "mirror-registry.pkar.tech:8443/ocp/openshift/release"

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
    name: assisted-installer-mirror-config
  osImages:
    - cpuArchitecture: x86_64
      openshiftVersion: '4.18'
      rootFSUrl: 'http://192.168.1.150:8080/ocp418/rhcos-4.18.30-x86_64-live-rootfs.x86_64.img'
      url: 'http://192.168.1.150:8080/ocp418/rhcos-4.18.30-x86_64-live.x86_64.iso'
      version: 4.18.30
EOF
---

- To know name of the operators from Redhat Operator Index

> Make sure grpcurl should install (wget https://github.com/fullstorydev/grpcurl/releases/download/v1.9.3/grpcurl_1.9.3_linux_amd64.rpm; yum install grpcurl_1.9.3_linux_amd64.rpm -y)

```
podman run -d --name rh-operator-index -p50051:50051 -it registry.redhat.io/redhat/redhat-operator-index:v4.18
grpcurl -plaintext localhost:50051 api.Registry/ListPackages > packages.out

#podman kill rh-operator-index; podman rm rh-operator-index
podman ps -a
```

- Restart process (command) if killed

> Modify PROCESS_COMMAND as per requirement 

```
cat << EOF > download-restart.sh
#!/bin/bash

PROCESS_COMMAND="/root/mirror-registry/tools/oc-mirror --config /root/mirror-registry/tools/imageset.yaml --workspace file://root/mirror-registry/base-images-418 docker://mirror-registry.pkar.tech:8443/ocp --v2 &"

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
