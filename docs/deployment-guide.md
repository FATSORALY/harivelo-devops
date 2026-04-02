# docs/deployment-guide.md

# Guide de déploiement

## Prérequis
- AWS CLI configuré
- kubectl installé
- Terraform >= 1.0
- Accès au cluster EKS

## Déploiement initial

1. **Créer l'infrastructure**
```bash
cd infra/terraform
terraform init
terraform plan -var-file="prod.tfvars"
terraform apply -var-file="prod.tfvars"