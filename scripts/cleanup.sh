#!/bin/bash
# cleanup.sh - Nettoyage complet des ressources AWS

REGION="eu-west-3"

echo "=== Nettoyage des clusters EKS ==="

# Supprimer les nodegroups
for cluster in harivelo-prod-v5 devops-dev; do
  echo "Traitement du cluster: $cluster"
  
  # Lister les nodegroups
  NODEGROUPS=$(aws eks list-nodegroups --cluster-name $cluster --region $REGION --query "nodegroups" --output text)
  
  for ng in $NODEGROUPS; do
    echo "  Suppression du nodegroup: $ng"
    aws eks delete-nodegroup --cluster-name $cluster --nodegroup-name $ng --region $REGION
  done
  
  # Attendre la suppression des nodegroups
  while true; do
    NGS=$(aws eks list-nodegroups --cluster-name $cluster --region $REGION --query "nodegroups" --output text)
    if [ -z "$NGS" ]; then
      echo "  Tous les nodegroups supprimés"
      break
    else
      echo "  En attente de suppression des nodegroups..."
      sleep 30
    fi
  done
  
  # Supprimer le cluster
  echo "  Suppression du cluster: $cluster"
  aws eks delete-cluster --name $cluster --region $REGION
done

echo "=== Nettoyage des instances EC2 orphelines ==="
INSTANCES=$(aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running,stopped" \
  --region $REGION \
  --query "Reservations[*].Instances[?contains(Tags[?Key=='eks:cluster-name'].Value, 'harivelo') || contains(Tags[?Key=='eks:cluster-name'].Value, 'devops')].[InstanceId]" \
  --output text)

for instance in $INSTANCES; do
  echo "  Terminaison de l'instance: $instance"
  aws ec2 terminate-instances --instance-ids $instance --region $REGION
done

echo "=== Nettoyage des VPC ==="
VPCS=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=harivelo-vpc,devops-vpc" \
  --region $REGION \
  --query "Vpcs[*].VpcId" \
  --output text)

for vpc in $VPCS; do
  echo "  Suppression de la VPC: $vpc"
  
  # Supprimer les subnets
  SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc" --region $REGION --query "Subnets[*].SubnetId" --output text)
  for subnet in $SUBNETS; do
    aws ec2 delete-subnet --subnet-id $subnet --region $REGION
  done
  
  # Supprimer les security groups (sauf le default)
  SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc" --region $REGION --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)
  for sg in $SGS; do
    aws ec2 delete-security-group --group-id $sg --region $REGION
  done
  
  # Supprimer les route tables (sauf la main)
  RTS=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc" --region $REGION --query "RouteTables[?Associations[0].Main!=true].RouteTableId" --output text)
  for rt in $RTS; do
    aws ec2 delete-route-table --route-table-id $rt --region $REGION
  done
  
  # Supprimer l'internet gateway
  IGWS=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc" --region $REGION --query "InternetGateways[*].InternetGatewayId" --output text)
  for igw in $IGWS; do
    aws ec2 detach-internet-gateway --internet-gateway-id $igw --vpc-id $vpc --region $REGION
    aws ec2 delete-internet-gateway --internet-gateway-id $igw --region $REGION
  done
  
  # Supprimer la VPC
  aws ec2 delete-vpc --vpc-id $vpc --region $REGION
done

echo "=== Nettoyage terminé ==="