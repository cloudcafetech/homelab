## SNO from Mirror Registry

- Download tools

```
dnf install /usr/bin/nmstatectl -y
wget https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/4.18.30/openshift-install-linux.tar.gz
wget https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/4.18.30/openshift-client-linux.tar.gz
tar zxvf openshift-install-linux.tar.gz
tar zxvf openshift-client-linux.tar.gz
mv oc /usr/local/bin/
mv kubectl /usr/local/bin/
rm openshift-install-linux.tar.gz openshift-client-linux.tar.gz README.md
```

- Transfer merged-pull-secret file (/home/cloudcafe/merge-pull-secret) from Mirror Registry server

> TIPS: Cluster Build in disconnected network from Mirror Registry, pull secret should contains credentials for both Mirror Registry and official Red Hat Registries.

```
scp cloudcafe@192.168.1.150:/home/cloudcafe/merge-pull-secret .
cp merge-pull-secret pull-secret
```
  
- Generate Agent and Install Config

```
ISO_URL=$(./openshift-install coreos print-stream-json | jq -r '.architectures.x86_64.artifacts' | grep location | grep iso | cut -d\" -f4)
REGURL=mirror-registry.pkar.tech
CLUSTER=sno-acm
ssh-keygen -t rsa -N '' -f id_rsa
PULLSECRET=`cat pull-secret` 
SSHKEY=`cat id_rsa.pub`
IP=192.168.1.135
MAC=52:54:00:42:a4:35
DNS=192.168.1.161
DOMAIN=pkar.tech
GW=192.168.1.1

echo $PULLSECRET
echo ""
echo $SSHKEY

mkdir ocp418
mkdir ocp418-backup

cat << EOF > agent-config.yaml
apiVersion: v1beta1
kind: AgentConfig
metadata:
  name: $CLUSTER
rendezvousIP: $IP
hosts:
  - hostname: $CLUSTER
    interfaces:
      - name: enp1s0
        macAddress: $MAC
    rootDeviceHints:
      deviceName: /dev/vda
    networkConfig:
      interfaces:
        - name: enp1s0
          type: ethernet
          state: up
          mac-address: $MAC
          ipv4:
            enabled: true
            address:
              - ip: $IP
                prefix-length: 24
            dhcp: false
      dns-resolver:
        config:
          search:
            - $DOMAIN
          server:
            - $DNS
            - $GW
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: $GW
            next-hop-interface: enp1s0
            table-id: 254
EOF

cat << EOF > install-config.yaml
apiVersion: v1
baseDomain: pkar.tech
compute:
- architecture: amd64
  name: worker
  replicas: 0
controlPlane:
  architecture: amd64
  name: master
  platform:
  replicas: 1
metadata:
  name: $CLUSTER
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 192.168.1.0/24
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  none: {}
pullSecret: '$PULLSECRET'
sshKey: $SSHKEY
imageDigestSources:
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
additionalTrustBundle: |
EOF
```

- Get Certificate Chain and merge in install-config.yaml

```
echo | openssl s_client -connect $REGURL:8443 -showcerts </dev/null | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' > certificate_chain.pem
sed -i 's/^/  /' certificate_chain.pem
cat certificate_chain.pem >> install-config.yaml

cp *-config.yaml ocp418-backup/
cp *-config.yaml ocp418/
```

- Create iso

```./openshift-install --dir=ocp418 agent create image --log-level=debug ```

- Create VM using ISO

```
qemu-img create -f qcow2 /home/sno/sno-sa.qcow2 120G

virt-install \
  --name=sno-sa \
  --ram=16384 \
  --vcpus=12 \
  --cpu host-passthrough \
  --os-variant=rhel8.0 \
  --noreboot \
  --events on_reboot=restart \
  --noautoconsole \
  --import \
  --cdrom /home/sno/standalone/ocp418/agent.x86_64.iso \
  --disk path=/home/sno/sno-sa.qcow2,size=120 \
  --network network=host-bridge,mac=52:54:00:42:a4:40 \
  --graphics vnc,listen=0.0.0.0,port=5979,password=pkar2675
```

- Monitor install boostrapping

```openshift-install --dir=ocp418 agent wait-for bootstrap-complete --log-level=debug```

- Verify install complete

```openshift-install --dir=ocp418 agent wait-for install-complete --log-level=debug```

- Login Cluster

```
export KUBECONFIG=/home/sno/standalone/ocp418/auth/kubeconfig
oc get no
oc get co
```

