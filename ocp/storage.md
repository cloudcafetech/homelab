## Storage

Local Path Provisioner on a Single-Node OpenShift (SNO)


- Create the local-path-storage namespace

```oc new-project local-path-storage```

- Create the service account for the provisioner

```oc create serviceaccount local-path-provisioner-service-account -n local-path-storage```

- Grant privileged access so the helper pods can manage host directories

```
oc adm policy add-scc-to-user hostmount-anyuid -z local-path-provisioner-service-account -n local-path-storage
oc adm policy add-scc-to-user privileged -z local-path-provisioner-service-account -n local-path-storage
```

- Create RBAC  

```
cat << EOF > local-path-rbac.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: local-path-provisioner-role
  namespace: local-path-storage
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch", "create", "patch", "update", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: local-path-provisioner-role
rules:
  - apiGroups: [""]
    resources: ["nodes", "persistentvolumeclaims", "configmaps", "pods", "pods/log"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["persistentvolumes"]
    verbs: ["get", "list", "watch", "create", "patch", "update", "delete"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["create", "patch"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: local-path-provisioner-bind
  namespace: local-path-storage
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: local-path-provisioner-role
subjects:
  - kind: ServiceAccount
    name: local-path-provisioner-service-account
    namespace: local-path-storage
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: local-path-provisioner-bind
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: local-path-provisioner-role
subjects:
  - kind: ServiceAccount
    name: local-path-provisioner-service-account
    namespace: local-path-storage
EOF

oc create -f local-path-rbac.yaml
```

- Deploy host path set helper pod

```
cat << EOF > run-command.yaml
apiVersion: v1
kind: Pod
metadata:
  name: host-command-executor
  namespace: local-path-storage
spec:
  nodeName: hcp-ctx-worker-01
  hostPID: true
  containers:
  - name: executor
    image: busybox:1.36
    command:
    - /bin/sh
    - -c
    - |
      echo "Entering host namespace..."
      nsenter -t 1 -m -u -n -i chcon -Rt container_file_t /opt/local-path-provisioner
      echo "Command completed."
    securityContext:
      privileged: true
      runAsUser: 0
  restartPolicy: Never
  serviceAccountName: local-path-provisioner-service-account
EOF

oc create -f run-command.yaml 
```

- Deploy Provisioner

```
cat << EOF > local-path-provisioner.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-path-config
  namespace: local-path-storage
data:
  config.json: |-
    {
            "nodePathMap":[
            {
                    "node":"hcp-ctx-worker-01",
                    "paths":["/opt/local-path-provisioner"]
            }
            ]
    }
  setup: |-
    #!/bin/sh
    set -eu
    mkdir -m 0777 -p "\$VOL_DIR"

  teardown: |-
    #!/bin/sh
    set -eu
    rm -rf "\$VOL_DIR"
  helperPod.yaml: |-
    apiVersion: v1
    kind: Pod
    metadata:
      name: helper-pod
    spec:
      priorityClassName: openshift-user-critical
      containers:
      - name: user-container
        image: alpine:latest
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: local-path-provisioner
  namespace: local-path-storage
spec:
  replicas: 1
  selector:
    matchLabels:
      app: local-path-provisioner
  template:
    metadata:
      labels:
        app: local-path-provisioner
    spec:
      serviceAccountName: local-path-provisioner-service-account
      priorityClassName: openshift-user-critical
      containers:
      - name: local-path-provisioner
        image: rancher/local-path-provisioner:v0.0.37
        imagePullPolicy: IfNotPresent
        command:
        - local-path-provisioner
        - --debug
        - start
        - --config
        - /etc/config/config.json
        volumeMounts:
        - name: config-volume
          mountPath: /etc/config/
        env:
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
      volumes:
      - name: config-volume
        configMap:
          name: local-path-config
EOF

oc apply -f local-path-provisioner.yaml
```

- Create Storage Class

```
cat << EOF > local-sc.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-path
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
EOF

oc create -f local-sc.yaml
```

- Verification

```
oc get sc

cat << EOF > test-pvc-pod.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: local-path-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: local-path-test
  namespace: default
spec:
  containers:
  - name: test
    image: busybox
    command: ["sh", "-c", "echo 'Local path works!' > /data/test.txt && cat /data/test.txt && df -h /data && sleep 3600"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: local-path-pvc
EOF

oc apply -f test-pvc-pod.yaml
oc get po,pvc -n default
```

