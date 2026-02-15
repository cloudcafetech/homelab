#!/bin/bash
# Script to Create Custom SSL certificate for (OMR) OpenShift Mirror Registry

DOMAIN=pkar.tech
COUNTRY=IN
STATE=WB
LOCAL=Kolkata
MAIL=cloudcafe@pkar.tech

echo - Create new root CA and private key

openssl genrsa -out rootCA.key 2048
openssl req -x509 -new -nodes -key rootCA.key -sha256 -days 3650 -out rootCA.pem -subj "/C=$COUNTRY/ST=$STATE/L=$LOCAL/O=Quay/OU=Quay/CN=*.$DOMAIN/emailAddress=$MAIL"

echo - Create a private key which will sign the certificate signing request

openssl genrsa -out ssl.key 2048

echo - Create an openssl.cnf file which will be used to apply SAN extensions to both CSR and end certificate

cat << EOF > openssl.cnf
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
countryName = $COUNTRY
stateOrProvinceName = $STATE
localityName = $LOCAL
organizationName = Quay
organizationalUnitName = Quay
commonName = *.$DOMAIN

[ v3_req ]
# Extensions to add to a certificate request
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = *.$DOMAIN
EOF

echo - Create certificate signing request using openssl.cnf

openssl req -new -key ssl.key -out ssl.csr -reqexts v3_req -config openssl.cnf

echo - To check the validity of the generated CSR

openssl req -in ssl.csr -noout -text

echo - Based on the created CSR, create server certificate

openssl x509 -req -in ssl.csr -CA rootCA.pem -CAkey rootCA.key -CAcreateserial -out ssl.cert -days 6350 -extensions v3_req -extfile openssl.cnf

echo - Check certificate has the proper extensions added

openssl x509 -in ssl.cert -noout -text
