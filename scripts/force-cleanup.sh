#!/bin/bash
# force-cleanup.sh - Nettoyage forcé de toutes les ressources

REGION="eu-west-3"

echo "=== 1. Suppression des clusters EKS ==="

# Supprimer tous les clusters EKS
for cluster in devops-dev harivelo-prod-v5; do
  echo "Traitement de $cluster..."
  
  # Supprimer les nodegroups
  NODEGROUPS=$(aws eks list-nodegroups --cluster-name $cluster --region $REGION --query "nodegroups" --output text 2>/dev/null)
  for ng in $NODEGROUPS; do
    echo "  Suppression du nodegroup: $ng"
    aws eks delete-nodegroup --cluster-name $cluster --nodegroup-name $ng --region $REGION 2>/dev/null
  done
  
  # Attendre 30 secondes
  sleep 30
  
  # Supprimer le cluster
  echo "  Suppression du cluster: $cluster"
  aws eks delete-cluster --name $cluster --region $REGION 2>/dev/null
done

echo ""
echo "=== 2. Suppression des instances EC2 ==="

# Terminer toutes les instances EC2
INSTANCES=$(aws ec2 describe-instances --region $REGION --query "Reservations[*].Instances[*].InstanceId" --output text)
for instance in $INSTANCES; do
  echo "  Terminaison de l'instance: $instance"
  aws ec2 terminate-instances --instance-ids $instance --region $REGION > /dev/null 2>&1
done

echo ""
echo "=== 3. Suppression des Load Balancers ==="

# Supprimer les load balancers
LBS=$(aws elbv2 describe-load-balancers --region $REGION --query "LoadBalancers[*].LoadBalancerArn" --output text)
for lb in $LBS; do
  echo "  Suppression du load balancer: $lb"
  aws elbv2 delete-load-balancer --load-balancer-arn $lb --region $REGION 2>/dev/null
done

echo ""
echo "=== 4. Suppression des Network Interfaces ==="

# Supprimer les interfaces réseau non attachées
ENIS=$(aws ec2 describe-network-interfaces --region $REGION --query "NetworkInterfaces[?Status=='available'].NetworkInterfaceId" --output text)
for eni in $ENIS; do
  echo "  Suppression de l'interface: $eni"
  aws ec2 delete-network-interface --network-interface-id $eni --region $REGION 2>/dev/null
done

echo ""
echo "=== 5. Suppression des Security Groups ==="

# Liste des VPC à nettoyer
VPCS=$(aws ec2 describe-vpcs --region $REGION --query "Vpcs[?Tags[?Value=='harivelo-vpc'] || Tags[?Value=='harivelo-production-vpc'] || Tags[?contains(Value,'devops')]].VpcId" --output text)

for vpc in $VPCS; do
  echo "Traitement de la VPC: $vpc"
  
  # Supprimer tous les security groups sauf le default
  SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc" --region $REGION --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)
  for sg in $SGS; do
    echo "  Suppression du security group: $sg"
    aws ec2 delete-security-group --group-id $sg --region $REGION 2>/dev/null
  done
done

echo ""
echo "=== 6. Suppression des Route Tables ==="

for vpc in $VPCS; do
  # Supprimer les route tables non principales
  RTS=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc" --region $REGION --query "RouteTables[?Associations[0].Main!=true].RouteTableId" --output text)
  for rt in $RTS; do
    echo "  Suppression de la route table: $rt"
    aws ec2 delete-route-table --route-table-id $rt --region $REGION 2>/dev/null
  done
done

echo ""
echo "=== 7. Suppression des Internet Gateways ==="

for vpc in $VPCS; do
  # Détacher et supprimer les internet gateways
  IGWS=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc" --region $REGION --query "InternetGateways[*].InternetGatewayId" --output text)
  for igw in $IGWS; do
    echo "  Détachement et suppression de l'IGW: $igw"
    aws ec2 detach-internet-gateway --internet-gateway-id $igw --vpc-id $vpc --region $REGION 2>/dev/null
    aws ec2 delete-internet-gateway --internet-gateway-id $igw --region $REGION 2>/dev/null
  done
done

echo ""
echo "=== 8. Suppression des Subnets ==="

for vpc in $VPCS; do
  # Supprimer les subnets
  SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc" --region $REGION --query "Subnets[*].SubnetId" --output text)
  for subnet in $SUBNETS; do
    echo "  Suppression du subnet: $subnet"
    aws ec2 delete-subnet --subnet-id $subnet --region $REGION 2>/dev/null
  done
done

echo ""
echo "=== 9. Suppression des VPC ==="

for vpc in $VPCS; do
  echo "  Suppression de la VPC: $vpc"
  aws ec2 delete-vpc --vpc-id $vpc --region $REGION 2>/dev/null
done

echo ""
echo "=== 10. Suppression des RDS ==="

# Supprimer les instances RDS
RDBS=$(aws rds describe-db-instances --region $REGION --query "DBInstances[*].DBInstanceIdentifier" --output text)
for rds in $RDBS; do
  echo "  Suppression de RDS: $rds"
  aws rds delete-db-instance --db-instance-identifier $rds --skip-final-snapshot --region $REGION 2>/dev/null
done

echo ""
echo "=== Nettoyage terminé ==="