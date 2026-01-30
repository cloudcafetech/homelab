## Change OMR (OpenShift Mirror Registry) Hostname/URL

- Shut down the OMR instance

```
systemctl stop quay-app.service

```

> SSL certs for OMR reside in the directory that bind mounts to /quay-registry/conf/stack directory inside the container. The location on the disk can be read from Quay's SystemD unit file

```
cat /etc/systemd/system/quay-app.service | grep -i conf -v /path/to/quay-install/quay-config:/quay-registry/conf/stack:Z \
```

- Navigate to quay-install directory (quay-config and quay-rootCA)

> In quay-config, all SSL related plus  and in quay-rootCA root CA

> same rootCA can be use

```
cd /path/to/quay-install
ls -lrth
ls -lrth quay-config
ls -lrth quay-rootCA

> Output

```
total 12K
-rw-------. 1 root root 1.7K Aug  8 04:48 rootCA.key
-rw-r--r--. 1 root root 1.4K Aug  8 04:48 rootCA.pem      <-- can be reuse the same rootCA 
-rw-r--r--. 1 root root   41 Aug  8 05:11 rootCA.srl
```

- Navigate to the quay-config directory indicated by the path and back up the existing ssl.key and ssl.cert, openssl.cnf files

```
cd quay-config
cp ssl.cert ssl.cert.bak
cp ssl.key ssl.key.bak
cp openssl.cnf openssl.cnf.bak
```

- Create a private key with which will sign the certificate signing request:

```
openssl genrsa -out ssl.key 2048
```

- Edit openssl.conf as follows

```
[req]
default_bits = 4096
default_md = sha256
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no
[req_distinguished_name]
C = US
ST = VA
L = New York
O = Quay
OU = Division
CN = mirror-registry.pkar.tech                <----edit with new hostname
[v3_req]
keyUsage = nonRepudiation, digitalSignature, keyEncipherment, keyCertSign
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS = mirror-registry.pkar.tech               <----edit with new hostname
```

- Create a certificate signing request based on the openssl.cnf file we just created:

```
openssl req -new -key ssl.key -out ssl.csr -reqexts v3_req -config openssl.cnf
```

> The generated CSR must have a v3 extensions section added to it. 

- To check the validity of the generated CSR:

```
openssl req -in ssl.csr -noout -text
```

> Output 

```
Certificate Request:
Data:
    Version: 1 (0x0)
    Subject: C = IE, ST = GALWAY, L = GALWAY, OU = QUAY, CN = mirror-registry.pkar.tech  <--- new hostname
...
    Attributes:
        Requested Extensions:
            X509v3 Basic Constraints:
                CA:FALSE
            X509v3 Key Usage:
                Digital Signature, Non Repudiation, Key Encipherment
            X509v3 Subject Alternative Name:
                DNS:mirror-registry.pkar.tech       <--- new hostname
```

- Based on the created CSR, create the server certificate that OMR will use:

```
openssl x509 -req -in ssl.csr -CA /pathto/quay-install/quay-rootCA/rootCA.pem -CAkey /athto/quay-install/quay-rootCA/rootCA.key -CAcreateserial -out ssl.cert -days 730 -extensions v3_req -extfile openssl.cnf
```

> Output

```
Signature ok
subject=C = US, ST = VA, L = New York, O = Quay, OU = Division, CN = mirror-registry.pkar.tech
Getting CA Private Key
```

- Quay runs all processes inside the container under user with id=1001. This user needs to be able to read the certificate and the private key for Quay to start properly:

```
# chown 1001:1001 ssl.cert ssl.key
```

- Set right ACLs:

```
# cd <quay-root>/quay-config/
# sudo find . -type f -exec setfacl -m user:1001:rw {} \;
# sudo find . -type d -exec setfacl -m user:1001:rwx {} \;
```

- Edit SERVER_HOSTNAME parameter in /path/to/quay-install/quay-config/config.yaml

> Output

```
SERVER_HOSTNAME: mirror-registry.pkar.tech:8443   <--- new hostname
```

- Restart OMR by running:

```
systemctl start quay-app.service
```

> The service should start momentarily. If you want, you can track the startup process by running journalctl -u quay-app.service -f. After 60-90 seconds, OMR should be available on the new hostname with new certificate.

- Next steps on OCP cluster using the mirror-registry:

> 1) If rootCA.crt is used while installing ocp, it should work without any issue.

> If ssl.cert is used, newly created certificate will need to be added to all OpenShift clusters that pull images from this OMR instance. This will ensure certificate trust. To add certs to OpenShift, please refer to the following documentation.

> 2) Update the global pull-secret to contain new hostname.
