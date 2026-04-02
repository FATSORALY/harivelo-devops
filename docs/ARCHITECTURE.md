# Architecture Technique - Harivelo

## Infrastructure AWS
- **Région**: eu-west-3 (Paris)
- **Orchestration**: Kubernetes EKS v1.30
- **Base de données**: PostgreSQL 15 sur RDS
- **Stockage**: S3 pour les assets
- **Conteneurs**: ECR pour les images Docker

## Services Déployés
| Service | Réplicas | Resources | Endpoint |
|---------|----------|-----------|----------|
| Backend API | 1 | 256Mi RAM, 200m CPU | backend-service:3000 |
| Frontend | 1 | 128Mi RAM, 100m CPU | nginx-service:80 |
| Nginx Proxy | 1 | 64Mi RAM, 50m CPU | nginx-service:80 |

## URLs (à configurer)
- **Production**: https://app.harivelo.com (à configurer avec DNS)
- **API Health**: https://app.harivelo.com/health
- **Grafana**: https://monitoring.harivelo.com
- **Jenkins**: https://ci.harivelo.com

## Équipe Support
- **DevOps**: [Votre nom] - [votre email]
- **On-call**: Disponible 24/7 pour incidents critiques
