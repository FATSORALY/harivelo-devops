#!/bin/bash
# install-monitoring.sh

set -e

echo "🚀 Installation du monitoring léger pour Harivelo"

# 1. Nettoyer
echo "🧹 Nettoyage des anciennes installations..."
helm uninstall prometheus -n monitoring 2>/dev/null || true
helm uninstall monitoring-stack -n monitoring 2>/dev/null || true
kubectl delete namespace monitoring --ignore-not-found

# 2. Attendre
sleep 10

# 3. Installer manuellement
echo "📦 Installation de Prometheus et Grafana..."
kubectl apply -f - << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prometheus
  namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus
rules:
- apiGroups: [""]
  resources: ["nodes", "nodes/metrics", "services", "endpoints", "pods"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get"]
- nonResourceURLs: ["/metrics"]
  verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prometheus
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: prometheus
subjects:
- kind: ServiceAccount
  name: prometheus
  namespace: monitoring
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: monitoring
data:
  prometheus.yml: |
    global:
      scrape_interval: 30s
    scrape_configs:
    - job_name: 'kubernetes-pods'
      kubernetes_sd_configs:
      - role: pod
      relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prometheus
  template:
    metadata:
      labels:
        app: prometheus
    spec:
      serviceAccountName: prometheus
      containers:
      - name: prometheus
        image: prom/prometheus:v2.45.0
        args:
        - "--config.file=/etc/prometheus/prometheus.yml"
        - "--storage.tsdb.path=/prometheus/"
        - "--storage.tsdb.retention.time=3d"
        ports:
        - containerPort: 9090
        resources:
          requests:
            memory: "128Mi"
            cpu: "50m"
          limits:
            memory: "256Mi"
            cpu: "100m"
        volumeMounts:
        - name: config
          mountPath: /etc/prometheus
        - name: storage
          mountPath: /prometheus
      volumes:
      - name: config
        configMap:
          name: prometheus-config
      - name: storage
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  namespace: monitoring
spec:
  selector:
    app: prometheus
  ports:
  - port: 9090
    targetPort: 9090
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: grafana
  template:
    metadata:
      labels:
        app: grafana
    spec:
      containers:
      - name: grafana
        image: grafana/grafana:10.1.0
        ports:
        - containerPort: 3000
        env:
        - name: GF_SECURITY_ADMIN_PASSWORD
          value: "admin123"
        resources:
          requests:
            memory: "64Mi"
            cpu: "20m"
          limits:
            memory: "128Mi"
            cpu: "50m"
        volumeMounts:
        - name: storage
          mountPath: /var/lib/grafana
      volumes:
      - name: storage
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: monitoring
spec:
  selector:
    app: grafana
  ports:
  - port: 80
    targetPort: 3000
EOF

# 4. Attendre que les pods démarrent
echo "⏳ Attente du démarrage des pods..."
sleep 10
kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=60s
kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=60s

# 5. Vérification
echo ""
echo "✅ Installation terminée !"
echo ""
echo "📊 Accès:"
echo "   Prometheus: kubectl port-forward -n monitoring svc/prometheus 9090:9090"
echo "   Grafana: kubectl port-forward -n monitoring svc/grafana 3000:80"
echo ""
echo "   Identifiants Grafana: admin / admin123"
echo ""

# 6. Afficher l'état
kubectl get pods -n monitoring