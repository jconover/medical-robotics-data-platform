#!/bin/bash

# Medical Robotics Data Platform - Phase 5 Cleanup Script
# Tears down EKS cluster and all resources

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

echo ""
header "Medical Robotics Data Platform - Phase 5 Cleanup"
echo ""

warn "This will delete:"
echo "  - EKS cluster and all workloads"
echo "  - Load balancers and network resources"
echo "  - Monitoring stack"
echo "  - CloudWatch logs"
echo ""

read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    info "Cleanup cancelled"
    exit 0
fi

echo ""

# Delete monitoring stack
header "Step 1/5: Deleting Monitoring Stack"

if kubectl get namespace monitoring &> /dev/null; then
    info "Uninstalling Prometheus/Grafana..."
    helm uninstall prometheus -n monitoring 2>/dev/null || warn "Prometheus not found"

    info "Deleting monitoring namespace..."
    kubectl delete namespace monitoring --ignore-not-found=true
else
    warn "Monitoring namespace not found"
fi

echo ""

# Delete application resources
header "Step 2/5: Deleting Applications"

if kubectl get namespace medrobotics &> /dev/null; then
    info "Deleting Ingress (this will remove ALB)..."
    kubectl delete ingress --all -n medrobotics --ignore-not-found=true

    info "Waiting for ALB to be deleted (this may take a few minutes)..."
    sleep 60  # Give AWS time to delete the ALB

    info "Deleting application deployments..."
    kubectl delete deployment --all -n medrobotics --ignore-not-found=true

    info "Deleting services..."
    kubectl delete service --all -n medrobotics --ignore-not-found=true

    info "Deleting HPAs..."
    kubectl delete hpa --all -n medrobotics --ignore-not-found=true

    info "Deleting ConfigMaps and Secrets..."
    kubectl delete configmap --all -n medrobotics --ignore-not-found=true
    kubectl delete secret --all -n medrobotics --ignore-not-found=true

    info "Deleting namespace..."
    kubectl delete namespace medrobotics --ignore-not-found=true
else
    warn "Application namespace not found"
fi

echo ""

# Delete ALB Controller
header "Step 3/5: Deleting AWS Load Balancer Controller"

if helm list -n kube-system | grep -q aws-load-balancer-controller; then
    info "Uninstalling ALB controller..."
    helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || warn "ALB controller not found"
else
    warn "ALB controller not installed"
fi

# Delete IAM service account
info "Deleting IAM service account..."
eksctl delete iamserviceaccount \
    --cluster=$CLUSTER_NAME \
    --namespace=kube-system \
    --name=aws-load-balancer-controller \
    --region $AWS_REGION 2>/dev/null || warn "Service account not found"

echo ""

# Delete EKS Cluster
header "Step 4/5: Deleting EKS Cluster"

if aws cloudformation describe-stacks \
    --stack-name ${ENVIRONMENT_NAME}-eks \
    --region $AWS_REGION &> /dev/null; then

    warn "Deleting EKS cluster (this may take 10-15 minutes)..."

    aws cloudformation delete-stack \
        --stack-name ${ENVIRONMENT_NAME}-eks \
        --region $AWS_REGION

    info "Waiting for stack deletion..."
    aws cloudformation wait stack-delete-complete \
        --stack-name ${ENVIRONMENT_NAME}-eks \
        --region $AWS_REGION

    info "EKS cluster deleted"
else
    warn "EKS stack not found"
fi

echo ""

# Clean up IAM policies
header "Step 5/5: Cleaning Up IAM Policies"

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

if aws iam get-policy \
    --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
    --region $AWS_REGION &> /dev/null; then

    info "Deleting ALB controller IAM policy..."

    # Detach policy from all roles first
    ATTACHED_ROLES=$(aws iam list-entities-for-policy \
        --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
        --query 'PolicyRoles[].RoleName' \
        --output text \
        --region $AWS_REGION)

    for role in $ATTACHED_ROLES; do
        info "Detaching policy from role: $role"
        aws iam detach-role-policy \
            --role-name $role \
            --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
            --region $AWS_REGION 2>/dev/null || true
    done

    # Delete policy versions
    VERSIONS=$(aws iam list-policy-versions \
        --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
        --query 'Versions[?!IsDefaultVersion].VersionId' \
        --output text \
        --region $AWS_REGION)

    for version in $VERSIONS; do
        aws iam delete-policy-version \
            --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
            --version-id $version \
            --region $AWS_REGION 2>/dev/null || true
    done

    # Delete policy
    aws iam delete-policy \
        --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
        --region $AWS_REGION 2>/dev/null || warn "Could not delete IAM policy"
else
    warn "ALB controller IAM policy not found"
fi

echo ""

# Delete CloudWatch Log Groups
info "Cleaning up CloudWatch logs..."
aws logs delete-log-group \
    --log-group-name /aws/eks/${ENVIRONMENT_NAME}-cluster/cluster \
    --region $AWS_REGION 2>/dev/null || warn "Log group not found"

echo ""

# Remove kubectl context
info "Removing kubectl context..."
kubectl config delete-context arn:aws:eks:${AWS_REGION}:${AWS_ACCOUNT_ID}:cluster/${CLUSTER_NAME} 2>/dev/null || warn "Context not found"
kubectl config delete-cluster arn:aws:eks:${AWS_REGION}:${AWS_ACCOUNT_ID}:cluster/${CLUSTER_NAME} 2>/dev/null || warn "Cluster config not found"

# Summary
header "Cleanup Complete"
echo ""
info "All Phase 5 resources have been deleted"
echo ""
warn "Note: The following may need manual cleanup:"
echo "  - Any orphaned ENIs in VPC"
echo "  - Any remaining CloudWatch log groups"
echo "  - ECR images (if created)"
echo ""
info "To check for orphaned resources:"
echo "  aws ec2 describe-network-interfaces --filters Name=vpc-id,Values=<vpc-id> --region $AWS_REGION"
echo "  aws logs describe-log-groups --region $AWS_REGION"
echo ""
