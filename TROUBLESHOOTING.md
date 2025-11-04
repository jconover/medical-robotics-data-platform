# Troubleshooting Guide

## Common Deployment Issues

### Issue: "S3 bucket already exists"

**Error Message:**
```
Resource handler returned message: "medrobotics-logs-457780993905 already exists
(Service: S3, Status Code: 0, Request ID: null)"
```

**Cause:** S3 bucket from previous deployment wasn't deleted properly.

**Solution:**

```bash
# Option 1: Use automated fix script
./scripts/fix-existing-buckets.sh

# Option 2: Delete manually
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws s3 rm s3://medrobotics-logs-${ACCOUNT_ID} --recursive --region us-east-1
aws s3 rb s3://medrobotics-logs-${ACCOUNT_ID} --region us-east-1

# Then retry deployment
cd phase2-infrastructure/scripts
./deploy-infrastructure.sh
```

**Prevention:** Always run pre-deployment check before deploying:
```bash
./scripts/pre-deployment-check.sh
```

---

### Issue: "Export cannot be deleted as it is in use"

**Error Message:**
```
Export medrobotics-vpc-id cannot be deleted as it is in use by
medrobotics-ecs-cluster
```

**Cause:** Trying to delete Phase 2 while Phase 3/4 still depend on it.

**Solution:**

```bash
# Use master cleanup script (handles dependencies automatically)
./scripts/cleanup-all-phases.sh

# OR delete manually in reverse order:
# Phase 4 → Phase 3 → Phase 2
```

**Prevention:**
- Always delete in reverse order (5 → 4 → 3 → 2)
- Use provided cleanup scripts instead of manual deletion

---

### Issue: CloudFormation stack stuck in "DELETE_IN_PROGRESS"

**Symptom:** Stack deletion takes > 30 minutes

**Cause:** Large resources (RDS, Redshift, NAT Gateways) take time to delete.

**Solution:**

```bash
# Check stack status
aws cloudformation describe-stacks \
  --stack-name medrobotics-network \
  --region us-east-1 \
  --query 'Stacks[0].StackStatus'

# Wait for it to complete (can take 5-15 minutes)
aws cloudformation wait stack-delete-complete \
  --stack-name medrobotics-network \
  --region us-east-1

# If truly stuck (> 30 mins), check events for errors
aws cloudformation describe-stack-events \
  --stack-name medrobotics-network \
  --region us-east-1 \
  --max-items 20
```

**Common reasons for stuck deletions:**
- S3 bucket not empty (must empty before deletion)
- ENI (Elastic Network Interface) still attached
- Security group still in use
- Lambda function still has VPC attachment

---

### Issue: "Stack does not exist"

**Error Message:**
```
An error occurred (ValidationError) when calling the DescribeStacks operation:
Stack with id medrobotics-network does not exist
```

**Cause:** Trying to deploy Phase 3/4 before Phase 2 is complete.

**Solution:**

```bash
# Check Phase 2 status
aws cloudformation describe-stacks \
  --stack-name medrobotics-network \
  --region us-east-1

# Deploy Phase 2 first
cd phase2-infrastructure/scripts
./deploy-infrastructure.sh
```

---

### Issue: RDS connection refused

**Error Message:**
```
psql: could not translate host name to address
```

**Cause:** RDS is in a private subnet with no public access.

**Solution:**

```bash
# Deploy bastion host
cd phase2-infrastructure/cloudformation
aws cloudformation create-stack \
  --stack-name medrobotics-bastion \
  --template-body file://06-bastion-host.yaml \
  --parameters ParameterKey=EnvironmentName,ParameterValue=medrobotics \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1

# Connect via Session Manager
BASTION_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=medrobotics-bastion" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

aws ssm start-session --target $BASTION_ID --region us-east-1

# From bastion, connect to RDS
export RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier medrobotics-rds \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

psql -h $RDS_ENDPOINT -U dbadmin -d medrobotics
```

---

### Issue: Lambda ETL function fails with "No module named 'psycopg2'"

**Error Message:**
```
[ERROR] Runtime.ImportModuleError: Unable to import module 'rds_to_redshift_etl':
No module named 'psycopg2._psycopg'
```

**Cause:** Lambda was packaged with local binaries instead of platform-specific ones.

**Solution:**

```bash
cd phase4-redshift/etl-functions

# Clean up old builds
rm -rf build *.zip

# Rebuild with correct platform
pip install -r requirements.txt -t build/rds_etl/ \
    --platform manylinux2014_x86_64 \
    --only-binary=:all: \
    --python-version 3.11

# Re-package
cd build/rds_etl && zip -r ../../rds_to_redshift_etl.zip . && cd ../..

# Re-upload to S3
BUCKET=$(aws cloudformation describe-stacks \
    --stack-name medrobotics-s3 \
    --query 'Stacks[0].Outputs[?OutputKey==`ProcessedDataBucket`].OutputValue' \
    --output text)

aws s3 cp rds_to_redshift_etl.zip \
    s3://${BUCKET}/lambda/rds_to_redshift_etl.zip \
    --sse AES256 \
    --region us-east-1

# Update Lambda function
aws lambda update-function-code \
    --function-name medrobotics-rds-to-redshift-etl \
    --s3-bucket $BUCKET \
    --s3-key lambda/rds_to_redshift_etl.zip \
    --region us-east-1
```

---

### Issue: "Access Denied" when uploading to S3

**Error Message:**
```
An error occurred (AccessDenied) when calling the PutObject operation:
Access Denied
```

**Cause:** Missing encryption flag required by bucket policy.

**Solution:**

```bash
# Always include --sse AES256 when uploading to S3
aws s3 cp myfile.txt s3://medrobotics-raw-data-123456789012/myfile.txt \
    --sse AES256 \
    --region us-east-1
```

---

### Issue: Redshift cluster endpoint not accessible

**Symptom:** Cannot connect to Redshift from Lambda or bastion.

**Cause:** Security group or VPC configuration issue.

**Solution:**

```bash
# Check security group rules
aws ec2 describe-security-groups \
    --filters "Name=tag:Name,Values=medrobotics-redshift-sg" \
    --query 'SecurityGroups[0].IpPermissions' \
    --region us-east-1

# Verify Lambda is in same VPC
aws lambda get-function-configuration \
    --function-name medrobotics-rds-to-redshift-etl \
    --query 'VpcConfig' \
    --region us-east-1

# Check Redshift cluster status
aws redshift describe-clusters \
    --cluster-identifier medrobotics-redshift \
    --query 'Clusters[0].{Status:ClusterStatus,Endpoint:Endpoint}' \
    --region us-east-1
```

---

### Issue: CloudFormation shows no updates to be performed

**Symptom:** Update stack command says "No updates are to be performed"

**Cause:** Stack is already in desired state, or change is not detected.

**Solution:**

This is usually fine - it means your infrastructure is already up to date.

If you need to force an update:
```bash
# Add a parameter change or update a resource property
# Or delete and recreate the stack

# For Lambda, force code update:
aws lambda update-function-code \
    --function-name medrobotics-rds-to-redshift-etl \
    --s3-bucket $BUCKET \
    --s3-key lambda/rds_to_redshift_etl.zip \
    --region us-east-1
```

---

## Pre-Deployment Checklist

Before deploying any phase, always:

1. **Run pre-deployment check**
   ```bash
   ./scripts/pre-deployment-check.sh
   ```

2. **Verify AWS credentials**
   ```bash
   aws sts get-caller-identity
   ```

3. **Check region configuration**
   ```bash
   echo $AWS_REGION
   ```

4. **Verify no conflicting resources**
   - No stacks with same name
   - No S3 buckets with same name
   - No VPCs with same tags

5. **Have required passwords ready**
   - RDS master password (Phase 2)
   - Redshift master password (Phase 4)

---

## Cleanup Issues

### Issue: Cleanup script fails with permission errors

**Solution:**

```bash
# Verify IAM permissions
aws iam get-user
aws iam list-attached-user-policies --user-name $(aws iam get-user --query 'User.UserName' --output text)

# Required permissions:
# - CloudFormation: Full
# - S3: Full
# - EC2: Full
# - RDS: Full
# - Redshift: Full
# - ECS: Full
# - Lambda: Full
# - IAM: Full (or at least read/delete for roles)
```

### Issue: S3 bucket won't delete

**Error:** "Bucket is not empty"

**Solution:**

```bash
# Force empty and delete
aws s3 rm s3://bucket-name --recursive --region us-east-1
aws s3 rb s3://bucket-name --force --region us-east-1
```

---

## Getting Help

If issues persist:

1. **Check CloudFormation events**
   ```bash
   aws cloudformation describe-stack-events \
     --stack-name medrobotics-network \
     --max-items 50 \
     --region us-east-1
   ```

2. **Check CloudWatch logs**
   ```bash
   aws logs tail /aws/lambda/medrobotics-rds-to-redshift-etl --follow
   ```

3. **Run verification script**
   ```bash
   ./scripts/verify-cleanup.sh
   ```

4. **Review documentation**
   - [CLAUDE.md](./CLAUDE.md) - Developer guide
   - [CLEANUP_GUIDE.md](./CLEANUP_GUIDE.md) - Cleanup procedures
   - [STACK_VERIFICATION.md](./STACK_VERIFICATION.md) - Dependency analysis

5. **Check AWS Service Health Dashboard**
   - https://health.aws.amazon.com/health/status

---

## Cost Optimization Issues

### Unexpected high costs?

**Check these:**

```bash
# Check running RDS instances
aws rds describe-db-instances --region us-east-1

# Check running Redshift clusters
aws redshift describe-clusters --region us-east-1

# Check NAT Gateways (expensive!)
aws ec2 describe-nat-gateways --region us-east-1

# Check running ECS tasks
aws ecs list-tasks --cluster medrobotics-cluster --region us-east-1

# Check ALBs
aws elbv2 describe-load-balancers --region us-east-1
```

**Pause Redshift instead of deleting:**
```bash
aws redshift pause-cluster --cluster-identifier medrobotics-redshift --region us-east-1
```

**Stop RDS instead of deleting:**
```bash
aws rds stop-db-instance --db-instance-identifier medrobotics-rds --region us-east-1
```

---

## Quick Reference

| Issue | Command |
|-------|---------|
| Check conflicts | `./scripts/pre-deployment-check.sh` |
| Fix S3 buckets | `./scripts/fix-existing-buckets.sh` |
| Complete cleanup | `./scripts/cleanup-all-phases.sh` |
| Verify cleanup | `./scripts/verify-cleanup.sh` |
| Check stack status | `aws cloudformation describe-stacks --stack-name <name>` |
| Check stack events | `aws cloudformation describe-stack-events --stack-name <name>` |
| Empty S3 bucket | `aws s3 rm s3://<bucket> --recursive` |
| Delete S3 bucket | `aws s3 rb s3://<bucket>` |
| Pause Redshift | `aws redshift pause-cluster --cluster-identifier <id>` |
