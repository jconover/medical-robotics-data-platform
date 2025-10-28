## Phase 2: AWS Infrastructure with CloudFormation

## Overview

This phase establishes the core AWS infrastructure for the Medical Robotics Data Platform using Infrastructure as Code (CloudFormation). It provisions networking, storage, database, and security components needed for the platform.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         AWS Cloud                            │
│                                                              │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                  VPC (10.5.0.0/16)                     │  │
│  │                                                        │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌─────────────┐ │  │
│  │  │   Public     │  │   Private    │  │    Data     │ │  │
│  │  │   Subnets    │  │   Subnets    │  │   Subnets   │ │  │
│  │  │  (AZ1, AZ2)  │  │  (AZ1, AZ2)  │  │ (AZ1, AZ2)  │ │  │
│  │  │              │  │              │  │             │ │  │
│  │  │    ALB       │  │  ECS Tasks   │  │     RDS     │ │  │
│  │  │              │  │              │  │  PostgreSQL │ │  │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬──────┘ │  │
│  │         │                 │                 │        │  │
│  │         └─────────────────┴─────────────────┘        │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │                   S3 Data Lake                         │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐            │  │
│  │  │   Raw    │  │Processed │  │Analytics │            │  │
│  │  │   Data   │  │   Data   │  │   Data   │            │  │
│  │  └──────────┘  └──────────┘  └──────────┘            │  │
│  └────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Infrastructure Components

### 1. VPC and Networking (`01-vpc-network.yaml`)
- **VPC**: 10.5.0.0/16 CIDR block (configurable, avoids common conflicts)
- **Public Subnets**: 2 subnets across 2 AZs (for ALB, NAT Gateways)
- **Private Subnets**: 2 subnets across 2 AZs (for ECS tasks, application layer)
- **Data Subnets**: 2 subnets across 2 AZs (for RDS, Redshift)
- **NAT Gateways**: 2 for high availability
- **Internet Gateway**: For public internet access
- **VPC Endpoint**: S3 gateway endpoint for cost-effective S3 access

### 2. Security Groups (`02-security-groups.yaml`)
- **ALB Security Group**: Allows HTTP/HTTPS from internet
- **ECS Security Group**: Allows traffic from ALB only
- **RDS Security Group**: Allows PostgreSQL (5432) from ECS and bastion
- **Redshift Security Group**: Allows Redshift (5439) from ECS and bastion
- **Bastion Security Group**: Allows SSH (22) for administrative access

### 3. S3 Data Lake (`03-s3-buckets.yaml`)
- **Raw Data Bucket**: Telemetry and sensor data (with lifecycle policies)
- **Processed Data Bucket**: Cleaned and transformed data
- **Analytics Bucket**: Query results and aggregated data
- **Logs Bucket**: Application and service logs
- **Backup Bucket**: Database backups and snapshots
- **Encryption**: All buckets use AES-256 encryption
- **Versioning**: Enabled on critical buckets
- **Lifecycle Policies**: Automatic transition to IA/Glacier

### 4. IAM Roles and Policies (`04-iam-roles.yaml`)
- **ECS Task Execution Role**: For ECS to pull images and write logs
- **ECS Task Role**: For application code to access S3 and RDS
- **Lambda Execution Role**: For ETL functions
- **Redshift Role**: For Redshift to read from S3
- **Data Pipeline Role**: For orchestration workflows
- **CloudWatch Events Role**: For scheduled tasks

### 5. RDS PostgreSQL (`05-rds-postgres.yaml`)
- **Engine**: PostgreSQL 17.4
- **Instance Class**: Configurable (default: db.t3.micro)
- **Storage**: GP3 SSD with encryption
- **Multi-AZ**: Optional for production
- **Backups**: Automated daily backups (7-day retention)
- **Monitoring**: CloudWatch alarms for CPU, storage, connections
- **Secrets Manager**: Secure credential storage

## Project Structure

```
phase2-infrastructure/
├── cloudformation/
│   ├── 00-master-stack.yaml         # Master nested stack (optional)
│   ├── 01-vpc-network.yaml           # VPC and networking
│   ├── 02-security-groups.yaml       # Security groups
│   ├── 03-s3-buckets.yaml            # S3 data lake buckets
│   ├── 04-iam-roles.yaml             # IAM roles and policies
│   └── 05-rds-postgres.yaml          # RDS PostgreSQL database
├── scripts/
│   ├── deploy-infrastructure.sh      # Deployment automation
│   └── cleanup-infrastructure.sh     # Cleanup automation
├── sql-schemas/
│   ├── 01-create-tables.sql          # Database schema
│   └── 02-load-sample-data.sql       # Data loading examples
└── README.md                         # This file
```

## Prerequisites

- AWS CLI installed and configured
- AWS account with appropriate permissions
- Bash shell (Linux/Mac) or WSL (Windows)
- PostgreSQL client (psql) for database access

## Deployment

### Option 1: Automated Deployment (Recommended)

Use the provided deployment script:

```bash
cd phase2-infrastructure/scripts

# Set environment variables
export ENVIRONMENT_NAME="medrobotics"
export AWS_REGION="us-east-1"
export DB_USERNAME="dbadmin"
export DB_PASSWORD="YourSecurePassword123!"  # Min 8 characters
export DB_INSTANCE_CLASS="db.t3.micro"

# Deploy all stacks
./deploy-infrastructure.sh
```

The script will:
1. Validate prerequisites
2. Deploy VPC and networking
3. Deploy security groups
4. Deploy S3 buckets
5. Deploy IAM roles
6. Deploy RDS PostgreSQL
7. Wait for each stack to complete

### Option 2: Manual Deployment

Deploy stacks individually in order:

```bash
cd phase2-infrastructure/cloudformation

# 1. VPC and Networking
aws cloudformation create-stack \
  --stack-name medrobotics-network \
  --template-body file://01-vpc-network.yaml \
  --parameters ParameterKey=EnvironmentName,ParameterValue=medrobotics \
  --region us-east-1

# Wait for completion
aws cloudformation wait stack-create-complete \
  --stack-name medrobotics-network \
  --region us-east-1

# 2. Security Groups
aws cloudformation create-stack \
  --stack-name medrobotics-security-groups \
  --template-body file://02-security-groups.yaml \
  --parameters ParameterKey=EnvironmentName,ParameterValue=medrobotics \
  --region us-east-1

# 3. S3 Buckets
aws cloudformation create-stack \
  --stack-name medrobotics-s3 \
  --template-body file://03-s3-buckets.yaml \
  --parameters ParameterKey=EnvironmentName,ParameterValue=medrobotics \
  --region us-east-1

# 4. IAM Roles
aws cloudformation create-stack \
  --stack-name medrobotics-iam \
  --template-body file://04-iam-roles.yaml \
  --parameters ParameterKey=EnvironmentName,ParameterValue=medrobotics \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1

# 5. RDS PostgreSQL
aws cloudformation create-stack \
  --stack-name medrobotics-rds \
  --template-body file://05-rds-postgres.yaml \
  --parameters \
    ParameterKey=EnvironmentName,ParameterValue=medrobotics \
    ParameterKey=DBUsername,ParameterValue=dbadmin \
    ParameterKey=DBPassword,ParameterValue=YourSecurePassword123 \
  --region us-east-1
```

## Post-Deployment Steps

### Important: RDS is in Private Subnet

Your RDS instance is deployed in **private subnets** and **cannot be accessed directly** from your local machine for security. You'll see this error if you try:

```
psql: error: could not translate host name "..." to address: No address associated with hostname
```

**Solution**: Deploy a bastion host to access RDS. See [BASTION-QUICKSTART.md](BASTION-QUICKSTART.md) for detailed instructions.

### 1. Deploy Bastion Host (Required for Database Access)

```bash
cd phase2-infrastructure/cloudformation

# Deploy bastion host
aws cloudformation create-stack \
  --stack-name medrobotics-bastion \
  --template-body file://06-bastion-host.yaml \
  --parameters ParameterKey=EnvironmentName,ParameterValue=medrobotics \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1

# Wait for completion
aws cloudformation wait stack-create-complete \
  --stack-name medrobotics-bastion \
  --region us-east-1
```

### 2. Connect to Bastion

```bash
# Get bastion instance ID
BASTION_ID=$(aws cloudformation describe-stacks \
  --stack-name medrobotics-bastion \
  --query 'Stacks[0].Outputs[?OutputKey==`BastionInstanceId`].OutputValue' \
  --output text)

# Connect via AWS Systems Manager (no SSH key needed!)
aws ssm start-session --target $BASTION_ID --region us-east-1
```

### 3. Create Database Schema (from Bastion)

Once connected to the bastion host:

```bash
# Get the RDS endpoint
RDS_ENDPOINT=$(aws cloudformation describe-stacks \
  --stack-name medrobotics-rds \
  --region us-east-1 \
  --query 'Stacks[0].Outputs[?OutputKey==`DBEndpoint`].OutputValue' \
  --output text)

# Upload your SQL schema file to /tmp (copy-paste or use S3)
# Then connect and create schema
psql -h $RDS_ENDPOINT -U dbadmin -d medrobotics -f /tmp/01-create-tables.sql
```

See [BASTION-QUICKSTART.md](BASTION-QUICKSTART.md) for multiple methods to upload SQL files.

### 3. Upload Sample Data to S3

```bash
# Get bucket name
RAW_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name medrobotics-s3 \
  --query 'Stacks[0].Outputs[?OutputKey==`RawDataBucket`].OutputValue' \
  --output text)

# Upload telemetry data from Phase 1
aws s3 cp ../../phase1-data-model/data_generators/sample_data/procedure_telemetry.json \
  s3://$RAW_BUCKET/telemetry/procedure_telemetry.json

# Upload CSV files
aws s3 cp ../../phase1-data-model/data_generators/sample_data/surgical_robots.csv \
  s3://$RAW_BUCKET/robots/surgical_robots.csv
```

### 4. Load Data into RDS (from Bastion)

```bash
# From bastion host
psql -h $RDS_ENDPOINT -U dbadmin -d medrobotics -f /tmp/02-load-sample-data.sql
```

Or use the provided SQL script and create a custom data loader.

## Verification

### Check Stack Status

```bash
aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --query 'StackSummaries[?contains(StackName, `medrobotics`)].{Name:StackName,Status:StackStatus}' \
  --output table
```

### Test Database Connection

From bastion host:

```bash
# Interactive connection using helper script
./connect-to-rds.sh

# Or manually
psql -h $RDS_ENDPOINT -U dbadmin -d medrobotics -c "\dt"
```

### List S3 Buckets

```bash
aws s3 ls | grep medrobotics
```

## Cost Estimation

**Monthly costs (approximate, us-east-1)**:

| Service | Configuration | Monthly Cost |
|---------|--------------|--------------|
| RDS (db.t3.micro) | 20 GB storage | ~$15 |
| NAT Gateways (2) | Standard pricing | ~$65 |
| S3 Storage | 1 GB (minimal) | ~$0.02 |
| Data Transfer | Minimal | ~$1 |
| **Total** | | **~$81/month** |

**Cost Optimization Tips**:
- Use single NAT Gateway for dev (not production)
- Stop/start RDS when not in use (dev only)
- Use S3 lifecycle policies to move to cheaper storage
- Delete resources when done testing

## Cleanup

### Automated Cleanup

```bash
cd phase2-infrastructure/scripts

export ENVIRONMENT_NAME="medrobotics"
export AWS_REGION="us-east-1"

./cleanup-infrastructure.sh
```

The script will:
1. Confirm deletion (double-check)
2. Empty all S3 buckets
3. Delete stacks in reverse order
4. Wait for each deletion to complete

### Manual Cleanup

```bash
# Delete in reverse order
aws cloudformation delete-stack --stack-name medrobotics-rds
aws cloudformation delete-stack --stack-name medrobotics-iam
aws cloudformation delete-stack --stack-name medrobotics-s3  # Empty buckets first!
aws cloudformation delete-stack --stack-name medrobotics-security-groups
aws cloudformation delete-stack --stack-name medrobotics-network
```

## Troubleshooting

### Stack Creation Failed

```bash
# View stack events
aws cloudformation describe-stack-events \
  --stack-name medrobotics-network \
  --max-items 20
```

### RDS Connection Issues

**Error: "could not translate host name to address"**
- This is expected! RDS is in a private subnet
- Deploy and use bastion host (see BASTION-QUICKSTART.md)
- Never make RDS publicly accessible in production

**Other issues:**
- Check security group rules allow bastion -> RDS traffic
- Verify bastion is in public subnet
- Check database credentials in Secrets Manager
- Verify VPC DNS is enabled

### S3 Access Denied

- Verify IAM roles have correct policies
- Check bucket policies
- Ensure encryption settings match

## Security Best Practices

1. **Never commit passwords** - Use Secrets Manager or Parameter Store
2. **Restrict bastion SSH** - Use your IP instead of 0.0.0.0/0
3. **Enable MFA delete** on S3 buckets in production
4. **Use private subnets** for all data resources
5. **Enable CloudTrail** for audit logging
6. **Regular backups** - Verify RDS snapshots

## Next Steps

After completing Phase 2:

1. **Phase 3**: Deploy ECS containers for data ingestion
2. **Phase 4**: Set up Redshift data warehouse
3. **Phase 5**: Migrate to EKS (Kubernetes)
4. **Phase 6**: Add CI/CD pipeline

## Additional Resources

- [AWS CloudFormation Documentation](https://docs.aws.amazon.com/cloudformation/)
- [AWS VPC Best Practices](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-best-practices.html)
- [RDS PostgreSQL Documentation](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html)
- [S3 Best Practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html)

## License

This project is for educational and portfolio purposes.
