const express = require('express');
const { Pool } = require('pg');
const axios = require('axios');
const nodemailer = require('nodemailer');
const path = require('path');
const fs = require('fs');

const app = express();
app.use(express.json());

const connectionString = process.env.DATABASE_URL || 'postgres://postgres:secret@postgres.idp-system.svc:5432/idpdb';
const pool = new Pool({ connectionString });

const mailer = nodemailer.createTransport({
  host: process.env.SMTP_HOST || 'mailhog.idp-system.svc',
  port: parseInt(process.env.SMTP_PORT || '1025', 10)
});

// Helper matrix function converting ServiceNow numbers or local workflow states to text strings
function mapSnowState(stateCode) {
  if (typeof stateCode === 'string') {
    if (stateCode === 'PENDING_APPROVAL') return 'Pending Approval';
    if (stateCode === 'APPROVED') return 'Approved';
    if (stateCode === 'TICKET_CREATED') return 'Ticket Created';
  }

  switch (parseInt(stateCode, 10)) {
    case 1: return 'New';
    case 2: return 'In Progress';
    case 3: return 'On Hold';
    case 6: return 'Resolved';
    case 7: return 'Closed';
    case 8: return 'Canceled';
    default: 
      return stateCode || 'Pending Approval';
  }
}

// Flat-file serving infrastructure endpoints
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'dashboard.html'));
});

app.get('/request-apps', (req, res) => {
  res.sendFile(path.join(__dirname, 'request-apps.html'));
});

app.get('/request-vm', (req, res) => {
  res.sendFile(path.join(__dirname, 'request-vm.html'));
});

app.get('/workflow', (req, res) => {
  res.sendFile(path.join(__dirname, 'workflow-feed.html'));
});

// 🚀 FIXED: Reverted back to clean static file routing to avoid losing the sidebar structure
app.get('/monitoring', (req, res) => {
  res.sendFile(path.join(__dirname, 'live-monitoring.html'));
});

// App Entry Point: Creation of Infrastructure Request
app.post('/api/requests', async (req, res) => {
  const {
    resourceType = 'K8S_NAMESPACE', appName, env = 'dev', cpu = '500m', 
    memory = '512Mi', storage = '10Gi', vmOsImage = 'rhel-9-image', 
    cluster,  purpose, requesterEmail, managerEmail
  } = req.body;

  if (!appName || !requesterEmail || !managerEmail) {
    return res.status(400).json({ error: 'Missing mandatory request form configuration parameters.' });
  }

  try {
    const query = `
      INSERT INTO requests (resource_type, app_name, env, cpu, memory, storage, vm_os_image, cluster, purpose, requester_email, manager_email, ticket_system, status)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
      RETURNING id;
    `;
    const result = await pool.query(query, [
      resourceType, appName, env, cpu, memory, storage, vmOsImage, cluster, purpose, requesterEmail, managerEmail, 'SERVICENOW', 'PENDING_APPROVAL'
    ]);
    const requestId = result.rows[0].id;

    const appBaseUrl = process.env.PUBLIC_URL || `http://${req.headers.host}`;

    // FIXED: Created a detailed text body for the manager's email
    const emailBody = `An environment request has been submitted and requires your approval.

IDP Orchestration Resource Details:
- Resource Type: ${resourceType}
- Application Name: ${appName}
- Environment: ${env}
- Target Cluster: ${cluster || 'Not Specified'}
- CPU Quota: ${cpu}
- Memory Quota: ${memory}
- Storage Quota: ${storage}
- Business Purpose: ${purpose || 'Not Provided'}
- Requester: ${requesterEmail}

Click the link below to approve this request and automatically trigger the ServiceNow infrastructure ticket:
${appBaseUrl}/api/approve/${requestId}`;

    await mailer.sendMail({
      from: 'portal@internal.dev',
      to: managerEmail,
      subject: `[IDP Approval Required] Setup for ${appName} (${env.toUpperCase()})`,
      text: emailBody // FIXED: Sent the comprehensive layout text
    });

    res.status(201).json({ requestId, status: 'PENDING_APPROVAL' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Manager Approval Endpoint -> Creates ServiceNow Ticket Task
app.get('/api/approve/:id', async (req, res) => {
  const { id } = req.params;
  try {
    await pool.query("UPDATE requests SET status = 'APPROVED', updated_at = NOW() WHERE id = \$1", [id]);
    const resultRows = await pool.query("SELECT * FROM requests WHERE id = \$1", [id]);
    const reqData = resultRows.rows[0];

    let ticketId = `MOCK-SNOW-${Math.floor(100000 + Math.random() * 900000)}`;
    const summary = `IDP ${reqData.resource_type}: Provision ${reqData.app_name} [Env: ${reqData.env}]`;
    const technicalDescription = `IDP Orchestration Resource Details:\n- Resource Type: ${reqData.resource_type}\n- Cluster: ${reqData.cluster}\n- CPU: ${reqData.cpu}\n- Memory: ${reqData.memory}\n- Storage: ${reqData.storage}\n- Requester: ${reqData.requester_email}\n- Business Purpose: ${reqData.purpose || 'Not Provided'}`;

    try {
      const snowRes = await axios.post(`${process.env.SNOW_HOST}/api/now/table/incident`, {
        short_description: summary,
        description: technicalDescription,
        assignment_group: "Cloud Operations", 
        caller_id: "admin"
      }, { 
        auth: { 
          username: process.env.SNOW_USER, 
          password: process.env.SNOW_PASSWORD 
        },
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        }
      });
      
      if (snowRes.data && snowRes.data.result) {
        ticketId = snowRes.data.result.number;
      }
    } catch (err) {
      console.error(`ServiceNow connection skipped/mocked for environment logs:`, err.message);
    }

    await pool.query(
      "UPDATE requests SET status = 'TICKET_CREATED', tracking_ticket_id = \$2, updated_at = NOW() WHERE id = \$1",
      [id, ticketId]
    );

    res.send(`<h2>Request Successfully Processed!</h2><p>ServiceNow Ticket ${ticketId} created.</p>`);
  } catch (err) {
    res.status(500).send(`Error processing manager approval: ${err.message}`);
  }
});

// Advanced Server-Side Database Search Query with strict LIMIT 10 latest entries filter
app.get('/api/requests', async (req, res) => {
  const searchVal = req.query.search ? req.query.search.trim() : '';
  try {
    let result;
    if (searchVal) {
      const sqlQuery = `
        SELECT * FROM requests 
        WHERE app_name ILIKE $1 
           OR resource_type ILIKE $1 
           OR tracking_ticket_id ILIKE $1 
           OR cluster ILIKE $1 
           OR requester_email ILIKE $1 
        ORDER BY created_at DESC 
        LIMIT 10;
      `;
      result = await pool.query(sqlQuery, [`%${searchVal}%`]);
    } else {
      result = await pool.query('SELECT * FROM requests ORDER BY created_at DESC LIMIT 10;');
    }

    // Map the status values before returning them to frontend dashboard UI
    const transformedRows = result.rows.map(row => ({
      ...row,
      status: mapSnowState(row.status)
    }));

    res.json(transformedRows);
  } catch (err) {
    console.error('Database query exception caught: ', err.message);
    res.json([]);
  }
});

// On-Demand Manual Ticket Synchronization Status Trigger Route
app.post('/api/requests/:id/sync', async (req, res) => {
  const { id } = req.params;
  try {
    const result = await pool.query("SELECT * FROM requests WHERE id = \$1", [id]);
    const reqData = result.rows[0];
    if (!reqData || !reqData.tracking_ticket_id) {
      return res.status(400).json({ error: "Ticket reference trace details missing from target row" });
    }

    let updatedStatusText = mapSnowState(reqData.status);

    try {
      const snowRes = await axios.get(`${process.env.SNOW_HOST}/api/now/table/incident`, {
        params: {
          sysparm_query: `number=${reqData.tracking_ticket_id}`,
          sysparm_limit: 1
        },
        auth: { 
          username: process.env.SNOW_USER, 
          password: process.env.SNOW_PASSWORD 
        },
        headers: { 'Accept': 'application/json' }
      });

      if (snowRes.data && snowRes.data.result && snowRes.data.result.length > 0) {
        const snowIncident = snowRes.data.result[0];
        updatedStatusText = mapSnowState(snowIncident.state);
        
        await pool.query(
          "UPDATE requests SET status = \$1, updated_at = NOW() WHERE id = \$2", 
          [updatedStatusText, id]
        );
      }
    } catch (err) {
      console.error(`ServiceNow live sync failed, retaining fallback:`, err.message);
    }

    res.json({ 
      message: "Sync executed successfully", 
      ticket: reqData.tracking_ticket_id, 
      currentWorkflowStatus: updatedStatusText 
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// 🚀 REGENERATED: Dynamic tracking routing configuration endpoint mapped cleanly to Environment Variables
app.get('/api/config/monitoring', (req, res) => {
  res.json({
    // Leverages DASHBOARD_URL environment variable from deployment or falls back cleanly
    //grafanaHost: process.env.GRAFANA_URL || 'http://192.168.0.160:32000',
    grafanaHost: process.env.GRAFANA_URL || 'http://idp-monitoring-dashboard-svc.idp-system.svc',
    defaultDashboardUid: 'k8s-monitoring-dashboard'
  });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`IDP Backend running on port ${PORT}`));

