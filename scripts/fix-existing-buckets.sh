#!/bin/bash

# Medical Robotics Data Platform - Fix Existing S3 Buckets
# Resolves "bucket already exists" errors during CloudFormation deployment

set -e

ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-medrobotics}"
AWS_REGION="${AWS_REGION:-us-east-1}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

header "S3 Bucket Conflict Resolution"
echo ""

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
info "Account ID: $ACCOUNT_ID"
info "Environment: $ENVIRONMENT_NAME"
info "Region: $AWS_REGION"
echo ""

# Expected bucket names
BUCKET_NAMES=(
    "${ENVIRONMENT_NAME}-raw-data-${ACCOUNT_ID}"
    "${ENVIRONMENT_NAME}-processed-data-${ACCOUNT_ID}"
    "${ENVIRONMENT_NAME}-analytics-${ACCOUNT_ID}"
    "${ENVIRONMENT_NAME}-logs-${ACCOUNT_ID}"
    "${ENVIRONMENT_NAME}-backups-${ACCOUNT_ID}"
)

# Check which buckets exist
header "Checking for Existing Buckets"
echo ""

EXISTING_BUCKETS=()
for BUCKET in "${BUCKET_NAMES[@]}"; do
    if aws s3 ls "s3://${BUCKET}" --region "$AWS_REGION" &> /dev/null; then
        warn "✗ Bucket EXISTS: $BUCKET"
        EXISTING_BUCKETS+=("$BUCKET")
    else
        info "✓ Bucket available: $BUCKET"
    fi
done

echo ""

if [ ${#EXISTING_BUCKETS[@]} -eq 0 ]; then
    info "=========================================="
    info "No existing buckets found. You're good to deploy!"
    info "=========================================="
    exit 0
fi

# Show options
header "Resolution Options"
echo ""
warn "Found ${#EXISTING_BUCKETS[@]} existing bucket(s) that conflict with deployment."
echo ""
echo "Choose an option:"
echo ""
echo "  1) Delete all existing buckets (DESTROYS ALL DATA)"
echo "  2) Import existing buckets into CloudFormation stack"
echo "  3) Show bucket contents and decide"
echo "  4) Cancel and investigate manually"
echo ""
read -p "Enter choice (1-4): " CHOICE

case $CHOICE in
    1)
        # Delete existing buckets
        echo ""
        warn "=========================================="
        warn "WARNING: DELETING BUCKETS"
        warn "=========================================="
        warn ""
        warn "This will PERMANENTLY DELETE these buckets and ALL their contents:"
        for BUCKET in "${EXISTING_BUCKETS[@]}"; do
            warn "  - $BUCKET"
        done
        warn ""
        read -p "Type 'DELETE' to confirm: " CONFIRM

        if [ "$CONFIRM" != "DELETE" ]; then
            info "Cancelled"
            exit 0
        fi

        echo ""
        info "Deleting buckets..."
        for BUCKET in "${EXISTING_BUCKETS[@]}"; do
            info "Emptying bucket: $BUCKET"

            # Remove all current objects
            aws s3 rm "s3://${BUCKET}" --recursive --region "$AWS_REGION" 2>/dev/null || warn "Failed to remove current objects from $BUCKET"

            # Remove all versioned objects and delete markers
            info "Removing all versions and delete markers from: $BUCKET"
            aws s3api delete-objects \
                --bucket "$BUCKET" \
                --delete "$(aws s3api list-object-versions \
                    --bucket "$BUCKET" \
                    --output json \
                    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
                    --max-items 1000)" \
                --region "$AWS_REGION" \
                2>/dev/null || info "No versions to delete in $BUCKET"

            # Remove delete markers
            aws s3api delete-objects \
                --bucket "$BUCKET" \
                --delete "$(aws s3api list-object-versions \
                    --bucket "$BUCKET" \
                    --output json \
                    --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
                    --max-items 1000)" \
                --region "$AWS_REGION" \
                2>/dev/null || info "No delete markers to remove in $BUCKET"

            info "Deleting bucket: $BUCKET"
            aws s3 rb "s3://${BUCKET}" --region "$AWS_REGION" 2>/dev/null || error "Failed to delete $BUCKET"

            info "✓ Deleted: $BUCKET"
        done

        echo ""
        header "✓ BUCKETS DELETED"
        echo ""
        info "You can now deploy CloudFormation stacks without conflicts."
        info "Run: cd phase2-infrastructure/scripts && ./deploy-infrastructure.sh"
        ;;

    2)
        # Import into CloudFormation
        echo ""
        header "Importing Buckets into CloudFormation"
        echo ""
        warn "This feature requires CloudFormation import operations."
        warn "This is an advanced operation. Here's how to do it:"
        echo ""
        echo "1. Create an import template that references existing buckets"
        echo "2. Use 'aws cloudformation create-change-set --change-set-type IMPORT'"
        echo "3. Execute the change set"
        echo ""
        warn "This is complex and not recommended for this project."
        warn "It's easier to delete and recreate the buckets (Option 1)."
        echo ""
        info "For more info: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/resource-import.html"
        ;;

    3)
        # Show contents
        echo ""
        header "Bucket Contents"
        echo ""

        for BUCKET in "${EXISTING_BUCKETS[@]}"; do
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "Bucket: $BUCKET"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

            # Get object count and total size
            OBJECT_COUNT=$(aws s3 ls "s3://${BUCKET}" --recursive --region "$AWS_REGION" 2>/dev/null | wc -l)
            TOTAL_SIZE=$(aws s3 ls "s3://${BUCKET}" --recursive --summarize --region "$AWS_REGION" 2>/dev/null | grep "Total Size" | awk '{print $3}')

            if [ "$OBJECT_COUNT" -eq 0 ]; then
                info "  Status: EMPTY"
                info "  Safe to delete"
            else
                warn "  Objects: $OBJECT_COUNT"
                warn "  Size: $TOTAL_SIZE bytes"
                echo ""
                echo "  Sample contents:"
                aws s3 ls "s3://${BUCKET}" --recursive --region "$AWS_REGION" 2>/dev/null | head -10
            fi
            echo ""
        done

        echo ""
        warn "To delete these buckets, run this script again and choose Option 1."
        ;;

    4)
        # Cancel
        echo ""
        info "Cancelled. No changes made."
        echo ""
        info "To investigate manually:"
        echo ""
        for BUCKET in "${EXISTING_BUCKETS[@]}"; do
            echo "  # List contents:"
            echo "  aws s3 ls s3://${BUCKET} --recursive --region $AWS_REGION"
            echo ""
            echo "  # Delete bucket (with versioning):"
            echo "  # 1. Remove current objects"
            echo "  aws s3 rm s3://${BUCKET} --recursive --region $AWS_REGION"
            echo ""
            echo "  # 2. Remove all versions"
            echo "  aws s3api delete-objects --bucket ${BUCKET} --delete \"\$(aws s3api list-object-versions --bucket ${BUCKET} --output json --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --max-items 1000)\" --region $AWS_REGION"
            echo ""
            echo "  # 3. Remove delete markers"
            echo "  aws s3api delete-objects --bucket ${BUCKET} --delete \"\$(aws s3api list-object-versions --bucket ${BUCKET} --output json --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --max-items 1000)\" --region $AWS_REGION"
            echo ""
            echo "  # 4. Delete the bucket"
            echo "  aws s3 rb s3://${BUCKET} --region $AWS_REGION"
            echo ""
        done
        ;;

    *)
        error "Invalid choice"
        exit 1
        ;;
esac

echo ""
