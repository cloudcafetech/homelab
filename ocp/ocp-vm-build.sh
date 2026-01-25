#! /bin/bash
# Openshift VM (sno-acm sno-sa ocp-m1 ocp-m2 ocp-m3) Create script

echo "Before execute edit as per requirement."

# Create SNO ACM VM
sno-acm() {

CLUSTER=sno-acm
MEM=28384
IP=192.168.1.135
MAC=52:54:00:42:a4:35
VNCPORT=5935
INSTDIR=/home/sno/$CLUSTER
mkdir -p $INSTDIR
cd $INSTDIR
wget http://192.168.1.159:8080/ocp/$CLUSTER.iso

qemu-img create -f qcow2 $INSTDIR/$CLUSTER-os-disk.qcow2 100G

virt-install \
  --name=$CLUSTER \
  --ram=$MEM \
  --vcpus=12 \
  --cpu host-passthrough \
  --os-variant=rhel8.0 \
  --noreboot \
  --events on_reboot=restart \
  --noautoconsole \
  --import \
  --cdrom $INSTDIR/$CLUSTER.iso \
  --disk path=$INSTDIR/$CLUSTER-os-disk.qcow2,size=100 \
  --network network=host-bridge,mac=$MAC \
  --graphics vnc,listen=0.0.0.0,port=$VNCPORT,password=pkar2675

sleep 10
virsh list --all

echo "Post Install follow!! ( https://github.com/cloudcafetech/homelab/blob/main/ocp/SNO-from-MirrorRegistry.md#post-installation )"

}

# Create SNO Stand Alone VM
sno-sa() {

CLUSTER=sno-sa
MEM=16384
IP=192.168.1.120
MAC=52:54:00:42:a4:20
VNCPORT=5920
INSTDIR=/home/sno/$CLUSTER
mkdir -p $INSTDIR
cd $INSTDIR
wget http://192.168.1.159:8080/ocp/$CLUSTER.iso

qemu-img create -f qcow2 $INSTDIR/$CLUSTER-os-disk.qcow2 100G

virt-install \
  --name=$CLUSTER \
  --ram=$MEM \
  --vcpus=12 \
  --cpu host-passthrough \
  --os-variant=rhel8.0 \
  --noreboot \
  --events on_reboot=restart \
  --noautoconsole \
  --import \
  --cdrom $INSTDIR/$CLUSTER.iso \
  --disk path=$INSTDIR/$CLUSTER-os-disk.qcow2,size=100 \
  --network network=host-bridge,mac=$MAC \
  --graphics vnc,listen=0.0.0.0,port=$VNCPORT,password=pkar2675

sleep 10
virsh list --all

echo "Post Install follow!! ( https://github.com/cloudcafetech/homelab/blob/main/ocp/SNO-from-MirrorRegistry.md#post-installation )"

}

# Create OCP Master1
ocp-m1() {

CLUSTER=ocp-m1
MEM=16384
IP=192.168.1.151
MAC=52:54:00:42:a4:51
VNCPORT=5951
INSTDIR=/home/sno/$CLUSTER
mkdir -p $INSTDIR
cd $INSTDIR
wget http://192.168.1.159:8080/ocp/ocp-ha.iso

qemu-img create -f qcow2 $INSTDIR/$CLUSTER-os-disk.qcow2 100G

virt-install \
  --name=$CLUSTER \
  --ram=$MEM \
  --vcpus=12 \
  --cpu host-passthrough \
  --os-variant=rhel8.0 \
  --noreboot \
  --events on_reboot=restart \
  --noautoconsole \
  --import \
  --cdrom $INSTDIR/ocp-ha.iso \
  --disk path=$INSTDIR/$CLUSTER-os-disk.qcow2,size=100 \
  --network network=host-bridge,mac=$MAC \
  --graphics vnc,listen=0.0.0.0,port=$VNCPORT,password=pkar2675

sleep 10
virsh list --all

echo "Post Install follow!! ( https://github.com/cloudcafetech/homelab/blob/main/ocp/SNO-from-MirrorRegistry.md#post-installation )"

}

# Create OCP Master2
ocp-m2() {

CLUSTER=ocp-m2
MEM=16384
IP=192.168.1.152
MAC=52:54:00:42:a4:52
VNCPORT=5952
INSTDIR=/home/ocp/$CLUSTER
mkdir -p $INSTDIR
cd $INSTDIR
wget http://192.168.1.159:8080/ocp/ocp-ha.iso

qemu-img create -f qcow2 $INSTDIR/$CLUSTER-os-disk.qcow2 100G

virt-install \
  --name=$CLUSTER \
  --ram=$MEM \
  --vcpus=12 \
  --cpu host-passthrough \
  --os-variant=rhel8.0 \
  --noreboot \
  --events on_reboot=restart \
  --noautoconsole \
  --import \
  --cdrom $INSTDIR/ocp-ha.iso \
  --disk path=$INSTDIR/$CLUSTER-os-disk.qcow2,size=100 \
  --network network=host-bridge,mac=$MAC \
  --graphics vnc,listen=0.0.0.0,port=$VNCPORT,password=pkar2675

sleep 10
virsh list --all

echo "Post Install follow!! ( https://github.com/cloudcafetech/homelab/blob/main/ocp/SNO-from-MirrorRegistry.md#post-installation )"

}

# Create OCP Master3
ocp-m3() {

CLUSTER=ocp-m3
MEM=16384
IP=192.168.1.153
MAC=52:54:00:42:a4:53
VNCPORT=5953
INSTDIR=/home/ocp/$CLUSTER
mkdir -p $INSTDIR
cd $INSTDIR
wget http://192.168.1.159:8080/ocp/ocp-ha.iso

qemu-img create -f qcow2 $INSTDIR/$CLUSTER-os-disk.qcow2 100G

virt-install \
  --name=$CLUSTER \
  --ram=$MEM \
  --vcpus=12 \
  --cpu host-passthrough \
  --os-variant=rhel8.0 \
  --noreboot \
  --events on_reboot=restart \
  --noautoconsole \
  --import \
  --cdrom $INSTDIR/ocp-ha.iso \
  --disk path=$INSTDIR/$CLUSTER-os-disk.qcow2,size=100 \
  --network network=host-bridge,mac=$MAC \
  --graphics vnc,listen=0.0.0.0,port=$VNCPORT,password=pkar2675

sleep 10
virsh list --all

echo "Post Install follow!! ( https://github.com/cloudcafetech/homelab/blob/main/ocp/SNO-from-MirrorRegistry.md#post-installation )"

}


case "$1" in
    'sno-acm')
            sno-acm
            ;;
    'sno-sa')
            sno-sa
            ;;
    'ocp-m1')
            ocp-m1
            ;;
    'ocp-m2')
            ocp-m2
            ;;
    'ocp-m3')
            ocp-m3
            ;;
    *)
            clear
            echo
            echo "Openshift VM (sno-acm sno-sa ocp-m1 ocp-m2 ocp-m3) Create script"
            echo
            echo "Usage: $0 { sno-acm | sno-sa | ocp-m1 | ocp-m2 | ocp-m3 }"
            echo
            exit 1
            ;;
esac

exit 0
