#!/bin/bash
# fix-grafana-lb.sh

set -e

echo "🔧 Correction du LoadBalancer Grafana..."

# 1. Récupérer l'OIDC provider
OIDC_URL=$(aws eks describe-cluster --name harivelo-prod-v5 --query 'cluster.identity.oidc.issuer' --output text --region eu-west-3 | sed 's/https:\/\///')
echo "OIDC URL: $OIDC_URL"

# 2. Télécharger et créer la politique IAM
curl -o iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.5.0/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerPolicy \
  --policy-document file://iam-policy.json \
  --region eu-west-3 2>/dev/null || echo "Policy exists"

POLICY_ARN=$(aws iam list-policies --query 'Policies[?PolicyName==`AWSLoadBalancerControllerPolicy`].Arn' --output text --region eu-west-3)

# 3. Créer ou mettre à jour le service account
eksctl create iamserviceaccount \
  --cluster=harivelo-prod-v5 \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=$POLICY_ARN \
  --override-existing-serviceaccounts \
  --approve \
  --region eu-west-3

# 4. Redémarrer le controller
echo "🔄 Redémarrage du Load Balancer Controller..."
kubectl rollout restart deployment aws-load-balancer-controller -n kube-system
sleep 10
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=aws-load-balancer-controller -n kube-system --timeout=60s

# 5. Vérifier les logs
echo "📋 Vérification des logs..."
kubectl logs -n kube-system deployment/aws-load-balancer-controller --tail=10

# 6. Recréer le service
echo "🔄 Recréation du service Grafana..."
kubectl delete svc grafana-lb -n monitoring 2>/dev/null || true

cat << 'EOF' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: grafana-lb
  namespace: monitoring
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
spec:
  selector:
    app: grafana
  ports:
  - port: 80
    targetPort: 3000
    protocol: TCP
  type: LoadBalancer
EOF

echo ""
echo "✅ Configuration terminée !"
echo ""
echo "📊 Pour obtenir l'URL du LoadBalancer:"
echo "   kubectl get svc grafana-lb -n monitoring -w"
echo ""
echo "🔐 Accès Grafana: admin / admin123"
echo ""
echo "💡 Alternative (si le LoadBalancer ne fonctionne pas):"
echo "   kubectl port-forward -n monitoring svc/grafana 3000:80"