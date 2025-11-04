#!/bin/bash

# Medical Robotics Data Platform - Pre-Deployment Check
# Validates no conflicting resources exist before deployment

set -e

ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-medrobotics}"
AWS_REGION="${AWS_REGION:-us-east-1}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }
check() { echo -e "${CYAN}→${NC} $1"; }
header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

header "Pre-Deployment Validation"
echo ""
info "Environment: $ENVIRONMENT_NAME"
info "Region: $AWS_REGION"
echo ""

ISSUES_FOUND=0
WARNINGS_FOUND=0

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
if [ $? -ne 0 ]; then
    error "Cannot get AWS account ID. Check your AWS credentials."
    exit 1
fi
info "Account ID: $ACCOUNT_ID"
echo ""

# ==========================================
# Check 1: CloudFormation Stacks
# ==========================================
header "1. Checking CloudFormation Stacks"
echo ""

CONFLICTING_STACKS=()
STACK_NAMES=(
    "${ENVIRONMENT_NAME}-network"
    "${ENVIRONMENT_NAME}-security-groups"
    "${ENVIRONMENT_NAME}-s3"
    "${ENVIRONMENT_NAME}-iam"
    "${ENVIRONMENT_NAME}-rds"
    "${ENVIRONMENT_NAME}-bastion"
    "${ENVIRONMENT_NAME}-ecs-cluster"
    "${ENVIRONMENT_NAME}-alb"
    "${ENVIRONMENT_NAME}-ecs-tasks"
    "${ENVIRONMENT_NAME}-ecs-services"
    "${ENVIRONMENT_NAME}-redshift"
    "${ENVIRONMENT_NAME}-etl-lambda"
    "${ENVIRONMENT_NAME}-step-functions"
    "${ENVIRONMENT_NAME}-eks"
)

for STACK in "${STACK_NAMES[@]}"; do
    check "Checking stack: $STACK"

    if aws cloudformation describe-stacks \
        --stack-name "$STACK" \
        --region "$AWS_REGION" &> /dev/null; then

        STATUS=$(aws cloudformation describe-stacks \
            --stack-name "$STACK" \
            --region "$AWS_REGION" \
            --query 'Stacks[0].StackStatus' \
            --output text)

        if [[ "$STATUS" == "DELETE_IN_PROGRESS" ]] || [[ "$STATUS" == "DELETE_COMPLETE" ]]; then
            warn "  Stack exists but is being deleted: $STATUS"
            WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
        else
            error "  Stack already exists: $STATUS"
            CONFLICTING_STACKS+=("$STACK")
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        fi
    else
        info "  Stack available"
    fi
done
echo ""

# ==========================================
# Check 2: S3 Buckets
# ==========================================
header "2. Checking S3 Buckets"
echo ""

CONFLICTING_BUCKETS=()
BUCKET_NAMES=(
    "${ENVIRONMENT_NAME}-raw-data-${ACCOUNT_ID}"
    "${ENVIRONMENT_NAME}-processed-data-${ACCOUNT_ID}"
    "${ENVIRONMENT_NAME}-analytics-${ACCOUNT_ID}"
    "${ENVIRONMENT_NAME}-logs-${ACCOUNT_ID}"
    "${ENVIRONMENT_NAME}-backups-${ACCOUNT_ID}"
)

for BUCKET in "${BUCKET_NAMES[@]}"; do
    check "Checking bucket: $BUCKET"

    if aws s3 ls "s3://${BUCKET}" --region "$AWS_REGION" &> /dev/null; then
        # Get object count
        OBJECT_COUNT=$(aws s3 ls "s3://${BUCKET}" --recursive --region "$AWS_REGION" 2>/dev/null | wc -l)

        error "  Bucket already exists ($OBJECT_COUNT objects)"
        CONFLICTING_BUCKETS+=("$BUCKET")
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    else
        info "  Bucket available"
    fi
done
echo ""

# ==========================================
# Check 3: ECR Repositories
# ==========================================
header "3. Checking ECR Repositories"
echo ""

CONFLICTING_REPOS=()
REPO_NAMES=(
    "${ENVIRONMENT_NAME}-data-ingestion"
    "${ENVIRONMENT_NAME}-api-service"
)

for REPO in "${REPO_NAMES[@]}"; do
    check "Checking repository: $REPO"

    if aws ecr describe-repositories \
        --repository-names "$REPO" \
        --region "$AWS_REGION" &> /dev/null; then

        IMAGE_COUNT=$(aws ecr list-images \
            --repository-name "$REPO" \
            --region "$AWS_REGION" \
            --query 'length(imageIds)' \
            --output text 2>/dev/null || echo "0")

        warn "  Repository exists ($IMAGE_COUNT images)"
        CONFLICTING_REPOS+=("$REPO")
        WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
    else
        info "  Repository available"
    fi
done
echo ""

# ==========================================
# Check 4: RDS Instances
# ==========================================
header "4. Checking RDS Instances"
echo ""

check "Checking for RDS instances with identifier: ${ENVIRONMENT_NAME}-*"

RDS_INSTANCES=$(aws rds describe-db-instances \
    --region "$AWS_REGION" \
    --query "DBInstances[?contains(DBInstanceIdentifier, '${ENVIRONMENT_NAME}')].{ID:DBInstanceIdentifier,Status:DBInstanceStatus}" \
    --output text 2>/dev/null || true)

if [ -z "$RDS_INSTANCES" ]; then
    info "No conflicting RDS instances found"
else
    error "Found existing RDS instances:"
    echo "$RDS_INSTANCES" | while read -r line; do
        error "  $line"
    done
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi
echo ""

# ==========================================
# Check 5: Redshift Clusters
# ==========================================
header "5. Checking Redshift Clusters"
echo ""

check "Checking for Redshift clusters with identifier: ${ENVIRONMENT_NAME}-*"

REDSHIFT_CLUSTERS=$(aws redshift describe-clusters \
    --region "$AWS_REGION" \
    --query "Clusters[?contains(ClusterIdentifier, '${ENVIRONMENT_NAME}')].{ID:ClusterIdentifier,Status:ClusterStatus}" \
    --output text 2>/dev/null || true)

if [ -z "$REDSHIFT_CLUSTERS" ]; then
    info "No conflicting Redshift clusters found"
else
    error "Found existing Redshift clusters:"
    echo "$REDSHIFT_CLUSTERS" | while read -r line; do
        error "  $line"
    done
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi
echo ""

# ==========================================
# Check 6: VPCs
# ==========================================
header "6. Checking VPCs"
echo ""

check "Checking for VPCs with tag: Name=${ENVIRONMENT_NAME}-*"

VPCS=$(aws ec2 describe-vpcs \
    --region "$AWS_REGION" \
    --filters "Name=tag:Name,Values=${ENVIRONMENT_NAME}-*" \
    --query 'Vpcs[].{ID:VpcId,CIDR:CidrBlock,Name:Tags[?Key==`Name`].Value|[0]}' \
    --output text 2>/dev/null || true)

if [ -z "$VPCS" ]; then
    info "No conflicting VPCs found"
else
    error "Found existing VPCs:"
    echo "$VPCS" | while read -r line; do
        error "  $line"
    done
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi
echo ""

# ==========================================
# Check 7: ECS Clusters
# ==========================================
header "7. Checking ECS Clusters"
echo ""

check "Checking for ECS clusters: ${ENVIRONMENT_NAME}-*"

ECS_CLUSTERS=$(aws ecs list-clusters \
    --region "$AWS_REGION" \
    --query "clusterArns[?contains(@, '${ENVIRONMENT_NAME}')]" \
    --output text 2>/dev/null || true)

if [ -z "$ECS_CLUSTERS" ]; then
    info "No conflicting ECS clusters found"
else
    error "Found existing ECS clusters:"
    echo "$ECS_CLUSTERS" | while read -r cluster; do
        error "  $cluster"
    done
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi
echo ""

# ==========================================
# Check 8: Lambda Functions
# ==========================================
header "8. Checking Lambda Functions"
echo ""

check "Checking for Lambda functions: ${ENVIRONMENT_NAME}-*"

LAMBDAS=$(aws lambda list-functions \
    --region "$AWS_REGION" \
    --query "Functions[?contains(FunctionName, '${ENVIRONMENT_NAME}')].{Name:FunctionName,Runtime:Runtime}" \
    --output text 2>/dev/null || true)

if [ -z "$LAMBDAS" ]; then
    info "No conflicting Lambda functions found"
else
    warn "Found existing Lambda functions:"
    echo "$LAMBDAS" | while read -r line; do
        warn "  $line"
    done
    WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
fi
echo ""

# ==========================================
# Check 9: Application Load Balancers
# ==========================================
header "9. Checking Load Balancers"
echo ""

check "Checking for ALBs: ${ENVIRONMENT_NAME}-*"

ALBS=$(aws elbv2 describe-load-balancers \
    --region "$AWS_REGION" \
    --query "LoadBalancers[?contains(LoadBalancerName, '${ENVIRONMENT_NAME}')].{Name:LoadBalancerName,DNS:DNSName}" \
    --output text 2>/dev/null || true)

if [ -z "$ALBS" ]; then
    info "No conflicting ALBs found"
else
    error "Found existing ALBs:"
    echo "$ALBS" | while read -r line; do
        error "  $line"
    done
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi
echo ""

# ==========================================
# Check 10: IAM Roles (Warning only)
# ==========================================
header "10. Checking IAM Roles"
echo ""

check "Checking for IAM roles: ${ENVIRONMENT_NAME}-*"

IAM_ROLES=$(aws iam list-roles \
    --query "Roles[?contains(RoleName, '${ENVIRONMENT_NAME}')].RoleName" \
    --output text 2>/dev/null || true)

if [ -z "$IAM_ROLES" ]; then
    info "No conflicting IAM roles found"
else
    warn "Found existing IAM roles (may be from previous deployment):"
    echo "$IAM_ROLES" | tr '\t' '\n' | while read -r role; do
        if [ -n "$role" ]; then
            warn "  $role"
        fi
    done
    WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
fi
echo ""

# ==========================================
# Check 11: Secrets Manager
# ==========================================
header "11. Checking Secrets Manager"
echo ""

check "Checking for secrets: ${ENVIRONMENT_NAME}-*"

SECRETS=$(aws secretsmanager list-secrets \
    --region "$AWS_REGION" \
    --query "SecretList[?contains(Name, '${ENVIRONMENT_NAME}')].{Name:Name,Status:DeletedDate}" \
    --output text 2>/dev/null || true)

if [ -z "$SECRETS" ]; then
    info "No conflicting secrets found"
else
    warn "Found existing secrets:"
    echo "$SECRETS" | while read -r line; do
        warn "  $line"
    done
    WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
fi
echo ""

# ==========================================
# Summary and Recommendations
# ==========================================
header "Validation Summary"
echo ""

if [ $ISSUES_FOUND -eq 0 ] && [ $WARNINGS_FOUND -eq 0 ]; then
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✓ ALL CHECKS PASSED${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    info "No conflicts detected. Safe to deploy!"
    echo ""
    echo "Next steps:"
    echo "  1. Deploy Phase 2: cd phase2-infrastructure/scripts && ./deploy-infrastructure.sh"
    echo "  2. Deploy Phase 3: cd phase3-ecs/scripts && ./deploy-ecs.sh"
    echo "  3. Deploy Phase 4: cd phase4-redshift/scripts && ./deploy.sh"
    echo ""
    exit 0
fi

if [ $ISSUES_FOUND -gt 0 ]; then
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}✗ BLOCKING ISSUES FOUND: $ISSUES_FOUND${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    error "Deployment will fail due to existing resources"
    echo ""
fi

if [ $WARNINGS_FOUND -gt 0 ]; then
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}⚠ WARNINGS FOUND: $WARNINGS_FOUND${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    warn "Some resources exist but may not block deployment"
    echo ""
fi

# Provide resolution steps
header "Resolution Steps"
echo ""

if [ ${#CONFLICTING_STACKS[@]} -gt 0 ]; then
    echo "CloudFormation Stacks (${#CONFLICTING_STACKS[@]} found):"
    echo "  Option 1: Delete all phases using cleanup script"
    echo "    ./scripts/cleanup-all-phases.sh"
    echo ""
    echo "  Option 2: Delete individual stacks in reverse order"
    for STACK in "${CONFLICTING_STACKS[@]}"; do
        echo "    aws cloudformation delete-stack --stack-name $STACK --region $AWS_REGION"
    done
    echo ""
fi

if [ ${#CONFLICTING_BUCKETS[@]} -gt 0 ]; then
    echo "S3 Buckets (${#CONFLICTING_BUCKETS[@]} found):"
    echo "  Option 1: Use automated bucket fix script"
    echo "    ./scripts/fix-existing-buckets.sh"
    echo ""
    echo "  Option 2: Delete buckets manually"
    for BUCKET in "${CONFLICTING_BUCKETS[@]}"; do
        echo "    aws s3 rm s3://${BUCKET} --recursive --region $AWS_REGION"
        echo "    aws s3 rb s3://${BUCKET} --region $AWS_REGION"
    done
    echo ""
fi

if [ ${#CONFLICTING_REPOS[@]} -gt 0 ]; then
    echo "ECR Repositories (${#CONFLICTING_REPOS[@]} found):"
    echo "  These typically don't block deployment, but can be deleted if desired:"
    for REPO in "${CONFLICTING_REPOS[@]}"; do
        echo "    aws ecr delete-repository --repository-name $REPO --force --region $AWS_REGION"
    done
    echo ""
fi

if [ ! -z "$RDS_INSTANCES" ] || [ ! -z "$REDSHIFT_CLUSTERS" ] || [ ! -z "$VPCS" ] || [ ! -z "$ECS_CLUSTERS" ] || [ ! -z "$ALBS" ]; then
    echo "Other Resources:"
    echo "  Use the cleanup script to remove all resources:"
    echo "    ./scripts/cleanup-all-phases.sh"
    echo ""
fi

echo "After resolving conflicts, run this check again:"
echo "  ./scripts/pre-deployment-check.sh"
echo ""

# Exit with error if blocking issues found
if [ $ISSUES_FOUND -gt 0 ]; then
    exit 1
else
    exit 0
fi
