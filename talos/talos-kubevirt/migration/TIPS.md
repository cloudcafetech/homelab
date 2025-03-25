- Setting Static IP in Ubuntu

```
echo "network: {config: disabled}" >> /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg

cat << EOF > /etc/netplan/50-cloud-init.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      addresses:
        - 192.168.0.125/24
      nameservers:
        addresses: [192.168.29.1]
      routes:
        - to: default
          via: 192.168.0.1
EOF
```
