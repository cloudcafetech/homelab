const express = require('express');
const { KubeConfig, CustomObjectsApi } = require('@kubernetes/client-node');

// 1. Initialize app framework first
const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());
app.use(express.static('/app/src/public')); // Serves index.html and browser.js

// 2. Initialize KubeConfig parsing patterns
const kc = new KubeConfig();
if (process.env.KUBECONFIG) {
    kc.loadFromFile(process.env.KUBECONFIG);
} else {
    kc.loadFromDefault();
}

// 3. Helper engine to swap or fallback cluster context frames securely
function getClientsForCluster(contextName) {
    console.log(`[Dashboard Backend] Client requested context lookup for: "${contextName}"`);
    try {
        const availableContexts = kc.getContexts().map(ctx => ctx.name);
        
        if (contextName && availableContexts.includes(contextName)) {
            kc.setCurrentContext(contextName);
        } else {
            const activeCtx = kc.getCurrentContext();
            console.log(`[Dashboard Backend] Context "${contextName}" not found. Falling back to active file context: "${activeCtx}"`);
            kc.setCurrentContext(activeCtx);
        }
    } catch (e) {
        console.error("[Dashboard Backend] Warning during context selection switch:", e.message);
        kc.setCurrentContext(kc.getCurrentContext());
    }
    return { customObjects: kc.makeApiClient(CustomObjectsApi) };
}

// --- Express API Routes ---

app.get('/api/clusters', (req, res) => {
    try {
        const clusterNames = kc.getContexts().map(ctx => ctx.name);
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
        
        // Fix: Checks response.items directly first, then falls back to response.body.items
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
        
        // Fix: Checks response.items directly first, then falls back to response.body.items
        const items = response.items || (response.body && response.body.items) || [];
        res.json(items);
    } catch (error) {
        console.error(`[Dashboard Backend] Failed to fetch pod metrics:`, error.message);
        res.status(500).json({ error: error.message, items: [] });
    }
});

app.listen(PORT, () => console.log(`[Dashboard Backend] Server safely listening on port ${PORT}`));

