#!/bin/bash
# =============================================================================
# nuke-vpcs.sh — Suppression forcée de tous les VPCs non-default et leurs
#                dépendances (ELB, EKS, ENI, SG, RT, IGW, NAT, Subnets...)
# Usage : ./nuke-vpcs.sh [--dry-run]
# =============================================================================

set -euo pipefail

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()     { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()   { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
err()    { echo -e "${RED}[ERR]${RESET}   $*"; }
run()    {
  if $DRY_RUN; then
    echo -e "${YELLOW}[DRY-RUN]${RESET} $*"
  else
    eval "$@" 2>&1 || true
  fi
}

wait_nat_deleted() {
  local nat_id=$1
  log "Attente suppression NAT Gateway $nat_id ..."
  for i in $(seq 1 24); do
    state=$(aws ec2 describe-nat-gateways --nat-gateway-ids "$nat_id" \
      --query "NatGateways[0].State" --output text 2>/dev/null || echo "deleted")
    [[ "$state" == "deleted" || "$state" == "None" ]] && { ok "NAT Gateway $nat_id supprimé"; return 0; }
    echo "  ... état: $state (${i}/24 — attente 10s)"
    sleep 10
  done
  warn "Timeout attente NAT Gateway $nat_id"
}

# =============================================================================
# 1. CLUSTERS EKS
# =============================================================================
delete_eks() {
  log "=== Vérification clusters EKS ==="
  clusters=$(aws eks list-clusters --query "clusters[]" --output text 2>/dev/null || true)
  if [[ -z "$clusters" ]]; then
    ok "Aucun cluster EKS trouvé"
    return
  fi
  for cluster in $clusters; do
    warn "Cluster EKS détecté : $cluster"
    # Supprimer les node groups d'abord
    nodegroups=$(aws eks list-nodegroups --cluster-name "$cluster" \
      --query "nodegroups[]" --output text 2>/dev/null || true)
    for ng in $nodegroups; do
      log "  Suppression node group $ng ..."
      run "aws eks delete-nodegroup --cluster-name $cluster --nodegroup-name $ng"
    done
    if [[ -n "$nodegroups" ]]; then
      log "  Attente suppression node groups (60s) ..."
      sleep 60
    fi
    log "  Suppression cluster EKS $cluster ..."
    run "aws eks delete-cluster --name $cluster"
    log "  Attente suppression cluster (120s) ..."
    $DRY_RUN || sleep 120
  done
}

# =============================================================================
# 2. LOAD BALANCERS (ELB v1 + ALB/NLB v2) dans un VPC
# =============================================================================
delete_elbs() {
  local vpc_id=$1
  log "  Suppression ELB v1 dans $vpc_id ..."
  elbs=$(aws elb describe-load-balancers \
    --query "LoadBalancerDescriptions[?VPCId=='$vpc_id'].LoadBalancerName" \
    --output text 2>/dev/null || true)
  for elb in $elbs; do
    log "    Suppression ELB: $elb"
    run "aws elb delete-load-balancer --load-balancer-name $elb"
  done

  log "  Suppression ALB/NLB v2 dans $vpc_id ..."
  albs=$(aws elbv2 describe-load-balancers \
    --query "LoadBalancers[?VpcId=='$vpc_id'].LoadBalancerArn" \
    --output text 2>/dev/null || true)
  for alb in $albs; do
    log "    Suppression ALB/NLB: $alb"
    run "aws elbv2 delete-load-balancer --load-balancer-arn $alb"
  done

  [[ -n "$elbs$albs" ]] && { log "  Attente suppression LBs (30s) ..."; $DRY_RUN || sleep 30; }
}

# =============================================================================
# 3. NAT GATEWAYS
# =============================================================================
delete_nats() {
  local vpc_id=$1
  nats=$(aws ec2 describe-nat-gateways \
    --filter "Name=vpc-id,Values=$vpc_id" "Name=state,Values=available,pending" \
    --query "NatGateways[*].NatGatewayId" --output text 2>/dev/null || true)
  for nat in $nats; do
    log "  Suppression NAT Gateway: $nat"
    run "aws ec2 delete-nat-gateway --nat-gateway-id $nat"
    $DRY_RUN || wait_nat_deleted "$nat"
  done
}

# =============================================================================
# 4. NETWORK INTERFACES
# =============================================================================
delete_enis() {
  local vpc_id=$1
  enis=$(aws ec2 describe-network-interfaces \
    --filters "Name=vpc-id,Values=$vpc_id" \
    --query "NetworkInterfaces[*].NetworkInterfaceId" --output text 2>/dev/null || true)
  for eni in $enis; do
    status=$(aws ec2 describe-network-interfaces \
      --network-interface-ids "$eni" \
      --query "NetworkInterfaces[0].Status" --output text 2>/dev/null || echo "deleted")
    attach=$(aws ec2 describe-network-interfaces \
      --network-interface-ids "$eni" \
      --query "NetworkInterfaces[0].Attachment.AttachmentId" --output text 2>/dev/null || true)
    if [[ "$attach" != "None" && -n "$attach" ]]; then
      log "  Détachement ENI: $eni (attachment: $attach)"
      run "aws ec2 detach-network-interface --attachment-id $attach --force"
      $DRY_RUN || sleep 5
    fi
    log "  Suppression ENI: $eni (état: $status)"
    run "aws ec2 delete-network-interface --network-interface-id $eni"
  done
}

# =============================================================================
# 5. SECURITY GROUPS (hors default)
# =============================================================================
delete_security_groups() {
  local vpc_id=$1
  sgs=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$vpc_id" \
    --query "SecurityGroups[?GroupName!='default'].GroupId" \
    --output text 2>/dev/null || true)
  for sg in $sgs; do
    log "  Suppression Security Group: $sg"
    # Vider les règles entrantes et sortantes d'abord
    in_rules=$(aws ec2 describe-security-groups --group-ids "$sg" \
      --query "SecurityGroups[0].IpPermissions" --output json 2>/dev/null || echo "[]")
    out_rules=$(aws ec2 describe-security-groups --group-ids "$sg" \
      --query "SecurityGroups[0].IpPermissionsEgress" --output json 2>/dev/null || echo "[]")
    [[ "$in_rules" != "[]" && -n "$in_rules" ]] && \
      run "aws ec2 revoke-security-group-ingress --group-id $sg --ip-permissions '$in_rules'"
    [[ "$out_rules" != "[]" && -n "$out_rules" ]] && \
      run "aws ec2 revoke-security-group-egress --group-id $sg --ip-permissions '$out_rules'"
    run "aws ec2 delete-security-group --group-id $sg"
  done
}

# =============================================================================
# 6. ROUTE TABLES (hors main)
# =============================================================================
delete_route_tables() {
  local vpc_id=$1
  rts=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$vpc_id" \
    --query "RouteTables[?Associations[0].Main!=\`true\`].RouteTableId" \
    --output text 2>/dev/null || true)
  for rt in $rts; do
    # Désassocier d'abord
    assoc_ids=$(aws ec2 describe-route-tables --route-table-ids "$rt" \
      --query "RouteTables[0].Associations[?!Main].RouteTableAssociationId" \
      --output text 2>/dev/null || true)
    for assoc in $assoc_ids; do
      log "  Désassociation route table: $assoc"
      run "aws ec2 disassociate-route-table --association-id $assoc"
    done
    log "  Suppression route table: $rt"
    run "aws ec2 delete-route-table --route-table-id $rt"
  done
}

# =============================================================================
# 7. INTERNET GATEWAYS
# =============================================================================
delete_igws() {
  local vpc_id=$1
  igws=$(aws ec2 describe-internet-gateways \
    --filters "Name=attachment.vpc-id,Values=$vpc_id" \
    --query "InternetGateways[*].InternetGatewayId" --output text 2>/dev/null || true)
  for igw in $igws; do
    log "  Détachement IGW: $igw"
    run "aws ec2 detach-internet-gateway --internet-gateway-id $igw --vpc-id $vpc_id"
    log "  Suppression IGW: $igw"
    run "aws ec2 delete-internet-gateway --internet-gateway-id $igw"
  done
}

# =============================================================================
# 8. VPC ENDPOINTS
# =============================================================================
delete_endpoints() {
  local vpc_id=$1
  endpoints=$(aws ec2 describe-vpc-endpoints \
    --filters "Name=vpc-id,Values=$vpc_id" "Name=vpc-endpoint-state,Values=available,pending" \
    --query "VpcEndpoints[*].VpcEndpointId" --output text 2>/dev/null || true)
  for ep in $endpoints; do
    log "  Suppression VPC Endpoint: $ep"
    run "aws ec2 delete-vpc-endpoints --vpc-endpoint-ids $ep"
  done
}

# =============================================================================
# 9. SUBNETS
# =============================================================================
delete_subnets() {
  local vpc_id=$1
  subnets=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$vpc_id" \
    --query "Subnets[*].SubnetId" --output text 2>/dev/null || true)
  for subnet in $subnets; do
    log "  Suppression subnet: $subnet"
    run "aws ec2 delete-subnet --subnet-id $subnet"
  done
}

# =============================================================================
# MAIN — Boucle sur tous les VPCs non-default
# =============================================================================
main() {
  echo -e "\n${BOLD}=============================================${RESET}"
  echo -e "${BOLD}  SUPPRESSION FORCÉE DE TOUS LES VPCs${RESET}"
  $DRY_RUN && echo -e "  ${YELLOW}MODE DRY-RUN — aucune suppression réelle${RESET}"
  echo -e "${BOLD}=============================================${RESET}\n"

  # Supprimer les clusters EKS en premier (global, pas lié à un VPC spécifique)
  delete_eks

  # Récupérer tous les VPCs non-default
  vpcs=$(aws ec2 describe-vpcs \
    --filters "Name=isDefault,Values=false" \
    --query "Vpcs[*].VpcId" --output text 2>/dev/null)

  if [[ -z "$vpcs" ]]; then
    ok "Aucun VPC non-default trouvé. Rien à supprimer."
    exit 0
  fi

  for vpc_id in $vpcs; do
    name=$(aws ec2 describe-vpcs --vpc-ids "$vpc_id" \
      --query "Vpcs[0].Tags[?Key=='Name'].Value | [0]" --output text 2>/dev/null || echo "sans-nom")
    echo -e "\n${BOLD}=============================================${RESET}"
    echo -e "${BOLD}  VPC: $vpc_id  ($name)${RESET}"
    echo -e "${BOLD}=============================================${RESET}"

    delete_elbs         "$vpc_id"
    delete_nats         "$vpc_id"
    delete_endpoints    "$vpc_id"
    delete_enis         "$vpc_id"
    delete_security_groups "$vpc_id"
    delete_route_tables "$vpc_id"
    delete_igws         "$vpc_id"
    delete_subnets      "$vpc_id"

    log "  Suppression du VPC: $vpc_id ..."
    if $DRY_RUN; then
      run "aws ec2 delete-vpc --vpc-id $vpc_id"
    else
      if aws ec2 delete-vpc --vpc-id "$vpc_id" 2>/dev/null; then
        ok "VPC $vpc_id supprimé ✓"
      else
        err "VPC $vpc_id — échec. Dépendances résiduelles :"
        aws ec2 describe-network-interfaces \
          --filters "Name=vpc-id,Values=$vpc_id" \
          --query "NetworkInterfaces[*].[NetworkInterfaceId,Status,Description]" \
          --output table 2>/dev/null || true
      fi
    fi
  done

  echo -e "\n${BOLD}=== VÉRIFICATION FINALE ===${RESET}"
  remaining=$(aws ec2 describe-vpcs \
    --filters "Name=isDefault,Values=false" \
    --query "Vpcs[*].[VpcId, Tags[?Key=='Name'].Value|[0], State]" \
    --output table 2>/dev/null)
  if [[ -z "$remaining" || "$remaining" == *"None"* ]]; then
    ok "Tous les VPCs non-default ont été supprimés ✓"
  else
    warn "VPCs restants :"
    echo "$remaining"
  fi
}

main