#!/bin/bash
# fix-postgres-connection.sh

set -e

echo "🔧 Correction de la connexion PostgreSQL"

# 1. Réinitialiser le mot de passe RDS
echo "1️⃣ Réinitialisation du mot de passe RDS..."
aws rds modify-db-instance \
  --db-instance-identifier harivelo-production-postgres \
  --master-user-password "Harivelo2024StrongPass!" \
  --apply-immediately \
  --region eu-west-3

echo "⏳ Attente de la mise à jour RDS (90 secondes)..."
sleep 90

# 2. Attendre que RDS soit disponible
echo "⏳ Attente que RDS soit disponible..."
aws rds wait db-instance-available \
  --db-instance-identifier harivelo-production-postgres \
  --region eu-west-3

# 3. Mettre à jour le secret
echo "2️⃣ Mise à jour du secret Kubernetes..."
kubectl create secret generic backend-secrets \
  --namespace=production \
  --from-literal=DB_PASSWORD='Harivelo2024StrongPass!' \
  --from-literal=JWT_SECRET='super-secret-jwt-key-2024-harivelo' \
  --dry-run=client -o yaml | kubectl apply -f -

# 4. Tester la connexion SSL
echo "3️⃣ Test de connexion SSL à RDS..."
if kubectl run test-connection \
  --image=postgres:13 \
  -it --rm --restart=Never \
  -n production \
  --env="PGPASSWORD=Harivelo2024StrongPass!" \
  -- psql \
  "sslmode=require host=harivelo-production-postgres.ctm440gqkvel.eu-west-3.rds.amazonaws.com port=5432 dbname=harivelo_prod user=harivelo_admin" \
  -c "SELECT '✅ Connexion réussie!' as status;"; then
  
  echo "✅ Connexion SSL réussie!"
  
  # 5. Mettre à jour la configuration du backend
  echo "4️⃣ Mise à jour de la configuration du backend..."
  kubectl patch configmap backend-config -n production --type merge -p \
    '{"data":{"DB_SSL_MODE":"require","DB_SSL":"true"}}'
  
  # 6. Mettre à jour les variables d'environnement
  kubectl set env deployment/backend -n production \
    DB_SSL_MODE=require \
    DB_SSL=true
  
  # 7. Redémarrer le backend
  echo "5️⃣ Redémarrage du backend..."
  kubectl rollout restart deployment/backend -n production
  kubectl rollout status deployment/backend -n production --timeout=120s
  
  # 8. Vérifier les logs
  echo "6️⃣ Vérification des logs..."
  sleep 10
  kubectl logs deployment/backend -n production --tail=30
  
  echo "✅ Configuration terminée !"
  
else
  echo "❌ Échec de la connexion à RDS"
  echo ""
  echo "Diagnostic manuel:"
  echo "1. Vérifiez que le mot de passe est correct"
  echo "2. Vérifiez que RDS est accessible depuis le VPC"
  echo "3. Vérifiez les règles de sécurité"
  
  # Diagnostic
  echo ""
  echo "=== Diagnostic ==="
  echo "RDS Endpoint: harivelo-production-postgres.ctm440gqkvel.eu-west-3.rds.amazonaws.com"
  echo "RDS Status: $(aws rds describe-db-instances --db-instance-identifier harivelo-production-postgres --query 'DBInstances[0].DBInstanceStatus' --output text --region eu-west-3)"
  echo "RDS Publicly Accessible: $(aws rds describe-db-instances --db-instance-identifier harivelo-production-postgres --query 'DBInstances[0].PubliclyAccessible' --output text --region eu-west-3)"
fi