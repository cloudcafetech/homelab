## Harvester Setup


- Setup Networking

First thing we need to do is setup the networking. In an enterprise situation we would isolate the data and management traffic to separate NICs. We need to create a network for the VMs to talk out.
We need to navigate Networks --> VM Networks.
Here we are going to Create an ```UntaggedNetwork``` named vlan1 network with a Cluster Network of mgmt.

![vmnetwork](https://github.com/user-attachments/assets/5a4978c3-8391-4fbb-9102-d83428dd477f)

- Create Hash Password

``` echo admin2675 | mkpasswd -m sha-512 -s ```

- cloud-int config

```
#cloud-config
# Generate-pass: echo admin2675 | mkpasswd -m sha-512 -s
# HashPassword: admin2675
disable_root: false
runcmd:
  - apt update -y
  - apt install -y iptables qemu-guest-agent vim iputils-ping
    apt-transport-https ca-certificates gpg nfs-common curl wget git net-tools
    unzip jq zip nmap telnet dos2unix
  - systemctl enable --now qemu-guest-agent
  - systemctl start qemu-guest-agent
  - sysctl -w net.ipv6.conf.all.disable_ipv6=1
hostname: jumphost.cloudcafe.tech
ssh_pwauth: True
users:
  - name: root
    hashed_passwd: $6$e1QXVI6hqUbrqQhQ$gjNUfY9qoPcumn9125bW6MFCYt1xA58Ap8uEx9iIoN1QYUi81re2Udl2hNOJaoedpQMN0OZD/c2r270lIGpwK0
    lock_passwd: false
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-rsa
        AAAAB3NzaC1yc2EAAAADAQABAAABAQC/DxthVrBHurzzzhJA0+XRq8zSCwXf/U4Xy8TKu9Ail6S9lkQS6SI13gxf9tFLc9FFCX5k7hbTaWk6WaZ+VKD+GqrE3g7P3VqrlZWPiEFCknZgWkQBASmzY3csB/f3Ve5GpeztbF4ZV8BGOI3RefswTt22moln0Gy+c+rbr4gIsrjS/bqe6emo92JaGLrF/MNLlt0LhtU+oaMq7we19FPPYPsb4nAFzaHxyL6J2uPGuPLDQas549IEjE+U0KSaRn8FWQxqDsC/T53g6nzuZFqpQw7oe0dqltmkOpOEk4sx+fjFRVxeyQqYM8NkkkIYEZ+UaEEclF4qw9mfPCNNvKaf
        cloudcafe
  - name: cloudcafe
    plain_text_passwd: admin2675
    lock_passwd: false
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - ssh-rsa
        AAAAB3NzaC1yc2EAAAADAQABAAABAQC/DxthVrBHurzzzhJA0+XRq8zSCwXf/U4Xy8TKu9Ail6S9lkQS6SI13gxf9tFLc9FFCX5k7hbTaWk6WaZ+VKD+GqrE3g7P3VqrlZWPiEFCknZgWkQBASmzY3csB/f3Ve5GpeztbF4ZV8BGOI3RefswTt22moln0Gy+c+rbr4gIsrjS/bqe6emo92JaGLrF/MNLlt0LhtU+oaMq7we19FPPYPsb4nAFzaHxyL6J2uPGuPLDQas549IEjE+U0KSaRn8FWQxqDsC/T53g6nzuZFqpQw7oe0dqltmkOpOEk4sx+fjFRVxeyQqYM8NkkkIYEZ+UaEEclF4qw9mfPCNNvKaf
        cloudcafe
ssh_authorized_keys:
  - ssh-rsa
    AAAAB3NzaC1yc2EAAAADAQABAAABAQC/DxthVrBHurzzzhJA0+XRq8zSCwXf/U4Xy8TKu9Ail6S9lkQS6SI13gxf9tFLc9FFCX5k7hbTaWk6WaZ+VKD+GqrE3g7P3VqrlZWPiEFCknZgWkQBASmzY3csB/f3Ve5GpeztbF4ZV8BGOI3RefswTt22moln0Gy+c+rbr4gIsrjS/bqe6emo92JaGLrF/MNLlt0LhtU+oaMq7we19FPPYPsb4nAFzaHxyL6J2uPGuPLDQas549IEjE+U0KSaRn8FWQxqDsC/T53g6nzuZFqpQw7oe0dqltmkOpOEk4sx+fjFRVxeyQqYM8NkkkIYEZ+UaEEclF4qw9mfPCNNvKaf
    cloudcafe
```

- Network Cloud-config

```
#cloud-config
version: 1
config:
- type: physical
  name: enp1s0
  subnets:
  - type: static
    address: 192.168.1.111/24
    gateway: 192.168.1.1
    dns_nameservers:
    - 8.8.8.8
```
