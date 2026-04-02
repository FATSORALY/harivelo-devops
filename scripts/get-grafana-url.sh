#!/bin/bash
# get-grafana-url.sh

echo "🔍 Recherche de l'URL Grafana..."

# Méthode 1: Via Ingress
INGRESS_HOST=$(kubectl get ingress grafana-ingress -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)

if [ -n "$INGRESS_HOST" ] && [ "$INGRESS_HOST" != "<pending>" ]; then
    echo "✅ Accès via Ingress:"
    echo "   http://$INGRESS_HOST"
    echo "   🔐 admin / admin123"
    exit 0
fi

# Méthode 2: Via Service LoadBalancer
LB_HOST=$(kubectl get svc grafana-public -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)

if [ -n "$LB_HOST" ] && [ "$LB_HOST" != "<pending>" ]; then
    echo "✅ Accès via LoadBalancer:"
    echo "   http://$LB_HOST"
    echo "   🔐 admin / admin123"
    exit 0
fi

# Méthode 3: Créer un port-forward
echo "⏳ Aucun accès externe trouvé, démarrage du port-forward..."
kubectl port-forward -n monitoring svc/grafana 3000:80 > /dev/null 2>&1 &
echo "✅ Accès local: http://localhost:3000"
echo "   🔐 admin / admin123"