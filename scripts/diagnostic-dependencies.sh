#!/bin/bash
# diagnostic-dependencies.sh

REGION="eu-west-3"

# Liste des VPC
VPCS=(
  "vpc-0e21249fafc2b895f"
  "vpc-019a0aae3c205dc25"
  "vpc-035c29922c9287684"
  "vpc-048d4c66353479c97"
  "vpc-0fcffd3113ccb0e8b"
)

for VPC_ID in "${VPCS[@]}"; do
  echo "========================================="
  echo "VPC: $VPC_ID"
  echo "========================================="
  
  # Récupérer le nom de la VPC
  VPC_NAME=$(aws ec2 describe-vpcs --vpc-ids $VPC_ID --region $REGION --query "Vpcs[0].Tags[?Key=='Name'].Value" --output text)
  echo "Nom: $VPC_NAME"
  
  # 1. Network Interfaces (même celles en cours d'utilisation)
  echo -e "\n--- Network Interfaces ---"
  aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" --region $REGION --query "NetworkInterfaces[*].[NetworkInterfaceId,Status,Description]" --output table
  
  # 2. Security Groups
  echo -e "\n--- Security Groups ---"
  aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --region $REGION --query "SecurityGroups[*].[GroupId,GroupName]" --output table
  
  # 3. Route Tables
  echo -e "\n--- Route Tables ---"
  aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --region $REGION --query "RouteTables[*].[RouteTableId,Associations[0].Main]" --output table
  
  # 4. Subnets
  echo -e "\n--- Subnets ---"
  aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --region $REGION --query "Subnets[*].[SubnetId,CidrBlock]" --output table
  
  # 5. Internet Gateways
  echo -e "\n--- Internet Gateways ---"
  aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --region $REGION --query "InternetGateways[*].[InternetGatewayId]" --output table
  
  # 6. Endpoints (VPC Endpoints) - souvent oubliés
  echo -e "\n--- VPC Endpoints ---"
  aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID" --region $REGION --query "VpcEndpoints[*].[VpcEndpointId,ServiceName,State]" --output table
  
  # 7. NAT Gateways
  echo -e "\n--- NAT Gateways ---"
  aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" --region $REGION --query "NatGateways[*].[NatGatewayId,State]" --output table
  
  echo ""
done