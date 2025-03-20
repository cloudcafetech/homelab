#! /bin/bash
# apt install qemu-kvm libvirt-daemon-system libvirt-clients virtinst cpu-checker libguestfs-tools libosinfo-bin virt-install genisoimage -y
# run with 2>&1 | tee outfile

ORI=rhel9-cis-lvl1.qcow2
GI=rhel9-golden.qcow2
PVC=temp-rhel9-gi-pvc
GIPVC=rhel9-gi-pvc
GINS=pkar
RWXSC=cephfs
NODEIP=87.53.85.80
export KUBECONFIG=/home/prasenjit/config/kubevirt-test.yaml

# Function Golden Image Create
golden_image() {
cp $GI rhel9-golden-bkp.qcow2
rm -rf $GI

echo - Copying Original Image
cp $ORI $GI

echo - Base Image prepare
virt-customize --format qcow2 -a $GI --memsize 1024 --selinux-relabel --timezone Europe/Copenhagen \
  --upload chrony.conf:/etc/chrony.conf --run-command 'systemctl restart chronyd' \
  --run-command 'subscription-manager register --activation TDCNET-Nephele-selfsupport --org 5904432' \
  --install cloud-init,vim,git,bash-completion,wget,telnet,unzip,net-tools,bind-utils,tmux,nano,nmap,traceroute,rsync,tree,zip,tar,iotop,python3,lsof,strace,bzip2,sysstat,openscap-scanner,scap-security-guide,qemu-guest-agent \
  --run-command 'useradd -p Jaihind@Jaibharat@2675 superman' \
  --run-command 'passwd -x 99999 superman;passwd -x 99999 root;echo "superman ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers' \
  --run-command 'echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf; echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf' \
  --run-command 'echo "net.ipv6.conf.lo.disable_ipv6 = 1" >> /etc/sysctl.conf' \
  --run-command 'systemctl disable firewalld' --run-command 'systemctl enable qemu-guest-agent' \
  --edit /etc/selinux/config:'s/^SELINUX=.*/SELINUX=permissive/g' \
  --run-command 'systemctl stop cockpit; systemctl disable cockpit' \
  --upload 04-patch-rhel9.sh:/tmp/04-patch-rhel9.sh --run-command '/tmp/04-patch-rhel9.sh' \
  --upload $PWD/tools/TaniumClient-7.6.2.1218-1.rhe9.x86_64.rpm:/tmp/ --upload $PWD/tools/tanium-init.dat:/tmp/ --upload $PWD/tools/SentinelAgent_linux_x86_64_v24_2_2_20.rpm:/tmp/ \
  --upload $PWD/tools/rapid7-insight-agent-4.0.12.14-1.x86_64.rpm:/tmp/ --upload $PWD/tools/managesoft-18.0.0-1.x86_64.rpm:/tmp/ --upload $PWD/tools/Agent-Core-RedHat_EL9-20.0.1-21510.x86_64.rpm:/tmp/ \
  --upload $PWD/tools/katello-ca-consumer-latest.noarch.rpm:/tmp/ \
  --run-command 'rpm -ivh /tmp/TaniumClient-7.6.2.1218-1.rhe9.x86_64.rpm' --run-command 'cp /tmp/tanium-init.dat /opt/Tanium/TaniumClient/' \
  --run-command 'rpm -ivh /tmp/SentinelAgent_linux_x86_64_v24_2_2_20.rpm' \
  --run-command '/opt/sentinelone/bin/sentinelctl management token set eyJ1cmwiOiAiaHR0cHM6Ly9ldWNlMS10ZGNuZXQuc2VudGluZWxvbmUubmV0IiwgInNpdGVfa2V5IjogIjczMjA0ZTA1YzcwZGQ0N2QifQ==' \
  --run-command 'rpm -ivh /tmp/managesoft-18.0.0-1.x86_64.rpm' --run-command 'rpm -ivh /tmp/Agent-Core-RedHat_EL9-20.0.1-21510.x86_64.rpm' \
  --upload 06-set-firewall.sh:/tmp/06-set-firewall.sh --run-command '/tmp/06-set-firewall.sh' \
  --upload 10-log_rotate.sh:/tmp/10-log_rotate.sh --run-command '/tmp/10-log_rotate.sh' \
  --upload 11-system-cleanup.sh:/tmp/11-system-cleanup.sh --run-command '/tmp/11-system-cleanup.sh' \
  --run-command 'subscription-manager unregister' \
  --run-command 'rpm -ivh /tmp/katello-ca-consumer-latest.noarch.rpm' \
  --run-command 'echo "95.166.240.14 serverpatch02.eng.tdc.net serverpatch02" >> /etc/hosts' \
  --run-command 'sed -i -r "s/proxy_hostname =/proxy_hostname = geoproxy.nms.tdc.net/" /etc/rhsm/rhsm.conf' --run-command 'sed -i -r "s/proxy_port =/proxy_port = 3128/" /etc/rhsm/rhsm.conf' \
  --upload 01-set-dns.sh:/tmp/01-set-dns.sh --run-command '/tmp/01-set-dns.sh' \
  --run-command 'rm -rf /tmp/*.rpm /tmp/*.dat /tmp/*.sh' 

cp $GI rhel9-golden-final.qcow2
}

# Golden Image Upload in PVC
upload_image() {
echo - Upload Image in PVC
kubectl virt image-upload pvc $PVC --size=15Gi --image-path=$PWD/rhel9-golden-final.qcow2 --uploadproxy-url=https://$NODEIP:31001 --insecure --storage-class ceph-rbd -n $GINS

echo - Waiting PVC to be Bound
kubectl wait pvc $PVC --for=jsonpath='{.status.phase}'=Bound --timeout=10m -n $GINS
}

# Create Golden Image PVC with Readonly
readonly_image() {
kubectl patch cdi cdi --patch '{"spec": {"config": {"podResourceRequirements": {"limits": {"memory": "5G"}}}}}' --type merge

echo - Cloning Golden Image PVC
cat >> clone-pkar-rhel9-gi-pvc.yaml << EOF
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: clone-rhel9-gi-pvc
  namespace: $GINS
spec:
  source:
    pvc:
      name: $PVC
      namespace: $GINS
  pvc:
    accessModes:
      - ReadWriteMany
    resources:
      requests:
        storage: 16Gi
    volumeMode: Filesystem
    storageClassName: $RWXSC
EOF
kubectl create -f clone-pkar-rhel9-gi-pvc.yaml -n $GINS

echo - Waiting Clone PVC to be Bound
kubectl wait pvc clone-rhel9-gi-pvc --for=jsonpath='{.status.phase}'=Bound --timeout=10m -n $GINS

PV=`kubectl get pvc clone-rhel9-gi-pvc -n $GINS | grep -v VOLUME | awk '{print $3}'`
echo - Retaining Golden Image PV [$PV]
kubectl patch pv $PV -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
sleep 11

echo - Delete DV and Clone PVC
kubectl delete -f clone-pkar-rhel9-gi-pvc.yaml -n $GINS

echo - Waiting Clone PV to be Release
kubectl wait pv $PV --for=jsonpath='{.status.phase}'=Released --timeout=1m 

echo - Making Clone PV ROX mode
kubectl patch pv $PV -p '{"spec":{"claimRef": null}}'
kubectl patch pv $PV -p '{"spec":{"accessModes":["ReadOnlyMany"]}}' 

cat >> rhel9-gi-pvc-rox.yaml << EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $GIPVC
  namespace: $GINS
spec:
  accessModes:
  - ReadOnlyMany
  resources:
    requests:
      storage: 16Gi
  storageClassName: $RWXSC
  volumeMode: Filesystem
  volumeName: $PV
EOF

kubectl create -f rhel9-gi-pvc-rox.yaml -n $GINS

echo - Waiting Golden Image PVC [Readonly] to be Ready 
kubectl wait pvc $GIPVC --for=jsonpath='{.status.phase}'=Bound --timeout=1m -n $GINS
}


validation() {
OP=`kubectl wait pvc $GIPVC --for=jsonpath='{.status.phase}'=Bound --timeout=1m -n $GINS`
RESULT=`echo $OP | grep "condition met"`

if [ ! -z "${RESULT}" ]; then
 echo - Golden Image PVC [$GIPVC] ready to use !!
fi
}

# Main script execution
#golden_image
#upload_image
#readonly_image
validation
