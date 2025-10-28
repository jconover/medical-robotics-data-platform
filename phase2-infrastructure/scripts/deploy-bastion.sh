#!/bin/bash

# Quick Bastion Host Deployment Script
# Deploys a bastion host for accessing RDS in private subnets

set -e

# Configuration
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-medrobotics}"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CF_DIR="$SCRIPT_DIR/../cloudformation"

info "========================================"
info "Bastion Host Deployment"
info "========================================"
info ""
info "Environment: $ENVIRONMENT_NAME"
info "Region: $AWS_REGION"
info ""

# Check if bastion already exists
if aws cloudformation describe-stacks --stack-name "${ENVIRONMENT_NAME}-bastion" --region "$AWS_REGION" &> /dev/null; then
    warn "Bastion host already exists. This will update it."
    read -p "Continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Aborted."
        exit 0
    fi
fi

info "Deploying bastion host..."
aws cloudformation create-stack \
  --stack-name "${ENVIRONMENT_NAME}-bastion" \
  --template-body "file://$CF_DIR/06-bastion-host.yaml" \
  --parameters ParameterKey=EnvironmentName,ParameterValue="$ENVIRONMENT_NAME" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region "$AWS_REGION" 2>/dev/null || \
aws cloudformation update-stack \
  --stack-name "${ENVIRONMENT_NAME}-bastion" \
  --template-body "file://$CF_DIR/06-bastion-host.yaml" \
  --parameters ParameterKey=EnvironmentName,ParameterValue="$ENVIRONMENT_NAME" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region "$AWS_REGION" 2>/dev/null || warn "No updates needed"

info "Waiting for deployment to complete (this may take 3-5 minutes)..."
aws cloudformation wait stack-create-complete \
  --stack-name "${ENVIRONMENT_NAME}-bastion" \
  --region "$AWS_REGION" 2>/dev/null || \
aws cloudformation wait stack-update-complete \
  --stack-name "${ENVIRONMENT_NAME}-bastion" \
  --region "$AWS_REGION" 2>/dev/null || true

# Get outputs
info ""
info "========================================"
info "Deployment Complete!"
info "========================================"
info ""

BASTION_ID=$(aws cloudformation describe-stacks \
  --stack-name "${ENVIRONMENT_NAME}-bastion" \
  --region "$AWS_REGION" \
  --query 'Stacks[0].Outputs[?OutputKey==`BastionInstanceId`].OutputValue' \
  --output text 2>/dev/null || echo "")

BASTION_IP=$(aws cloudformation describe-stacks \
  --stack-name "${ENVIRONMENT_NAME}-bastion" \
  --region "$AWS_REGION" \
  --query 'Stacks[0].Outputs[?OutputKey==`BastionElasticIP`].OutputValue' \
  --output text 2>/dev/null || echo "")

if [ -n "$BASTION_ID" ]; then
    info "Bastion Instance ID: $BASTION_ID"
    info "Bastion IP Address: $BASTION_IP"
    info ""
    info "Connect to bastion using AWS Systems Manager:"
    info "  aws ssm start-session --target $BASTION_ID --region $AWS_REGION"
    info ""
    info "Once connected, use these helper scripts:"
    info "  ./connect-to-rds.sh         - Interactive PostgreSQL connection"
    info "  ./setup-schema.sh <file>    - Run SQL schema file"
    info ""
    info "To upload SQL files from your local machine:"
    info "  # Option 1: Via S3 temporary storage"
    info "  aws s3 cp ../sql-schemas/01-create-tables.sql s3://YOUR_BUCKET/temp/"
    info "  # Then download from bastion: aws s3 cp s3://YOUR_BUCKET/temp/01-create-tables.sql /tmp/"
    info ""
    info "  # Option 2: Via SSM port forwarding (advanced)"
    info "  aws ssm start-session --target $BASTION_ID \\"
    info "    --document-name AWS-StartPortForwardingSessionToRemoteHost \\"
    info "    --parameters '{\"host\":[\"YOUR_RDS_ENDPOINT\"],\"portNumber\":[\"5432\"],\"localPortNumber\":[\"5433\"]}'"
    info ""
    info "See BASTION-QUICKSTART.md for detailed instructions."
else
    warn "Could not retrieve bastion information. Check CloudFormation console."
fi

info ""
info "Cost: ~\$0.01/hour (~\$7.50/month for t3.micro)"
info "Stop when not in use: aws ec2 stop-instances --instance-ids $BASTION_ID"
info "Delete when done: aws cloudformation delete-stack --stack-name ${ENVIRONMENT_NAME}-bastion"
