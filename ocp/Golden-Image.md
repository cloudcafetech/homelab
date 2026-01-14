### Golden Image

- Folder creation

```
mkdir golden-image
cd golden-image
```

- Download Images locally

```
#curl https://cloud.centos.org/centos/8/x86_64/images/CentOS-8-GenericCloud-8.4.2105-20210603.0.x86_64.qcow2 -o centos8.qcow2
wget https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-20251223.0.x86_64.qcow2 -O centos9.qcow2
cp centos9.qcow2 centos9-ori.qcow2
```

- Check Filesystem size of image

```virt-filesystems --long -h --all -a centos9.qcow2 ```

- Increase Filesystem size of image

```
qemu-img create -f qcow2 mirror-registry.qcow2 40G
virt-resize --expand /dev/sda1 centos9.qcow2 mirror-registry.qcow2
virt-filesystems --long -h --all -a mirror-registry.qcow2
```

- Build Mirror Registry Golden Image

```
virt-customize -a mirror-registry.qcow2 --memsize 8192 --update --selinux-relabel \
  --root-password password:admin2675 --run-command "useradd -m cloudcafe" \
  --password cloudcafe:password:cloudcafe2675 --uninstall cloud-init \
  --hostname registry --timezone Asia/Kolkata \
  --run-command "sed -i 's/^mirrorlist/#mirrorlist/g' /etc/yum.repos.d/*.repo" \
  --run-command "sed -i 's|^#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|' /etc/yum.repos.d/*.repo" \
  --install git,wget,httpd,podman,tar,openssl,jq,openssh-server --firstboot-command "systemctl enable sshd && systemctl start sshd" \
  --edit '/etc/ssh/sshd_config:s/^#?PermitRootLogin.*/PermitRootLogin yes/' \
  --run-command "/usr/libexec/openssh/sshd-keygen rsa" \
  --run-command "systemctl enable httpd" --run-command "systemctl enable podman" \
  --run-command "sed -i 's/Listen 80/Listen 0.0.0.0:8080/' /etc/httpd/conf/httpd.conf" \
  --run-command "mkdir -p /var/www/html/ocp" --run-command "mkdir -p /root/registry/tools" --run-command "mkdir -p mkdir /root/.docker" \
  --run-command "wget https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-linux-amd64-rhel9.tar.gz" \
  --run-command "tar xvzpf openshift-client-linux-amd64-rhel9.tar.gz -C /usr/local/bin/" --run-command "rm -rf /usr/local/bin/README.md" \
  --run-command "wget https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/ocp/ocp-env-setup.sh" \
  --run-command "chmod 755 ocp-env-setup.sh"
```

- Backup Golden Image

```cp mirror-registry.qcow2 mirror-registry.qcow2-bkp```

# Test VM
virt-install \
  --name registry \
  --memory 2048 \
  --vcpus=6 \
  --cpu host-passthrough \
  --os-variant centos-stream9 \
  --noreboot \
  --events on_reboot=restart \
  --noautoconsole \
  --import \
  --disk /root/golden-image/mirror-registry.qcow2 \
  --network network=host-bridge \
  --graphics vnc,listen=0.0.0.0,port=5999,password=pkar2675


- Make Bootable (not tested)

```
wget https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/ocp/qcow2-to-liveos.sh
chmod 755 qcow2-to-liveos.sh
./qcow2-to-liveos.sh mirror-registry.qcow2
```

