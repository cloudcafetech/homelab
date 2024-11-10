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
mkdir -p /opt/netboot/{config,assets}
docker run -d --name=pxeboot --restart unless-stopped -p 3000:3000 -p 69:69/udp -p 8080:80 -v /opt/netboot/config:/config -v /opt/netboot/assets:/assets ghcr.io/netbootxyz/netbootxyz
```

- Setup Custom Menu

```
wget https://gist.githubusercontent.com/clemenko/8df23cb764b326defcb4624b58ab4da2/raw/6d623f91c79f1d05082f9372ea3c475273f8563a/menu.ipxe
mv menu.ipxe /opt/netboot/config/menus/
HIP=`ip -o -4 addr list eth0 | awk '{print $4}' | cut -d/ -f1`
sed -i "s/192.168.1.220/$HIP/g" /opt/netboot/config/menus/menu.ipxe
```


