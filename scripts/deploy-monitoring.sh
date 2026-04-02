#!/bin/bash
set -e

echo "🚀 Déploiement du monitoring complet"

# 1. Appliquer les configurations
kubectl apply -f monitoring/grafana-dashboards.yaml
kubectl apply -f monitoring/grafana-alerts.yaml
kubectl apply -f monitoring/service-monitors.yaml
kubectl apply -f monitoring/prometheus-rules.yaml

# 2. Configurer les datasources Grafana
cat << 'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasources
  namespace: monitoring
  labels:
    grafana_datasource: "1"
data:
  prometheus.yaml: |
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      access: proxy
      url: http://prometheus.monitoring:9090
      isDefault: true
      editable: true
EOF

# 3. Restart Grafana pour charger les nouveaux dashboards
kubectl rollout restart deployment/grafana -n monitoring

# 4. Attendre que tout soit prêt
kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=60s

echo "✅ Monitoring déployé avec succès !"
echo ""
echo "📊 Accès:"
echo "   Grafana: kubectl port-forward -n monitoring svc/grafana 3000:80"
echo "   Prometheus: kubectl port-forward -n monitoring svc/prometheus 9090:9090"
echo ""
echo "🔐 Identifiants Grafana: admin / admin123"
