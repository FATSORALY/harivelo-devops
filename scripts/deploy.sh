#!/bin/bash
# scripts/deploy.sh
set -e

APP_NAME="harivelo-app"
NAMESPACE="${1:-production}"
TAG="${2:-latest}"

echo "🚀 Déploiement de ${APP_NAME}:${TAG} dans ${NAMESPACE}"

# Vérifier les prérequis
command -v kubectl >/dev/null 2>&1 || { echo "kubectl n'est pas installé" >&2; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "aws CLI n'est pas installé" >&2; exit 1; }

# Se connecter à ECR
aws ecr get-login-password --region eu-west-3 | \
    kubectl create secret docker-registry regcred \
    --docker-server=123456789012.dkr.ecr.eu-west-3.amazonaws.com \
    --docker-username=AWS \
    --docker-password-stdin \
    --namespace=${NAMESPACE} \
    --dry-run=client -o yaml | kubectl apply -f -

# Déployer
kubectl set image deployment/${APP_NAME} \
    ${APP_NAME}=123456789012.dkr.ecr.eu-west-3.amazonaws.com/${APP_NAME}:${TAG} \
    -n ${NAMESPACE}

# Attendre le déploiement
kubectl rollout status deployment/${APP_NAME} -n ${NAMESPACE} --timeout=5m

# Vérifier les pods
kubectl get pods -n ${NAMESPACE} -l app=${APP_NAME}

echo "✅ Déploiement terminé avec succès !"



