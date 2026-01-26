#!/bin/bash
# Script to extract kubeconfig & kubeadmin credentials from RHACM Managed Cluster

# read cluster name from CLI
CLUSTER=${1:-demo}
LOCATION=/root/ocp
mkdir -p $LOCATION/$CLUSTER

oc extract -n "$CLUSTER" \
     $(oc get secret -o name -n "$CLUSTER" \
          -l hive.openshift.io/cluster-deployment-name="$CLUSTER" \
          -l hive.openshift.io/secret-type=kubeconfig) \
     --to="$LOCATION/$CLUSTER/" \
     --confirm

oc extract -n "$CLUSTER" \
     $(oc get secret -o name -n "$CLUSTER" \
          -l hive.openshift.io/cluster-deployment-name="$CLUSTER" \
          -l hive.openshift.io/secret-type=kubeadmincreds ) \
     --to="$LOCATION/$CLUSTER/" \
     --confirm
