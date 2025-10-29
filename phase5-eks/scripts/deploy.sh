#!/bin/bash

# Medical Robotics Data Platform - Phase 5 Deployment Script
# Deploys EKS cluster and Kubernetes resources

set -e

# Configuration
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-medrobotics}"
AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${ENVIRONMENT_NAME}-cluster"

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

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        error "kubectl not found. Please install it first."
        exit 1
    fi

    # Check helm
    if ! command -v helm &> /dev/null; then
        error "Helm not found. Please install it first."
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

# Deploy EKS Cluster
deploy_eks_cluster() {
    header "Step 1/6: Deploying EKS Cluster"

    info "Creating EKS cluster stack (this will take 15-20 minutes)..."
    aws cloudformation create-stack \
        --stack-name ${ENVIRONMENT_NAME}-eks \
        --template-body file://cloudformation/01-eks-cluster.yaml \
        --parameters \
            ParameterKey=EnvironmentName,ParameterValue=$ENVIRONMENT_NAME \
            ParameterKey=KubernetesVersion,ParameterValue=1.28 \
            ParameterKey=NodeInstanceType,ParameterValue=t3.medium \
            ParameterKey=NodeGroupDesiredSize,ParameterValue=3 \
        --region $AWS_REGION \
        --capabilities CAPABILITY_NAMED_IAM

    info "Waiting for EKS cluster stack to complete..."
    aws cloudformation wait stack-create-complete \
        --stack-name ${ENVIRONMENT_NAME}-eks \
        --region $AWS_REGION

    info "EKS cluster deployed successfully"
    echo ""
}

# Configure kubectl
configure_kubectl() {
    header "Step 2/6: Configuring kubectl"

    info "Updating kubeconfig..."
    aws eks update-kubeconfig \
        --name $CLUSTER_NAME \
        --region $AWS_REGION

    info "Verifying cluster access..."
    kubectl cluster-info
    kubectl get nodes

    info "kubectl configured successfully"
    echo ""
}

# Install AWS Load Balancer Controller
install_alb_controller() {
    header "Step 3/6: Installing AWS Load Balancer Controller"

    # Get OIDC provider
    OIDC_PROVIDER=$(aws eks describe-cluster \
        --name $CLUSTER_NAME \
        --region $AWS_REGION \
        --query 'cluster.identity.oidc.issuer' \
        --output text | sed 's|https://||')

    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

    info "Creating IAM policy for ALB controller..."
    curl -o iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.0/docs/install/iam_policy.json

    aws iam create-policy \
        --policy-name AWSLoadBalancerControllerIAMPolicy \
        --policy-document file://iam-policy.json \
        --region $AWS_REGION 2>/dev/null || info "IAM policy already exists"

    rm iam-policy.json

    info "Creating service account..."
    eksctl create iamserviceaccount \
        --cluster=$CLUSTER_NAME \
        --namespace=kube-system \
        --name=aws-load-balancer-controller \
        --attach-policy-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
        --override-existing-serviceaccounts \
        --region $AWS_REGION \
        --approve || warn "Service account may already exist"

    info "Installing ALB controller via Helm..."
    helm repo add eks https://aws.github.io/eks-charts
    helm repo update

    helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
        -n kube-system \
        --set clusterName=$CLUSTER_NAME \
        --set serviceAccount.create=false \
        --set serviceAccount.name=aws-load-balancer-controller \
        --set region=$AWS_REGION \
        --set vpcId=$(aws cloudformation describe-stacks \
            --stack-name ${ENVIRONMENT_NAME}-vpc \
            --query 'Stacks[0].Outputs[?OutputKey==`VpcId`].OutputValue' \
            --output text \
            --region $AWS_REGION) \
        --wait || warn "ALB controller may already be installed"

    info "ALB controller installed"
    echo ""
}

# Deploy application resources
deploy_applications() {
    header "Step 4/6: Deploying Applications"

    # Get RDS endpoint and S3 bucket
    RDS_ENDPOINT=$(aws cloudformation describe-stacks \
        --stack-name ${ENVIRONMENT_NAME}-rds \
        --query 'Stacks[0].Outputs[?OutputKey==`DBEndpoint`].OutputValue' \
        --output text \
        --region $AWS_REGION)

    S3_RAW_BUCKET=$(aws cloudformation describe-stacks \
        --stack-name ${ENVIRONMENT_NAME}-s3 \
        --query 'Stacks[0].Outputs[?OutputKey==`RawBucket`].OutputValue' \
        --output text \
        --region $AWS_REGION)

    RDS_SECRET_ARN=$(aws cloudformation describe-stacks \
        --stack-name ${ENVIRONMENT_NAME}-rds \
        --query 'Stacks[0].Outputs[?OutputKey==`DBSecretArn`].OutputValue' \
        --output text \
        --region $AWS_REGION)

    # Get RDS password from Secrets Manager
    RDS_PASSWORD=$(aws secretsmanager get-secret-value \
        --secret-id $RDS_SECRET_ARN \
        --query SecretString \
        --output text \
        --region $AWS_REGION | jq -r '.password')

    info "Creating namespace..."
    kubectl apply -f kubernetes/manifests/namespace.yaml

    info "Creating service account and RBAC..."
    kubectl apply -f kubernetes/manifests/serviceaccount.yaml

    info "Creating ConfigMap with environment variables..."
    kubectl create configmap app-config \
        --from-literal=RDS_HOST=$RDS_ENDPOINT \
        --from-literal=RDS_PORT=5432 \
        --from-literal=RDS_DBNAME=medrobotics \
        --from-literal=RDS_USER=dbadmin \
        --from-literal=S3_RAW_BUCKET=$S3_RAW_BUCKET \
        --namespace=medrobotics \
        --dry-run=client -o yaml | kubectl apply -f -

    info "Creating Secret with RDS password..."
    kubectl create secret generic rds-credentials \
        --from-literal=password=$RDS_PASSWORD \
        --namespace=medrobotics \
        --dry-run=client -o yaml | kubectl apply -f -

    info "Deploying Data Ingestion service..."
    kubectl apply -f kubernetes/manifests/data-ingestion-deployment.yaml

    info "Deploying API service..."
    kubectl apply -f kubernetes/manifests/api-service-deployment.yaml

    info "Creating Ingress..."
    kubectl apply -f kubernetes/manifests/ingress.yaml

    info "Creating Horizontal Pod Autoscalers..."
    kubectl apply -f kubernetes/manifests/hpa.yaml

    info "Waiting for deployments to be ready..."
    kubectl wait --for=condition=available --timeout=300s \
        deployment/data-ingestion -n medrobotics
    kubectl wait --for=condition=available --timeout=300s \
        deployment/api-service -n medrobotics

    info "Applications deployed successfully"
    echo ""
}

# Install monitoring
install_monitoring() {
    header "Step 5/6: Installing Monitoring Stack"

    info "Adding Prometheus Helm repository..."
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update

    info "Installing Prometheus + Grafana..."
    helm install prometheus prometheus-community/kube-prometheus-stack \
        -n monitoring \
        --create-namespace \
        -f kubernetes/monitoring/prometheus-values.yaml \
        --wait || warn "Monitoring stack may already be installed"

    info "Applying ServiceMonitors..."
    kubectl apply -f kubernetes/monitoring/servicemonitor.yaml

    info "Monitoring stack installed"
    echo ""
}

# Display summary
deployment_summary() {
    header "Step 6/6: Deployment Summary"

    # Get ALB DNS
    ALB_DNS=$(kubectl get ingress medrobotics-ingress -n medrobotics \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Pending...")

    # Get Grafana service
    GRAFANA_PORT=$(kubectl get svc prometheus-grafana -n monitoring \
        -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "N/A")

    info "Phase 5 deployment completed successfully!"
    echo ""
    echo "EKS Cluster:"
    echo "  Cluster Name: $CLUSTER_NAME"
    echo "  Region: $AWS_REGION"
    echo "  Nodes: $(kubectl get nodes --no-headers | wc -l)"
    echo ""
    echo "Applications:"
    echo "  API Service URL: http://$ALB_DNS/api/health"
    echo "  Ingestion Service URL: http://$ALB_DNS/ingest/health"
    echo ""
    echo "Monitoring:"
    echo "  Grafana: kubectl port-forward svc/prometheus-grafana -n monitoring 3000:$GRAFANA_PORT"
    echo "  Grafana URL: http://localhost:3000 (admin/changeme)"
    echo ""
    echo "Useful Commands:"
    echo "  kubectl get pods -n medrobotics"
    echo "  kubectl logs -f deployment/api-service -n medrobotics"
    echo "  kubectl logs -f deployment/data-ingestion -n medrobotics"
    echo "  kubectl get hpa -n medrobotics"
    echo ""
    echo "Estimated monthly cost: ~\$250-300"
    echo "  - EKS Control Plane: ~\$73"
    echo "  - EC2 Nodes (3x t3.medium): ~\$100"
    echo "  - ALB: ~\$20"
    echo "  - Data Transfer: ~\$20-50"
    echo "  - EBS Volumes: ~\$20"
    echo ""
}

# Main execution
main() {
    echo ""
    header "Medical Robotics Data Platform - Phase 5"
    echo "Deploying EKS Cluster and Kubernetes Resources"
    echo ""

    check_prerequisites
    deploy_eks_cluster
    configure_kubectl
    install_alb_controller
    deploy_applications
    install_monitoring
    deployment_summary

    info "Deployment complete!"
}

# Run main function
main
