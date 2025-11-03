# Stack Management Recommendations

## Current Problem

### ❌ Issue: Manual Deletion Required & Cleanup Script Failures

**What's happening:**
1. Individual stacks are deployed separately (not using the master stack)
2. Cleanup scripts only delete Phase 2, but Phase 3/4 depend on Phase 2
3. CloudFormation prevents deleting Phase 2 stacks when Phase 3/4 still exist
4. You have to manually figure out deletion order across all phases

**Example failure scenario:**
```bash
# You try to clean up Phase 2
./phase2-infrastructure/scripts/cleanup-infrastructure.sh

# But Phase 3 ECS services are still running
# Phase 4 Redshift cluster still references Phase 2 security groups
# CloudFormation Error: "Export medrobotics-vpc-id cannot be deleted as it is in use by..."
# Result: Manual cleanup required 😞
```

## Two Solutions

### ✅ Solution 1: Use Nested Stack Architecture (RECOMMENDED)

**Pros:**
- ✅ Single stack deletion removes everything
- ✅ CloudFormation manages dependencies automatically
- ✅ Atomic deployments (all or nothing)
- ✅ Easier to version control
- ✅ No manual cleanup needed

**Cons:**
- ❌ Requires uploading templates to S3 first
- ❌ Slightly more complex initial setup
- ❌ Can't selectively deploy phases (e.g., Phase 2 only)

**What needs to change:**
1. Use the existing `00-master-stack.yaml` as the foundation
2. Extend it to include Phase 3, 4, 5 as nested stacks
3. Upload templates to S3 before deployment
4. Deploy single master stack instead of individual stacks

### ✅ Solution 2: Improve Cleanup Scripts (SIMPLER, RECOMMENDED FOR NOW)

**Pros:**
- ✅ No architecture changes needed
- ✅ Keep flexibility to deploy phases independently
- ✅ Can still use existing deployment scripts

**Cons:**
- ❌ Requires running multiple cleanup scripts
- ❌ Must remember correct order
- ❌ More prone to human error

**What needs to change:**
1. Create a master cleanup script that orchestrates all phases
2. Fix existing cleanup scripts to handle dependencies
3. Add better error handling for "stack not found"

## Recommended Approach: Enhanced Cleanup Scripts

I recommend **Solution 2** because:
- It's less disruptive to your current workflow
- You keep the flexibility to deploy/test individual phases
- The master stack approach requires S3 setup that complicates local development

### Implementation: Master Cleanup Script

Create `/scripts/cleanup-all-phases.sh`:

```bash
#!/bin/bash

# Medical Robotics Data Platform - Complete Cleanup Script
# Deletes ALL phases in correct order

set -e

ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-medrobotics}"
AWS_REGION="${AWS_REGION:-us-east-1}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if stack exists
stack_exists() {
    aws cloudformation describe-stacks \
        --stack-name "$1" \
        --region "$AWS_REGION" &> /dev/null
}

# Delete stack with wait
delete_stack() {
    local STACK_NAME=$1

    if stack_exists "$STACK_NAME"; then
        info "Deleting stack: $STACK_NAME"
        aws cloudformation delete-stack \
            --stack-name "$STACK_NAME" \
            --region "$AWS_REGION"

        info "Waiting for $STACK_NAME to be deleted..."
        aws cloudformation wait stack-delete-complete \
            --stack-name "$STACK_NAME" \
            --region "$AWS_REGION" || warn "Stack deletion completed with warnings"

        info "✓ $STACK_NAME deleted"
    else
        info "Stack $STACK_NAME doesn't exist, skipping"
    fi
}

# Main
warn "========================================"
warn "COMPLETE INFRASTRUCTURE CLEANUP"
warn "========================================"
warn "Environment: $ENVIRONMENT_NAME"
warn "Region: $AWS_REGION"
warn ""
warn "This will delete ALL resources across ALL phases:"
warn "  Phase 5: EKS cluster (if exists)"
warn "  Phase 4: Redshift + ETL"
warn "  Phase 3: ECS services + ALB"
warn "  Phase 2: VPC + RDS + S3 + IAM"
warn ""
warn "⚠️  ALL DATA WILL BE LOST ⚠️"
warn ""
read -p "Are you ABSOLUTELY sure? Type 'DELETE' to confirm: " CONFIRM

if [ "$CONFIRM" != "DELETE" ]; then
    info "Cleanup cancelled"
    exit 0
fi

echo ""
info "Starting cleanup in reverse order..."
echo ""

# ==========================================
# Phase 5: EKS (if exists)
# ==========================================
info "=== Phase 5: Checking for EKS resources ==="

if stack_exists "${ENVIRONMENT_NAME}-eks"; then
    warn "EKS cluster detected. Please run phase5-eks/scripts/cleanup.sh first"
    warn "Then re-run this script."
    exit 1
fi

# ==========================================
# Phase 4: Redshift & ETL
# ==========================================
info "=== Phase 4: Redshift & ETL Cleanup ==="

# Step Functions first (depends on Lambda)
delete_stack "${ENVIRONMENT_NAME}-step-functions"

# Lambda functions (depend on Redshift)
delete_stack "${ENVIRONMENT_NAME}-etl-lambda"

# Redshift cluster
if stack_exists "${ENVIRONMENT_NAME}-redshift"; then
    warn "Deleting Redshift cluster (5-10 minutes)..."
    delete_stack "${ENVIRONMENT_NAME}-redshift"
fi

# Clean up Lambda packages from S3
info "Cleaning up Lambda deployment packages..."
PROCESSED_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name "${ENVIRONMENT_NAME}-s3" \
    --region "$AWS_REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`ProcessedDataBucket`].OutputValue' \
    --output text 2>/dev/null) || true

if [ -n "$PROCESSED_BUCKET" ]; then
    aws s3 rm "s3://${PROCESSED_BUCKET}/lambda/" --recursive --region "$AWS_REGION" 2>/dev/null || true
fi

echo ""

# ==========================================
# Phase 3: ECS Services
# ==========================================
info "=== Phase 3: ECS Services Cleanup ==="

# Delete services first (they depend on task definitions and ALB)
delete_stack "${ENVIRONMENT_NAME}-ecs-services"

# Delete task definitions
delete_stack "${ENVIRONMENT_NAME}-ecs-tasks"

# Delete ALB (depends on target groups which are deleted with services)
delete_stack "${ENVIRONMENT_NAME}-alb"

# Delete ECS cluster
delete_stack "${ENVIRONMENT_NAME}-ecs-cluster"

# Clean up ECR repositories
info "Cleaning up ECR repositories..."
for REPO in data-ingestion api-service; do
    if aws ecr describe-repositories \
        --repository-names "${ENVIRONMENT_NAME}-${REPO}" \
        --region "$AWS_REGION" &> /dev/null; then

        info "Deleting ECR repository: ${ENVIRONMENT_NAME}-${REPO}"
        aws ecr delete-repository \
            --repository-name "${ENVIRONMENT_NAME}-${REPO}" \
            --force \
            --region "$AWS_REGION" 2>/dev/null || true
    fi
done

echo ""

# ==========================================
# Phase 2: Core Infrastructure
# ==========================================
info "=== Phase 2: Core Infrastructure Cleanup ==="

# Empty all S3 buckets before deletion
info "Emptying S3 buckets..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

for BUCKET_SUFFIX in raw-data processed-data analytics logs backups; do
    BUCKET="${ENVIRONMENT_NAME}-${BUCKET_SUFFIX}-${ACCOUNT_ID}"
    if aws s3 ls "s3://${BUCKET}" &> /dev/null 2>&1; then
        info "Emptying bucket: $BUCKET"
        aws s3 rm "s3://${BUCKET}" --recursive --region "$AWS_REGION" 2>/dev/null || true
    fi
done

# Delete Phase 2 stacks in reverse dependency order
delete_stack "${ENVIRONMENT_NAME}-bastion"
delete_stack "${ENVIRONMENT_NAME}-rds"
delete_stack "${ENVIRONMENT_NAME}-iam"
delete_stack "${ENVIRONMENT_NAME}-s3"
delete_stack "${ENVIRONMENT_NAME}-security-groups"
delete_stack "${ENVIRONMENT_NAME}-network"

echo ""
info "========================================"
info "✓ CLEANUP COMPLETE"
info "========================================"
info "All infrastructure has been deleted."
echo ""
warn "Note: Manual cleanup may be required for:"
echo "  - CloudWatch Log Groups (may persist)"
echo "  - Redshift snapshots (if any)"
echo "  - ECR images (if any remain)"
echo ""
info "To verify all stacks are gone:"
echo "  aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --region $AWS_REGION | grep $ENVIRONMENT_NAME"
```

### Fix Phase 2 Cleanup Script

The current Phase 2 cleanup doesn't check for dependent stacks. Add this check:

```bash
# Add to beginning of phase2-infrastructure/scripts/cleanup-infrastructure.sh
# After the confirmation prompts, before emptying S3 buckets:

# Check for dependent stacks
info "Checking for dependent stacks..."
DEPENDENT_STACKS=()

for STACK in \
    "${ENVIRONMENT_NAME}-ecs-cluster" \
    "${ENVIRONMENT_NAME}-ecs-services" \
    "${ENVIRONMENT_NAME}-alb" \
    "${ENVIRONMENT_NAME}-redshift" \
    "${ENVIRONMENT_NAME}-etl-lambda" \
    "${ENVIRONMENT_NAME}-step-functions" \
    "${ENVIRONMENT_NAME}-eks"; do

    if aws cloudformation describe-stacks --stack-name "$STACK" --region "$AWS_REGION" &> /dev/null; then
        DEPENDENT_STACKS+=("$STACK")
    fi
done

if [ ${#DEPENDENT_STACKS[@]} -gt 0 ]; then
    error "Cannot delete Phase 2 infrastructure. The following dependent stacks exist:"
    for STACK in "${DEPENDENT_STACKS[@]}"; do
        error "  - $STACK"
    done
    echo ""
    error "Please delete Phase 3/4/5 stacks first, or use the master cleanup script:"
    error "  ./scripts/cleanup-all-phases.sh"
    exit 1
fi
```

## File Structure for Scripts

```
/
├── scripts/
│   ├── cleanup-all-phases.sh         # NEW: Master cleanup script
│   └── verify-cleanup.sh              # NEW: Verify all resources deleted
├── phase2-infrastructure/
│   └── scripts/
│       ├── deploy-infrastructure.sh   # Existing
│       └── cleanup-infrastructure.sh  # MODIFIED: Add dependency check
├── phase3-ecs/
│   └── scripts/
│       ├── deploy-ecs.sh             # Existing
│       └── cleanup-ecs.sh            # NEW: Dedicated cleanup
├── phase4-redshift/
│   └── scripts/
│       ├── deploy.sh                 # Existing
│       └── cleanup.sh                # Existing (already good)
└── phase5-eks/
    └── scripts/
        ├── deploy.sh                 # Existing
        └── cleanup.sh                # Existing
```

## Verification Script

Create `/scripts/verify-cleanup.sh`:

```bash
#!/bin/bash

ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-medrobotics}"
AWS_REGION="${AWS_REGION:-us-east-1}"

echo "Checking for remaining $ENVIRONMENT_NAME resources..."
echo ""

# Check CloudFormation stacks
echo "=== CloudFormation Stacks ==="
STACKS=$(aws cloudformation list-stacks \
    --region "$AWS_REGION" \
    --query "StackSummaries[?contains(StackName, '${ENVIRONMENT_NAME}') && StackStatus != 'DELETE_COMPLETE'].StackName" \
    --output text)

if [ -z "$STACKS" ]; then
    echo "✓ No stacks found"
else
    echo "⚠️  Found stacks:"
    echo "$STACKS"
fi
echo ""

# Check S3 buckets
echo "=== S3 Buckets ==="
BUCKETS=$(aws s3 ls | grep "$ENVIRONMENT_NAME" || true)
if [ -z "$BUCKETS" ]; then
    echo "✓ No buckets found"
else
    echo "⚠️  Found buckets:"
    echo "$BUCKETS"
fi
echo ""

# Check ECR repositories
echo "=== ECR Repositories ==="
REPOS=$(aws ecr describe-repositories \
    --region "$AWS_REGION" \
    --query "repositories[?contains(repositoryName, '${ENVIRONMENT_NAME}')].repositoryName" \
    --output text 2>/dev/null || true)
if [ -z "$REPOS" ]; then
    echo "✓ No repositories found"
else
    echo "⚠️  Found repositories:"
    echo "$REPOS"
fi
echo ""

# Check Redshift snapshots
echo "=== Redshift Snapshots ==="
SNAPSHOTS=$(aws redshift describe-cluster-snapshots \
    --region "$AWS_REGION" \
    --query "Snapshots[?contains(SnapshotIdentifier, '${ENVIRONMENT_NAME}')].SnapshotIdentifier" \
    --output text 2>/dev/null || true)
if [ -z "$SNAPSHOTS" ]; then
    echo "✓ No snapshots found"
else
    echo "⚠️  Found snapshots:"
    echo "$SNAPSHOTS"
fi
echo ""

echo "Verification complete!"
```

## Usage

### Complete Cleanup (All Phases)
```bash
# Set environment
export ENVIRONMENT_NAME="medrobotics"
export AWS_REGION="us-east-1"

# Run master cleanup
./scripts/cleanup-all-phases.sh

# Verify everything is deleted
./scripts/verify-cleanup.sh
```

### Cleanup Individual Phases (Careful!)
```bash
# Must delete in this order:
cd phase5-eks/scripts && ./cleanup.sh          # If deployed
cd ../../phase4-redshift/scripts && ./cleanup.sh
cd ../../phase3-ecs/scripts && ./cleanup-ecs.sh  # Create this
cd ../../phase2-infrastructure/scripts && ./cleanup-infrastructure.sh
```

## Alternative: Master Stack Architecture

If you want to switch to nested stacks (more complex but cleaner long-term):

### Benefits
- Delete everything with one command: `aws cloudformation delete-stack --stack-name medrobotics-master`
- Automatic dependency management
- Atomic deployments

### Implementation
1. Upload templates to S3
2. Extend `00-master-stack.yaml` to include Phase 3, 4, 5
3. Use `aws cloudformation create-stack --template-body file://00-master-stack.yaml`

**Note:** This requires significant refactoring and loses the ability to deploy phases independently for testing.

## Recommendation

**Implement Solution 2 (Enhanced Cleanup Scripts) because:**
1. ✅ Quick to implement
2. ✅ No architecture changes
3. ✅ Keeps deployment flexibility
4. ✅ Solves the manual deletion problem
5. ✅ Easy to test and verify

The master cleanup script handles all cross-phase dependencies automatically, and you can still deploy phases independently for development/testing.
