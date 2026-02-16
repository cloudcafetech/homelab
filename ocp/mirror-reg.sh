#!/bin/bash
# Script to Create Custom SSL certificate for (OMR) OpenShift Mirror Registry

OCPVER=4.18
REGURL=mirror-registry.pkar.tech
NEWREGURL=mirror-registry2.pkar.tech
NEWIP=192.168.149
PASS=Admin2675

HIP=`ip -o -4 addr list br0 | grep -v secondary | awk '{print $4}' | cut -d/ -f1`
systemctl stop firewalld; systemctl disable firewalld

# Check pull-secret
if [ ! -f /root/pull-secret ]; then
  echo "pull-secret file not found under /root folder, PLEASE download pull secret from RedHat Console & save in /root folder"
  exit
fi

# Install required packages
yum install podman openssl jq httpd -y

echo - Generating Certificates
certgen() {
if [ ! -d "/root/mirror-registry/certs" ]; then
 yum install openssl jq -y
 mkdir -p /root/mirror-registry/certs
 cd /root/mirror-registry/certs
 wget https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/ocp/mirror-cert-gen.sh
 chmod 755 /root/mirror-registry/certs/mirror-cert-gen.sh
 /root/mirror-registry/certs/mirror-cert-gen.sh
}

echo - Downloading tools
mirrortools() {
if [ ! -d "/root/mirror-registry/tools" ]; then
 mkdir -p /root/mirror-registry/tools
 mkdir /root/.docker
 cd /root/mirror-registry/tools

 wget https://mirror.openshift.com/pub/cgw/mirror-registry/latest/mirror-registry-amd64.tar.gz
 wget https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/latest/oc-mirror.rhel9.tar.gz
 wget https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-linux-amd64-rhel9.tar.gz

 tar xvzpf mirror-registry-amd64.tar.gz
 tar xvzpf oc-mirror.rhel9.tar.gz
 tar xvzpf openshift-client-linux-amd64-rhel9.tar.gz
 chmod 755 oc-mirror
 cp oc kubectl oc-mirror /usr/local/bin
 rm -rf *.tar.gz README.md
fi
}

echo - Creating Mirror Registry
mirrorinstall() {
yum install podman -y
/root/mirror-registry/tools/mirror-registry install \
  --quayHostname $REGURL \
  --quayRoot /root/mirror-registry/quay-config \
  --quayStorage /root/mirror-registry/storage \
  --sqliteStorage /root/mirror-registry/sqlite-storage \
  --sslCert /root/mirror-registry/cert/ssl.cert --sslKey /root/mirror-registry/cert/ssl.key \
  --sslCheckSkip --initUser admin --initPassword "$PASS"

sleep 40

echo - Trust root certificate of Quay registry
cp /root/mirror-registry/certs/rootCA.pem /etc/pki/ca-trust/source/anchors/
update-ca-trust extract

mkdir /root/.docker
AUTH=`echo -n 'admin:$PASS'|base64 -w0`

cat << EOF > config.json
"$REGURL:8443": {
   "auth": "${AUTH}",
   "email": "cloudcafe@gmail.com"
}
EOF

cat /root/pull-secret | jq . > pull-secret.json
cat pull-secret.json |jq ".auths += {`cat config.json`}"|tr -d '[:space:]' > /root/.docker/config.json
more /root/.docker/config.json | jq .
more /root/.docker/config.json | jq '.auths | keys[]'
podman login -u admin -p $PASS $REGURL:8443
}

echo - Get Operators list and channels from RedHat Operator Index
getoplist() {
wget https://github.com/fullstorydev/grpcurl/releases/download/v1.9.3/grpcurl_1.9.3_linux_amd64.rpm
mv grpcurl_1.9.3_linux_amd64.rpm grpcurl.rpm
yum install podman grpcurl.rpm -y
rm grpcurl.rpm
podman run -d --name rh-operator-index -p50051:50051 -it registry.redhat.io/redhat/redhat-operator-index:v$OCPVER
> /root/mirror-registry/tools/operator-list-csv
grpcurl -plaintext localhost:50051 api.Registry/ListPackages | jq -r --raw-output '.name' | while read pkg; do
    grpcurl -plaintext -d "{\"name\":\"$pkg\"}" localhost:50051 api.Registry/GetPackage | jq -r --raw-output 'select(.defaultChannelName) | [.name, .defaultChannelName] | @csv' >> /root/mirror-registry/tools/operator-list-csv
done
sed -i 's/"//g' /root/mirror-registry/tools/operator-list-csv
wget https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/ocp/isc-platform.yaml
wget https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/ocp/isc-operator.yaml
echo "Modify Image Set Configuration files ..(in /root/mirror-registry/tools path)"
}


echo - Start mirroring for OpenShift Platform Images
mirrorpt() {
/root/mirror-registry/tools/oc-mirror --v2 -c /root/mirror-registry/tools/isc-pltform.yaml --image-timeout 60m --cache-dir /home/cache --workspace file:///home/work-dir docker://$REGURL:8443/ocp
}

echo - Start mirroring for OpenShift Operators Images
mirrorop() {
/root/mirror-registry/tools/oc-mirror --v2 -c /root/mirror-registry/tools/isc-operator.yaml --image-timeout 60m --cache-dir /home/cache --workspace file:///home/work-dir docker://$REGURL:8443/ocp
}

echo - Setup Web Server
websetup() {
 yum install -y httpd
 systemctl enable --now httpd
 sed -i 's/Listen 80/Listen 0.0.0.0:8080/' /etc/httpd/conf/httpd.conf
 mkdir /var/www/html/ocp
 systemctl restart httpd
}

case "$1" in
    'certgen')
            certgen
            ;;
    'mirrortools')
            mirrortools
            ;;
    'mirrorinstall')
            mirrorinstall
            ;;
    'getoplist')
            getoplist
            ;;
    'mirrorpt')
            mirrorpt
            ;;
    'mirrorop')
            mirrorop
            ;;
    'websetup')
            websetup
            ;;           
    *)
            clear
            echo
            echo "OpenShift Mirror Registry (Certificate | Mirrortool  | Registry | Operator List | Mirror Platform | Mirror Operator | WEB) setup"
            echo
            echo "Usage: $0 { certgen | mirrortools | mirrorinstall | getoplist | mirrorpt | mirrorop | websetup }"
            echo
            exit 1
            ;;
esac

exit 0

