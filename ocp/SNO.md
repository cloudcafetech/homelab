# Single Node Openshift (SNO)

- Install necessary packages & create ssh key

```
mkdir -p /root/sno
cd /root/sno
VERSION=4.14.34
PULLSECRET='copy-and-paste-secret-file'

ssh-keygen -t rsa -N '' -f cloudcafe

SSHKEY=`cat cloudcafe.pub`

yum install podman -y
curl -k https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$VERSION/openshift-client-linux.tar.gz > oc-$VERSION.tar.gz
tar zxf oc-$VERSION.tar.gz
chmod +x oc
mv oc /usr/local/bin/
mv kubectl /usr/local/bin/

curl -k https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$VERSION/openshift-install-linux.tar.gz > openshift-install-linux-$VERSION.tar.gz
tar zxvf openshift-install-linux-$VERSION.tar.gz
chmod +x openshift-install
mv openshift-install /usr/local/bin/
```

- Check the ISO_URL

```
ISO_URL=$(openshift-install coreos print-stream-json | grep location | grep x86_64 | grep iso | cut -d\" -f4)
echo $ISO_URL
curl -L $ISO_URL > rhcos-live-414.x86_64.iso
```

- Create the install config file

```
cat <<EOF > install-config.yaml
apiVersion: v1
baseDomain: cloudcafe.tech
compute:
  - name: worker
    replicas: 0
controlPlane:
  name: master
  replicas: 1
metadata:
  name: sno-414
networking:
  networkType: OVNKubernetes
  clusterNetworks:
    - cidr: 10.128.0.0/14
      hostPrefix: 23
  serviceNetwork:
    - 172.30.0.0/16
BootstrapInPlace:
  InstallationDisk: /dev/sda
platform:
  none: {}
pullSecret: $PULLSECRET
sshKey: $SSHKEY
EOF
```

- Create single node ignition file

```
mkdir ocp && cp install-config.yaml ocp/
openshift-install --dir=ocp create single-node-ignition-config
```

- Prepare coreos-installer command

```alias coreos-installer='podman run --privileged --rm -v /dev:/dev -v /run/udev:/run/udev -v $PWD:/data -w /data quay.io/coreos/coreos-installer:release'```

- Create a script which will be used to replace the bootstrap ignition content.

```
cat <<EOF > install-to-disk-customized.sh
#!/usr/bin/env bash
set -euoE pipefail ## -E option will cause functions to inherit trap

# This script is executed by install-to-disk service when installing single node with bootstrap in place

. /usr/local/bin/bootstrap-service-record.sh

record_service_stage_start "wait-for-bootkube"
echo "Waiting for /opt/openshift/.bootkube.done"
until [ -f /opt/openshift/.bootkube.done ]; do
  sleep 5
done
record_service_stage_success

if [ ! -f coreos-installer.done ]; then
  record_service_stage_start "coreos-installer"
  # Write image + ignition to disk
  echo "Executing coreos-installer with the following options: install -i /opt/openshift/master.ign /dev/sda"
  coreos-installer install -n -i /opt/openshift/master.ign /dev/sda
  touch coreos-installer.done
  record_service_stage_success
fi

record_service_stage_start "reboot"
echo "Going to reboot"
shutdown -r +1 "Bootstrap completed, server is going to reboot."
touch /opt/openshift/.install-to-disk.done
echo "Done"
record_service_stage_success
EOF
```

- make a copy of original bootstrap ign file

```
cp ocp/bootstrap-in-place-for-live-iso.ign iso.ign
cp rhcos-live-414.x86_64.iso ocp/
```

- Encode the install-to-disk script and replace relevant content in bootstrap ign file.

```
newb64=$(cat install-to-disk-customized.sh |base64 -w0)
sed -i "s/IyEvdXNyL2Jpbi9lbnYgYmFzaApzZXQgLWV1b0UgcGlwZWZhaWwgIyMgLUUgb3B0aW9uIHdpbGwgY2F1c2UgZnVuY3Rpb25zIHRvIGluaGVyaXQgdHJhcAoKIyBUaGlzIHNjcmlwdCBpcyBleGVjdXRlZCBieSBpbnN0YWxsLXRvLWRpc2sgc2VydmljZSB3aGVuIGluc3RhbGxpbmcgc2luZ2xlIG5vZGUgd2l0aCBib290c3RyYXAgaW4gcGxhY2UKCi4gL3Vzci9sb2NhbC9iaW4vYm9vdHN0cmFwLXNlcnZpY2UtcmVjb3JkLnNoCgpyZWNvcmRfc2VydmljZV9zdGFnZV9zdGFydCAid2FpdC1mb3ItYm9vdGt1YmUiCmVjaG8gIldhaXRpbmcgZm9yIC9vcHQvb3BlbnNoaWZ0Ly5ib290a3ViZS5kb25lIgp1bnRpbCBbIC1mIC9vcHQvb3BlbnNoaWZ0Ly5ib290a3ViZS5kb25lIF07IGRvCiAgc2xlZXAgNQpkb25lCnJlY29yZF9zZXJ2aWNlX3N0YWdlX3N1Y2Nlc3MKCmlmIFsgISAtZiBjb3Jlb3MtaW5zdGFsbGVyLmRvbmUgXTsgdGhlbgogIHJlY29yZF9zZXJ2aWNlX3N0YWdlX3N0YXJ0ICJjb3Jlb3MtaW5zdGFsbGVyIgogICMgV3JpdGUgaW1hZ2UgKyBpZ25pdGlvbiB0byBkaXNrCiAgZWNobyAiRXhlY3V0aW5nIGNvcmVvcy1pbnN0YWxsZXIgd2l0aCB0aGUgZm9sbG93aW5nIG9wdGlvbnM6IGluc3RhbGwgLWkgL29wdC9vcGVuc2hpZnQvbWFzdGVyLmlnbiAvZGV2L3NkYSIKICBjb3Jlb3MtaW5zdGFsbGVyIGluc3RhbGwgLWkgL29wdC9vcGVuc2hpZnQvbWFzdGVyLmlnbiAvZGV2L3NkYQoKICB0b3VjaCBjb3Jlb3MtaW5zdGFsbGVyLmRvbmUKICByZWNvcmRfc2VydmljZV9zdGFnZV9zdWNjZXNzCmZpCgpyZWNvcmRfc2VydmljZV9zdGFnZV9zdGFydCAicmVib290IgplY2hvICJHb2luZyB0byByZWJvb3QiCnNodXRkb3duIC1yICsxICJCb290c3RyYXAgY29tcGxldGVkLCBzZXJ2ZXIgaXMgZ29pbmcgdG8gcmVib290LiIKdG91Y2ggL29wdC9vcGVuc2hpZnQvLmluc3RhbGwtdG8tZGlzay5kb25lCmVjaG8gIkRvbmUiCnJlY29yZF9zZXJ2aWNlX3N0YWdlX3N1Y2Nlc3MK/${newb64}/g" iso.ign
```

- Embed the bootstrap ign file to CoreOS live ISO file & verify

```
coreos-installer iso ignition embed -fi iso.ign rhcos-live-414.x86_64.iso
coreos-installer iso ignition show rhcos-live-414.x86_64.iso
```

- Add static IP setting to ISO kernel arguments ( Format: "ip=${ip}::${gateway}:${netmask}:${hostname}:${interface}:none:${nameserver}" )

```coreos-installer iso kargs modify -a "ip=192.168.29.230::192.168.29.1:255.255.255.0:ocpsno:ens18:off:192.168.29.1" rhcos-live-414.x86_64.iso```

### Now it's time to launch you SNO vm with the customized ISO file.

- Transfer image to proxmox 

```scp rhcos-live-414.x86_64.iso root@192.168.29.112:/var/lib/vz/template/iso/```

- ssh to proxmox and create vm 

```
qm create 230 --name ocpsno --ide2 local:iso/rhcos-live-414.x86_64.iso,media=cdrom --ostype l26 --boot order='scsi0;ide2;net0' \
  --cpu cputype=max --cores 6 --sockets 1 --memory 10240 --scsihw virtio-scsi-pci --bootdisk scsi0 \
  --net0 virtio,bridge=vmbr0 --scsi0 local-lvm:60,discard=on,ssd=1 \
  --serial0 socket --onboot yes
sleep 10
qm start 230
```

### Post boot setup

- login from jumphost

```
ssh -i cloudcafe core@192.168.29.230
sudo su -
```

- Setup DNSMASQ after login

```
cat << EOF > /etc/dnsmasq.d/single-node.conf
address=/apps.sno-414.cloudcafe.tech/192.168.29.230
address=/api-int.sno-414.cloudcafe.tech/192.168.29.230
address=/api.sno-414.cloudcafe.tech/192.168.29.230
EOF

systemctl enable dnsmasq
systemctl start dnsmasq

#sed -i '1s/^/nameserver 192.168.29.230\n/' /etc/resolv.conf
#echo "search cloudcafe.tech" >> /etc/resolv.conf

nmcli con mod ens18 +ipv4.dns-search cloudcafe.tech
nmcli con mod ens18 -ipv4.dns 192.168.29.1
nmcli con mod ens18 +ipv4.dns 192.168.29.230
nmcli con mod ens18 +ipv4.dns 192.168.29.1
nmcli con up ens18

echo "192.168.29.230 api.sno-414.cloudcafe.tech console-openshift-console.apps.sno-414.cloudcafe.tech integrated-oauth-server-openshift-authentication.apps.sno-414.cloudcafe.tech oauth-openshift.apps.sno-414.cloudcafe.tech prometheus-k8s-openshift-monitoring.apps.sno-414.cloudcafe.tech grafana-openshift-monitoring.apps.sno-414.cloudcafe.tech" >> /etc/hosts

journalctl -b -f -u release-image.service -u bootkube.service
```

- Set hostname after 2nd boot

```
cat << EOF > /etc/dnsmasq.d/single-node.conf
address=/apps.sno-414.cloudcafe.tech/192.168.29.230
address=/api-int.sno-414.cloudcafe.tech/192.168.29.230
address=/api.sno-414.cloudcafe.tech/192.168.29.230
EOF

systemctl enable dnsmasq
systemctl start dnsmasq
hostnamectl set-hostname ocpsno
```

- Check the Bootstrap status

```openshift-install --dir ocp/ wait-for bootstrap-complete --log-level=debug```

- Check the Install status

```openshift-install --dir ocp/ wait-for install-complete --log-level=debug```

- Check the cluster operator status

```
export KUBECONFIG=./ocp/auth/kubeconfig
oc get co
oc get no
```

- Validate Certificate

```openssl s_client -servername api.sno-414.cloudcafe.tech -connect api.sno-414.cloudcafe.tech:6443 | openssl x509 -noout -dates```

[Ref#1](https://ibm.github.io/waiops-tech-jam/blog/single-node-openshift-deployment-with-static-ip/)
[Ref#2](https://k8s.co.il/openshift/how-to-deploy-single-node-openshift/)
[Ref#3](https://www.certdepot.net/rhel7-configure-ipv4-addresses/)
