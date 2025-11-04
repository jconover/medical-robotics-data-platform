# Pre-Deployment Check Guide

## What It Does

The pre-deployment check script validates your AWS environment before you deploy infrastructure, preventing common deployment failures.

## Usage

```bash
export ENVIRONMENT_NAME="medrobotics"
export AWS_REGION="us-east-1"

./scripts/pre-deployment-check.sh
```

**Exit codes:**
- `0` = ✅ Safe to deploy (no conflicts)
- `1` = ❌ Conflicts found (must resolve first)

## What It Checks

### 1. CloudFormation Stacks
Scans for existing stacks that would conflict:
- `medrobotics-network`
- `medrobotics-security-groups`
- `medrobotics-s3`, `medrobotics-iam`
- `medrobotics-rds`, `medrobotics-bastion`
- `medrobotics-ecs-cluster`, `medrobotics-alb`
- `medrobotics-redshift`, `medrobotics-etl-lambda`
- All other phase stacks

**Why it matters:** CloudFormation won't create a stack if one already exists with the same name.

### 2. S3 Buckets
Checks for buckets that match your environment:
- `medrobotics-raw-data-{account-id}`
- `medrobotics-processed-data-{account-id}`
- `medrobotics-analytics-{account-id}`
- `medrobotics-logs-{account-id}`
- `medrobotics-backups-{account-id}`

**Why it matters:** S3 bucket names are globally unique. If a bucket exists, CloudFormation deployment will fail with "bucket already exists" error.

### 3. ECR Repositories
Checks for existing container registries:
- `medrobotics-data-ingestion`
- `medrobotics-api-service`

**Why it matters:** Usually just a warning, but good to know they exist.

### 4. RDS Instances
Checks for existing PostgreSQL databases:
- Any RDS instance with identifier containing `medrobotics`

**Why it matters:** RDS instances can't have duplicate identifiers in the same region.

### 5. Redshift Clusters
Checks for existing data warehouse clusters:
- Any Redshift cluster with identifier containing `medrobotics`

**Why it matters:** Prevents creating duplicate Redshift clusters.

### 6. VPCs
Checks for existing VPCs with matching tags:
- VPCs tagged with `Name=medrobotics-*`

**Why it matters:** May indicate incomplete cleanup from previous deployment.

### 7. ECS Clusters
Checks for existing container clusters:
- Any ECS cluster ARN containing `medrobotics`

**Why it matters:** ECS cluster names must be unique within a region.

### 8. Lambda Functions
Checks for existing serverless functions:
- Any Lambda function with name containing `medrobotics`

**Why it matters:** Usually just a warning, indicates incomplete cleanup.

### 9. Application Load Balancers
Checks for existing ALBs:
- Any ALB with name containing `medrobotics`

**Why it matters:** ALB names must be unique within a region.

### 10. IAM Roles
Checks for existing IAM roles:
- Any role with name containing `medrobotics`

**Why it matters:** Warning only - IAM roles might be from previous deployment.

### 11. Secrets Manager
Checks for existing secrets:
- Any secret with name containing `medrobotics`

**Why it matters:** Warning only - secrets may be in pending deletion (7-day recovery period).

## Example Output

### ✅ No Conflicts (Safe to Deploy)

```
========================================
Pre-Deployment Validation
========================================

✓ Environment: medrobotics
✓ Region: us-east-1
✓ Account ID: 123456789012

========================================
1. Checking CloudFormation Stacks
========================================

→ Checking stack: medrobotics-network
✓   Stack available
→ Checking stack: medrobotics-security-groups
✓   Stack available
...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ ALL CHECKS PASSED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✓ No conflicts detected. Safe to deploy!

Next steps:
  1. Deploy Phase 2: cd phase2-infrastructure/scripts && ./deploy-infrastructure.sh
  2. Deploy Phase 3: cd phase3-ecs/scripts && ./deploy-ecs.sh
  3. Deploy Phase 4: cd phase4-redshift/scripts && ./deploy.sh
```

### ❌ Conflicts Found

```
========================================
2. Checking S3 Buckets
========================================

→ Checking bucket: medrobotics-logs-457780993905
✗   Bucket already exists (47 objects)
→ Checking bucket: medrobotics-raw-data-457780993905
✗   Bucket already exists (1203 objects)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✗ BLOCKING ISSUES FOUND: 2
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✗ Deployment will fail due to existing resources

========================================
Resolution Steps
========================================

S3 Buckets (2 found):
  Option 1: Use automated bucket fix script
    ./scripts/fix-existing-buckets.sh

  Option 2: Delete buckets manually
    aws s3 rm s3://medrobotics-logs-457780993905 --recursive --region us-east-1
    aws s3 rb s3://medrobotics-logs-457780993905 --region us-east-1
    ...

After resolving conflicts, run this check again:
  ./scripts/pre-deployment-check.sh
```

## Integration with Deployment Workflow

### Recommended Workflow

```bash
# Step 1: Run pre-deployment check
./scripts/pre-deployment-check.sh

# Step 2: If conflicts found, resolve them
./scripts/fix-existing-buckets.sh        # For S3 conflicts
./scripts/cleanup-all-phases.sh          # For all other conflicts

# Step 3: Run check again to verify
./scripts/pre-deployment-check.sh

# Step 4: Deploy when check passes
cd phase2-infrastructure/scripts
./deploy-infrastructure.sh
```

### Automated Integration

You can integrate this into your deployment scripts:

```bash
#!/bin/bash

# Run pre-deployment check first
if ! ./scripts/pre-deployment-check.sh; then
    echo "Pre-deployment check failed. Please resolve conflicts first."
    exit 1
fi

# Proceed with deployment
cd phase2-infrastructure/scripts
./deploy-infrastructure.sh
```

## When to Use This Script

**Always run before:**
- ✅ Initial deployment of any phase
- ✅ Re-deploying after cleanup
- ✅ Deploying in a new AWS account
- ✅ Deploying with a different environment name
- ✅ After manual resource deletion

**No need to run if:**
- ❌ Just updating existing stacks (stack already exists intentionally)
- ❌ Running cleanup scripts (those handle conflicts)

## Resolving Common Conflicts

### S3 Bucket Conflicts

**Quick fix:**
```bash
./scripts/fix-existing-buckets.sh
```

**Manual fix:**
```bash
aws s3 rm s3://bucket-name --recursive --region us-east-1
aws s3 rb s3://bucket-name --region us-east-1
```

### CloudFormation Stack Conflicts

**Quick fix:**
```bash
./scripts/cleanup-all-phases.sh
```

**Manual fix:**
```bash
# Delete in reverse order (5 → 4 → 3 → 2)
aws cloudformation delete-stack --stack-name medrobotics-redshift --region us-east-1
aws cloudformation delete-stack --stack-name medrobotics-ecs-cluster --region us-east-1
aws cloudformation delete-stack --stack-name medrobotics-network --region us-east-1
```

### Other Resource Conflicts

Most other conflicts (RDS, Redshift, VPCs, etc.) indicate incomplete cleanup.

**Solution:**
```bash
./scripts/cleanup-all-phases.sh
```

## Customization

### Check Different Environment

```bash
export ENVIRONMENT_NAME="dev-medrobotics"
export AWS_REGION="us-west-2"
./scripts/pre-deployment-check.sh
```

### Check Multiple Environments

```bash
for ENV in dev staging prod; do
    echo "Checking environment: $ENV"
    ENVIRONMENT_NAME="$ENV-medrobotics" ./scripts/pre-deployment-check.sh
done
```

## What's NOT Checked

The script does NOT check:
- ❌ AWS quotas/limits (use AWS Service Quotas console)
- ❌ IAM permissions (assumes you have sufficient permissions)
- ❌ Budget/cost limits
- ❌ Network connectivity
- ❌ DNS records or Route53 zones

These are assumed to be correct or handled separately.

## Troubleshooting

### "Cannot get AWS account ID"

**Cause:** AWS credentials not configured or expired.

**Solution:**
```bash
# Check credentials
aws sts get-caller-identity

# Reconfigure if needed
aws configure
```

### Check says "safe" but deployment still fails

**Cause:** The check validates resource names, not all deployment requirements.

**Other things to check:**
- IAM permissions
- AWS service quotas
- Required parameters (DB passwords, etc.)
- Dependencies (Phase 2 must exist before Phase 3)

**Solution:** See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) for deployment-specific issues.

### False positives (resources exist but are okay)

**Cause:** Resources from a partially completed deployment that you want to keep.

**Solution:**
- Review the specific resources flagged
- If they're intentional, you can proceed with caution
- The check is conservative (better safe than sorry)

## Summary

**Benefits:**
- ✅ Prevents common deployment failures
- ✅ Saves time (catch issues before deploying)
- ✅ Provides clear resolution steps
- ✅ Validates environment before spending AWS resources

**When to use:**
- ✅ Before every fresh deployment
- ✅ After cleanup operations
- ✅ When deployment previously failed

**Quick commands:**
```bash
./scripts/pre-deployment-check.sh         # Run validation
./scripts/fix-existing-buckets.sh         # Fix S3 conflicts
./scripts/cleanup-all-phases.sh           # Fix all conflicts
./scripts/verify-cleanup.sh               # Verify after cleanup
```

The pre-deployment check is your first line of defense against deployment failures. Always run it before deploying! 🛡️
