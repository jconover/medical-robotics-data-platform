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
DEPLOY_BASTION="${DEPLOY_BASTION:-false}"  # Set to "true" to deploy bastion host

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
    info "Step 1/6: Deploying VPC and Networking..."
    deploy_stack \
        "${ENVIRONMENT_NAME}-network" \
        "$CF_DIR/01-vpc-network.yaml" \
        "ParameterKey=EnvironmentName,ParameterValue=$ENVIRONMENT_NAME"

    info ""
    info "Step 2/6: Deploying Security Groups..."
    deploy_stack \
        "${ENVIRONMENT_NAME}-security-groups" \
        "$CF_DIR/02-security-groups.yaml" \
        "ParameterKey=EnvironmentName,ParameterValue=$ENVIRONMENT_NAME"

    info ""
    info "Step 3/6: Deploying S3 Buckets..."
    deploy_stack \
        "${ENVIRONMENT_NAME}-s3" \
        "$CF_DIR/03-s3-buckets.yaml" \
        "ParameterKey=EnvironmentName,ParameterValue=$ENVIRONMENT_NAME"

    info ""
    info "Step 4/6: Deploying IAM Roles..."
    deploy_stack \
        "${ENVIRONMENT_NAME}-iam" \
        "$CF_DIR/04-iam-roles.yaml" \
        "ParameterKey=EnvironmentName,ParameterValue=$ENVIRONMENT_NAME"

    info ""
    info "Step 5/6: Deploying RDS PostgreSQL..."
    deploy_stack \
        "${ENVIRONMENT_NAME}-rds" \
        "$CF_DIR/05-rds-postgres.yaml" \
        "ParameterKey=EnvironmentName,ParameterValue=$ENVIRONMENT_NAME ParameterKey=DBUsername,ParameterValue=$DB_USERNAME ParameterKey=DBPassword,ParameterValue=$DB_PASSWORD ParameterKey=DBInstanceClass,ParameterValue=$DB_INSTANCE_CLASS"

    # Optional: Deploy bastion host
    if [ "$DEPLOY_BASTION" = "true" ]; then
        info ""
        info "Step 6/6: Deploying Bastion Host (Optional)..."
        deploy_stack \
            "${ENVIRONMENT_NAME}-bastion" \
            "$CF_DIR/06-bastion-host.yaml" \
            "ParameterKey=EnvironmentName,ParameterValue=$ENVIRONMENT_NAME"

        info ""
        info "Bastion host deployed! Connect with:"
        BASTION_ID=$(aws cloudformation describe-stacks \
            --stack-name "${ENVIRONMENT_NAME}-bastion" \
            --region "$AWS_REGION" \
            --query 'Stacks[0].Outputs[?OutputKey==`BastionInstanceId`].OutputValue' \
            --output text 2>/dev/null || echo "")

        if [ -n "$BASTION_ID" ]; then
            info "  aws ssm start-session --target $BASTION_ID --region $AWS_REGION"
        fi
    else
        info ""
        info "Step 6/6: Bastion Host (Skipped)"
        info "To deploy bastion later, run: export DEPLOY_BASTION=true && ./deploy-infrastructure.sh"
        info "Or deploy manually - see BASTION-QUICKSTART.md"
    fi

    info ""
    info "========================================"
    info "Deployment Complete!"
    info "========================================"
    info ""
    info "RDS is in a PRIVATE subnet and cannot be accessed directly from your local machine."
    info ""
    info "To access RDS and create the database schema, you have two options:"
    info ""
    info "Option 1 (RECOMMENDED): Deploy a bastion host"
    info "  cd $CF_DIR"
    info "  aws cloudformation create-stack --stack-name ${ENVIRONMENT_NAME}-bastion --template-body file://06-bastion-host.yaml --parameters ParameterKey=EnvironmentName,ParameterValue=$ENVIRONMENT_NAME --capabilities CAPABILITY_NAMED_IAM --region $AWS_REGION"
    info "  aws cloudformation wait stack-create-complete --stack-name ${ENVIRONMENT_NAME}-bastion --region $AWS_REGION"
    info ""
    info "  Then connect: aws ssm start-session --target \$(aws cloudformation describe-stacks --stack-name ${ENVIRONMENT_NAME}-bastion --query 'Stacks[0].Outputs[?OutputKey==\`BastionInstanceId\`].OutputValue' --output text) --region $AWS_REGION"
    info ""
    info "Option 2: Use ECS task with exec enabled (Phase 3)"
    info ""
    info "See BASTION-QUICKSTART.md for detailed instructions."
    info ""
    info "Other resources:"
    info "  - View all outputs: aws cloudformation describe-stacks --stack-name ${ENVIRONMENT_NAME}-rds --query 'Stacks[0].Outputs' --region $AWS_REGION"
    info "  - S3 buckets: aws cloudformation describe-stacks --stack-name ${ENVIRONMENT_NAME}-s3 --query 'Stacks[0].Outputs' --region $AWS_REGION"
}

# Run main function
main
