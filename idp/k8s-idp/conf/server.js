const express = require('express');
const { Pool } = require('pg');
const axios = require('axios');
const nodemailer = require('nodemailer');
const path = require('path');
const fs = require('fs');

const app = express();
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

const connectionString = process.env.DATABASE_URL || 'postgres://postgres:secret@postgres.idp-system.svc:5432/idpdb';
const pool = new Pool({ connectionString });

const mailer = nodemailer.createTransport({
  host: process.env.SMTP_HOST || 'mailhog.idp-system.svc',
  port: parseInt(process.env.SMTP_PORT || '1025', 10)
});

async function initDbWithRetry(retries = 10, delayMs = 3000) {
  for (let i = 1; i <= retries; i++) {
    try {
      const client = await pool.connect();
      const initSqlPath = '/app/db/init.sql';
      if (fs.existsSync(initSqlPath)) {
        const sql = fs.readFileSync(initSqlPath, 'utf8');
        await client.query(sql);
        console.log('Database tables and VM columns verified.');
      }
      client.release();
      return;
    } catch (err) {
      console.warn(`DB connection attempt ${i}/${retries} failed (${err.message}). Retrying...`);
      await new Promise(r => setTimeout(r, delayMs));
    }
  }
  console.error('All DB connection retries exhausted.');
}

app.post('/api/requests', async (req, res) => {
  const {
    resourceType = 'K8S_NAMESPACE',
    appName, env = 'dev', cpu = '500m', memory = '512Mi', storage = '10Gi',
    vmOsImage = 'rhel-9-image', cluster, requesterEmail, managerEmail
  } = req.body;

  try {
    const query = `
      INSERT INTO requests (resource_type, app_name, env, cpu, memory, storage, vm_os_image, cluster, requester_email, manager_email, status)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
      RETURNING id;
    `;
    const result = await pool.query(query, [
      resourceType, appName, env, cpu, memory, storage, vmOsImage, cluster, requesterEmail, managerEmail, 'PENDING_APPROVAL'
    ]);
    const requestId = result.rows[0].id;

    const appBaseUrl = process.env.PUBLIC_URL || 'http://localhost:3000';
    const isVm = resourceType === 'VIRTUAL_MACHINE';
    const labelText = isVm ? `Virtual Machine: ${appName}` : `Namespace: ${appName}`;
    await mailer.sendMail({
      from: 'portal@internal.dev',
      to: managerEmail,
      subject: `Approval Required: ${labelText}`,
      text: `Approve here: ${appBaseUrl}/api/approve/${requestId}`
    });

    res.status(201).json({ requestId, status: 'PENDING_APPROVAL' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/approve/:id', async (req, res) => {
  const { id } = req.params;
  try {
    await pool.query("UPDATE requests SET status = 'APPROVED', updated_at = NOW() WHERE id = $1", [id]);
    const reqData = (await pool.query("SELECT * FROM requests WHERE id = $1", [id])).rows[0];

    let jiraKey = 'MOCK-JIRA-456';
    const summaryPrefix = reqData.resource_type === 'VIRTUAL_MACHINE' ? 'Provision KubeVirt VM' : 'Provision Namespace';
    try {
      const jiraRes = await axios.post(`${process.env.JIRA_HOST}/rest/api/3/issue`, {
        fields: {
          project: { key: 'K8SOPS' },
          summary: `${summaryPrefix}: ${reqData.app_name} (${reqData.storage} storage) on ${reqData.cluster}`,
          issuetype: { name: 'Task' }
        }
      }, {
        auth: { username: process.env.JIRA_USER, password: process.env.JIRA_TOKEN }
      });
      jiraKey = jiraRes.data.key;
    } catch (err) {
      console.log('Jira skipped/mocked for dev:', err.message);
    }

    await pool.query("UPDATE requests SET status = 'JIRA_CREATED', jira_ticket = $2, updated_at = NOW() WHERE id = $1", [id, jiraKey]);

    setTimeout(async () => {
      try {
        await pool.query("UPDATE requests SET status = 'LIVE', updated_at = NOW() WHERE id = $1", [id]);
        await mailer.sendMail({
          from: 'portal@internal.dev',
          to: reqData.requester_email,
          subject: `Your ${reqData.resource_type === 'VIRTUAL_MACHINE' ? 'VM' : 'Namespace'} ${reqData.app_name} is Live!`,
          text: `Cluster: ${reqData.cluster}\nStorage: ${reqData.storage}\nJira: ${jiraKey}`
        });
      } catch (e) { console.error('Async completion notification failed:', e.message); }
    }, 5000);

    res.send(`<h2>Request Approved!</h2><p>Jira ticket ${jiraKey} created. Infrastructure syncing.</p>`);
  } catch (err) {
    res.status(500).send(`Error processing approval: ${err.message}`);
  }
});

app.get('/api/requests', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM requests ORDER BY created_at DESC');
    res.json(result.rows);
  } catch (err) {
    res.json([]);
  }
});

app.get('/api/config/monitoring', (req, res) => {
  res.json({
    grafanaHost: process.env.GRAFANA_URL || 'http://grafana.idp-system.svc:3000',
    defaultDashboardUid: process.env.GRAFANA_DASHBOARD_UID || 'k8s-cluster-ns-overview'
  });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, async () => {
  console.log(`HTTP server listening on port ${PORT}`);
  await initDbWithRetry();
});

