# Cleanup Guide

## Quick Reference

### Complete Cleanup (Recommended)

Delete **everything** in the correct order with a single command:

```bash
export ENVIRONMENT_NAME="medrobotics"
export AWS_REGION="us-east-1"

./scripts/cleanup-all-phases.sh
```

Then verify:

```bash
./scripts/verify-cleanup.sh
```

---

## Individual Phase Cleanup

### Phase 5: EKS (if deployed)

```bash
cd phase5-eks/scripts
./cleanup.sh
```

### Phase 4: Redshift & ETL

```bash
cd phase4-redshift/scripts
./cleanup.sh
```

**What it deletes:**
- Step Functions workflows
- Lambda functions (RDS ETL, Telemetry ETL)
- Redshift cluster (creates final snapshot)
- Lambda deployment packages from S3
- CloudWatch log groups

### Phase 3: ECS Services

```bash
cd phase3-ecs/scripts
./cleanup-ecs.sh
```

**What it deletes:**
- ECS services (data-ingestion, api-service)
- ECS task definitions
- Application Load Balancer + target groups
- ECS cluster
- ECR repositories and all Docker images

**⚠️ Warning:** This script will warn you if Phase 4 (Redshift) is still running, since it may depend on Phase 3 resources.

### Phase 2: Core Infrastructure

```bash
cd phase2-infrastructure/scripts
./cleanup-infrastructure.sh
```

**What it deletes:**
- Bastion host
- RDS PostgreSQL database
- IAM roles
- S3 buckets (after emptying them)
- Security groups
- VPC and all networking

**⚠️ Important:** This script will **refuse to run** if Phase 3, 4, or 5 stacks still exist. CloudFormation prevents deleting Phase 2 because other phases depend on its exports (VPC, subnets, security groups, etc.).

---

## Why Order Matters

### The Dependency Chain

```
Phase 2 (VPC, Security Groups, IAM, S3, RDS)
    ↑ depends on
Phase 3 (ECS services, ALB)
    ↑ depends on
Phase 4 (Redshift, Lambda ETL)
    ↑ depends on
Phase 5 (EKS - optional)
```

**You must delete in reverse order:**
Phase 5 → Phase 4 → Phase 3 → Phase 2

### What Happens If You Delete Out of Order?

```bash
# ❌ This will FAIL
cd phase2-infrastructure/scripts
./cleanup-infrastructure.sh

# Error you'll see:
# "Cannot delete Phase 2 infrastructure!"
# "The following dependent stacks still exist:"
# "  - medrobotics-ecs-cluster"
# "  - medrobotics-redshift"
# "CloudFormation will prevent Phase 2 deletion because these
#  stacks depend on Phase 2 exports (VPC, subnets, etc.)"
```

**Why it fails:**
- Phase 3 ECS services use `medrobotics-vpc-id`, `medrobotics-ecs-sg-id`, etc.
- Phase 4 Redshift uses `medrobotics-redshift-sg-id`, `medrobotics-data-subnet-1`, etc.
- CloudFormation tracks these dependencies and prevents deletion

---

## Troubleshooting

### "Stack is stuck in DELETE_IN_PROGRESS"

**Solution:** Wait 5-10 minutes. Large resources (RDS, Redshift, NAT Gateways) take time to delete.

Check status:
```bash
aws cloudformation describe-stacks \
  --stack-name medrobotics-network \
  --region us-east-1 \
  --query 'Stacks[0].StackStatus'
```

### "Cannot delete stack: Export is in use"

**Solution:** You're trying to delete Phase 2 before Phase 3/4. Use the master cleanup script or delete in reverse order.

### "S3 bucket is not empty"

**Solution:** The cleanup scripts automatically empty buckets. If it fails, do it manually:

```bash
aws s3 rm s3://medrobotics-raw-data-123456789012 --recursive --region us-east-1
```

### "ECR repository still has images"

**Solution:** The cleanup scripts use `--force` to delete repositories with images. If it fails:

```bash
aws ecr delete-repository \
  --repository-name medrobotics-data-ingestion \
  --force \
  --region us-east-1
```

### Finding Orphaned Resources

Run the verification script to scan for any remaining resources:

```bash
./scripts/verify-cleanup.sh
```

It will check:
- CloudFormation stacks
- S3 buckets
- ECR repositories
- RDS instances
- Redshift clusters and snapshots
- ECS clusters
- Lambda functions
- Application Load Balancers
- Secrets Manager secrets

---

## Manual Cleanup Commands

If scripts fail, you can delete stacks manually:

```bash
# Set environment
export ENV="medrobotics"
export REGION="us-east-1"

# Phase 5
aws cloudformation delete-stack --stack-name ${ENV}-eks --region $REGION

# Phase 4
aws cloudformation delete-stack --stack-name ${ENV}-step-functions --region $REGION
aws cloudformation delete-stack --stack-name ${ENV}-etl-lambda --region $REGION
aws cloudformation delete-stack --stack-name ${ENV}-redshift --region $REGION

# Phase 3
aws cloudformation delete-stack --stack-name ${ENV}-ecs-services --region $REGION
aws cloudformation delete-stack --stack-name ${ENV}-ecs-tasks --region $REGION
aws cloudformation delete-stack --stack-name ${ENV}-alb --region $REGION
aws cloudformation delete-stack --stack-name ${ENV}-ecs-cluster --region $REGION

# Phase 2 (only after Phase 3 & 4 are deleted)
aws cloudformation delete-stack --stack-name ${ENV}-bastion --region $REGION
aws cloudformation delete-stack --stack-name ${ENV}-rds --region $REGION
aws cloudformation delete-stack --stack-name ${ENV}-iam --region $REGION
aws cloudformation delete-stack --stack-name ${ENV}-s3 --region $REGION  # Empty buckets first!
aws cloudformation delete-stack --stack-name ${ENV}-security-groups --region $REGION
aws cloudformation delete-stack --stack-name ${ENV}-network --region $REGION
```

Wait for each stack to complete before moving to the next:

```bash
aws cloudformation wait stack-delete-complete \
  --stack-name medrobotics-network \
  --region us-east-1
```

---

## Cost Savings

**When to delete:**
- Testing completed
- Development paused
- End of day/week (if not in active use)

**What to keep running:**
- S3 buckets (minimal cost, ~$0.02/GB/month)
- IAM roles (free)

**What's expensive to keep running:**
- Redshift cluster (~$200/month for 2x dc2.large)
- NAT Gateways (~$65/month for 2x)
- RDS instance (~$15/month for db.t3.micro)
- ECS tasks (~$30/month for 2x tasks)

**Alternative to full deletion:**
```bash
# Pause Redshift instead of deleting
aws redshift pause-cluster --cluster-identifier medrobotics-redshift --region us-east-1

# Resume later
aws redshift resume-cluster --cluster-identifier medrobotics-redshift --region us-east-1
```

---

## Summary

| What to Do | Command |
|------------|---------|
| Delete everything | `./scripts/cleanup-all-phases.sh` |
| Verify cleanup | `./scripts/verify-cleanup.sh` |
| Delete Phase 4 only | `cd phase4-redshift/scripts && ./cleanup.sh` |
| Delete Phase 3 only | `cd phase3-ecs/scripts && ./cleanup-ecs.sh` |
| Delete Phase 2 only | `cd phase2-infrastructure/scripts && ./cleanup-infrastructure.sh` |
| Pause Redshift | `aws redshift pause-cluster --cluster-identifier medrobotics-redshift` |

**Remember:** Always delete in reverse order (5 → 4 → 3 → 2) or use the master cleanup script!
