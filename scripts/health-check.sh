#!/bin/bash
# scripts/health-check.sh
set -e

ENDPOINT="${1:-https://app.harivelo.com/health}"
MAX_RETRIES=5
RETRY_DELAY=10

echo "🔍 Vérification de la santé de l'application..."

for i in $(seq 1 ${MAX_RETRIES}); do
    if curl -f -s -o /dev/null ${ENDPOINT}; then
        echo "✅ Health check passed!"
        
        # Vérifier les métriques
        echo "📊 Métriques de l'application:"
        curl -s ${ENDPOINT/health/metrics} | grep -E "http_requests_total|http_request_duration"
        
        exit 0
    else
        echo "⚠️  Attempt ${i}/${MAX_RETRIES}: Health check failed"
        if [ ${i} -lt ${MAX_RETRIES} ]; then
            sleep ${RETRY_DELAY}
        fi
    fi
done

echo "❌ Health check failed after ${MAX_RETRIES} attempts"
exit 1