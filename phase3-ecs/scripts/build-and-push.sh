#!/bin/bash

# Medical Robotics Data Platform - Build and Push Docker Images
# Builds Docker images and pushes them to ECR

set -e

# Configuration
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-medrobotics}"
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

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

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SERVICES_DIR="$SCRIPT_DIR/../services"

info "========================================"
info "Docker Image Build & Push"
info "========================================"
info "Environment: $ENVIRONMENT_NAME"
info "Region: $AWS_REGION"
info "Account: $AWS_ACCOUNT_ID"
info ""

# Authenticate with ECR
info "Authenticating with ECR..."
aws ecr get-login-password --region $AWS_REGION | \
    docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Create ECR repositories if they don't exist
create_ecr_repo() {
    local REPO_NAME=$1
    info "Checking ECR repository: $REPO_NAME"

    if ! aws ecr describe-repositories --repository-names $REPO_NAME --region $AWS_REGION &> /dev/null; then
        info "Creating ECR repository: $REPO_NAME"
        aws ecr create-repository \
            --repository-name $REPO_NAME \
            --region $AWS_REGION \
            --image-scanning-configuration scanOnPush=true \
            --encryption-configuration encryptionType=AES256
    else
        info "Repository $REPO_NAME already exists"
    fi
}

# Build and push service
build_and_push() {
    local SERVICE_NAME=$1
    local SERVICE_DIR=$2
    local REPO_NAME="${ENVIRONMENT_NAME}-${SERVICE_NAME}"
    local IMAGE_TAG="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${REPO_NAME}:latest"

    info ""
    info "Building $SERVICE_NAME..."

    # Create ECR repo
    create_ecr_repo $REPO_NAME

    # Build Docker image
    info "Building Docker image..."
    docker build -t $REPO_NAME:latest $SERVICE_DIR

    # Tag image
    docker tag $REPO_NAME:latest $IMAGE_TAG

    # Push to ECR
    info "Pushing image to ECR..."
    docker push $IMAGE_TAG

    info "✓ $SERVICE_NAME built and pushed successfully"
    info "  Image: $IMAGE_TAG"
}

# Build services
build_and_push "data-ingestion" "$SERVICES_DIR/data-ingestion"
build_and_push "api-service" "$SERVICES_DIR/api-service"

info ""
info "========================================"
info "Build Complete!"
info "========================================"
info ""
info "Images pushed to ECR:"
info "  - ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ENVIRONMENT_NAME}-data-ingestion:latest"
info "  - ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ENVIRONMENT_NAME}-api-service:latest"
info ""
info "Next steps:"
info "1. Deploy ECS infrastructure: ./deploy-ecs.sh"
info "2. Verify services: ./check-services.sh"
