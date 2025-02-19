curl -o centos9-disk.qcow2 https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-20250113.0.x86_64.qcow2

qemu-img info centos9-disk.qcow2
qemu-img resize centos9-disk.qcow2 10G

cp centos9-disk.qcow2 golden-centos9-disk-10g.qcow2
virt-resize --expand /dev/sda1 centos9-disk.qcow2 golden-centos9-disk-10g.qcow2
qemu-img info golden-centos9-disk-10g.qcow
virt-filesystems --partitions --long -a golden-centos9-disk-10g.qcow2

export LIBGUESTFS_BACKEND=direct
export LIBGUESTFS_DEBUG=1 LIBGUESTFS_TRACE=1

virt-customize --format qcow2 -a golden-centos9-disk-10g.qcow2 \
   --install cloud-init,mod_ssl,httpd,mariadb-server,php,openssh-server \
   --memsize 1024 --selinux-relabel --timezone India/Kolkata \
   --root-password password:admin2675 --password centos:password:developer123 \
   --run-command 'systemctl enable httpd' --run-command 'systemctl enable mariadb' \
   --mkdir /var/www/html/manual --upload ~/lorax/index.html:/var/www/html/manual/index.html
