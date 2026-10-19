## Internal Developer Portal

>Web Portal k8s based, which will connect multiple k8s cluster and take a request for provision namespace based application hosting, manage application, deployment and monitor as well .. request goes to manager for approval then Jira ticket creation .... ticket assign to k8s operation team ... and once done mail send to requester .... all workflow requester can see in dashboard.

<p align="center">
  <img src="https://github.com/cloudcafetech/homelab/blob/main/idp/screenshot/updated.jpg" width="676" height="580" alt="Migration Diagram">
</p>

- Folder structure

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
└── yamls/
    └── idp-all.yaml 
```

- Base Runtime Image (base-image/package.json)

```
{
  "name": "idp-base-runtime",
  "version": "1.0.0",
  "dependencies": {
    "axios": "^1.7.0",
    "express": "^4.19.0",
    "nodemailer": "^6.9.13",
    "pg": "^8.11.5"
  }
}
```

- Dockerfile (base-image/Dockerfile)

```
FROM node:20-alpine
WORKDIR /app
# Create working directory structure and ensure GID 0 write access
RUN mkdir -p /app/src/public /app/db && \
    chown -R 1001:0 /app && \
    chmod -R 775 /app
COPY package*.json ./
RUN npm install --production && \
    chown -R 1001:0 /app/node_modules && \
    chmod -R 775 /app/node_modules
# Use a non-root UID; OpenShift overrides this dynamically anyway
USER 1001:0
ENV NODE_PATH=/app/node_modules
CMD ["node", "/app/src/server.js"]
```

- Build Docker 

```
podman build -it docker.io/prasenforu/idp-base:v1 .
podman login docker.io
podman push docker.io/prasenforu/idp-base:v1
```

- Application Source  (server.js)
> Backend (conf/server.js). Updated paths to read from /app/src and /app/db.

- Dashboard Frontend (index.html)

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

- Deploy all in one yaml

```
oc create ns idp-system

oc create -f configmap.yaml

oc create -f idp-all.yaml

oc get cm,po,svc,pvc -n idp-system
```

### Manually Create DB

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


