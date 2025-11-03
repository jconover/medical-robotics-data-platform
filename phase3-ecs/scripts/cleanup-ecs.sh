#!/bin/bash

# Medical Robotics Data Platform - Phase 3 ECS Cleanup Script
# Tears down ECS services, tasks, ALB, and container images

set -e

# Configuration
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-medrobotics}"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

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
header "Phase 3: ECS Infrastructure Cleanup"
echo ""
warn "Environment: $ENVIRONMENT_NAME"
warn "Region: $AWS_REGION"
echo ""
warn "This will delete:"
warn "  - ECS services (data-ingestion, api-service)"
warn "  - ECS task definitions"
warn "  - Application Load Balancer"
warn "  - ECS cluster and log groups"
warn "  - ECR repositories and Docker images"
echo ""
warn "⚠️  Services will become unavailable ⚠️"
echo ""
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    info "Cleanup cancelled"
    exit 0
fi

echo ""

# Check prerequisites
info "Checking for Phase 2 infrastructure..."
if ! stack_exists "${ENVIRONMENT_NAME}-network"; then
    warn "Phase 2 infrastructure not found. This is expected if you're cleaning up everything."
    echo ""
fi

# Check for dependent stacks
info "Checking for dependent stacks..."
DEPENDENT_STACKS=()

for STACK in \
    "${ENVIRONMENT_NAME}-redshift" \
    "${ENVIRONMENT_NAME}-etl-lambda" \
    "${ENVIRONMENT_NAME}-step-functions"; do

    if stack_exists "$STACK"; then
        DEPENDENT_STACKS+=("$STACK")
    fi
done

if [ ${#DEPENDENT_STACKS[@]} -gt 0 ]; then
    warn "Warning: Found Phase 4 (Redshift) stacks that may depend on Phase 3 resources:"
    for STACK in "${DEPENDENT_STACKS[@]}"; do
        warn "  - $STACK"
    done
    echo ""
    warn "It's recommended to delete Phase 4 first."
    echo ""
    read -p "Do you want to continue anyway? (yes/no): " CONTINUE

    if [ "$CONTINUE" != "yes" ]; then
        info "Cleanup cancelled"
        echo ""
        info "To clean up everything in order, run:"
        info "  cd ../.. && ./scripts/cleanup-all-phases.sh"
        exit 0
    fi
fi

echo ""
info "Starting cleanup in reverse dependency order..."
echo ""

# ==========================================
# Step 1: Delete ECS Services
# ==========================================
header "Step 1/5: Deleting ECS Services"

delete_stack "${ENVIRONMENT_NAME}-ecs-services"

# ==========================================
# Step 2: Delete Task Definitions
# ==========================================
header "Step 2/5: Deleting Task Definitions"

delete_stack "${ENVIRONMENT_NAME}-ecs-tasks"

# ==========================================
# Step 3: Delete Application Load Balancer
# ==========================================
header "Step 3/5: Deleting Application Load Balancer"

delete_stack "${ENVIRONMENT_NAME}-alb"

# ==========================================
# Step 4: Delete ECS Cluster
# ==========================================
header "Step 4/5: Deleting ECS Cluster"

delete_stack "${ENVIRONMENT_NAME}-ecs-cluster"

# ==========================================
# Step 5: Clean up ECR repositories
# ==========================================
header "Step 5/5: Cleaning Up ECR Repositories"

info "Deleting ECR repositories and all Docker images..."

for REPO in data-ingestion api-service; do
    REPO_NAME="${ENVIRONMENT_NAME}-${REPO}"

    if aws ecr describe-repositories \
        --repository-names "$REPO_NAME" \
        --region "$AWS_REGION" &> /dev/null; then

        # Get image count
        IMAGE_COUNT=$(aws ecr list-images \
            --repository-name "$REPO_NAME" \
            --region "$AWS_REGION" \
            --query 'length(imageIds)' \
            --output text 2>/dev/null || echo "0")

        info "Deleting repository: $REPO_NAME ($IMAGE_COUNT images)"

        aws ecr delete-repository \
            --repository-name "$REPO_NAME" \
            --force \
            --region "$AWS_REGION" 2>/dev/null || warn "Failed to delete $REPO_NAME"

        info "✓ Repository $REPO_NAME deleted"
    else
        info "Repository $REPO_NAME doesn't exist, skipping"
    fi
done

echo ""

# ==========================================
# Verification
# ==========================================
header "Cleanup Complete - Verification"

info "Checking for remaining Phase 3 resources..."

# Check for ECS clusters
REMAINING_CLUSTERS=$(aws ecs list-clusters \
    --region "$AWS_REGION" \
    --query "clusterArns[?contains(@, '${ENVIRONMENT_NAME}')]" \
    --output text 2>/dev/null || true)

# Check for ALBs
REMAINING_ALBS=$(aws elbv2 describe-load-balancers \
    --region "$AWS_REGION" \
    --query "LoadBalancers[?contains(LoadBalancerName, '${ENVIRONMENT_NAME}')].LoadBalancerName" \
    --output text 2>/dev/null || true)

# Check for ECR repos
REMAINING_REPOS=$(aws ecr describe-repositories \
    --region "$AWS_REGION" \
    --query "repositories[?contains(repositoryName, '${ENVIRONMENT_NAME}')].repositoryName" \
    --output text 2>/dev/null || true)

# Check CloudFormation stacks
REMAINING_STACKS=$(aws cloudformation list-stacks \
    --region "$AWS_REGION" \
    --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
    --query "StackSummaries[?contains(StackName, '${ENVIRONMENT_NAME}-ecs') || contains(StackName, '${ENVIRONMENT_NAME}-alb')].StackName" \
    --output text 2>/dev/null || true)

ALL_CLEAN=true

if [ -n "$REMAINING_CLUSTERS" ]; then
    warn "⚠ ECS clusters still exist: $REMAINING_CLUSTERS"
    ALL_CLEAN=false
fi

if [ -n "$REMAINING_ALBS" ]; then
    warn "⚠ ALBs still exist: $REMAINING_ALBS"
    ALL_CLEAN=false
fi

if [ -n "$REMAINING_REPOS" ]; then
    warn "⚠ ECR repositories still exist: $REMAINING_REPOS"
    ALL_CLEAN=false
fi

if [ -n "$REMAINING_STACKS" ]; then
    warn "⚠ CloudFormation stacks still exist: $REMAINING_STACKS"
    warn "These may be in DELETE_IN_PROGRESS state. Wait and check again."
    ALL_CLEAN=false
fi

echo ""

if [ "$ALL_CLEAN" = true ]; then
    header "✓ PHASE 3 CLEANUP COMPLETE"
    echo ""
    info "All Phase 3 (ECS) resources have been deleted."
else
    header "⚠ CLEANUP PARTIALLY COMPLETE"
    echo ""
    warn "Some resources may still be deleting. Check again in a few minutes."
fi

echo ""
warn "Note: CloudWatch Log Groups may persist beyond stack deletion:"
echo "  /aws/ecs/${ENVIRONMENT_NAME}/data-ingestion"
echo "  /aws/ecs/${ENVIRONMENT_NAME}/api-service"
echo ""
info "To delete log groups manually:"
echo "  aws logs delete-log-group --log-group-name /aws/ecs/${ENVIRONMENT_NAME}/data-ingestion --region $AWS_REGION"
echo "  aws logs delete-log-group --log-group-name /aws/ecs/${ENVIRONMENT_NAME}/api-service --region $AWS_REGION"
echo ""
info "Phase 2 infrastructure (VPC, RDS, S3) is still running."
info "To clean up Phase 2:"
echo "  cd ../../phase2-infrastructure/scripts && ./cleanup-infrastructure.sh"
echo ""
info "Or to clean up everything:"
echo "  cd ../.. && ./scripts/cleanup-all-phases.sh"
echo ""
