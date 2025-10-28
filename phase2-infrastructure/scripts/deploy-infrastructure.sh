#!/bin/bash

# Medical Robotics Data Platform - Infrastructure Deployment Script
# This script deploys the CloudFormation stacks in the correct order

set -e  # Exit on error

# Configuration
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-medrobotics}"
AWS_REGION="${AWS_REGION:-us-east-1}"
DB_USERNAME="${DB_USERNAME:-dbadmin}"
DB_PASSWORD="${DB_PASSWORD}"
DB_INSTANCE_CLASS="${DB_INSTANCE_CLASS:-db.t3.micro}"

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
    exit 1
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."

    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi

    if [ -z "$DB_PASSWORD" ]; then
        error "DB_PASSWORD environment variable is not set. Please set it before running this script."
    fi

    if [ ${#DB_PASSWORD} -lt 8 ]; then
        error "DB_PASSWORD must be at least 8 characters long."
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials are not configured. Please run 'aws configure'."
    fi

    info "Prerequisites check passed!"
}

# Deploy stack
deploy_stack() {
    local STACK_NAME=$1
    local TEMPLATE_FILE=$2
    local PARAMETERS=$3

    info "Deploying stack: $STACK_NAME"

    if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" &> /dev/null; then
        info "Stack $STACK_NAME already exists. Updating..."
        aws cloudformation update-stack \
            --stack-name "$STACK_NAME" \
            --template-body "file://$TEMPLATE_FILE" \
            --parameters $PARAMETERS \
            --capabilities CAPABILITY_NAMED_IAM \
            --region "$AWS_REGION" || warn "No updates to be performed"
    else
        info "Creating new stack: $STACK_NAME"
        aws cloudformation create-stack \
            --stack-name "$STACK_NAME" \
            --template-body "file://$TEMPLATE_FILE" \
            --parameters $PARAMETERS \
            --capabilities CAPABILITY_NAMED_IAM \
            --region "$AWS_REGION"
    fi

    info "Waiting for stack $STACK_NAME to complete..."
    aws cloudformation wait stack-create-complete \
        --stack-name "$STACK_NAME" \
        --region "$AWS_REGION" 2>/dev/null || \
    aws cloudformation wait stack-update-complete \
        --stack-name "$STACK_NAME" \
        --region "$AWS_REGION" 2>/dev/null || true

    # Check stack status
    STACK_STATUS=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$AWS_REGION" \
        --query 'Stacks[0].StackStatus' \
        --output text)

    if [[ "$STACK_STATUS" == *"COMPLETE"* ]]; then
        info "Stack $STACK_NAME deployed successfully! Status: $STACK_STATUS"
    else
        error "Stack $STACK_NAME deployment failed! Status: $STACK_STATUS"
    fi
}

# Main deployment
main() {
    info "========================================"
    info "Medical Robotics Data Platform"
    info "Infrastructure Deployment"
    info "========================================"
    info ""
    info "Environment: $ENVIRONMENT_NAME"
    info "Region: $AWS_REGION"
    info "DB Instance Class: $DB_INSTANCE_CLASS"
    info ""

    check_prerequisites

    # Get script directory
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    CF_DIR="$SCRIPT_DIR/../cloudformation"

    # Deploy stacks in order
    info ""
    info "Step 1/5: Deploying VPC and Networking..."
    deploy_stack \
        "${ENVIRONMENT_NAME}-network" \
        "$CF_DIR/01-vpc-network.yaml" \
        "ParameterKey=EnvironmentName,ParameterValue=$ENVIRONMENT_NAME"

    info ""
    info "Step 2/5: Deploying Security Groups..."
    deploy_stack \
        "${ENVIRONMENT_NAME}-security-groups" \
        "$CF_DIR/02-security-groups.yaml" \
        "ParameterKey=EnvironmentName,ParameterValue=$ENVIRONMENT_NAME"

    info ""
    info "Step 3/5: Deploying S3 Buckets..."
    deploy_stack \
        "${ENVIRONMENT_NAME}-s3" \
        "$CF_DIR/03-s3-buckets.yaml" \
        "ParameterKey=EnvironmentName,ParameterValue=$ENVIRONMENT_NAME"

    info ""
    info "Step 4/5: Deploying IAM Roles..."
    deploy_stack \
        "${ENVIRONMENT_NAME}-iam" \
        "$CF_DIR/04-iam-roles.yaml" \
        "ParameterKey=EnvironmentName,ParameterValue=$ENVIRONMENT_NAME"

    info ""
    info "Step 5/5: Deploying RDS PostgreSQL..."
    deploy_stack \
        "${ENVIRONMENT_NAME}-rds" \
        "$CF_DIR/05-rds-postgres.yaml" \
        "ParameterKey=EnvironmentName,ParameterValue=$ENVIRONMENT_NAME ParameterKey=DBUsername,ParameterValue=$DB_USERNAME ParameterKey=DBPassword,ParameterValue=$DB_PASSWORD ParameterKey=DBInstanceClass,ParameterValue=$DB_INSTANCE_CLASS"

    info ""
    info "========================================"
    info "Deployment Complete!"
    info "========================================"
    info ""
    info "Next steps:"
    info "1. Verify stacks in AWS Console CloudFormation"
    info "2. Get RDS endpoint: aws cloudformation describe-stacks --stack-name ${ENVIRONMENT_NAME}-rds --query 'Stacks[0].Outputs'"
    info "3. Run SQL schema: psql -h <endpoint> -U $DB_USERNAME -d medrobotics -f ../sql-schemas/01-create-tables.sql"
    info "4. Load sample data from Phase 1"
}

# Run main function
main
