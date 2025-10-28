#!/bin/bash

# Medical Robotics Data Platform - Check ECS Services Status
# Displays status of ECS services, tasks, and health checks

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

# Get cluster name
CLUSTER_NAME="${ENVIRONMENT_NAME}-cluster"

# Check if cluster exists
if ! aws ecs describe-clusters --clusters $CLUSTER_NAME --region $AWS_REGION &> /dev/null; then
    error "ECS cluster $CLUSTER_NAME not found"
    exit 1
fi

header "ECS Services Status"
echo ""

# Check Data Ingestion Service
info "Data Ingestion Service"
echo "----------------------------"
aws ecs describe-services \
    --cluster $CLUSTER_NAME \
    --services ${ENVIRONMENT_NAME}-data-ingestion \
    --region $AWS_REGION \
    --query 'services[0].{Status:status,DesiredCount:desiredCount,RunningCount:runningCount,PendingCount:pendingCount}' \
    --output table 2>/dev/null || warn "Service not found"

echo ""

# Check API Service
info "API Service"
echo "----------------------------"
aws ecs describe-services \
    --cluster $CLUSTER_NAME \
    --services ${ENVIRONMENT_NAME}-api-service \
    --region $AWS_REGION \
    --query 'services[0].{Status:status,DesiredCount:desiredCount,RunningCount:runningCount,PendingCount:pendingCount}' \
    --output table 2>/dev/null || warn "Service not found"

echo ""
header "Running Tasks"
echo ""

# List all running tasks
RUNNING_TASKS=$(aws ecs list-tasks \
    --cluster $CLUSTER_NAME \
    --desired-status RUNNING \
    --region $AWS_REGION \
    --query 'taskArns' \
    --output text)

if [ -z "$RUNNING_TASKS" ]; then
    warn "No running tasks found"
else
    TASK_COUNT=$(echo "$RUNNING_TASKS" | wc -w)
    info "Total running tasks: $TASK_COUNT"
    echo ""

    # Get task details
    aws ecs describe-tasks \
        --cluster $CLUSTER_NAME \
        --tasks $RUNNING_TASKS \
        --region $AWS_REGION \
        --query 'tasks[].{TaskId:taskArn,Status:lastStatus,Health:healthStatus,StartedAt:startedAt}' \
        --output table
fi

echo ""
header "Target Group Health"
echo ""

# Get target groups
API_TG_ARN=$(aws cloudformation describe-stacks \
    --stack-name ${ENVIRONMENT_NAME}-alb \
    --region $AWS_REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`APITargetGroupArn`].OutputValue' \
    --output text 2>/dev/null)

INGESTION_TG_ARN=$(aws cloudformation describe-stacks \
    --stack-name ${ENVIRONMENT_NAME}-alb \
    --region $AWS_REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`DataIngestionTargetGroupArn`].OutputValue' \
    --output text 2>/dev/null)

if [ -n "$API_TG_ARN" ]; then
    info "API Target Group Health"
    aws elbv2 describe-target-health \
        --target-group-arn $API_TG_ARN \
        --region $AWS_REGION \
        --query 'TargetHealthDescriptions[].{Target:Target.Id,Port:Target.Port,Health:TargetHealth.State,Reason:TargetHealth.Reason}' \
        --output table 2>/dev/null || warn "No targets registered"
    echo ""
fi

if [ -n "$INGESTION_TG_ARN" ]; then
    info "Data Ingestion Target Group Health"
    aws elbv2 describe-target-health \
        --target-group-arn $INGESTION_TG_ARN \
        --region $AWS_REGION \
        --query 'TargetHealthDescriptions[].{Target:Target.Id,Port:Target.Port,Health:TargetHealth.State,Reason:TargetHealth.Reason}' \
        --output table 2>/dev/null || warn "No targets registered"
    echo ""
fi

# Get ALB URL
ALB_DNS=$(aws cloudformation describe-stacks \
    --stack-name ${ENVIRONMENT_NAME}-alb \
    --region $AWS_REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerDNS`].OutputValue' \
    --output text 2>/dev/null)

if [ -n "$ALB_DNS" ]; then
    echo ""
    header "Load Balancer"
    echo ""
    info "ALB URL: http://$ALB_DNS"
    echo ""
    info "Testing endpoints..."

    # Test API health
    echo -n "  API Health: "
    if curl -s -o /dev/null -w "%{http_code}" "http://$ALB_DNS/api/health" | grep -q "200"; then
        echo -e "${GREEN}✓ Healthy${NC}"
    else
        echo -e "${RED}✗ Unhealthy${NC}"
    fi

    # Test Ingestion health
    echo -n "  Ingestion Health: "
    if curl -s -o /dev/null -w "%{http_code}" "http://$ALB_DNS/ingest/health" | grep -q "200"; then
        echo -e "${GREEN}✓ Healthy${NC}"
    else
        echo -e "${RED}✗ Unhealthy${NC}"
    fi
fi

echo ""
header "Recent Events"
echo ""

# Get recent service events for API service
info "API Service Events (last 5)"
aws ecs describe-services \
    --cluster $CLUSTER_NAME \
    --services ${ENVIRONMENT_NAME}-api-service \
    --region $AWS_REGION \
    --query 'services[0].events[:5].{Time:createdAt,Message:message}' \
    --output table 2>/dev/null || warn "No events found"

echo ""

# Get recent service events for Data Ingestion
info "Data Ingestion Service Events (last 5)"
aws ecs describe-services \
    --cluster $CLUSTER_NAME \
    --services ${ENVIRONMENT_NAME}-data-ingestion \
    --region $AWS_REGION \
    --query 'services[0].events[:5].{Time:createdAt,Message:message}' \
    --output table 2>/dev/null || warn "No events found"

echo ""
header "CloudWatch Logs"
echo ""
info "View logs with:"
echo "  aws logs tail /aws/ecs/${ENVIRONMENT_NAME}/api-service --follow"
echo "  aws logs tail /aws/ecs/${ENVIRONMENT_NAME}/data-ingestion --follow"

echo ""
info "Check complete!"
