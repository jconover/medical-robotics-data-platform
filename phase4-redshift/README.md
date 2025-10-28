# Phase 4: Data Warehouse (Redshift) and ETL Pipeline

## Overview

Phase 4 establishes a complete data warehouse solution using Amazon Redshift with automated ETL pipelines to move data from operational databases (RDS) and raw data storage (S3) into a star schema optimized for analytics.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Data Sources                             │
├─────────────────────────────────────────────────────────────┤
│  RDS PostgreSQL          S3 Raw Bucket                       │
│  (Operational Data)      (Telemetry JSON)                    │
└───────────┬─────────────────────┬───────────────────────────┘
            │                     │
            ▼                     ▼
┌─────────────────────────────────────────────────────────────┐
│                    ETL Lambda Functions                      │
├─────────────────────────────────────────────────────────────┤
│  • RDS to Redshift ETL   • Telemetry ETL                    │
│  • Dimension loading     • Fact table loading                │
│  • SCD Type 2 handling   • Batch processing                  │
└───────────┬─────────────────────────────────────────────────┘
            │
            ▼
┌─────────────────────────────────────────────────────────────┐
│              Step Functions Orchestration                    │
├─────────────────────────────────────────────────────────────┤
│  1. Load Dimensions (Surgeons, Robots, Facilities)          │
│  2. Load Procedure Facts                                     │
│  3. Load Telemetry Facts                                     │
│  4. Error handling & retry logic                             │
└───────────┬─────────────────────────────────────────────────┘
            │
            ▼
┌─────────────────────────────────────────────────────────────┐
│              Amazon Redshift Cluster                         │
├─────────────────────────────────────────────────────────────┤
│  Star Schema Design:                                         │
│  • Dimension Tables (SCD2): dim_robots, dim_surgeons,       │
│    dim_facilities, dim_date, dim_time                        │
│  • Fact Tables: fact_procedures, fact_procedure_telemetry   │
│  • Pre-built Views: vw_robot_utilization,                   │
│    vw_surgeon_performance, etc.                              │
└─────────────────────────────────────────────────────────────┘
```

## Components

### 1. Redshift Cluster

**CloudFormation:** `cloudformation/01-redshift-cluster.yaml`

- **Node Type:** dc2.large (configurable)
- **Nodes:** 2-node cluster (160 GB storage total)
- **Database:** medrobotics_dw
- **Security:**
  - VPC isolation in data subnets
  - Encryption at rest with KMS
  - SSL required for connections
  - Enhanced VPC routing
- **Features:**
  - Automated snapshots (7-day retention)
  - CloudWatch monitoring and alarms
  - Query logging enabled

### 2. Data Warehouse Schema

**SQL Scripts:** `sql-schemas/`

#### Star Schema Design

**Dimension Tables:**
- `dim_robots` - Robot information with SCD Type 2
- `dim_surgeons` - Surgeon information with SCD Type 2
- `dim_facilities` - Facility information with SCD Type 2
- `dim_date` - Pre-populated date dimension (10 years)
- `dim_time` - Pre-populated time dimension (1-minute granularity)

**Fact Tables:**
- `fact_procedures` - Surgical procedure records with outcomes
- `fact_procedure_telemetry` - High-frequency telemetry data

**Distribution Strategy:**
- Dimension tables: `DISTSTYLE ALL` (broadcast to all nodes)
- Fact tables: `DISTSTYLE KEY` distributed on robot_key/procedure_key
- Sort keys optimized for date-based queries

### 3. ETL Lambda Functions

**Code:** `etl-functions/`

#### RDS to Redshift ETL (`rds_to_redshift_etl.py`)

Extracts data from RDS PostgreSQL and loads into Redshift:

**Functions:**
- `load_dimension_surgeons()` - SCD2 merge for surgeons
- `load_dimension_robots()` - SCD2 merge for robots
- `load_fact_procedures()` - Incremental procedure loading

**Process:**
1. Extract data from RDS with joins
2. Export to S3 as pipe-delimited CSV
3. Use Redshift COPY command for bulk loading
4. Apply SCD2 logic (expire old records, insert new)
5. Join with dimension keys

#### Telemetry ETL (`s3_telemetry_to_redshift.py`)

Processes high-volume telemetry from S3:

**Process:**
1. List telemetry JSON files in S3
2. Parse and transform JSON to flat structure
3. Consolidate into CSV batches
4. Upload to staging bucket
5. COPY into Redshift via temp table
6. Join with procedure keys

**CloudFormation:** `cloudformation/02-etl-lambda.yaml`

- Runtime: Python 3.11
- Memory: 1024 MB (RDS ETL), 2048 MB (Telemetry ETL)
- Timeout: 15 minutes
- VPC: Private subnets with access to RDS and Redshift
- Secrets: Retrieves credentials from Secrets Manager

### 4. Step Functions Orchestration

**CloudFormation:** `cloudformation/03-step-functions.yaml`

**Workflow Steps:**
1. **Load Dimensions** - Loads surgeons and robots (SCD2)
2. **Check Dimension Load** - Verifies success
3. **Load Procedures** - Loads procedure facts
4. **Check Procedure Load** - Verifies success
5. **Load Telemetry** - Loads telemetry facts
6. **Check Telemetry Load** - Verifies success

**Features:**
- Automatic retry with exponential backoff
- Error handling with partial success support
- CloudWatch Logs integration
- X-Ray tracing enabled
- Daily scheduled execution (3 AM UTC)
- SNS notifications for failures

### 5. Analytics Views

**SQL Scripts:** `queries/01-create-views.sql`

Pre-built views for common analytics:

- `vw_robot_utilization` - Robot usage statistics
- `vw_robot_utilization_monthly` - Monthly utilization trends
- `vw_procedure_outcomes` - Procedure success rates by type
- `vw_outcomes_by_robot_model` - Outcomes comparison by model
- `vw_surgeon_performance` - Surgeon performance metrics
- `vw_surgeon_procedure_categories` - Surgeon specialization analysis
- `vw_facility_performance` - Facility benchmarking
- `vw_daily_procedure_volume` - Daily volume trends
- `vw_procedures_by_time_of_day` - Time-of-day analysis
- `vw_outcomes_by_demographics` - Patient demographic analysis
- `vw_telemetry_system_health` - Robot system health metrics

### 6. Sample Queries

**SQL Scripts:** `queries/02-sample-queries.sql`

15 production-ready analytical queries:

1. Overall platform metrics dashboard
2. Top 10 most utilized robots
3. Monthly procedure volume trends
4. Complication rates by procedure type
5. Patient outcomes by robot model
6. Readmission analysis
7. Top performing surgeons
8. Surgeon experience correlation
9. Facility performance comparison
10. Facility utilization efficiency
11. Robot system health analysis
12. Procedure volume by day of week
13. Success rate by time of day
14. Year-over-year growth analysis
15. Patient cohort analysis

## Deployment

### Prerequisites

1. Phase 2 infrastructure deployed (VPC, RDS, S3)
2. AWS CLI configured
3. Python 3.11+ installed
4. pip and virtualenv

### Step 1: Deploy Infrastructure

```bash
cd phase4-redshift
./scripts/deploy.sh
```

This script will:
1. Package Lambda functions with dependencies
2. Upload Lambda code to S3
3. Deploy Redshift cluster (~10-15 minutes)
4. Deploy Lambda functions
5. Deploy Step Functions workflow

**Note:** You'll be prompted for the Redshift master password (8-64 alphanumeric characters).

### Step 2: Initialize Database

Connect to Redshift from a bastion host or authorized location:

```bash
# Get Redshift endpoint
REDSHIFT_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name medrobotics-redshift \
    --query 'Stacks[0].Outputs[?OutputKey==`ClusterEndpoint`].OutputValue' \
    --output text)

# Connect using psql
psql -h $REDSHIFT_ENDPOINT -U dwadmin -d medrobotics_dw -p 5439
```

Run initialization scripts in order:

```sql
-- Create tables and schema
\i sql-schemas/01-create-tables.sql

-- Populate dimension tables
\i sql-schemas/02-populate-dimensions.sql

-- Create analytical views
\i queries/01-create-views.sql
```

### Step 3: Run Initial ETL

```bash
# Run full ETL (dimensions + procedures + telemetry)
./scripts/run-etl.sh full

# Or run specific ETL types
./scripts/run-etl.sh dimensions
./scripts/run-etl.sh procedures "2024-01-01" "2024-12-31"
```

### Step 4: Verify Data

```sql
-- Check record counts
SELECT 'dim_robots' as table_name, COUNT(*) FROM dim_robots WHERE is_current = TRUE
UNION ALL
SELECT 'dim_surgeons', COUNT(*) FROM dim_surgeons WHERE is_current = TRUE
UNION ALL
SELECT 'dim_facilities', COUNT(*) FROM dim_facilities WHERE is_current = TRUE
UNION ALL
SELECT 'fact_procedures', COUNT(*) FROM fact_procedures
UNION ALL
SELECT 'fact_procedure_telemetry', COUNT(*) FROM fact_procedure_telemetry;

-- Test a view
SELECT * FROM vw_robot_utilization ORDER BY total_procedures DESC LIMIT 10;
```

## Usage

### Manual ETL Execution

```bash
# Full ETL (all components)
./scripts/run-etl.sh full

# Dimensions only
./scripts/run-etl.sh dimensions

# Procedures for specific date range
./scripts/run-etl.sh procedures "2024-01-01" "2024-01-31"

# Telemetry for specific batch
./scripts/run-etl.sh telemetry "20240115"
```

### Scheduled ETL

ETL runs automatically daily at 3 AM UTC via EventBridge. To modify the schedule:

1. Edit `cloudformation/03-step-functions.yaml`
2. Change the `ScheduleExpression` in `DailyETLSchedule`
3. Redeploy: `aws cloudformation update-stack ...`

### Query Examples

```sql
-- Executive dashboard - last 30 days
SELECT
    COUNT(DISTINCT p.procedure_key) as total_procedures,
    COUNT(DISTINCT r.robot_key) as active_robots,
    ROUND(AVG(p.duration_minutes), 2) as avg_duration,
    ROUND(AVG(p.patient_satisfaction_score), 2) as avg_satisfaction
FROM fact_procedures p
INNER JOIN dim_robots r ON p.robot_key = r.robot_key
INNER JOIN dim_date d ON p.start_date_key = d.date_key
WHERE d.date >= CURRENT_DATE - 30
  AND p.status = 'completed';

-- Top performing facilities
SELECT * FROM vw_facility_performance
ORDER BY success_rate_pct DESC, avg_satisfaction DESC
LIMIT 10;

-- Robot utilization trend
SELECT * FROM vw_robot_utilization_monthly
WHERE year = 2024
ORDER BY year, month;
```

### Monitoring

**CloudWatch Dashboards:**
- Redshift cluster metrics (CPU, disk, queries)
- Lambda execution metrics (invocations, errors, duration)
- Step Functions execution status

**CloudWatch Alarms:**
- `medrobotics-redshift-high-cpu` - CPU > 80%
- `medrobotics-redshift-low-disk` - Disk > 80% used
- `medrobotics-redshift-unhealthy` - Cluster unhealthy
- `medrobotics-etl-failures` - Step Functions failures
- `medrobotics-etl-long-running` - ETL > 30 minutes

**View Logs:**
```bash
# RDS ETL Lambda logs
aws logs tail /aws/lambda/medrobotics-rds-to-redshift-etl --follow

# Telemetry ETL Lambda logs
aws logs tail /aws/lambda/medrobotics-telemetry-etl --follow

# Step Functions logs
aws logs tail /aws/vendedlogs/states/medrobotics-etl-orchestration --follow
```

## Troubleshooting

### Issue: ETL Fails with Timeout

**Solution:** Increase Lambda timeout or reduce batch size
```yaml
# In cloudformation/02-etl-lambda.yaml
Timeout: 900  # Increase to 15 minutes
```

### Issue: Dimension Keys Not Matching

**Cause:** Dimensions not loaded before facts

**Solution:** Run dimensions ETL first
```bash
./scripts/run-etl.sh dimensions
./scripts/run-etl.sh procedures
```

### Issue: Redshift Connection Timeout

**Cause:** Security group or network configuration

**Solution:** Check security group rules
```bash
# Verify Lambda can access Redshift
aws ec2 describe-security-groups \
    --group-ids <redshift-sg-id> \
    --query 'SecurityGroups[0].IpPermissions'
```

### Issue: High Redshift Costs

**Solution:**
1. Pause cluster when not in use
2. Use dc2.large instead of ra3.xlplus for dev
3. Reduce snapshot retention
4. Consider Reserved Instances for production

```bash
# Pause cluster
aws redshift pause-cluster --cluster-identifier medrobotics-redshift

# Resume cluster
aws redshift resume-cluster --cluster-identifier medrobotics-redshift
```

## Cost Estimate

**Monthly costs (us-east-1):**

| Resource | Configuration | Monthly Cost |
|----------|--------------|--------------|
| Redshift Cluster | 2x dc2.large | ~$180 |
| Lambda (RDS ETL) | 1GB, daily runs | ~$5 |
| Lambda (Telemetry ETL) | 2GB, daily runs | ~$10 |
| Step Functions | Daily executions | ~$1 |
| Data Transfer | Within VPC | Minimal |
| CloudWatch Logs | 14-day retention | ~$5 |
| **Total** | | **~$200-220/month** |

**Cost Optimization:**
- Use Redshift pause/resume for dev environments
- Implement data retention policies
- Archive old data to S3 with Spectrum
- Use Concurrency Scaling only when needed

## Cleanup

To delete all Phase 4 resources:

```bash
./scripts/cleanup.sh
```

This will delete:
- Step Functions workflow
- Lambda functions
- Redshift cluster (with final snapshot)
- CloudWatch log groups
- Lambda deployment packages from S3

**Note:** Manual snapshot deletion may be required:
```bash
# List snapshots
aws redshift describe-cluster-snapshots

# Delete specific snapshot
aws redshift delete-cluster-snapshot --snapshot-identifier <snapshot-id>
```

## Next Steps

**Phase 5: Kubernetes (EKS)**
- Migrate ECS services to EKS
- Implement auto-scaling with HPA
- Add service mesh (Istio/LinkerD)
- Integrate with Redshift for real-time analytics

**Phase 6: CI/CD Pipeline**
- GitHub Actions workflows
- Automated testing
- Infrastructure validation
- Blue/green deployments

## Files Structure

```
phase4-redshift/
├── cloudformation/
│   ├── 01-redshift-cluster.yaml      # Redshift cluster definition
│   ├── 02-etl-lambda.yaml            # Lambda functions
│   └── 03-step-functions.yaml        # Workflow orchestration
├── etl-functions/
│   ├── rds_to_redshift_etl.py        # RDS ETL logic
│   ├── s3_telemetry_to_redshift.py   # Telemetry ETL logic
│   └── requirements.txt               # Python dependencies
├── sql-schemas/
│   ├── 01-create-tables.sql          # Star schema DDL
│   └── 02-populate-dimensions.sql    # Dimension data
├── queries/
│   ├── 01-create-views.sql           # Analytical views
│   └── 02-sample-queries.sql         # Example queries
├── scripts/
│   ├── deploy.sh                      # Deployment script
│   ├── run-etl.sh                     # Manual ETL trigger
│   └── cleanup.sh                     # Resource cleanup
└── README.md                          # This file
```

## Support

For issues or questions:
1. Check CloudWatch Logs for error details
2. Review AWS CloudFormation events
3. Verify security group configurations
4. Check IAM role permissions

## License

This project is part of a DevOps portfolio demonstration.
