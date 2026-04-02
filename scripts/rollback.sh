#!/bin/bash
# scripts/rollback.sh
set -e

APP_NAME="harivelo-app"
NAMESPACE="${1:-production}"
REVISION="${2}"

if [ -z "${REVISION}" ]; then
    echo "Rollback to previous revision..."
    kubectl rollout undo deployment/${APP_NAME} -n ${NAMESPACE}
else
    echo "Rollback to revision ${REVISION}..."
    kubectl rollout undo deployment/${APP_NAME} -n ${NAMESPACE} --to-revision=${REVISION}
fi

kubectl rollout status deployment/${APP_NAME} -n ${NAMESPACE} --timeout=5m

echo "✅ Rollback effectué avec succès !"