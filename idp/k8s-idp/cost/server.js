const express = require('express');
const axios = require('axios');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

const PUBLIC_DIR = '/app/src/public';
app.use(express.static(PUBLIC_DIR));
app.use(express.json());

app.use((req, res, next) => {
  console.log(`[ROUTE TRANSACTION] -> Method: ${req.method} | Path: ${req.url}`);
  next();
});

function discoverClusters() {
  const clustersMap = {};
  Object.keys(process.env).forEach(key => {
    if (key.includes('CLUSTER_')) {
      const match = key.match(/CLUSTER_(?:R_)?(\d+)_(NAME|URL)/);
      if (match) {
        const id = match[1];
        const type = match[2].toLowerCase(); // "name" or "url"
        if (!clustersMap[id]) clustersMap[id] = {};
        clustersMap[id][type] = process.env[key];
      }
    }
  });
  return Object.values(clustersMap).filter(c => c.name && c.url);
}

app.get('/', (req, res) => {
  res.sendFile(path.join(PUBLIC_DIR, 'index.html'));
});

app.get('/api/costs', async (req, res) => {
  const days = req.query.days || '30';
  const targetCluster = req.query.cluster;
  const targetNamespace = req.query.namespace;
  const aggregateBy = req.query.aggregate || 'namespace';
  
  // Format window param as required by OpenCost allocation timeline formats
  const windowParam = `${days}d`;
  const aggregatedData = [];
  let systemIdleCost = 0;
  
  const activeClusters = discoverClusters();
  console.log(`[API ENGINE] Syncing data matrix over window: ${windowParam} for ${activeClusters.length} clusters.`);

  for (const cluster of activeClusters) {
    if (targetCluster && targetCluster !== cluster.name) continue;

    // Point exactly to your verified layout pathway endpoint
    const targetUrl = `${cluster.url.replace(/\/$/, '')}/allocation`;
    console.log(` -> Reaching cluster [${cluster.name}] via URL: ${targetUrl}`);

    try {
      const response = await axios.get(targetUrl, {
        params: { window: windowParam, aggregate: aggregateBy },
        timeout: 10000 
      });

      // OpenCost returns layout wrap array directly under response data
      const allocations = response.data?.data || [];
      console.log(` -> [HTTP SUCCESS] Core cost matrix pulled from ${cluster.name}, processing items...`);
      
      const recordsArray = Array.isArray(allocations) ? allocations : [allocations];
      
      recordsArray.forEach(timeWindow => {
        if (!timeWindow) return;
        
        // Loop through keys (e.g., namespace names like "cdi", "kube-system", etc.)
        for (const [objName, metrics] of Object.entries(timeWindow)) {
          if (!metrics) continue;
          if (targetNamespace && aggregateBy === 'namespace' && targetNamespace !== objName) continue;
          
          if (objName === '__idle__' || objName === '__unallocated__') {
            systemIdleCost += metrics.totalCost || 0;
            continue;
          }

          // OpenCost fields compute storage components using these precise mapping definitions
          aggregatedData.push({
            cluster: cluster.name,
            resourceObject: objName,
            cpuCost: metrics.cpuCost || 0,
            ramCost: metrics.ramCost || 0,
            storageCost: metrics.pvCost || metrics.storageCost || 0,
            totalCost: metrics.totalCost || 0
          });
        }
      });
    } catch (error) {
      console.error(` -> [HTTP FAILURE] Connection failed on cluster [${cluster.name}]: ${error.message}`);
    }
  }

  console.log(` [RESPONSE COMPLETE] Dispatching ${aggregatedData.length} records back to client dashboard browser.`);
  res.json({ 
    clusters: activeClusters.map(c => c.name), 
    idleCost: systemIdleCost, 
    data: aggregatedData 
  });
});

app.listen(PORT, () => console.log(`[STARTUP] OpenCost Aggregator Server successfully initialized on container port ${PORT}`));

