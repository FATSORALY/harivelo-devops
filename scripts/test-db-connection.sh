#!/bin/bash
# test-db-connection.sh

echo "🔍 Test de connexion à la base de données"

# Récupérer les informations
RDS_HOST=$(kubectl get configmap backend-config -n production -o jsonpath='{.data.DB_HOST}')
RDS_USER=$(kubectl get configmap backend-config -n production -o jsonpath='{.data.DB_USER}')
RDS_DB=$(kubectl get configmap backend-config -n production -o jsonpath='{.data.DB_NAME}')
RDS_PORT=$(kubectl get configmap backend-config -n production -o jsonpath='{.data.DB_PORT}')

echo "📡 Informations de connexion:"
echo "   Host: $RDS_HOST"
echo "   Port: $RDS_PORT"
echo "   User: $RDS_USER"
echo "   DB: $RDS_DB"

# Option 1: Tester avec un pod PostgreSQL
echo -e "\n🔧 Test avec pod PostgreSQL temporaire..."
kubectl run test-psql \
  --image=postgres:15 \
  --restart=Never \
  -n production \
  --rm -it \
  --env="PGPASSWORD=VeloAWS123" \
  -- psql -h $RDS_HOST -U $RDS_USER -d $RDS_DB -c "SELECT '✅ Connexion PostgreSQL réussie!' as status, version();"

# Option 2: Tester avec Node.js depuis le backend
echo -e "\n🔧 Test avec Node.js depuis le pod backend..."
kubectl exec deployment/backend -n production -- \
  node -e "
  const { Client } = require('pg');
  const client = new Client({
    host: process.env.DB_HOST,
    port: process.env.DB_PORT,
    database: process.env.DB_NAME,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD
  });
  client.connect()
    .then(() => client.query('SELECT current_database(), current_user, version()'))
    .then(res => {
      console.log('✅ Connexion Node.js réussie!');
      console.log('Database:', res.rows[0].current_database);
      console.log('User:', res.rows[0].current_user);
      console.log('Version:', res.rows[0].version.split(',')[0]);
      client.end();
    })
    .catch(err => {
      console.error('❌ Erreur:', err.message);
      client.end();
      process.exit(1);
    });
  "

# Option 3: Lister les tables de l'application
echo -e "\n📊 Liste des tables dans la base de données..."
kubectl run list-tables \
  --image=postgres:15 \
  --restart=Never \
  -n production \
  --rm -it \
  --env="PGPASSWORD=VeloAWS123" \
  -- psql -h $RDS_HOST -U $RDS_USER -d $RDS_DB -c "\dt"

echo -e "\n✅ Tests terminés!"