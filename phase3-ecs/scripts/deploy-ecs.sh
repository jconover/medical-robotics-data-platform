#!/bin/bash

# Medical Robotics Data Platform - ECS Deployment Script
# Deploys ECS cluster, services, and load balancer

set -e

# Configuration
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-medrobotics}"
AWS_REGION="${AWS_REGION:-us-east-1}"
RDS_PASSWORD="${RDS_PASSWORD}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

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
        error "AWS CLI is not installed"
    fi

    if ! command -v docker &> /dev/null; then
        error "Docker is not installed"
    fi

    if [ -z "$RDS_PASSWORD" ]; then
        error "RDS_PASSWORD environment variable is not set"
    fi

    # Check if Phase 2 infrastructure exists
    if ! aws cloudformation describe-stacks --stack-name "${ENVIRONMENT_NAME}-network" --region "$AWS_REGION" &> /dev/null; then
        error "Phase 2 infrastructure not found. Please deploy Phase 2 first."
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
        info "Stack $STACK_NAME exists. Updating..."
        aws cloudformation update-stack \
            --stack-name "$STACK_NAME" \
            --template-body "file://$TEMPLATE_FILE" \
            --parameters $PARAMETERS \
            --capabilities CAPABILITY_NAMED_IAM \
            --region "$AWS_REGION" 2>&1 | grep -v "No updates" || warn "No updates to perform"
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
    aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME" --region "$AWS_REGION" 2>/dev/null || \
    aws cloudformation wait stack-update-complete --stack-name "$STACK_NAME" --region "$AWS_REGION" 2>/dev/null || true

    STACK_STATUS=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$AWS_REGION" \
        --query 'Stacks[0].StackStatus' \
        --output text)

    if [[ "$STACK_STATUS" == *"COMPLETE"* ]]; then
        info "✓ Stack $STACK_NAME deployed successfully! Status: $STACK_STATUS"
    else
        error "Stack $STACK_NAME deployment failed! Status: $STACK_STATUS"
    fi
}

# Main
main() {
    info "========================================"
    info "ECS Infrastructure Deployment"
    info "========================================"
    info "Environment: $ENVIRONMENT_NAME"
    info "Region: $AWS_REGION"
    info ""

    check_prerequisites

    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    CF_DIR="$SCRIPT_DIR/../cloudformation"

    # Step 1: Deploy ECS Cluster
    info ""
    info "Step 1/4: Deploying ECS Cluster..."
    deploy_stack \
        "${ENVIRONMENT_NAME}-ecs-cluster" \
        "$CF_DIR/01-ecs-cluster.yaml" \
        "ParameterKey=EnvironmentName,ParameterValue=$ENVIRONMENT_NAME"

    # Step 2: Deploy Application Load Balancer
    info ""
    info "Step 2/4: Deploying Application Load Balancer..."
    deploy_stack \
        "${ENVIRONMENT_NAME}-alb" \
        "$CF_DIR/02-alb.yaml" \
        "ParameterKey=EnvironmentName,ParameterValue=$ENVIRONMENT_NAME"

    # Step 3: Deploy ECS Task Definitions
    info ""
    info "Step 3/4: Deploying ECS Task Definitions..."
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    deploy_stack \
        "${ENVIRONMENT_NAME}-ecs-tasks" \
        "$CF_DIR/03-ecs-task-definitions.yaml" \
        "ParameterKey=EnvironmentName,ParameterValue=$ENVIRONMENT_NAME ParameterKey=RDSPassword,ParameterValue=$RDS_PASSWORD"

    # Step 4: Deploy ECS Services
    info ""
    info "Step 4/4: Deploying ECS Services..."
    deploy_stack \
        "${ENVIRONMENT_NAME}-ecs-services" \
        "$CF_DIR/04-ecs-services.yaml" \
        "ParameterKey=EnvironmentName,ParameterValue=$ENVIRONMENT_NAME"

    # Get ALB DNS
    ALB_DNS=$(aws cloudformation describe-stacks \
        --stack-name "${ENVIRONMENT_NAME}-alb" \
        --region "$AWS_REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerDNS`].OutputValue' \
        --output text)

    info ""
    info "========================================"
    info "Deployment Complete!"
    info "========================================"
    info ""
    info "Application Load Balancer:"
    info "  URL: http://$ALB_DNS"
    info ""
    info "API Endpoints:"
    info "  Health: http://$ALB_DNS/api/health"
    info "  Robots: http://$ALB_DNS/api/robots"
    info "  Procedures: http://$ALB_DNS/api/procedures"
    info ""
    info "Data Ingestion:"
    info "  Health: http://$ALB_DNS/ingest/health"
    info "  Ingest: http://$ALB_DNS/ingest/telemetry"
    info ""
    info "Monitor services:"
    info "  ./check-services.sh"
}

main
