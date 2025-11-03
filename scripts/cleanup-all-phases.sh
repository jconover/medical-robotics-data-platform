#!/bin/bash

# Medical Robotics Data Platform - Complete Cleanup Script
# Deletes ALL phases in correct order

set -e

ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-medrobotics}"
AWS_REGION="${AWS_REGION:-us-east-1}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Check if stack exists
stack_exists() {
    aws cloudformation describe-stacks \
        --stack-name "$1" \
        --region "$AWS_REGION" &> /dev/null
}

# Delete stack with wait
delete_stack() {
    local STACK_NAME=$1

    if stack_exists "$STACK_NAME"; then
        info "Deleting stack: $STACK_NAME"
        aws cloudformation delete-stack \
            --stack-name "$STACK_NAME" \
            --region "$AWS_REGION"

        info "Waiting for $STACK_NAME to be deleted..."
        aws cloudformation wait stack-delete-complete \
            --stack-name "$STACK_NAME" \
            --region "$AWS_REGION" 2>/dev/null || warn "Stack deletion completed with warnings"

        info "✓ $STACK_NAME deleted"
    else
        info "Stack $STACK_NAME doesn't exist, skipping"
    fi
    echo ""
}

# Main
header "COMPLETE INFRASTRUCTURE CLEANUP"
echo ""
warn "Environment: $ENVIRONMENT_NAME"
warn "Region: $AWS_REGION"
echo ""
warn "This will delete ALL resources across ALL phases:"
warn "  Phase 5: EKS cluster (if exists)"
warn "  Phase 4: Redshift + ETL + Lambda"
warn "  Phase 3: ECS services + ALB + Docker images"
warn "  Phase 2: VPC + RDS + S3 + IAM + Security Groups"
echo ""
warn "⚠️  ALL DATA WILL BE PERMANENTLY LOST ⚠️"
echo ""
read -p "Are you ABSOLUTELY sure? Type 'DELETE' to confirm: " CONFIRM

if [ "$CONFIRM" != "DELETE" ]; then
    info "Cleanup cancelled"
    exit 0
fi

echo ""
info "Starting cleanup in reverse dependency order..."
echo ""

# ==========================================
# Phase 5: EKS (if exists)
# ==========================================
header "Phase 5: Checking for EKS Resources"

if stack_exists "${ENVIRONMENT_NAME}-eks"; then
    error "EKS cluster detected!"
    echo ""
    error "Please run the following first:"
    error "  cd phase5-eks/scripts && ./cleanup.sh"
    echo ""
    error "Then re-run this script."
    exit 1
fi

info "✓ No EKS resources found"
echo ""

# ==========================================
# Phase 4: Redshift & ETL
# ==========================================
header "Phase 4: Redshift & ETL Cleanup"

# Step Functions first (depends on Lambda)
delete_stack "${ENVIRONMENT_NAME}-step-functions"

# Lambda functions (depend on Redshift and VPC)
delete_stack "${ENVIRONMENT_NAME}-etl-lambda"

# Redshift cluster (can take 5-10 minutes)
if stack_exists "${ENVIRONMENT_NAME}-redshift"; then
    warn "Deleting Redshift cluster (this may take 5-10 minutes)..."
    delete_stack "${ENVIRONMENT_NAME}-redshift"
fi

# Clean up Lambda packages from S3
info "Cleaning up Lambda deployment packages from S3..."
PROCESSED_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name "${ENVIRONMENT_NAME}-s3" \
    --region "$AWS_REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`ProcessedDataBucket`].OutputValue' \
    --output text 2>/dev/null) || true

if [ -n "$PROCESSED_BUCKET" ]; then
    info "Removing lambda/ folder from bucket: $PROCESSED_BUCKET"
    aws s3 rm "s3://${PROCESSED_BUCKET}/lambda/" --recursive --region "$AWS_REGION" 2>/dev/null || true
    info "✓ Lambda packages cleaned up"
else
    warn "Could not find processed bucket"
fi
echo ""

# ==========================================
# Phase 3: ECS Services
# ==========================================
header "Phase 3: ECS Services Cleanup"

# Delete services first (they depend on task definitions, clusters, and ALB target groups)
delete_stack "${ENVIRONMENT_NAME}-ecs-services"

# Delete task definitions (depend on IAM roles and log groups)
delete_stack "${ENVIRONMENT_NAME}-ecs-tasks"

# Delete ALB (depends on VPC and security groups, but target groups deleted with services)
delete_stack "${ENVIRONMENT_NAME}-alb"

# Delete ECS cluster (contains log groups)
delete_stack "${ENVIRONMENT_NAME}-ecs-cluster"

# Clean up ECR repositories
info "Cleaning up ECR repositories..."
for REPO in data-ingestion api-service; do
    REPO_NAME="${ENVIRONMENT_NAME}-${REPO}"
    if aws ecr describe-repositories \
        --repository-names "$REPO_NAME" \
        --region "$AWS_REGION" &> /dev/null; then

        info "Deleting ECR repository: $REPO_NAME"
        aws ecr delete-repository \
            --repository-name "$REPO_NAME" \
            --force \
            --region "$AWS_REGION" 2>/dev/null || warn "Failed to delete $REPO_NAME"
    fi
done
info "✓ ECR cleanup complete"
echo ""

# ==========================================
# Phase 2: Core Infrastructure
# ==========================================
header "Phase 2: Core Infrastructure Cleanup"

# Empty all S3 buckets before deletion (buckets must be empty to delete)
info "Emptying S3 buckets (required before deletion)..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

for BUCKET_SUFFIX in raw-data processed-data analytics logs backups; do
    BUCKET="${ENVIRONMENT_NAME}-${BUCKET_SUFFIX}-${ACCOUNT_ID}"
    if aws s3 ls "s3://${BUCKET}" &> /dev/null 2>&1; then
        info "Emptying bucket: $BUCKET"
        aws s3 rm "s3://${BUCKET}" --recursive --region "$AWS_REGION" 2>/dev/null || warn "Failed to empty $BUCKET"
    fi
done
info "✓ S3 buckets emptied"
echo ""

# Delete Phase 2 stacks in reverse dependency order
info "Deleting Phase 2 stacks in reverse order..."
echo ""

# Bastion host (optional, depends on VPC and security groups)
delete_stack "${ENVIRONMENT_NAME}-bastion"

# RDS (depends on VPC, security groups, secrets)
delete_stack "${ENVIRONMENT_NAME}-rds"

# IAM roles (no dependencies, but other services depend on it)
delete_stack "${ENVIRONMENT_NAME}-iam"

# S3 buckets (no dependencies, but IAM and services depend on it)
delete_stack "${ENVIRONMENT_NAME}-s3"

# Security groups (depend on VPC)
delete_stack "${ENVIRONMENT_NAME}-security-groups"

# VPC and networking (foundation stack, deleted last)
delete_stack "${ENVIRONMENT_NAME}-network"

# ==========================================
# Final Verification
# ==========================================
header "Cleanup Complete - Verification"

info "Checking for any remaining stacks..."
REMAINING=$(aws cloudformation list-stacks \
    --region "$AWS_REGION" \
    --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE ROLLBACK_COMPLETE UPDATE_ROLLBACK_COMPLETE \
    --query "StackSummaries[?contains(StackName, '${ENVIRONMENT_NAME}')].StackName" \
    --output text 2>/dev/null || true)

if [ -z "$REMAINING" ]; then
    info "✓ All stacks successfully deleted!"
else
    warn "The following stacks still exist:"
    echo "$REMAINING"
    echo ""
    warn "These may be in DELETE_IN_PROGRESS state. Wait a few minutes and check again."
fi

echo ""
header "✓ CLEANUP COMPLETE"
echo ""
info "All infrastructure has been deleted."
echo ""
warn "Note: Manual cleanup may be required for:"
echo "  - CloudWatch Log Groups (may persist beyond stack deletion)"
echo "  - Redshift snapshots (check with: aws redshift describe-cluster-snapshots)"
echo "  - Secrets Manager secrets (check with: aws secretsmanager list-secrets)"
echo ""
info "To verify complete cleanup, run:"
echo "  aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE --region $AWS_REGION | grep $ENVIRONMENT_NAME"
echo "  aws s3 ls | grep $ENVIRONMENT_NAME"
echo "  aws ecr describe-repositories --region $AWS_REGION | grep $ENVIRONMENT_NAME"
echo ""
