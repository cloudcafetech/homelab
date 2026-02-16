#!/bin/bash
# Script to Create OpenShift Mirror Registry (OMR)
REGURL=mirror-registry.pkar.tech

mkdir -p /root/mirror-registry/{tools,certs}
mkdir -p /home/{work-dir,cache}

echo - Generating Certificates
cd /root/mirror-registry/certs
wget https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/ocp/mirror-cert-gen.sh
chmod 755 mirror-cert-gen.sh
./mirror-cert-gen.sh

echo - Downloading tools
cd ../tools
wget https://mirror.openshift.com/pub/cgw/mirror-registry/latest/mirror-registry-amd64.tar.gz
wget https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/latest/oc-mirror.rhel9.tar.gz
wget https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-linux-amd64-rhel9.tar.gz

tar xvzpf mirror-registry-amd64.tar.gz
tar xvzpf oc-mirror.rhel9.tar.gz
tar xvzpf openshift-client-linux-amd64-rhel9.tar.gz
chmod 755 oc-mirror
rm -rf *.tar.gz README.md

cat << EOF > isc.yaml
apiVersion: mirror.openshift.io/v2alpha1
kind: ImageSetConfiguration
mirror:
  platform:
    architectures:
    - amd64
    channels:
    - name: stable-4.18
      minVersion: 4.18.30
      maxVersion: 4.18.30
    graph: true
  additionalImages:
  - name: gcr.io/k8s-staging-sig-storage/nfs-subdir-external-provisioner:v4.0.0
  operators:
  - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.18
    packages:
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
    - name: openshift-lifecycle-agent
      channels:
      - name: stable
EOF

echo - Creating Mirror Registry
./mirror-registry install \
  --quayHostname $REGURL \
  --quayRoot /root/mirror-registry/quay-config \
  --quayStorage /root/mirror-registry/storage \
  --sqliteStorage /root/mirror-registry/sqlite-storage \
  --sslCert /root/mirror-registry/cert/ssl.cert --sslKey /root/mirror-registry/cert/ssl.key \
  --sslCheckSkip --initUser admin --initPassword "Admin2675"

sleep 40

echo - Trust root certificate of Quay registry
cp /root/mirror-registry/certs/rootCA.pem /etc/pki/ca-trust/source/anchors/
update-ca-trust extract

echo - Start mirroring for OpenShift
./oc-mirror --v2 -c ./isc.yaml --image-timeout 60m --cache-dir /home/cache --workspace file:///home/work-dir docker://$REGURL:8443/ocp

#echo - Start mirroring for OpenShift Platform Images
#wget https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/ocp/isc-platform.yaml
#./oc-mirror --v2 -c ./isc-platform.yaml --image-timeout 60m --cache-dir /home/cache --workspace file:///home/work-dir docker://$REGURL:8443/ocp
#sleep 20
#echo - Start mirroring for OpenShift Operators Images
#wget https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/ocp/isc-operator.yaml
#./oc-mirror --v2 -c ./isc-operator.yaml --image-timeout 60m --cache-dir /home/cache --workspace file:///home/work-dir docker://$REGURL:8443/ocp

