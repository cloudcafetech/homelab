## Proxmox VE Wifi

### Prerequisites:

- Wired ethernet connection - this is required to install wpasupplicant

- Configure your wifi router to route to networks that will be associated with wifi adapter.

```
Destination = 192.168.29.0
Netmask = 255.255.255.0
Gateway = 192.168.29.100 (specify IP address of wifi adapter)
```

### Proxmox Setup with wifi

- Connect ethernet cable.

- Install Proxmox

- After the install completes and the system has rebooted, install wpasupplicant (and install vim while you're at it):

```
apt update -y && apt install wpasupplicant vim -y
systemctl disable wpa_supplicant
```

- Configure wpasupplicant:

```
wpa_passphrase SSIDNAME PASSWORD >> /etc/wpa_supplicant/wpa_supplicant.conf
```

- Determine wireless adapter device name. (example: wlp0s20f3)

```
dmesg | grep -i wlp
```

##### output: ([    4.098921] iwlwifi 0000:00:14.3 wlp0s20f3: renamed from wlan0)

- Create /etc/systemd/system/wpa_supplicant.service and add configuration:

```
cat <<EOF > /etc/systemd/system/wpa_supplicant.service

[Unit]
Description=WPA supplicant
Before=network.target
After=dbus.service
Wants=network.target
IgnoreOnIsolate=true
 
[Service]
Type=dbus
BusName=fi.w1.wpa_supplicant1
ExecStart=/sbin/wpa_supplicant -u -s -c /etc/wpa_supplicant/wpa_supplicant.conf -i wlp0s20f3  ## specify your wireless device here
Restart=always
 
[Install]
WantedBy=multi-user.target
Alias=dbus-fi.w1.wpa_supplicant1.service
EOF
```

- Enable wpasupplicant service:

```systemctl enable wpa_supplicant```

- Configure network intefaces:

```
cat <<EOF > add-wifi
auto wlp0s20f3  		               ## specify your wireless device here
iface wlp0s20f3 inet manual	     ## specify your wireless device here
    address 192.168.29.100/24
    gateway 192.168.29.1

# remove comment after SDN create (step #13)
#iface vnet1 inet static
#               address 192.168.3.1/24
#               bridge-ports none
#               bridge-stp off
#               bridge-fd 0
#               post-up echo 1 > /proc/sys/net/ipv4/ip_forward
#               post-up iptables -t nat -A POSTROUTING -s '192.168.3.0/24' -o wlp0s20f3 -j MASQUERADE     ## specify your wireless device here
#               post-up iptables -t raw -I PREROUTING -i fwbr+ -j CT --zone zone1  ## Zone ID
#               post-down iptables -t nat -D POSTROUTING -s '192.168.3.0/24' -o wlp0s20f3 -j MASQUERADE   ## specify your wireless device here
#               post-down iptables -t raw -D PREROUTING -i fwbr+ -j CT --zone zone1  ## Zone ID

source /etc/network/interfaces.d/*
EOF
cat add-wifi >> /etc/network/interfaces
```

- Restart wpa_supplicant and networking services to connect wireless adapter to wifi network:

```systemctl restart wpa_supplicant && systemctl restart networking```

- Remove subscription nag message:

```
sed -Ezi.bak "s/(Ext.Msg.show\(\{\s+title: gettext\('No valid sub)/void\(\{ \/\/\1/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js 
systemctl restart pveproxy.service
```

- Log into proxmox web interface: https://192.168.29.100:8006

- Create SDN config (Datacenter --> SDN): (step #13)

Zone: Simple, ID = Zone1 (use any name you like for ID)
Vnet: Name = vnet1 (use any name you like for Name), Zone = Zone1 (must match Zone ID)
Subnet: Subnet = 192.168.3.0/24, Gateway = 192.168.3.1, SNAT (check)

- Apply config: SDN --> Apply

- Edit once again network intefaces & remove # (which we did earlier steps)

```
vi /etc/network/interfaces
```

- Restart network service:

```systemctl restart networking```

[Ref#1](https://forum.proxmox.com/threads/howto-proxmox-ve-8-1-2-wifi-w-snat.142831/)

[Ref#2](https://x88.in/proxmox-with-wifi/)
