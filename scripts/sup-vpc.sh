#!/bin/bash
# Supprimer toutes les VPC restantes

REGION="eu-west-3"

# Liste de toutes les VPC à supprimer
VPCS=(
  "vpc-0e21249fafc2b895f"
  "vpc-019a0aae3c205dc25"
  "vpc-035c29922c9287684"
  "vpc-048d4c66353479c97"
  "vpc-0fcffd3113ccb0e8b"
)

for VPC_ID in "${VPCS[@]}"; do
  echo ""
  echo "========================================="
  echo "Suppression de la VPC: $VPC_ID"
  echo "========================================="
  
  # 1. Supprimer les security groups (sauf default)
  echo "Suppression des security groups..."
  SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --region $REGION --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)
  for sg in $SGS; do
    echo "  Suppression du security group: $sg"
    aws ec2 delete-security-group --group-id $sg --region $REGION 2>/dev/null && echo "    ✓ Supprimé" || echo "    ✗ Échec"
  done
  
  # 2. Supprimer les route tables (non principales)
  echo "Suppression des route tables..."
  RTS=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --region $REGION --query "RouteTables[?Associations[0].Main!=true].RouteTableId" --output text)
  for rt in $RTS; do
    echo "  Suppression de la route table: $rt"
    aws ec2 delete-route-table --route-table-id $rt --region $REGION 2>/dev/null && echo "    ✓ Supprimé" || echo "    ✗ Échec"
  done
  
  # 3. Détacher et supprimer les internet gateways
  echo "Suppression des internet gateways..."
  IGWS=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --region $REGION --query "InternetGateways[*].InternetGatewayId" --output text)
  for igw in $IGWS; do
    echo "  Détachement de l'IGW: $igw"
    aws ec2 detach-internet-gateway --internet-gateway-id $igw --vpc-id $VPC_ID --region $REGION 2>/dev/null && echo "    ✓ Détaché" || echo "    ✗ Échec"
    echo "  Suppression de l'IGW: $igw"
    aws ec2 delete-internet-gateway --internet-gateway-id $igw --region $REGION 2>/dev/null && echo "    ✓ Supprimé" || echo "    ✗ Échec"
  done
  
  # 4. Supprimer les subnets
  echo "Suppression des subnets..."
  SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --region $REGION --query "Subnets[*].SubnetId" --output text)
  for subnet in $SUBNETS; do
    echo "  Suppression du subnet: $subnet"
    aws ec2 delete-subnet --subnet-id $subnet --region $REGION 2>/dev/null && echo "    ✓ Supprimé" || echo "    ✗ Échec"
  done
  
  # 5. Supprimer la VPC
  echo "Suppression de la VPC: $VPC_ID"
  aws ec2 delete-vpc --vpc-id $VPC_ID --region $REGION 2>/dev/null && echo "  ✓ VPC supprimée" || echo "  ✗ Échec - vérifiez les dépendances"
  
  echo "========================================="
done

echo ""
echo "=== Vérification finale ==="
aws ec2 describe-vpcs --region $REGION --query "Vpcs[*].[VpcId,Tags[?Key=='Name'].Value,State]" --output table