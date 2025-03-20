#! /bin/bash
# This script will create temporary VM, run some inhouse script to make a RHEL9 Golden Image PVC [readonly]
# Auther: pnjk@tdcnet.dk
#

GIPVC=rhel9-gi-pvc
GINS=kubevirt-images
RWXSC=cephfs

# Function Pull repo
pull_repo() {


echo - Pulling repo
#git clone https://p-boss-gitlab-01.eng.tdc.net/cloud-and-platform-ops/iac/server-image-builder/kubevirt-rhel9-image.git

}

# Cluster access
ctx_access() {

echo - Access Cluster

#kubectl config set-credentials "$CI_PROJECT_ID" --token="$KTOKEN"
#kubectl config set-context "$CI_PROJECT_ID" --cluster="$CI_PROJECT_ID" --user="$CI_PROJECT_ID"
#kubectl config use-context "$CI_PROJECT_ID"

}

# VM Provision
vm_build() {

ctx_access

echo - deploying manifests
kubectl create -f $pwd/templates/namespace.yaml 
kubectl create -f $pwd/templates/secrets.yaml -f $pwd/templates/scripts-cm.yaml -f $pwd/templates/image-pvc.yaml

echo - Waiting PVC to be Bound
kubectl wait pvc rhel9-golden-image --for=jsonpath='{.status.phase}'=Bound --timeout=10m -n $GINS

echo - Deploying VM
kubectl create -f $pwd/templates/vm.yaml

echo - Checking VM logs for completions
kubectl logs -l vm.kubevirt.io/name=golden-img-vm -n $GINS | grep -q "Cleanup completed"

}

# Create Golden Image PVC with Readonly
readonly_image() {

ctx_access

echo - Cloning Golden Image PVC
cat >> clone-rhel9-gi-pvc.yaml << EOF
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: clone-rhel9-gi-pvc
  namespace: $GINS
spec:
  source:
    pvc:
      name: rhel9-golden-image
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
kubectl create -f clone-rhel9-gi-pvc.yaml -n $GINS

echo - Waiting Clone PVC to be bound
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

########################### usage #############################
usage () {
  echo ""
  echo " Usage: $0 {pull_repo | vm_build | readonly_image | validation}"
  echo ""
  echo " $0 pull_repo # Pull repo"
  echo ""
  echo " $0 vm_build # Build VM"
  echo ""
  echo " $0 readonly_image # Make PVC Readonly"
  echo ""
  echo " $0 validation # Validate"
  echo ""
  exit 1
}

case "$1" in
        pull_repo ) pull_repo;;
        vm_build ) vm_build;;
        readonly_image ) readonly_image;;
        validation ) validation;;  
        *) usage;;
esac


