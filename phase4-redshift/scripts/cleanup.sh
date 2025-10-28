#!/bin/bash

# Medical Robotics Data Platform - Phase 4 Cleanup Script
# Tears down Redshift and ETL infrastructure

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

echo ""
header "Medical Robotics Data Platform - Phase 4 Cleanup"
echo ""

warn "This will delete:"
echo "  - Redshift cluster and all data"
echo "  - ETL Lambda functions"
echo "  - Step Functions workflows"
echo "  - CloudWatch logs"
echo ""

read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    info "Cleanup cancelled"
    exit 0
fi

echo ""

# Delete Step Functions
header "Step 1/3: Deleting Step Functions"

if aws cloudformation describe-stacks \
    --stack-name ${ENVIRONMENT_NAME}-step-functions \
    --region $AWS_REGION &> /dev/null; then

    info "Deleting Step Functions stack..."
    aws cloudformation delete-stack \
        --stack-name ${ENVIRONMENT_NAME}-step-functions \
        --region $AWS_REGION

    info "Waiting for stack deletion..."
    aws cloudformation wait stack-delete-complete \
        --stack-name ${ENVIRONMENT_NAME}-step-functions \
        --region $AWS_REGION

    info "Step Functions deleted"
else
    warn "Step Functions stack not found"
fi

echo ""

# Delete Lambda functions
header "Step 2/3: Deleting Lambda Functions"

if aws cloudformation describe-stacks \
    --stack-name ${ENVIRONMENT_NAME}-etl-lambda \
    --region $AWS_REGION &> /dev/null; then

    info "Deleting Lambda stack..."
    aws cloudformation delete-stack \
        --stack-name ${ENVIRONMENT_NAME}-etl-lambda \
        --region $AWS_REGION

    info "Waiting for stack deletion..."
    aws cloudformation wait stack-delete-complete \
        --stack-name ${ENVIRONMENT_NAME}-etl-lambda \
        --region $AWS_REGION

    info "Lambda functions deleted"
else
    warn "Lambda stack not found"
fi

echo ""

# Delete Redshift cluster
header "Step 3/3: Deleting Redshift Cluster"

if aws cloudformation describe-stacks \
    --stack-name ${ENVIRONMENT_NAME}-redshift \
    --region $AWS_REGION &> /dev/null; then

    warn "Deleting Redshift cluster (this may take 5-10 minutes)..."

    # Delete final snapshot if exists
    CLUSTER_ID="${ENVIRONMENT_NAME}-redshift"
    FINAL_SNAPSHOT="${CLUSTER_ID}-final-snapshot-$(date '+%Y%m%d%H%M%S')"

    info "Creating final snapshot: $FINAL_SNAPSHOT"

    aws cloudformation delete-stack \
        --stack-name ${ENVIRONMENT_NAME}-redshift \
        --region $AWS_REGION

    info "Waiting for stack deletion..."
    aws cloudformation wait stack-delete-complete \
        --stack-name ${ENVIRONMENT_NAME}-redshift \
        --region $AWS_REGION

    info "Redshift cluster deleted"
else
    warn "Redshift stack not found"
fi

echo ""

# Clean up Lambda deployment packages from S3
header "Cleaning Up Lambda Packages"

LAMBDA_CODE_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name ${ENVIRONMENT_NAME}-s3 \
    --region $AWS_REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`ProcessedBucket`].OutputValue' \
    --output text 2>/dev/null) || true

if [ -n "$LAMBDA_CODE_BUCKET" ]; then
    info "Deleting Lambda packages from S3..."
    aws s3 rm s3://${LAMBDA_CODE_BUCKET}/lambda/ --recursive --region $AWS_REGION || true
    info "Lambda packages deleted"
else
    warn "Could not find Lambda code bucket"
fi

echo ""

# Delete CloudWatch Log Groups
header "Cleaning Up CloudWatch Logs"

LOG_GROUPS=(
    "/aws/lambda/${ENVIRONMENT_NAME}-rds-to-redshift-etl"
    "/aws/lambda/${ENVIRONMENT_NAME}-telemetry-etl"
    "/aws/vendedlogs/states/${ENVIRONMENT_NAME}-etl-orchestration"
)

for LOG_GROUP in "${LOG_GROUPS[@]}"; do
    if aws logs describe-log-groups \
        --log-group-name-prefix $LOG_GROUP \
        --region $AWS_REGION &> /dev/null; then
        info "Deleting log group: $LOG_GROUP"
        aws logs delete-log-group \
            --log-group-name $LOG_GROUP \
            --region $AWS_REGION 2>/dev/null || true
    fi
done

info "CloudWatch logs deleted"
echo ""

# Summary
header "Cleanup Complete"
echo ""
info "All Phase 4 resources have been deleted"
echo ""
warn "Note: Redshift snapshots may still exist. To delete them:"
echo "  aws redshift describe-cluster-snapshots --region $AWS_REGION"
echo "  aws redshift delete-cluster-snapshot --snapshot-identifier <ID> --region $AWS_REGION"
echo ""
