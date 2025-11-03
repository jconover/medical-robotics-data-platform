#!/bin/bash

# Medical Robotics Data Platform - Cleanup Verification Script
# Checks for any remaining resources after cleanup

ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-medrobotics}"
AWS_REGION="${AWS_REGION:-us-east-1}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }
header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

header "Cleanup Verification"
echo "Environment: $ENVIRONMENT_NAME"
echo "Region: $AWS_REGION"
echo ""

ISSUES_FOUND=0

# ==========================================
# Check CloudFormation stacks
# ==========================================
echo "=== CloudFormation Stacks ==="
STACKS=$(aws cloudformation list-stacks \
    --region "$AWS_REGION" \
    --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE ROLLBACK_COMPLETE UPDATE_ROLLBACK_COMPLETE \
    --query "StackSummaries[?contains(StackName, '${ENVIRONMENT_NAME}')].{Name:StackName,Status:StackStatus}" \
    --output text 2>/dev/null || true)

if [ -z "$STACKS" ]; then
    info "No active stacks found"
else
    error "Found active stacks:"
    echo "$STACKS" | while read -r line; do
        echo "  $line"
    done
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi
echo ""

# ==========================================
# Check S3 buckets
# ==========================================
echo "=== S3 Buckets ==="
BUCKETS=$(aws s3 ls --region "$AWS_REGION" 2>/dev/null | grep "$ENVIRONMENT_NAME" || true)
if [ -z "$BUCKETS" ]; then
    info "No buckets found"
else
    error "Found buckets:"
    echo "$BUCKETS" | while read -r line; do
        echo "  $line"
    done
    echo ""
    echo "  To delete manually:"
    echo "$BUCKETS" | awk '{print "  aws s3 rb s3://"$3" --force"}'
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi
echo ""

# ==========================================
# Check ECR repositories
# ==========================================
echo "=== ECR Repositories ==="
REPOS=$(aws ecr describe-repositories \
    --region "$AWS_REGION" \
    --query "repositories[?contains(repositoryName, '${ENVIRONMENT_NAME}')].{Name:repositoryName,URI:repositoryUri}" \
    --output text 2>/dev/null || true)
if [ -z "$REPOS" ]; then
    info "No repositories found"
else
    error "Found repositories:"
    echo "$REPOS" | while read -r line; do
        echo "  $line"
    done
    echo ""
    echo "  To delete manually:"
    echo "$REPOS" | awk '{print "  aws ecr delete-repository --repository-name "$1" --force --region '"$AWS_REGION"'"}'
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi
echo ""

# ==========================================
# Check RDS instances
# ==========================================
echo "=== RDS Instances ==="
RDS_INSTANCES=$(aws rds describe-db-instances \
    --region "$AWS_REGION" \
    --query "DBInstances[?contains(DBInstanceIdentifier, '${ENVIRONMENT_NAME}')].{ID:DBInstanceIdentifier,Status:DBInstanceStatus}" \
    --output text 2>/dev/null || true)
if [ -z "$RDS_INSTANCES" ]; then
    info "No RDS instances found"
else
    error "Found RDS instances:"
    echo "$RDS_INSTANCES" | while read -r line; do
        echo "  $line"
    done
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi
echo ""

# ==========================================
# Check Redshift clusters
# ==========================================
echo "=== Redshift Clusters ==="
REDSHIFT_CLUSTERS=$(aws redshift describe-clusters \
    --region "$AWS_REGION" \
    --query "Clusters[?contains(ClusterIdentifier, '${ENVIRONMENT_NAME}')].{ID:ClusterIdentifier,Status:ClusterStatus}" \
    --output text 2>/dev/null || true)
if [ -z "$REDSHIFT_CLUSTERS" ]; then
    info "No Redshift clusters found"
else
    error "Found Redshift clusters:"
    echo "$REDSHIFT_CLUSTERS" | while read -r line; do
        echo "  $line"
    done
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi
echo ""

# ==========================================
# Check Redshift snapshots
# ==========================================
echo "=== Redshift Snapshots ==="
SNAPSHOTS=$(aws redshift describe-cluster-snapshots \
    --region "$AWS_REGION" \
    --query "Snapshots[?contains(SnapshotIdentifier, '${ENVIRONMENT_NAME}')].{ID:SnapshotIdentifier,Status:Status,Type:SnapshotType}" \
    --output text 2>/dev/null || true)
if [ -z "$SNAPSHOTS" ]; then
    info "No snapshots found"
else
    warn "Found snapshots (these may be intentional backups):"
    echo "$SNAPSHOTS" | while read -r line; do
        echo "  $line"
    done
    echo ""
    echo "  To delete manually:"
    echo "$SNAPSHOTS" | awk '{print "  aws redshift delete-cluster-snapshot --snapshot-identifier "$1" --region '"$AWS_REGION"'"}'
    # Don't count as error since snapshots might be intentional
fi
echo ""

# ==========================================
# Check ECS clusters
# ==========================================
echo "=== ECS Clusters ==="
ECS_CLUSTERS=$(aws ecs list-clusters \
    --region "$AWS_REGION" \
    --query "clusterArns[?contains(@, '${ENVIRONMENT_NAME}')]" \
    --output text 2>/dev/null || true)
if [ -z "$ECS_CLUSTERS" ]; then
    info "No ECS clusters found"
else
    error "Found ECS clusters:"
    echo "$ECS_CLUSTERS" | while read -r line; do
        echo "  $line"
    done
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi
echo ""

# ==========================================
# Check Lambda functions
# ==========================================
echo "=== Lambda Functions ==="
LAMBDAS=$(aws lambda list-functions \
    --region "$AWS_REGION" \
    --query "Functions[?contains(FunctionName, '${ENVIRONMENT_NAME}')].{Name:FunctionName,Runtime:Runtime}" \
    --output text 2>/dev/null || true)
if [ -z "$LAMBDAS" ]; then
    info "No Lambda functions found"
else
    error "Found Lambda functions:"
    echo "$LAMBDAS" | while read -r line; do
        echo "  $line"
    done
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi
echo ""

# ==========================================
# Check ALBs
# ==========================================
echo "=== Application Load Balancers ==="
ALBS=$(aws elbv2 describe-load-balancers \
    --region "$AWS_REGION" \
    --query "LoadBalancers[?contains(LoadBalancerName, '${ENVIRONMENT_NAME}')].{Name:LoadBalancerName,State:State.Code}" \
    --output text 2>/dev/null || true)
if [ -z "$ALBS" ]; then
    info "No ALBs found"
else
    error "Found ALBs:"
    echo "$ALBS" | while read -r line; do
        echo "  $line"
    done
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi
echo ""

# ==========================================
# Check Secrets Manager
# ==========================================
echo "=== Secrets Manager Secrets ==="
SECRETS=$(aws secretsmanager list-secrets \
    --region "$AWS_REGION" \
    --query "SecretList[?contains(Name, '${ENVIRONMENT_NAME}')].{Name:Name,Status:DeletedDate}" \
    --output text 2>/dev/null || true)
if [ -z "$SECRETS" ]; then
    info "No secrets found"
else
    warn "Found secrets (these may be in pending deletion):"
    echo "$SECRETS" | while read -r line; do
        echo "  $line"
    done
    # Don't count as error since secrets have recovery period
fi
echo ""

# ==========================================
# Summary
# ==========================================
header "Verification Summary"
echo ""

if [ $ISSUES_FOUND -eq 0 ]; then
    echo -e "${GREEN}✓ CLEANUP VERIFIED${NC}"
    echo ""
    info "No active resources found for environment: $ENVIRONMENT_NAME"
    echo ""
else
    echo -e "${RED}✗ ISSUES FOUND${NC}"
    echo ""
    error "Found $ISSUES_FOUND categories of resources that need cleanup"
    echo ""
    echo "Run the cleanup commands shown above, or re-run:"
    echo "  ./scripts/cleanup-all-phases.sh"
    echo ""
    exit 1
fi
