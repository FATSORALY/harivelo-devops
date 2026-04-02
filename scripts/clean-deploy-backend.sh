#!/bin/bash
# clean-deploy-backend.sh

set -e

echo "🧹 Nettoyage complet du backend..."

# 1. Supprimer tout
kubectl delete deployment backend -n production 2>/dev/null || true
kubectl delete pods -n production -l component=backend --force --grace-period=0 2>/dev/null || true

# 2. Attendre
echo "⏳ Attente de la suppression..."
sleep 10

# 3. Vérifier que ConfigMap et Secret existent
echo "📝 Vérification des configurations..."
kubectl get configmap backend-config -n production > /dev/null || echo "⚠️ ConfigMap manquant"
kubectl get secret backend-secrets -n production > /dev/null || echo "⚠️ Secret manquant"

# 4. Recréer le déploiement
echo "🚀 Création du nouveau déploiement..."
kubectl apply -f - << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: production
spec:
  replicas: 1
  selector:
    matchLabels:
      app: harivelo
      component: backend
  template:
    metadata:
      labels:
        app: harivelo
        component: backend
    spec:
      initContainers:
      - name: create-uploads-dir
        image: busybox:latest
        command:
        - sh
        - -c
        - |
          echo "Création des dossiers..."
          mkdir -p /app/uploads/projects
          mkdir -p /app/uploads/users
          mkdir -p /app/uploads/tenders
          mkdir -p /app/uploads/calculations
          mkdir -p /app/uploads/images
          mkdir -p /app/src/uploads/projects
          mkdir -p /app/src/uploads/users
          mkdir -p /app/src/uploads/tenders
          mkdir -p /app/src/uploads/calculations
          mkdir -p /app/src/uploads/images
          chmod -R 777 /app/uploads /app/src/uploads
          echo "✅ Dossiers créés"
        volumeMounts:
        - name: uploads
          mountPath: /app/uploads
        - name: src-uploads
          mountPath: /app/src/uploads
      containers:
      - name: backend
        image: 240676008744.dkr.ecr.eu-west-3.amazonaws.com/harivelo-app-backend:latest
        imagePullPolicy: Always
        ports:
        - containerPort: 3000
        env:
        - name: NODE_ENV
          value: "production"
        - name: PORT
          value: "3000"
        - name: DB_HOST
          valueFrom:
            configMapKeyRef:
              name: backend-config
              key: DB_HOST
        - name: DB_PORT
          valueFrom:
            configMapKeyRef:
              name: backend-config
              key: DB_PORT
        - name: DB_NAME
          valueFrom:
            configMapKeyRef:
              name: backend-config
              key: DB_NAME
        - name: DB_USER
          valueFrom:
            configMapKeyRef:
              name: backend-config
              key: DB_USER
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: backend-secrets
              key: DB_PASSWORD
        - name: DB_SSL
          value: "true"
        - name: DB_SSL_MODE
          value: "require"
        volumeMounts:
        - name: uploads
          mountPath: /app/uploads
        - name: src-uploads
          mountPath: /app/src/uploads
      volumes:
      - name: uploads
        emptyDir: {}
      - name: src-uploads
        emptyDir: {}
      imagePullSecrets:
      - name: regcred
EOF

# 5. Attendre le démarrage
echo "⏳ Attente du démarrage..."
sleep 15

# 6. Vérifier
echo "📊 État des pods:"
kubectl get pods -n production -l component=backend

# 7. Afficher les logs
echo "📝 Logs du backend:"
kubectl logs -n production -l component=backend --tail=30

echo "✅ Déploiement terminé !"