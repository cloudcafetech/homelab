### Talos on Baremetal

- Set Env

```
TALOS_VER=v1.9.1
NIC=`ip -o -4 route show to default | awk '{print $5}'`
HIP=`ip -o -4 addr list $NIC | awk '{print $4}' | cut -d/ -f1`

DHCPS=192.168.0.30
DHCPE=192.168.0.50
GW=192.168.0.1
```

- Download kernel & setup matchbox

```
mkdir -p /var/lib/matchbox/{assets,groups,profiles}
wget -q https://factory.talos.dev/image/b553b4a25d76e938fd7a9aaa7f887c06ea4ef75275e64f4630e6f8f739cf07df/$TALOS_VER/kernel-amd64
wget -q https://factory.talos.dev/image/b553b4a25d76e938fd7a9aaa7f887c06ea4ef75275e64f4630e6f8f739cf07df/$TALOS_VER/initramfs-amd64.xz
mv kernel-amd64 /var/lib/matchbox/assets/vmlinuz
mv initramfs-amd64.xz /var/lib/matchbox/assets/initramfs.xz

cat <<EOF > /var/lib/matchbox/groups/default.json
{
  "id": "default",
  "name": "default",
  "profile": "default"
}
EOF

cat <<EOF > /var/lib/matchbox/profiles/default.json
{
  "id": "default",
  "name": "default",
  "boot": {
    "kernel": "/assets/vmlinuz",
    "initrd": ["/assets/initramfs.xz"],
    "args": [
      "initrd=initramfs.xz",
      "init_on_alloc=1",
      "slab_nomerge",
      "pti=on",
      "console=tty0",
      "console=ttyS0",
      "printk.devkmsg=on",
      "talos.platform=metal"
    ]
  }
}
EOF
```

- Start Matchbox

```
docker run --name=matchbox -d --net=host -v /var/lib/matchbox:/var/lib/matchbox:Z \
 quay.io/poseidon/matchbox:v0.10.0 -address=:8080 -log-level=debug
```

- Start DHCP Server

```
docker run --name=dnsmasq -d --cap-add=NET_ADMIN --net=host quay.io/poseidon/dnsmasq:v0.5.0-32-g4327d60-amd64 \
  -d -q -p0 --enable-tftp --tftp-root=/var/lib/tftpboot \
  --dhcp-range=$DHCPS,$DHCPE --dhcp-option=option:router,$GW \
  --dhcp-match=set:bios,option:client-arch,0 --dhcp-boot=tag:bios,undionly.kpxe \
  --dhcp-match=set:efi32,option:client-arch,6 --dhcp-boot=tag:efi32,ipxe.efi \
  --dhcp-match=set:efibc,option:client-arch,7 --dhcp-boot=tag:efibc,ipxe.efi \
  --dhcp-match=set:efi64,option:client-arch,9 --dhcp-boot=tag:efi64,ipxe.efi \
  --dhcp-userclass=set:ipxe,iPXE --dhcp-boot=tag:ipxe,http://$HIP:8080/boot.ipxe \
  --log-queries --log-dhcp
```

[REF #1](https://cozystack.io/docs/talos/installation/pxe/)

[REF #2](https://github.com/dellathefella/talos-baremetal-install/tree/master)

[Ref #3](https://github.com/MichaelTrip/taloscon2024)
