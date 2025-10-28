#!/bin/bash

# Medical Robotics Data Platform - Phase 4 Deployment Script
# Deploys Redshift cluster and ETL infrastructure

set -e

# Configuration
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-medrobotics}"
AWS_REGION="${AWS_REGION:-us-east-1}"
LAMBDA_CODE_BUCKET="${LAMBDA_CODE_BUCKET:-}"

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

# Check prerequisites
check_prerequisites() {
    header "Checking Prerequisites"

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI not found. Please install it first."
        exit 1
    fi

    # Check if Phase 2 is deployed
    if ! aws cloudformation describe-stacks \
        --stack-name ${ENVIRONMENT_NAME}-vpc \
        --region $AWS_REGION &> /dev/null; then
        error "Phase 2 infrastructure not found. Please deploy Phase 2 first."
        exit 1
    fi

    info "Prerequisites check passed"
    echo ""
}

# Package Lambda functions
package_lambda_functions() {
    header "Packaging Lambda Functions"

    cd etl-functions

    # Create deployment packages
    info "Creating RDS to Redshift ETL package..."
    mkdir -p build/rds_etl
    cp rds_to_redshift_etl.py build/rds_etl/
    pip install -r requirements.txt -t build/rds_etl/ --quiet
    cd build/rds_etl && zip -r ../../rds_to_redshift_etl.zip . > /dev/null && cd ../..

    info "Creating Telemetry ETL package..."
    mkdir -p build/telemetry_etl
    cp s3_telemetry_to_redshift.py build/telemetry_etl/
    pip install -r requirements.txt -t build/telemetry_etl/ --quiet
    cd build/telemetry_etl && zip -r ../../s3_telemetry_to_redshift.zip . > /dev/null && cd ../..

    cd ..
    info "Lambda packages created"
    echo ""
}

# Upload Lambda code to S3
upload_lambda_code() {
    header "Uploading Lambda Code to S3"

    # Use processed bucket from Phase 2
    if [ -z "$LAMBDA_CODE_BUCKET" ]; then
        LAMBDA_CODE_BUCKET=$(aws cloudformation describe-stacks \
            --stack-name ${ENVIRONMENT_NAME}-s3 \
            --region $AWS_REGION \
            --query 'Stacks[0].Outputs[?OutputKey==`ProcessedBucket`].OutputValue' \
            --output text)
    fi

    info "Using S3 bucket: $LAMBDA_CODE_BUCKET"

    # Upload Lambda packages
    aws s3 cp etl-functions/rds_to_redshift_etl.zip \
        s3://${LAMBDA_CODE_BUCKET}/lambda/rds_to_redshift_etl.zip \
        --region $AWS_REGION

    aws s3 cp etl-functions/s3_telemetry_to_redshift.zip \
        s3://${LAMBDA_CODE_BUCKET}/lambda/s3_telemetry_to_redshift.zip \
        --region $AWS_REGION

    info "Lambda code uploaded"
    echo ""
}

# Deploy Redshift cluster
deploy_redshift() {
    header "Step 1/3: Deploying Redshift Cluster"

    # Prompt for Redshift password
    echo -n "Enter Redshift master password (8-64 chars, alphanumeric only): "
    read -s REDSHIFT_PASSWORD
    echo ""

    if [ ${#REDSHIFT_PASSWORD} -lt 8 ] || [ ${#REDSHIFT_PASSWORD} -gt 64 ]; then
        error "Password must be 8-64 characters"
        exit 1
    fi

    info "Creating Redshift cluster stack..."
    aws cloudformation create-stack \
        --stack-name ${ENVIRONMENT_NAME}-redshift \
        --template-body file://cloudformation/01-redshift-cluster.yaml \
        --parameters \
            ParameterKey=EnvironmentName,ParameterValue=$ENVIRONMENT_NAME \
            ParameterKey=MasterUserPassword,ParameterValue=$REDSHIFT_PASSWORD \
            ParameterKey=NodeType,ParameterValue=dc2.large \
            ParameterKey=NumberOfNodes,ParameterValue=2 \
        --region $AWS_REGION \
        --capabilities CAPABILITY_NAMED_IAM

    info "Waiting for Redshift cluster stack to complete (this may take 10-15 minutes)..."
    aws cloudformation wait stack-create-complete \
        --stack-name ${ENVIRONMENT_NAME}-redshift \
        --region $AWS_REGION

    info "Redshift cluster deployed successfully"
    echo ""
}

# Deploy ETL Lambda functions
deploy_lambda() {
    header "Step 2/3: Deploying ETL Lambda Functions"

    info "Creating Lambda functions stack..."
    aws cloudformation create-stack \
        --stack-name ${ENVIRONMENT_NAME}-etl-lambda \
        --template-body file://cloudformation/02-etl-lambda.yaml \
        --parameters \
            ParameterKey=EnvironmentName,ParameterValue=$ENVIRONMENT_NAME \
            ParameterKey=LambdaCodeBucket,ParameterValue=$LAMBDA_CODE_BUCKET \
        --region $AWS_REGION \
        --capabilities CAPABILITY_NAMED_IAM

    info "Waiting for Lambda stack to complete..."
    aws cloudformation wait stack-create-complete \
        --stack-name ${ENVIRONMENT_NAME}-etl-lambda \
        --region $AWS_REGION

    info "Lambda functions deployed successfully"
    echo ""
}

# Deploy Step Functions
deploy_step_functions() {
    header "Step 3/3: Deploying Step Functions Workflow"

    info "Creating Step Functions stack..."
    aws cloudformation create-stack \
        --stack-name ${ENVIRONMENT_NAME}-step-functions \
        --template-body file://cloudformation/03-step-functions.yaml \
        --parameters \
            ParameterKey=EnvironmentName,ParameterValue=$ENVIRONMENT_NAME \
        --region $AWS_REGION \
        --capabilities CAPABILITY_NAMED_IAM

    info "Waiting for Step Functions stack to complete..."
    aws cloudformation wait stack-create-complete \
        --stack-name ${ENVIRONMENT_NAME}-step-functions \
        --region $AWS_REGION

    info "Step Functions deployed successfully"
    echo ""
}

# Initialize Redshift database
initialize_redshift() {
    header "Initializing Redshift Database"

    # Get Redshift endpoint
    REDSHIFT_ENDPOINT=$(aws cloudformation describe-stacks \
        --stack-name ${ENVIRONMENT_NAME}-redshift \
        --region $AWS_REGION \
        --query 'Stacks[0].Outputs[?OutputKey==`ClusterEndpoint`].OutputValue' \
        --output text)

    info "Redshift endpoint: $REDSHIFT_ENDPOINT"
    info ""
    info "To initialize the database, connect using:"
    echo "  psql -h $REDSHIFT_ENDPOINT -U dwadmin -d medrobotics_dw -p 5439"
    echo ""
    info "Then run the following SQL files in order:"
    echo "  1. sql-schemas/01-create-tables.sql"
    echo "  2. sql-schemas/02-populate-dimensions.sql"
    echo "  3. queries/01-create-views.sql"
    echo ""
    warn "Note: You must connect from a bastion host or configure security groups to allow access"
    echo ""
}

# Display deployment summary
deployment_summary() {
    header "Deployment Summary"

    # Get stack outputs
    REDSHIFT_ENDPOINT=$(aws cloudformation describe-stacks \
        --stack-name ${ENVIRONMENT_NAME}-redshift \
        --region $AWS_REGION \
        --query 'Stacks[0].Outputs[?OutputKey==`ClusterEndpoint`].OutputValue' \
        --output text)

    STATE_MACHINE_ARN=$(aws cloudformation describe-stacks \
        --stack-name ${ENVIRONMENT_NAME}-step-functions \
        --region $AWS_REGION \
        --query 'Stacks[0].Outputs[?OutputKey==`StateMachineArn`].OutputValue' \
        --output text)

    info "Phase 4 deployment completed successfully!"
    echo ""
    echo "Resources created:"
    echo "  - Redshift Cluster: ${ENVIRONMENT_NAME}-redshift"
    echo "  - Endpoint: $REDSHIFT_ENDPOINT:5439"
    echo "  - Database: medrobotics_dw"
    echo "  - RDS ETL Lambda: ${ENVIRONMENT_NAME}-rds-to-redshift-etl"
    echo "  - Telemetry ETL Lambda: ${ENVIRONMENT_NAME}-telemetry-etl"
    echo "  - Step Functions: ${ENVIRONMENT_NAME}-etl-orchestration"
    echo ""
    echo "Next steps:"
    echo "  1. Initialize Redshift database with SQL schemas"
    echo "  2. Test ETL pipeline: ./scripts/run-etl.sh"
    echo "  3. View sample queries: queries/02-sample-queries.sql"
    echo ""
    echo "Estimated monthly cost: ~\$180-220"
    echo "  - Redshift (2x dc2.large): ~\$180"
    echo "  - Lambda + Step Functions: ~\$10-40"
    echo ""
}

# Main execution
main() {
    echo ""
    header "Medical Robotics Data Platform - Phase 4"
    echo "Deploying Redshift Data Warehouse and ETL Pipeline"
    echo ""

    check_prerequisites
    package_lambda_functions
    upload_lambda_code
    deploy_redshift
    deploy_lambda
    deploy_step_functions
    initialize_redshift
    deployment_summary

    info "Deployment complete!"
}

# Run main function
main
