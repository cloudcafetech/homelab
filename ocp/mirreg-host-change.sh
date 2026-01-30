#! /bin/bash
# Change OMR (OpenShift Mirror Registry) Hostname/URL script
# Ref (https://access.redhat.com/solutions/7091008)

DOMAIN=pkar.tech
NEWIP=192.168.1.149
NEWDNS=192.168.1.159
NEWHOST=mirror-registry2
NEWHN=$NEWHOST.$DOMAIN

MIRPATH=/root/mirror-registry/
MOUNTPATH=/mnt/qcow2-mount
QCOW2PATH=/home/sno/mirreg2-os-disk.qcow2

OLDHOST=mirror-registry
OLDHN=$OLDHOST.$DOMAIN

mkdir -p /mnt/qcow2-mount

guestmount -a $QCOW2PATH -i --rw $MOUNTPATH

echo - Change IP DNS and Hostname

OLDIP=`cat $MOUNTPATH/etc/NetworkManager/system-connections/enp1s0.nmconnection | grep address | cut -d "=" -f2 | cut -d "/" -f1`
OLDNS=`cat $MOUNTPATH/etc/NetworkManager/system-connections/enp1s0.nmconnection | grep dns= | cut -d ";" -f1 | cut -d "=" -f2`

sed -i "s/$OLDIP/$NEWIP/g" $MOUNTPATH/etc/NetworkManager/system-connections/enp1s0.nmconnection 
sed -i "s/$OLDNS/$NEWDNS/g" $MOUNTPATH/etc/NetworkManager/system-connections/enp1s0.nmconnection
#sed -i "s/$OLDHOST/$NEWHOST/g" $MOUNTPATH/etc/hostname
sed -i "s/registry/registry2/g" $MOUNTPATH/etc/hostname

# Navigate to quay-install directory (quay-config and quay-rootCA)
# In quay-config, all SSL related plus and in quay-rootCA root CA. Same rootCA can be use

echo - Checking files

cd $MOUNTPATH/$MIRPATH/quay-config
ls -lrth
ls -lrth quay-config
ls -lrth quay-rootCA

echo - Backup existing ssl.key ssl.cert and openssl.cnf files

cd quay-config
cp ssl.cert ssl.cert.bak
cp ssl.key ssl.key.bak
cp openssl.cnf openssl.cnf.bak

echo - Creating private key with which will sign the certificate signing request

openssl genrsa -out ssl.key 2048

echo - Modify openssl.conf and config.yaml

sed -i "s/$OLDHN/$NEWHN/g" openssl.cnf
sed -i "s/$OLDHN/$NEWHN/g" config.yaml

echo - Create a certificate signing request based on openssl.cnf

openssl req -new -key ssl.key -out ssl.csr -reqexts v3_req -config openssl.cnf

echo - Validity of the generated CSR

openssl req -in ssl.csr -noout -text

echo - Using CSR creating server certificate.

openssl x509 -req -in ssl.csr -CA ../quay-rootCA/rootCA.pem -CAkey ../quay-rootCA/rootCA.key -CAcreateserial -out ssl.cert -days 3650 -extensions v3_req -extfile openssl.cnf

echo - Modify docker config.json and Trust Certificate copy

sed -i "s/$OLDHN/$NEWHN/g" $MOUNTPATH/root/.docker/config.json
cp -rf ../quay-rootCA/rootCA.pem $MOUNTPATH/etc/pki/ca-trust/source/anchors/

# Change Owner with user id=1001 and set right ACLs

#chown 1001:1001 ssl.cert ssl.key
#find . -type f -exec setfacl -m user:1001:rw {} \;
#find . -type d -exec setfacl -m user:1001:rwx {} \;

echo - Unmount
cd
guestunmount $MOUNTPATH
