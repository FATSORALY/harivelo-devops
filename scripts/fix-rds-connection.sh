#!/bin/bash
# fix-rds-connection.sh

set -e

echo "🔧 Correction de la connexion RDS"

# 1. Récupérer les informations
RDS_ENDPOINT="harivelo-production-postgres.ctm440gqkvel.eu-west-3.rds.amazonaws.com"
RDS_SG=$(aws rds describe-db-instances \
  --db-instance-identifier harivelo-production-postgres \
  --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
  --output text \
  --region eu-west-3)

EKS_SG=$(aws eks describe-cluster \
  --name harivelo-prod-v5 \
  --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' \
  --output text \
  --region eu-west-3)

echo "✅ RDS Endpoint: $RDS_ENDPOINT"
echo "✅ RDS Security Group: $RDS_SG"
echo "✅ EKS Security Group: $EKS_SG"

# 2. Ajouter la règle dans RDS pour autoriser EKS
echo "🔐 Configuration des règles de sécurité..."
aws ec2 authorize-security-group-ingress \
  --group-id $RDS_SG \
  --protocol tcp \
  --port 5432 \
  --source-group $EKS_SG \
  --region eu-west-3 2>/dev/null || echo "La règle existe déjà"

# 3. Mettre à jour le ConfigMap
echo "📝 Mise à jour du ConfigMap..."
kubectl patch configmap backend-config -n production --type merge -p \
  "{\"data\":{\"DB_HOST\":\"$RDS_ENDPOINT\"}}"

# 4. Tester la connexion
echo "🧪 Test de connexion à RDS..."
if kubectl run test-connection \
  --image=postgres:13 \
  -it --rm --restart=Never \
  -n production \
  --env="PGPASSWORD=Harivelo2024StrongPass" \
  -- psql \
  -h $RDS_ENDPOINT \
  -U harivelo_admin \
  -d harivelo_prod \
  -c "SELECT '✅ Connexion réussie!' as status;"; then
  
  echo "✅ Connexion RDS réussie!"
  
  # 5. Redémarrer le backend
  echo "🔄 Redémarrage du backend..."
  kubectl rollout restart deployment/backend -n production
  kubectl rollout status deployment/backend -n production --timeout=120s
  
  # 6. Vérifier les logs
  echo "📊 Logs du backend:"
  kubectl logs deployment/backend -n production --tail=30
  
  echo "✅ Application prête!"
  
  # 7. Vérifier le healthcheck
  echo "🏥 Test du healthcheck..."
  kubectl port-forward -n production svc/backend-service 3000:3000 &
  sleep 5
  curl http://localhost:3000/health
  kill %1
  
else
  echo "❌ Échec de la connexion à RDS"
  echo "Vérifiez:"
  echo "  1. Le mot de passe est correct"
  echo "  2. Les security groups autorisent le trafic"
  echo "  3. RDS est en état 'available'"
fi