#!/bin/bash

# Medical Robotics Data Platform - Infrastructure Cleanup Script
# This script deletes all CloudFormation stacks in reverse order

set -e  # Exit on error

# Configuration
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-medrobotics}"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Delete stack
delete_stack() {
    local STACK_NAME=$1

    if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" &> /dev/null; then
        info "Deleting stack: $STACK_NAME"
        aws cloudformation delete-stack \
            --stack-name "$STACK_NAME" \
            --region "$AWS_REGION"

        info "Waiting for stack $STACK_NAME to be deleted..."
        aws cloudformation wait stack-delete-complete \
            --stack-name "$STACK_NAME" \
            --region "$AWS_REGION" || warn "Stack deletion timed out or failed"

        info "Stack $STACK_NAME deleted successfully!"
    else
        warn "Stack $STACK_NAME does not exist. Skipping..."
    fi
}

# Empty S3 buckets before deletion
empty_s3_buckets() {
    info "Emptying S3 buckets..."

    local ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

    local BUCKETS=(
        "${ENVIRONMENT_NAME}-raw-data-${ACCOUNT_ID}"
        "${ENVIRONMENT_NAME}-processed-data-${ACCOUNT_ID}"
        "${ENVIRONMENT_NAME}-analytics-${ACCOUNT_ID}"
        "${ENVIRONMENT_NAME}-logs-${ACCOUNT_ID}"
        "${ENVIRONMENT_NAME}-backups-${ACCOUNT_ID}"
    )

    for BUCKET in "${BUCKETS[@]}"; do
        if aws s3 ls "s3://$BUCKET" &> /dev/null; then
            info "Emptying bucket: $BUCKET"
            aws s3 rm "s3://$BUCKET" --recursive || warn "Failed to empty bucket $BUCKET"
        fi
    done
}

# Main cleanup
main() {
    warn "========================================"
    warn "WARNING: Infrastructure Cleanup"
    warn "========================================"
    warn ""
    warn "This will DELETE all infrastructure for environment: $ENVIRONMENT_NAME"
    warn "Region: $AWS_REGION"
    warn ""
    warn "This includes:"
    warn "  - Bastion Host (if deployed)"
    warn "  - RDS Database (and all data)"
    warn "  - S3 Buckets (and all data)"
    warn "  - VPC and all networking"
    warn "  - Security Groups"
    warn "  - IAM Roles"
    warn ""
    read -p "Are you sure you want to continue? (yes/no): " CONFIRM

    if [ "$CONFIRM" != "yes" ]; then
        info "Cleanup cancelled."
        exit 0
    fi

    warn ""
    read -p "Type the environment name '$ENVIRONMENT_NAME' to confirm: " CONFIRM_ENV

    if [ "$CONFIRM_ENV" != "$ENVIRONMENT_NAME" ]; then
        error "Environment name mismatch. Cleanup cancelled."
    fi

    info ""
    info "Starting cleanup..."

    # Check for dependent stacks
    info "Checking for dependent stacks from Phase 3, 4, and 5..."
    DEPENDENT_STACKS=()

    for STACK in \
        "${ENVIRONMENT_NAME}-ecs-cluster" \
        "${ENVIRONMENT_NAME}-ecs-services" \
        "${ENVIRONMENT_NAME}-ecs-tasks" \
        "${ENVIRONMENT_NAME}-alb" \
        "${ENVIRONMENT_NAME}-redshift" \
        "${ENVIRONMENT_NAME}-etl-lambda" \
        "${ENVIRONMENT_NAME}-step-functions" \
        "${ENVIRONMENT_NAME}-eks"; do

        if aws cloudformation describe-stacks --stack-name "$STACK" --region "$AWS_REGION" &> /dev/null; then
            DEPENDENT_STACKS+=("$STACK")
        fi
    done

    if [ ${#DEPENDENT_STACKS[@]} -gt 0 ]; then
        error ""
        error "=========================================="
        error "Cannot delete Phase 2 infrastructure!"
        error "=========================================="
        error ""
        error "The following dependent stacks still exist:"
        for STACK in "${DEPENDENT_STACKS[@]}"; do
            error "  - $STACK"
        done
        error ""
        error "CloudFormation will prevent Phase 2 deletion because these"
        error "stacks depend on Phase 2 exports (VPC, subnets, security groups, etc.)"
        error ""
        error "You must delete dependent stacks first:"
        error ""
        error "Option 1 (Recommended): Use the master cleanup script:"
        error "  cd ../.. && ./scripts/cleanup-all-phases.sh"
        error ""
        error "Option 2: Delete phases manually in reverse order:"
        error "  Phase 5 (EKS) → Phase 4 (Redshift) → Phase 3 (ECS) → Phase 2"
        error ""
        exit 1
    fi

    info "✓ No dependent stacks found. Safe to proceed."
    echo ""

    # Empty S3 buckets first
    empty_s3_buckets

    # Delete stacks in reverse order
    info ""
    info "Step 1/6: Deleting Bastion Host stack (if exists)..."
    delete_stack "${ENVIRONMENT_NAME}-bastion"

    info ""
    info "Step 2/6: Deleting RDS stack..."
    delete_stack "${ENVIRONMENT_NAME}-rds"

    info ""
    info "Step 3/6: Deleting IAM stack..."
    delete_stack "${ENVIRONMENT_NAME}-iam"

    info ""
    info "Step 4/6: Deleting S3 stack..."
    delete_stack "${ENVIRONMENT_NAME}-s3"

    info ""
    info "Step 5/6: Deleting Security Groups stack..."
    delete_stack "${ENVIRONMENT_NAME}-security-groups"

    info ""
    info "Step 6/6: Deleting Network stack..."
    delete_stack "${ENVIRONMENT_NAME}-network"

    info ""
    info "========================================"
    info "Cleanup Complete!"
    info "========================================"
    info "All infrastructure has been removed."
}

# Run main function
main
