#!/bin/bash

# Medical Robotics Data Platform - Manual ETL Execution
# Trigger ETL pipeline manually via Step Functions

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

# Get command line arguments
ETL_TYPE="${1:-full}"
START_DATE="${2:-$(date -d 'yesterday' '+%Y-%m-%d')}"
END_DATE="${3:-$(date '+%Y-%m-%d')}"
BATCH_DATE="${4:-$(date '+%Y%m%d')}"

header "Medical Robotics ETL Pipeline"
echo "ETL Type: $ETL_TYPE"
echo "Date Range: $START_DATE to $END_DATE"
echo "Batch Date: $BATCH_DATE"
echo ""

# Get State Machine ARN
info "Looking up Step Functions state machine..."
STATE_MACHINE_ARN=$(aws cloudformation describe-stacks \
    --stack-name ${ENVIRONMENT_NAME}-step-functions \
    --region $AWS_REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`StateMachineArn`].OutputValue' \
    --output text)

if [ -z "$STATE_MACHINE_ARN" ]; then
    error "Could not find Step Functions state machine"
    exit 1
fi

info "State Machine: $STATE_MACHINE_ARN"
echo ""

# Start execution
info "Starting ETL execution..."

EXECUTION_NAME="${ENVIRONMENT_NAME}-etl-$(date '+%Y%m%d-%H%M%S')"

EXECUTION_ARN=$(aws stepfunctions start-execution \
    --state-machine-arn $STATE_MACHINE_ARN \
    --name $EXECUTION_NAME \
    --input "{
        \"etl_type\": \"$ETL_TYPE\",
        \"start_date\": \"$START_DATE\",
        \"end_date\": \"$END_DATE\",
        \"batch_date\": \"$BATCH_DATE\"
    }" \
    --region $AWS_REGION \
    --query 'executionArn' \
    --output text)

info "Execution started: $EXECUTION_NAME"
echo ""

# Monitor execution
info "Monitoring execution status..."
echo "Press Ctrl+C to stop monitoring (execution will continue)"
echo ""

while true; do
    STATUS=$(aws stepfunctions describe-execution \
        --execution-arn $EXECUTION_ARN \
        --region $AWS_REGION \
        --query 'status' \
        --output text)

    case $STATUS in
        RUNNING)
            echo -n "."
            sleep 5
            ;;
        SUCCEEDED)
            echo ""
            info "ETL execution completed successfully!"
            echo ""

            # Get output
            OUTPUT=$(aws stepfunctions describe-execution \
                --execution-arn $EXECUTION_ARN \
                --region $AWS_REGION \
                --query 'output' \
                --output text)

            echo "Results:"
            echo "$OUTPUT" | python3 -m json.tool 2>/dev/null || echo "$OUTPUT"
            break
            ;;
        FAILED|TIMED_OUT|ABORTED)
            echo ""
            error "ETL execution failed with status: $STATUS"
            echo ""

            # Get error details
            aws stepfunctions describe-execution \
                --execution-arn $EXECUTION_ARN \
                --region $AWS_REGION \
                --query '{Status:status,Error:error,Cause:cause}' \
                --output table
            exit 1
            ;;
    esac
done

echo ""
info "View execution details in AWS Console:"
echo "  https://${AWS_REGION}.console.aws.amazon.com/states/home?region=${AWS_REGION}#/executions/details/${EXECUTION_ARN}"
