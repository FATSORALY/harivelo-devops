#!/bin/bash
# force-delete-vpc.sh

REGION="eu-west-3"

# Fonction pour supprimer une VPC
delete_vpc() {
  local VPC_ID=$1
  local VPC_NAME=$2
  
  echo "========================================="
  echo "Suppression de la VPC: $VPC_ID ($VPC_NAME)"
  echo "========================================="
  
  # 1. Supprimer les VPC Endpoints
  echo "Suppression des VPC Endpoints..."
  ENDPOINTS=$(aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID" --region $REGION --query "VpcEndpoints[*].VpcEndpointId" --output text)
  for endpoint in $ENDPOINTS; do
    echo "  Suppression de l'endpoint: $endpoint"
    aws ec2 delete-vpc-endpoints --vpc-endpoint-ids $endpoint --region $REGION
  done
  
  # 2. Supprimer les NAT Gateways
  echo "Suppression des NAT Gateways..."
  NATS=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" --region $REGION --query "NatGateways[*].NatGatewayId" --output text)
  for nat in $NATS; do
    echo "  Suppression du NAT Gateway: $nat"
    aws ec2 delete-nat-gateway --nat-gateway-id $nat --region $REGION
  done
  
  # Attendre que les NAT Gateways soient supprimées
  if [ -n "$NATS" ]; then
    echo "  Attente de la suppression des NAT Gateways (30 secondes)..."
    sleep 30
  fi
  
  # 3. Supprimer les Network Interfaces
  echo "Suppression des Network Interfaces..."
  ENIS=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" --region $REGION --query "NetworkInterfaces[*].NetworkInterfaceId" --output text)
  for eni in $ENIS; do
    echo "  Suppression de l'interface: $eni"
    aws ec2 delete-network-interface --network-interface-id $eni --region $REGION 2>/dev/null
  done
  
  # 4. Supprimer les Security Groups (sauf default)
  echo "Suppression des Security Groups..."
  SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --region $REGION --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)
  for sg in $SGS; do
    echo "  Suppression du security group: $sg"
    aws ec2 delete-security-group --group-id $sg --region $REGION 2>/dev/null
  done
  
  # 5. Supprimer les Route Tables (non principales)
  echo "Suppression des Route Tables..."
  RTS=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --region $REGION --query "RouteTables[?Associations[0].Main!=true].RouteTableId" --output text)
  for rt in $RTS; do
    echo "  Suppression de la route table: $rt"
    aws ec2 delete-route-table --route-table-id $rt --region $REGION 2>/dev/null
  done
  
  # 6. Détacher et supprimer les Internet Gateways
  echo "Suppression des Internet Gateways..."
  IGWS=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --region $REGION --query "InternetGateways[*].InternetGatewayId" --output text)
  for igw in $IGWS; do
    echo "  Détachement de l'IGW: $igw"
    aws ec2 detach-internet-gateway --internet-gateway-id $igw --vpc-id $VPC_ID --region $REGION 2>/dev/null
    echo "  Suppression de l'IGW: $igw"
    aws ec2 delete-internet-gateway --internet-gateway-id $igw --region $REGION 2>/dev/null
  done
  
  # 7. Supprimer les Subnets
  echo "Suppression des Subnets..."
  SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --region $REGION --query "Subnets[*].SubnetId" --output text)
  for subnet in $SUBNETS; do
    echo "  Suppression du subnet: $subnet"
    aws ec2 delete-subnet --subnet-id $subnet --region $REGION 2>/dev/null
  done
  
  # 8. Supprimer la VPC
  echo "Suppression de la VPC: $VPC_ID"
  aws ec2 delete-vpc --vpc-id $VPC_ID --region $REGION 2>/dev/null
  
  if [ $? -eq 0 ]; then
    echo "  ✓ VPC supprimée avec succès"
  else
    echo "  ✗ Échec - Vérifiez les dépendances restantes"
  fi
}

# Supprimer chaque VPC
delete_vpc "vpc-0e21249fafc2b895f" "eksctl-devops-dev-cluster"
delete_vpc "vpc-019a0aae3c205dc25" "harivelo-production-vpc"
delete_vpc "vpc-035c29922c9287684" "harivelo-vpc"
delete_vpc "vpc-048d4c66353479c97" "harivelo-vpc"
delete_vpc "vpc-0fcffd3113ccb0e8b" "harivelo-production-vpc"

echo ""
echo "=== Vérification finale ==="
aws ec2 describe-vpcs --region $REGION --query "Vpcs[*].[VpcId,Tags[?Key=='Name'].Value,State]" --output table