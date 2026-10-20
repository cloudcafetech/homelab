let currentCluster = '';
let currentNamespace = 'All namespaces';

const clusterSelect = document.getElementById('clusterSelect');
const namespaceSelect = document.getElementById('namespaceSelect');
const refreshBtn = document.getElementById('refreshBtn');
const nodeTableBody = document.getElementById('nodeTableBody');
const podTableBody = document.getElementById('podTableBody');

function parseCpu(c) { 
    if (!c) return 0;
    return c.endsWith('n') ? Math.round(parseInt(c)/1000000) : parseInt(c) || 0; 
}
function parseMemory(m) { 
    if (!m) return 0;
    return m.endsWith('Ki') ? Math.round(parseInt(m)/1024) : parseInt(m) || 0; 
}

async function loadClusters() {
    try {
        console.log('[Dashboard Frontend] Fetching configured contexts...');
        const res = await fetch('/api/clusters');
        const clusters = await res.json();
        
        if (!clusters || clusters.length === 0) {
            clusterSelect.innerHTML = '<option value="">-- No Clusters Found --</option>';
            return;
        }

        clusterSelect.innerHTML = '';
        clusters.forEach(c => { 
            const opt = document.createElement('option');
            opt.value = c;
            opt.textContent = c;
            clusterSelect.appendChild(opt);
        });

        // Fix: Auto-selects the first string value correctly
        currentCluster = clusters[0];
        clusterSelect.value = currentCluster;
        console.log(`[Dashboard Frontend] Selected active context target: "${currentCluster}"`);
        
        fetchMetrics();
    } catch (err) { 
        console.error('[Dashboard Frontend] Failed to load cluster list:', err);
        clusterSelect.innerHTML = '<option value="">-- Error loading clusters --</option>';
    }
}

async function fetchMetrics() {
    if (!currentCluster) return;
    refreshBtn.textContent = 'Loading...';
    refreshBtn.disabled = true;
    try {
        console.log(`[Dashboard Frontend] Querying metrics for cluster: "${currentCluster}"`);
        const nRes = await fetch(`/api/metrics/nodes?cluster=${encodeURIComponent(currentCluster)}`);
        const nodes = await nRes.json();
        
        const pRes = await fetch(`/api/metrics/pods?cluster=${encodeURIComponent(currentCluster)}&namespace=${encodeURIComponent(currentNamespace)}`);
        const pods = await pRes.json();
        
        render(nodes, pods);
    } catch (err) { 
        console.error('[Dashboard Frontend] Metrics aggregation failed:', err); 
    } finally {
        refreshBtn.textContent = '🔄 Refresh';
        refreshBtn.disabled = false;
    }
}

function render(nodes, pods) {
    // 1. Populate Namespace Dropdown if scoped globally
    if (currentNamespace === 'All namespaces') {
        namespaceSelect.innerHTML = '<option value="All namespaces">All namespaces</option>';
        if (pods && pods.length > 0) {
            const nsSet = new Set(pods.map(p => p.metadata.namespace));
            nsSet.forEach(ns => { 
                const opt = document.createElement('option');
                opt.value = ns;
                opt.textContent = ns;
                namespaceSelect.appendChild(opt);
            });
        }
    }

    // 2. Process KPI metrics
    document.getElementById('kpiNodes').textContent = nodes ? nodes.length : '0';
    document.getElementById('kpiPods').textContent = pods ? pods.length : '0';
    
    // 3. Render Nodes Matrix Table
    nodeTableBody.innerHTML = '';
    if (!nodes || nodes.length === 0) {
        nodeTableBody.innerHTML = '<tr><td colspan="3" style="text-align:center;color:#6b7280;padding:20px;">No metrics reported from nodes.</td></tr>';
    } else {
        nodes.forEach(n => {
            const tr = document.createElement('tr');
            tr.innerHTML = `<td><b>${n.metadata.name}</b></td><td>${parseCpu(n.usage?.cpu)}m</td><td>${parseMemory(n.usage?.memory)} MiB</td>`;
            nodeTableBody.appendChild(tr);
        });
    }

    // 4. Render Pods Matrix Table
    let tCpu = 0, tMem = 0;
    podTableBody.innerHTML = '';
    
    if (!pods || pods.length === 0) {
        podTableBody.innerHTML = '<tr><td colspan="4" style="text-align:center;color:#6b7280;padding:20px;">No pods running or reporting resource metrics.</td></tr>';
    } else {
        pods.forEach(p => {
            let pCpu = 0, pMem = 0;
            p.containers?.forEach(c => { 
                pCpu += parseCpu(c.usage?.cpu); 
                pMem += parseMemory(c.usage?.memory); 
            });
            tCpu += pCpu; tMem += pMem;
            
            const tr = document.createElement('tr');
            tr.innerHTML = `<td>${p.metadata.name}</td><td>${p.metadata.namespace}</td><td>${pCpu}m</td><td>${pMem} MiB</td>`;
            podTableBody.appendChild(tr);
        });
    }
    
    document.getElementById('kpiCpu').textContent = tCpu + 'm';
    document.getElementById('kpiMemory').textContent = tMem + ' MiB';
}

clusterSelect.addEventListener('change', (e) => { 
    currentCluster = e.target.value; 
    currentNamespace = 'All namespaces'; 
    fetchMetrics(); 
});
namespaceSelect.addEventListener('change', (e) => { 
    currentNamespace = e.target.value; 
    fetchMetrics(); 
});
refreshBtn.addEventListener('click', fetchMetrics);

// Trigger on boot
loadClusters();

