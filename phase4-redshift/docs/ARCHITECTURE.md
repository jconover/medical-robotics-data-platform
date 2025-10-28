# Phase 4: Data Warehouse Architecture

## Overview

Phase 4 implements a production-grade data warehouse solution using Amazon Redshift with automated ETL pipelines orchestrated by AWS Step Functions.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            DATA SOURCES                                  │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                ┌───────────────────┴───────────────────┐
                │                                       │
                ▼                                       ▼
┌───────────────────────────┐           ┌──────────────────────────────┐
│   RDS PostgreSQL          │           │   S3 Raw Bucket              │
│   (Operational Database)  │           │   (Telemetry JSON)           │
│                           │           │                              │
│   • surgical_robots       │           │   telemetry/                 │
│   • surgical_procedures   │           │   ├── procedure-1/           │
│   • procedure_outcomes    │           │   │   ├── 20240115.json     │
│   • robot_maintenance     │           │   │   └── 20240116.json     │
│                           │           │   └── procedure-2/           │
└───────────┬───────────────┘           └──────────────┬───────────────┘
            │                                          │
            │                                          │
            ▼                                          ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         EXTRACTION LAYER                                 │
│                                                                          │
│   ┌──────────────────────────────┐   ┌──────────────────────────────┐  │
│   │  RDS to Redshift ETL Lambda  │   │  Telemetry ETL Lambda        │  │
│   │                              │   │                              │  │
│   │  • Extract from PostgreSQL   │   │  • List S3 JSON files        │  │
│   │  • Transform to CSV          │   │  • Parse & transform         │  │
│   │  • Upload to S3 staging      │   │  • Consolidate batches       │  │
│   │  • COPY to Redshift          │   │  • Upload to S3 staging      │  │
│   │  • Apply SCD2 logic          │   │  • COPY to Redshift          │  │
│   └──────────────────────────────┘   └──────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                       ORCHESTRATION LAYER                                │
│                                                                          │
│                       AWS Step Functions                                 │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │  1. Load Dimensions (Surgeons, Robots, Facilities)             │   │
│   │     ├── Extract from RDS                                        │   │
│   │     ├── Stage to S3                                             │   │
│   │     └── Merge with SCD2 logic                                   │   │
│   │                                                                 │   │
│   │  2. Load Procedure Facts                                        │   │
│   │     ├── Extract procedures with outcomes                        │   │
│   │     ├── Join with dimension keys                                │   │
│   │     └── Insert into fact table                                  │   │
│   │                                                                 │   │
│   │  3. Load Telemetry Facts                                        │   │
│   │     ├── Process JSON files from S3                              │   │
│   │     ├── Transform to flat structure                             │   │
│   │     └── Insert with procedure key lookup                        │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│   • Retry logic with exponential backoff                                │
│   • Error handling with partial success                                 │
│   • Daily scheduled execution (3 AM UTC)                                │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         DATA WAREHOUSE                                   │
│                      Amazon Redshift Cluster                             │
│                                                                          │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                    DIMENSION TABLES                             │   │
│   │                                                                 │   │
│   │   dim_robots (SCD2)         dim_surgeons (SCD2)               │   │
│   │   ├── robot_key (PK)        ├── surgeon_key (PK)              │   │
│   │   ├── robot_id              ├── surgeon_id                     │   │
│   │   ├── robot_model           ├── surgeon_name                   │   │
│   │   ├── facility_key (FK)     ├── specialization                 │   │
│   │   ├── effective_date        ├── years_experience               │   │
│   │   ├── expiration_date       ├── effective_date                 │   │
│   │   └── is_current            ├── expiration_date                │   │
│   │                             └── is_current                      │   │
│   │                                                                 │   │
│   │   dim_facilities (SCD2)     dim_date                           │   │
│   │   ├── facility_key (PK)     ├── date_key (PK)                  │   │
│   │   ├── facility_id           ├── date                           │   │
│   │   ├── facility_name         ├── year, quarter, month           │   │
│   │   ├── city, state           ├── week, day                      │   │
│   │   ├── facility_type         ├── is_weekend, is_holiday         │   │
│   │   ├── effective_date        └── fiscal_year, fiscal_quarter    │   │
│   │   └── is_current                                               │   │
│   │                             dim_time                           │   │
│   │                             ├── time_key (PK)                  │   │
│   │                             ├── time_value                     │   │
│   │                             ├── hour, minute                   │   │
│   │                             ├── time_of_day                    │   │
│   │                             └── business_hours                 │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                      FACT TABLES                                │   │
│   │                                                                 │   │
│   │   fact_procedures                                               │   │
│   │   ├── procedure_key (PK)                                        │   │
│   │   ├── robot_key (FK) ─────────┐                                │   │
│   │   ├── surgeon_key (FK)        │                                │   │
│   │   ├── facility_key (FK)       │                                │   │
│   │   ├── start_date_key (FK)     │                                │   │
│   │   ├── start_time_key (FK)     │                                │   │
│   │   ├── procedure_type          │                                │   │
│   │   ├── duration_minutes        │                                │   │
│   │   ├── complexity_score        │                                │   │
│   │   ├── success_status          │                                │   │
│   │   ├── blood_loss_ml           │                                │   │
│   │   └── patient_satisfaction    │                                │   │
│   │                               │                                │   │
│   │   fact_procedure_telemetry    │                                │   │
│   │   ├── telemetry_key (PK)      │                                │   │
│   │   ├── procedure_key (FK) ─────┘                                │   │
│   │   ├── timestamp_key (FK)                                       │   │
│   │   ├── sample_timestamp                                         │   │
│   │   ├── arm_position (x,y,z)                                     │   │
│   │   ├── arm_rotation (x,y,z)                                     │   │
│   │   ├── force_feedback                                           │   │
│   │   ├── tool_type, tool_active                                   │   │
│   │   └── system metrics (temp, current, latency, fps)            │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│   Distribution Strategy:                                                │
│   • Dimensions: DISTSTYLE ALL (replicated to all nodes)                 │
│   • Facts: DISTSTYLE KEY on robot_key/procedure_key                     │
│   • Sort Keys: Optimized for date-based queries                         │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        ANALYTICS LAYER                                   │
│                                                                          │
│   Pre-built Views:                                                       │
│   ├── vw_robot_utilization - Robot usage statistics                     │
│   ├── vw_surgeon_performance - Surgeon metrics                          │
│   ├── vw_facility_performance - Facility benchmarking                   │
│   ├── vw_procedure_outcomes - Success rates by type                     │
│   ├── vw_daily_procedure_volume - Daily trends                          │
│   └── vw_telemetry_system_health - System health metrics                │
│                                                                          │
│   Sample Queries: 15 production-ready analytical queries                │
│   ├── Executive dashboard metrics                                       │
│   ├── Top performing surgeons/robots/facilities                         │
│   ├── Complication and readmission analysis                             │
│   ├── Time-based patterns and trends                                    │
│   └── Year-over-year growth analysis                                    │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                     MONITORING & ALERTING                                │
│                                                                          │
│   CloudWatch Logs:                                                       │
│   ├── Lambda execution logs (RDS ETL, Telemetry ETL)                    │
│   ├── Step Functions execution logs                                     │
│   └── Redshift query logs                                               │
│                                                                          │
│   CloudWatch Alarms:                                                     │
│   ├── Redshift CPU > 80%                                                │
│   ├── Redshift Disk > 80%                                               │
│   ├── Redshift cluster unhealthy                                        │
│   ├── ETL execution failures                                            │
│   └── ETL duration > 30 minutes                                         │
│                                                                          │
│   SNS Notifications:                                                     │
│   └── Alerts sent to operations team                                    │
└─────────────────────────────────────────────────────────────────────────┘
```

## Key Design Decisions

### 1. Star Schema Design

**Why Star Schema?**
- Optimized for analytical queries (OLAP)
- Simplified joins for reporting tools
- Better query performance vs normalized schema
- Industry standard for data warehousing

**SCD Type 2 Implementation:**
- Tracks historical changes in dimensions
- `effective_date` and `expiration_date` columns
- `is_current` flag for latest version
- Enables temporal analysis

### 2. Distribution Strategy

**ALL Distribution (Dimensions):**
- Replicates table to all compute nodes
- Eliminates network traffic for joins
- Ideal for small reference tables (<millions of rows)

**KEY Distribution (Facts):**
- Distributes rows based on key column
- Co-locates related data on same node
- Optimizes join performance
- Scales with data volume

**Sort Keys:**
- Date-based sort keys for time-series queries
- Reduces disk I/O by 50-90%
- Improves query planning

### 3. ETL Architecture

**Lambda Functions:**
- Serverless, pay-per-use
- Automatic scaling
- VPC integration for security
- 15-minute max runtime suitable for batch ETL

**Step Functions:**
- Visual workflow definition
- Built-in retry and error handling
- Audit trail of all executions
- Parallel execution support

**COPY Command:**
- Redshift's native bulk loading
- 10-100x faster than INSERT
- Automatic compression
- Parallel loading from S3

### 4. Data Loading Strategy

**Incremental Loading:**
- Only load new/changed records
- Reduces processing time and costs
- Uses watermark patterns (last processed date)

**Staging Tables:**
- Temporary tables for data validation
- Allows rollback on failure
- Enables complex transformations

**Batch Processing:**
- Groups telemetry records for efficiency
- Reduces number of COPY operations
- Balances throughput vs latency

## Performance Characteristics

### Expected Query Performance

| Query Type | Row Count | Avg Response Time |
|------------|-----------|-------------------|
| Dimension lookup | 1 row | < 100ms |
| Aggregation (daily) | 1000s rows | < 1s |
| Aggregation (monthly) | 100k rows | 1-3s |
| Join (fact + dims) | 1M rows | 2-5s |
| Full table scan | 10M+ rows | 10-30s |

### ETL Performance

| ETL Job | Data Volume | Execution Time |
|---------|-------------|----------------|
| Dimension load | 100s rows | 1-2 min |
| Procedure load | 1000s rows | 2-5 min |
| Telemetry load | 100k rows | 5-10 min |
| Full pipeline | All data | 10-20 min |

## Scalability

### Current Capacity (2x dc2.large)

- **Storage:** 160 GB SSD (80 GB per node)
- **Memory:** 30.5 GB (15.25 GB per node)
- **vCPUs:** 4 (2 per node)
- **Max Connections:** 500

### Scaling Options

**Vertical Scaling:**
- Upgrade to dc2.8xlarge (2.56 TB per node)
- Upgrade to ra3.4xlarge (128 TB with managed storage)

**Horizontal Scaling:**
- Add compute nodes (elastic resize)
- Near-zero downtime
- Linear performance improvement

**Concurrency Scaling:**
- Auto-scales for read queries
- Charges only during bursts
- Unlimited concurrent users

## Security

### Network Security

- **VPC Isolation:** Cluster in data subnets (no internet access)
- **Security Groups:** Port 5439 only from authorized sources
- **Enhanced VPC Routing:** All traffic stays within VPC

### Encryption

- **At Rest:** KMS encryption for cluster storage
- **In Transit:** SSL/TLS required for all connections
- **Snapshots:** Encrypted with same KMS key

### Access Control

- **IAM Roles:** Separate roles for Redshift, Lambda, Step Functions
- **Database Users:** Master user + application-specific users
- **Secrets Manager:** Credentials never in code or configs

## Monitoring & Observability

### Metrics

**Redshift Cluster:**
- CPU Utilization
- Disk Space Used
- Query Duration
- Connection Count
- Read/Write IOPS

**Lambda Functions:**
- Invocations
- Duration
- Errors
- Concurrent Executions
- Throttles

**Step Functions:**
- Executions Started
- Executions Succeeded
- Executions Failed
- Execution Duration

### Logs

**CloudWatch Log Groups:**
- `/aws/lambda/medrobotics-rds-to-redshift-etl`
- `/aws/lambda/medrobotics-telemetry-etl`
- `/aws/vendedlogs/states/medrobotics-etl-orchestration`

**Redshift Logs:**
- Connection log
- User activity log
- Query execution log

### Alarms

**Critical Alarms:**
- Cluster health status
- ETL pipeline failures
- High error rates

**Warning Alarms:**
- High CPU usage (> 80%)
- Low disk space (< 20%)
- Long-running queries (> 30 min)

## Cost Optimization Strategies

1. **Pause/Resume:** Pause cluster during non-business hours
2. **Reserved Instances:** 1-year or 3-year commitment (up to 75% savings)
3. **Right-sizing:** Start small (dc2.large), scale as needed
4. **Data Retention:** Archive old data to S3 with Redshift Spectrum
5. **Query Optimization:** Use EXPLAIN and optimize slow queries
6. **Concurrency Scaling:** Only enable if needed

## Future Enhancements

1. **Redshift Spectrum:** Query S3 data without loading
2. **Materialized Views:** Pre-compute complex aggregations
3. **Workload Management:** Prioritize critical queries
4. **Data Sharing:** Share live data with other Redshift clusters
5. **Machine Learning:** Use Redshift ML for predictive analytics
6. **Real-time Streaming:** Kinesis Data Firehose integration

## Related Documentation

- [Main README](../README.md) - Deployment and usage guide
- [Sample Queries](../queries/02-sample-queries.sql) - Example analytics
- [Schema DDL](../sql-schemas/01-create-tables.sql) - Table definitions
