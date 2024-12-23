## Docker PXE Boot

- Install Docker

```
if ! command -v docker &> /dev/null;
then
  echo "MISSING REQUIREMENT: docker engine could not be found on your system. Please install docker engine"
  echo "Trying to Install Docker..."
  if [[ $(uname -a | grep amzn) ]]; then
    echo "Installing Docker for Amazon Linux"
    amazon-linux-extras install docker -y
  elif [[ -n $(uname -a | grep -iE 'ubuntu|debian') ]]; then 
     apt update -y
     apt install docker.io -y
  else
      yum install docker-ce docker-ce-cli -y
      systemctl start docker
      systemctl enable docker
  fi
fi
```

- Install Netboot

```
mkdir -p /opt/netboot/{config,assets,dns}
docker run -d --name=pxeboot --restart unless-stopped -p 3000:3000 -p 69:69/udp -p 8080:80 -v /opt/netboot/config:/config -v /opt/netboot/assets:/assets ghcr.io/netbootxyz/netbootxyz
```

- Install DNSMASQ

```
systemctl disable systemd-resolved
systemctl stop systemd-resolved

cat <<EOF > /opt/netboot/dns/dnsmasq.conf
# DHCP Settings 
dhcp-range=192.168.1.210,192.168.1.215,255.255.255.0,24h 
dhcp-option=3,192.168.1.1 
dhcp-option=6,192.168.1.35,192.168.1.1,8.8.8.8
dhcp-boot=netboot.xyz.kpxe,192.168.1.35
EOF

docker run --name dnsmasq -d -p 53:53/udp -p 53:53 -v /opt/netboot/dns/dnsmasq.conf:/etc/dnsmasq.conf --cap-add=NET_ADMIN andyshinn/dnsmasq
```

- Setup Custom Menu

```
wget https://gist.githubusercontent.com/clemenko/8df23cb764b326defcb4624b58ab4da2/raw/6d623f91c79f1d05082f9372ea3c475273f8563a/menu.ipxe
mv menu.ipxe /opt/netboot/config/menus/
HIP=`ip -o -4 addr list eth0 | awk '{print $4}' | cut -d/ -f1`
sed -i "s/192.168.1.220/$HIP/g" /opt/netboot/config/menus/menu.ipxe
```

[REF](https://gist.github.com/clemenko/8df23cb764b326defcb4624b58ab4da2)
[Ref#1](https://syncbricks.com/netboot-xyz-pfsense-docker-full-tutorial/)

[Video](https://www.youtube.com/watch?v=p8woPhLJ_DA)
[video#1](https://www.youtube.com/watch?v=GHs5JJZEsXI)
