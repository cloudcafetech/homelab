const express = require('express');
const { KubeConfig, CustomObjectsApi } = require('@kubernetes/client-node');

// 1. Initialize app framework first
const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());
app.use(express.static('/app/src/public')); // Serves index.html and browser.js

// 2. Cache the Kubeconfig file path or load it dynamically to prevent race conditions
const KUBECONFIG_PATH = process.env.KUBECONFIG;

// 3. Helper engine to generate an isolated client instance per request frame
function getClientsForCluster(contextName) {
    console.log(`[Dashboard Backend] Client requested context lookup for: "${contextName}"`);
    
    // Create a local, independent KubeConfig instance to avoid global state mutation issues
    const requestKc = new KubeConfig();
    try {
        if (KUBECONFIG_PATH) {
            requestKc.loadFromFile(KUBECONFIG_PATH);
        } else {
            requestKc.loadFromDefault();
        }

        const availableContexts = requestKc.getContexts().map(ctx => ctx.name);
        
        if (contextName && availableContexts.includes(contextName)) {
            requestKc.setCurrentContext(contextName);
        } else {
            const activeCtx = requestKc.getCurrentContext();
            console.log(`[Dashboard Backend] Context "${contextName}" not found. Falling back to active file context: "${activeCtx}"`);
            requestKc.setCurrentContext(activeCtx);
        }
    } catch (e) {
        console.error("[Dashboard Backend] Warning during context selection switch:", e.message);
        // Attempt a graceful fallback on failure using standard configuration defaults
        try {
            if (KUBECONFIG_PATH) requestKc.loadFromFile(KUBECONFIG_PATH);
            else requestKc.loadFromDefault();
        } catch (innerErr) {
            console.error("[Dashboard Backend] Critical configuration recovery failure:", innerErr.message);
        }
    }
    return { customObjects: requestKc.makeApiClient(CustomObjectsApi) };
}

// --- Express API Routes ---

app.get('/api/clusters', (req, res) => {
    try {
        // Create an ephemeral instance just to scan the context inventory reliably
        const bootKc = new KubeConfig();
        if (KUBECONFIG_PATH) bootKc.loadFromFile(KUBECONFIG_PATH);
        else bootKc.loadFromDefault();
        
        const clusterNames = bootKc.getContexts().map(ctx => ctx.name);
        res.json(clusterNames);
    } catch (error) {
        console.error('[Dashboard Backend] Failed to fetch contexts:', error.message);
        res.status(500).json({ error: 'Failed to extract contexts' });
    }
});

app.get('/api/metrics/nodes', async (req, res) => {
    const { cluster } = req.query;
    if (!cluster) return res.status(400).json({ error: 'Cluster parameter required' });
    try {
        const { customObjects } = getClientsForCluster(cluster);
        
        const response = await customObjects.getClusterCustomObject({
            group: 'metrics.k8s.io',
            version: 'v1beta1',
            plural: 'nodes',
            name: ''
        });
        
        const items = response.items || (response.body && response.body.items) || [];
        res.json(items);
    } catch (error) {
        console.error(`[Dashboard Backend] Failed to fetch node metrics:`, error.message);
        res.status(500).json({ error: error.message, items: [] });
    }
});

app.get('/api/metrics/pods', async (req, res) => {
    const { cluster, namespace } = req.query;
    if (!cluster) return res.status(400).json({ error: 'Cluster parameter required' });
    try {
        const { customObjects } = getClientsForCluster(cluster);
        let response;
        
        if (namespace && namespace !== 'All namespaces' && namespace !== '') {
            response = await customObjects.getNamespacedCustomObject({
                group: 'metrics.k8s.io',
                version: 'v1beta1',
                namespace: namespace,
                plural: 'pods',
                name: ''
            });
        } else {
            response = await customObjects.getClusterCustomObject({
                group: 'metrics.k8s.io',
                version: 'v1beta1',
                plural: 'pods',
                name: ''
            });
        }
        
        const items = response.items || (response.body && response.body.items) || [];
        res.json(items);
    } catch (error) {
        console.error(`[Dashboard Backend] Failed to fetch pod metrics:`, error.message);
        res.status(500).json({ error: error.message, items: [] });
    }
});

app.listen(PORT, () => console.log(`[Dashboard Backend] Server safely listening on port ${PORT}`));

