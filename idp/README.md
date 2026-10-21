## Internal Developer Portal

>A self-service portal (IDP), take request for provision namespace/project or VM. Based on manager approval it will create ServiceNOW ticket. Requester can see status of ticket in portal and get on-demand update.

#### Architecture

<p align="center">
  <img src="https://github.com/cloudcafetech/homelab/blob/main/idp/screenshot/updated.jpg" width="676" height="580" alt="Migration Diagram">
</p>

#### Folder structure

```
k8s-idp/
├── base-image/
│   ├── package.json
│   └── Dockerfile          
├── conf/
│   ├── server.js           
│   ├── dashboard.html
│   ├── request-apps.html
│   ├── request-vm.html
│   ├── workflow-feed.html
│   ├── live-monitoring.html      
│   └── init.sql
├── mon/
│   ├── server.js
│   ├── browser.js      
│   ├── index.html
│   ├── app.yaml
│   └── rbac.yaml        
└── yamls/
    └── idp-all.yaml 
```

#### Image Build

- Base Runtime Image (base-image/package.json)

- Dockerfile (base-image/Dockerfile)

- Build Docker 

```
podman build -it docker.io/prasenforu/idp-base:v3 .
podman login docker.io
podman push docker.io/prasenforu/idp-base:v3
```

#### Deploy Application

- Create Configmap 
```
cat <<EOF > configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: idp-source-code
  namespace: idp-system
binaryData:
  server.js: $(base64 -w 0 ./server.js)
  dashboard.html: $(base64 -w 0 ./dashboard.html)
  request-apps.html: $(base64 -w 0 ./request-apps.html)
  request-vm.html: $(base64 -w 0 ./request-vm.html)
  workflow-feed.html: $(base64 -w 0 ./workflow-feed.html)
  live-monitoring.html: $(base64 -w 0 ./live-monitoring.html)
EOF
```

- Create NS, Deploy Configmap and all in one yaml
```
oc create ns idp-system
oc create -f configmap.yaml
oc create -f idp-all.yaml

oc get cm,po,svc,pvc -n idp-system
```

#### Monitoring App
This Monitoring only fetch data from cluster metric-server, make sure metric server install, or deploy (```kubectl apply -f https://raw.githubusercontent.com/cloudcafetech/homelab/refs/heads/main/idp/k8s-idp/mon/metric.yaml```)

> Goto mon folder

- Create Configmap yaml

```
cat <<EOF > monitoring-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: monitoring-code
  namespace: idp-system
binaryData:
  server.js: $(base64 -w 0 ./server.js)
  browser.js: $(base64 -w 0 ./browser.js)
  index.html: $(base64 -w 0 ./index.html)
EOF
```
- Create RBAC
> This RBAC, need to deploy every Clusters

```
kubectl create ns idp-system
kubectl create -f rbac.yaml
```

- Get TOKEN 
> Need to generate TOKEN every Clusters for create kubeconfig file (Check example)

```
kubectl get secret dashboard-admin-sa-token -n idp-system -o jsonpath='{.data.token}' | base64 --decode
```

- Create kubeconfig from every cluster using each Cluster TOKEN

- Merge All kubeconfig files

```
export KUBECONFIG=/path/to/first-config.yaml:/path/to/second-config.yaml
kubectl config view --flatten > merged-config.yaml
cp merged-config.yaml kubeconfig.yaml
```

- Create Kubeconfig secret

```
kubectl create secret generic multi-cluster-kubeconfig --from-file=config=kubeconfig.yaml -n idp-system 
```

- Create Monitoring App

```
kubectl create -f app.yaml
```

- Update Main IDP app variable GRAFANA_URL 

#### Ops

- Connect and create the database

```
oc exec -it pod/postgres-0 -n idp-system -- psql -U postgres -c "CREATE DATABASE idpdb;"
```

- Apply your schema directly into idpdb

```
oc exec -it pod/postgres-0 -n idp-system -- psql -U postgres -d idpdb -c "
CREATE TABLE IF NOT EXISTS requests (
  id SERIAL PRIMARY KEY,
  app_name VARCHAR(100) NOT NULL,
  env VARCHAR(20) NOT NULL DEFAULT 'dev',
  cpu VARCHAR(20) NOT NULL DEFAULT '500m',
  memory VARCHAR(20) NOT NULL DEFAULT '512Mi',
  cluster VARCHAR(100) NOT NULL,
  requester_email VARCHAR(150) NOT NULL,
  manager_email VARCHAR(150) NOT NULL,
  jira_ticket VARCHAR(50),
  status VARCHAR(40) NOT NULL DEFAULT 'PENDING_APPROVAL',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_requests_status ON requests(status);
CREATE INDEX IF NOT EXISTS idx_requests_cluster ON requests(cluster);
"
```

- Reinstalled DB 

```
oc delete statefulset postgres -n idp-system
oc delete pvc pgdata-postgres-0 -n idp-system
oc apply -f idp-all.yaml
```

- Restart app

```
kubectl rollout restart deployment/monitoring-dashboard -n idp-system
```


