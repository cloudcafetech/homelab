#!/bin/bash
# Script to Create Custom SSL certificate for (OMR) OpenShift Mirror Registry

DOMAIN=pkar.tech
COUNTRY=IN
STATE=WB
LOCAL=Kolkata
MAIL=cloudcafe@pkar.tech

cat << EOF > openssl.cnf
[req]
default_bits = 4096
default_md = sha256
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no
[req_distinguished_name]
C = $COUNTRY
ST = $STATE
L = $LOCAL
O = Quay
OU = Division
CN = *.$DOMAIN
[v3_req]
keyUsage = nonRepudiation, digitalSignature, keyEncipherment, keyCertSign
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS = *.$DOMAIN
EOF

echo - Create root CA and private key
openssl genrsa -out rootCA.key 2048
openssl req -x509 -new -config openssl.cnf -nodes -key rootCA.key -sha256 -days 3650 -out rootCA.pem -addext basicConstraints=critical,CA:TRUE,pathlen:1

echo "Create private key which will sign Certificate Signing Request (CSR)"
openssl genrsa -out ssl.key 2048

echo - Create CSR using openssl.cnf
openssl req -new -key ssl.key -out ssl.csr -subj "/CN=quay-enterprise" -config openssl.cnf

echo - Validiting generated CSR
openssl req -in ssl.csr -noout -text

echo - Create Server certificate
openssl x509 -req -in ssl.csr -CA rootCA.pem -CAkey rootCA.key -CAcreateserial -out ssl.cert -days 3560 -extensions v3_req -extfile openssl.cnf

echo -  Create Chain Cert
cat ssl.cert rootCA.pem > chain.cert

echo - Replace ssl cert with chain cert
mv --force chain.cert ssl.cert

echo - Checking Certificate has the proper extensions added
openssl x509 -in ssl.cert -noout -text
