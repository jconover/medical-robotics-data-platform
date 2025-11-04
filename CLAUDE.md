# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Medical Robotics Surgery Data Platform** - a comprehensive DevOps portfolio project demonstrating AWS infrastructure, data engineering, and modern cloud practices. The platform simulates collecting, storing, and analyzing data from surgical robots performing minimally invasive procedures.

**Important**: All data is completely synthetic and fictional. No real patient information is used.

## Project Structure

The project is organized into 5 phases, each building on the previous:

- **phase1-data-model/**: Data model design and Python data generators for synthetic medical robotics data
- **phase2-infrastructure/**: Core AWS infrastructure (VPC, RDS, S3, IAM) via CloudFormation
- **phase3-ecs/**: Containerized microservices on ECS Fargate (data ingestion & API services)
- **phase4-redshift/**: Data warehouse with Redshift, ETL Lambda functions, and Step Functions orchestration
- **phase5-eks/**: Kubernetes migration with EKS and Helm charts

## High-Level Architecture

```
Data Generators (Phase 1)
    ↓
AWS Infrastructure (Phase 2)
    ├── VPC (10.5.0.0/16) with public, private, data subnets across 2 AZs
    ├── RDS PostgreSQL (operational database)
    └── S3 Data Lake (raw, processed, analytics buckets)
    ↓
Data Ingestion Services (Phase 3)
    ├── ECS Fargate cluster with Container Insights
    ├── Data Ingestion Service (Flask, Port 8080)
    ├── API Service (Flask, Port 5000)
    └── Application Load Balancer (path-based routing)
    ↓
Data Warehouse & Analytics (Phase 4)
    ├── Redshift Cluster (star schema: dim_*, fact_*)
    ├── Lambda ETL Functions (RDS→Redshift, S3→Redshift)
    ├── Step Functions Orchestration (daily scheduled runs)
    └── Pre-built Analytical Views
    ↓
Kubernetes Alternative (Phase 5)
    └── EKS cluster with Helm charts
```

## Pre-Deployment Validation

**IMPORTANT**: Always run the pre-deployment check before deploying to avoid conflicts:

```bash
export ENVIRONMENT_NAME="medrobotics"
export AWS_REGION="us-east-1"

./scripts/pre-deployment-check.sh
```

**What it checks:**
- CloudFormation stacks that would conflict
- S3 buckets with matching names
- ECR repositories
- RDS instances
- Redshift clusters
- VPCs and networking resources
- ECS clusters
- Lambda functions
- Application Load Balancers
- IAM roles and Secrets Manager

**Exit codes:**
- `0` = Safe to deploy
- `1` = Conflicts found, must resolve first

**If conflicts are found**, use the provided resolution commands or run:
```bash
./scripts/fix-existing-buckets.sh      # For S3 bucket conflicts
./scripts/cleanup-all-phases.sh        # For all other conflicts
```

## Common Commands

### Phase 1: Data Generation

```bash
cd phase1-data-model

# Set up virtual environment
python3 -m venv venv
source venv/bin/activate  # On Linux/Mac

# Install dependencies
pip install -r requirements.txt

# Generate all synthetic data (~460k telemetry records)
cd data_generators
python generate_all.py

# Verify generated data
ls -lh sample_data/
```

### Phase 2: Infrastructure Deployment

```bash
# IMPORTANT: Run pre-deployment check first!
./scripts/pre-deployment-check.sh

cd phase2-infrastructure/scripts

# Set required environment variables
export ENVIRONMENT_NAME="medrobotics"
export AWS_REGION="us-east-1"
export DB_USERNAME="dbadmin"
export DB_PASSWORD="YourSecurePassword123"

# Deploy all CloudFormation stacks
./deploy-infrastructure.sh

# Connect to bastion host (RDS is in private subnet)
aws ssm start-session --target $(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=medrobotics-bastion" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text) --region us-east-1

# Clean up infrastructure
./cleanup-infrastructure.sh
```

### Phase 3: ECS Services

```bash
cd phase3-ecs/scripts

# Build Docker images and push to ECR
export ENVIRONMENT_NAME="medrobotics"
export AWS_REGION="us-east-1"
./build-and-push.sh

# Deploy ECS cluster, ALB, and services
export RDS_PASSWORD="YourSecurePassword123"
./deploy-ecs.sh

# Get ALB URL and test services
ALB_URL=$(aws cloudformation describe-stacks \
  --stack-name medrobotics-alb \
  --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerURL`].OutputValue' \
  --output text)

curl $ALB_URL/api/health
curl $ALB_URL/ingest/health

# View service logs
aws logs tail /aws/ecs/medrobotics/data-ingestion --follow
aws logs tail /aws/ecs/medrobotics/api-service --follow
```

### Phase 4: Redshift Data Warehouse

```bash
cd phase4-redshift

# Deploy Redshift cluster, Lambda functions, and Step Functions
./scripts/deploy.sh

# Initialize Redshift database (requires bastion connection)
# Connect to bastion first, then run:
export PGPASSWORD='YourRedshiftPassword'
export REDSHIFT_HOST='your-redshift-endpoint.region.redshift.amazonaws.com'
psql -h $REDSHIFT_HOST -U dwadmin -d medrobotics_dw -p 5439 -f 01-create-tables.sql
psql -h $REDSHIFT_HOST -U dwadmin -d medrobotics_dw -p 5439 -f 02-populate-dimensions.sql

# Run ETL pipeline manually
./scripts/run-etl.sh

# Monitor ETL execution
aws logs tail /aws/lambda/medrobotics-rds-to-redshift-etl --follow
aws logs tail /aws/lambda/medrobotics-telemetry-etl --follow

# Clean up Phase 4 resources
./scripts/cleanup.sh
```

### Phase 5: EKS Deployment

```bash
cd phase5-eks/scripts

# Deploy EKS cluster and services
./deploy.sh

# Clean up EKS resources
./cleanup.sh
```

## Key Technical Details

### CloudFormation Stack Dependencies

Stacks must be deployed in order due to cross-stack references:

1. **medrobotics-network** (Phase 2) - Exports VPC, subnet, and other network resources
2. **medrobotics-security-groups** (Phase 2) - Exports security group IDs
3. **medrobotics-s3** (Phase 2) - Exports S3 bucket names
4. **medrobotics-iam** (Phase 2) - Exports IAM role ARNs
5. **medrobotics-rds** (Phase 2) - Exports RDS endpoint
6. All subsequent stacks import from Phase 2

### Naming Conventions

- **Environment prefix**: `medrobotics` (configurable via `$ENVIRONMENT_NAME`)
- **Stack names**: `{environment}-{component}` (e.g., `medrobotics-network`)
- **CloudFormation exports**: `{environment}-{resource-name}` (e.g., `medrobotics-vpc-id`)
- **S3 buckets**: `{environment}-{purpose}-{random-suffix}` (e.g., `medrobotics-raw-data-abc123`)
- **Lambda functions**: `{environment}-{function-name}` (e.g., `medrobotics-rds-to-redshift-etl`)

### Data Model

**RDS PostgreSQL Tables** (operational/transactional):
- `surgical_robots` - Robot inventory and metadata
- `surgical_procedures` - Individual surgeries with surgeon, patient info
- `procedure_outcomes` - Post-op results and complications
- `robot_maintenance_logs` - Service records

**S3 Data Lake** (high-volume/unstructured):
- `procedure_telemetry.json` - High-frequency sensor data (NDJSON format)
- Organized by: `telemetry/{procedure-id}/{date}.json`

**Redshift Star Schema** (analytics):
- **Dimensions** (SCD Type 2): `dim_robots`, `dim_surgeons`, `dim_facilities`, `dim_date`, `dim_time`
- **Facts**: `fact_procedures`, `fact_procedure_telemetry`
- **Distribution**: Dimensions use `DISTSTYLE ALL`, facts use `DISTSTYLE KEY` on robot_key/procedure_key
- **Sort Keys**: Date-based for time-series query optimization

### ETL Pipeline Architecture

**Step Functions Workflow** (runs daily at 3 AM UTC):
1. Load dimension tables from RDS (surgeons, robots, facilities) with SCD2 merge
2. Load procedure facts from RDS
3. Load telemetry facts from S3 JSON files
4. Built-in retry logic with exponential backoff

**Lambda Functions**:
- `rds_to_redshift_etl.py` (1024 MB, 15 min timeout) - Extracts from RDS, loads to Redshift
- `s3_telemetry_to_redshift.py` (2048 MB, 15 min timeout) - Processes S3 telemetry JSON

**Key ETL Pattern**:
1. Extract from source (RDS query or S3 list/read)
2. Transform to pipe-delimited CSV
3. Upload to S3 staging bucket with `--sse AES256`
4. Use Redshift `COPY` command for bulk loading
5. Apply dimension SCD2 logic or fact table inserts

### Security Architecture

- **VPC Isolation**: All data resources (RDS, Redshift) in private data subnets with no internet access
- **Bastion Host**: Required for database access, accessible via AWS Systems Manager Session Manager (no SSH keys needed)
- **Encryption**: All S3 uploads require `--sse AES256`, RDS and Redshift use encryption at rest
- **Secrets Management**: Database credentials stored in AWS Secrets Manager
- **Security Groups**: Least-privilege access (ALB→ECS, ECS→RDS/S3, Lambda→RDS/Redshift)

### Important Platform-Specific Details

**Lambda Packaging**: ETL Lambda functions require platform-specific binaries for `psycopg2`:
```bash
pip install -r requirements.txt -t build/ \
    --platform manylinux2014_x86_64 \
    --only-binary=:all: \
    --python-version 3.11
```

**S3 Encryption**: All S3 uploads must include `--sse AES256` flag or API calls will fail with AccessDenied.

**Redshift Connection**: Always use port `5439` (not 5432). Connection string format:
```
psql -h <endpoint> -U dwadmin -d medrobotics_dw -p 5439
```

**Phase 2 Export Names**: The processed data bucket is exported as `medrobotics-processed-data-bucket` (not `medrobotics-processed-bucket`).

## Troubleshooting Common Issues

### RDS Connection Issues

**Error**: "could not translate host name to address"

This is expected! RDS is in a private subnet. Deploy and connect through the bastion host:
```bash
cd phase2-infrastructure/cloudformation
aws cloudformation create-stack \
  --stack-name medrobotics-bastion \
  --template-body file://06-bastion-host.yaml \
  --capabilities CAPABILITY_NAMED_IAM
```

### Lambda ETL Failures

**Error**: "No module named 'psycopg2._psycopg'"

Lambda was packaged with local binaries. Rebuild with:
```bash
cd phase4-redshift/etl-functions
rm -rf build *.zip
pip install -r requirements.txt -t build/rds_etl/ \
    --platform manylinux2014_x86_64 --only-binary=:all: --python-version 3.11
```

**Error**: "relation 'dim_surgeons' does not exist"

You skipped database initialization. Connect to Redshift via bastion and run `01-create-tables.sql` and `02-populate-dimensions.sql`.

### CloudFormation Export Not Found

**Error**: "No export named medrobotics-processed-bucket found"

The export name in Phase 4 doesn't match Phase 2. Check the stack outputs:
```bash
aws cloudformation describe-stacks --stack-name medrobotics-s3 \
  --query 'Stacks[0].Outputs[?OutputKey==`ProcessedDataBucket`]'
```

## Development Workflow

When modifying services:

1. **Update code** in `phase3-ecs/services/{service-name}/app.py`
2. **Rebuild Docker image**: `cd phase3-ecs/scripts && ./build-and-push.sh`
3. **Force redeployment**:
   ```bash
   aws ecs update-service \
     --cluster medrobotics-cluster \
     --service medrobotics-{service-name} \
     --force-new-deployment
   ```
4. **Monitor logs**: `aws logs tail /aws/ecs/medrobotics/{service-name} --follow`

When modifying CloudFormation:

1. **Update template** in `phase*/cloudformation/*.yaml`
2. **Update stack**:
   ```bash
   aws cloudformation update-stack \
     --stack-name {stack-name} \
     --template-body file://{template-file} \
     --capabilities CAPABILITY_NAMED_IAM
   ```
3. **Monitor events**: `aws cloudformation describe-stack-events --stack-name {stack-name}`

## Cleanup & Teardown

### Complete Cleanup (All Phases)

**IMPORTANT**: The project has a master cleanup script that handles all dependencies:

```bash
cd /path/to/medical-robotics-data-platform
export ENVIRONMENT_NAME="medrobotics"
export AWS_REGION="us-east-1"

# Clean up ALL phases in correct dependency order
./scripts/cleanup-all-phases.sh

# Verify everything was deleted
./scripts/verify-cleanup.sh
```

**What it does:**
1. Deletes Phase 5 (EKS) if exists
2. Deletes Phase 4 (Redshift, Lambda, Step Functions)
3. Deletes Phase 3 (ECS services, ALB, ECR images)
4. Empties all S3 buckets
5. Deletes Phase 2 (VPC, RDS, S3, IAM, Security Groups)

**Manual deletion order** (if scripts fail):
- Phase 5 → Phase 4 → Phase 3 → Phase 2 (always reverse of deployment)
- Never try to delete Phase 2 while Phase 3 or 4 still exist (CloudFormation will prevent it due to cross-stack references)

### Individual Phase Cleanup

Only use these if you need to keep other phases running:

```bash
# Phase 4 only
cd phase4-redshift/scripts && ./cleanup.sh

# Phase 3 only (you need to create services first, or use master cleanup)
cd phase3-ecs/scripts && ./cleanup-ecs.sh

# Phase 2 only (will fail if Phase 3/4 exist)
cd phase2-infrastructure/scripts && ./cleanup-infrastructure.sh
```

## Cost Considerations

**Estimated Monthly Costs** (us-east-1):
- Phase 2 (Infrastructure): ~$80/month (RDS db.t3.micro + 2 NAT Gateways)
- Phase 3 (ECS): ~$55/month (2 Fargate tasks + ALB)
- Phase 4 (Redshift): ~$200/month (2x dc2.large cluster + Lambda)
- **Total**: ~$335/month for full deployment

**Cost Optimization**:
- Pause Redshift cluster when not in use: `aws redshift pause-cluster --cluster-identifier medrobotics-redshift`
- Use single NAT Gateway for dev (edit `01-vpc-network.yaml`)
- Delete stacks when done testing: `./scripts/cleanup-all-phases.sh`

## Additional Notes

- The project uses Python 3.11+ for Lambda functions and Python 3.8+ for data generators
- Flask services run on ports 8080 (ingestion) and 5000 (API)
- ETL is scheduled daily at 3 AM UTC via EventBridge (configurable in `03-step-functions.yaml`)
- Analytical views are pre-built for common queries (robot utilization, surgeon performance, facility benchmarking)
- All shell scripts assume Bash (Linux/Mac) or WSL (Windows)
