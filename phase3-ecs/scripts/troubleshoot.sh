#!/bin/bash

# Medical Robotics Data Platform - Troubleshooting Script
# Diagnose ECS service issues

set -e

ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-medrobotics}"
AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${ENVIRONMENT_NAME}-cluster"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "========================================"
echo "ECS Troubleshooting"
echo "========================================"
echo ""

# 1. Check if tasks are running
info "Step 1: Checking running tasks..."
RUNNING_TASKS=$(aws ecs list-tasks \
    --cluster $CLUSTER_NAME \
    --desired-status RUNNING \
    --region $AWS_REGION \
    --query 'taskArns' \
    --output text)

if [ -z "$RUNNING_TASKS" ]; then
    error "No running tasks found!"
    echo ""
    info "Checking stopped tasks for errors..."

    STOPPED_TASKS=$(aws ecs list-tasks \
        --cluster $CLUSTER_NAME \
        --desired-status STOPPED \
        --region $AWS_REGION \
        --query 'taskArns[0]' \
        --output text)

    if [ -n "$STOPPED_TASKS" ] && [ "$STOPPED_TASKS" != "None" ]; then
        echo ""
        warn "Found stopped tasks. Showing most recent failure:"
        aws ecs describe-tasks \
            --cluster $CLUSTER_NAME \
            --tasks $STOPPED_TASKS \
            --region $AWS_REGION \
            --query 'tasks[0].{StoppedReason:stoppedReason,Containers:containers[].{Name:name,Reason:reason,ExitCode:exitCode}}' \
            --output json
    fi
else
    info "Found running tasks"
    echo ""
    info "Task details:"
    aws ecs describe-tasks \
        --cluster $CLUSTER_NAME \
        --tasks $RUNNING_TASKS \
        --region $AWS_REGION \
        --query 'tasks[].{TaskArn:taskArn,LastStatus:lastStatus,HealthStatus:healthStatus,Containers:containers[].{Name:name,Status:lastStatus,Health:healthStatus}}' \
        --output json
fi

echo ""
echo "========================================"
info "Step 2: Checking service status..."
echo ""

# Check API Service
aws ecs describe-services \
    --cluster $CLUSTER_NAME \
    --services ${ENVIRONMENT_NAME}-api-service \
    --region $AWS_REGION \
    --query 'services[0].events[0:3]' \
    --output table

echo ""

# Check Data Ingestion Service
aws ecs describe-services \
    --cluster $CLUSTER_NAME \
    --services ${ENVIRONMENT_NAME}-data-ingestion \
    --region $AWS_REGION \
    --query 'services[0].events[0:3]' \
    --output table

echo ""
echo "========================================"
info "Step 3: Checking CloudWatch Logs..."
echo ""

info "Recent API Service logs:"
aws logs tail /aws/ecs/${ENVIRONMENT_NAME}/api-service \
    --since 10m \
    --format short \
    --region $AWS_REGION 2>/dev/null | head -20 || warn "No logs found yet"

echo ""
info "Recent Data Ingestion logs:"
aws logs tail /aws/ecs/${ENVIRONMENT_NAME}/data-ingestion \
    --since 10m \
    --format short \
    --region $AWS_REGION 2>/dev/null | head -20 || warn "No logs found yet"

echo ""
echo "========================================"
info "Step 4: Checking Target Health..."
echo ""

API_TG_ARN=$(aws cloudformation describe-stacks \
    --stack-name ${ENVIRONMENT_NAME}-alb \
    --region $AWS_REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`APITargetGroupArn`].OutputValue' \
    --output text)

aws elbv2 describe-target-health \
    --target-group-arn $API_TG_ARN \
    --region $AWS_REGION \
    --output table

echo ""
echo "========================================"
info "Common Issues & Solutions:"
echo ""
echo "1. Tasks failing to start:"
echo "   - Check if Docker images exist in ECR"
echo "   - Verify RDS_PASSWORD is correct"
echo "   - Check IAM role permissions"
echo ""
echo "2. Tasks running but unhealthy:"
echo "   - Check security groups allow ECS -> RDS traffic"
echo "   - Verify RDS endpoint is accessible"
echo "   - Check database exists and schema is created"
echo ""
echo "3. Target health check failing:"
echo "   - Tasks need 60s grace period to start"
echo "   - Check /health endpoints respond on correct ports"
echo "   - Verify ALB -> ECS security group rules"
echo ""
echo "To view live logs:"
echo "  aws logs tail /aws/ecs/${ENVIRONMENT_NAME}/api-service --follow"
echo "  aws logs tail /aws/ecs/${ENVIRONMENT_NAME}/data-ingestion --follow"
