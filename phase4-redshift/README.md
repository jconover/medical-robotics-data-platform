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

1. **Phase 2 infrastructure deployed** (VPC, RDS, S3, Bastion Host)
2. **AWS CLI configured** with appropriate credentials
3. **Python 3.11+** installed locally
4. **pip** and **virtualenv**
5. **psql client** (PostgreSQL client tools) on bastion host or local machine

### Step 1: Deploy Infrastructure

```bash
cd phase4-redshift
./scripts/deploy.sh
```

The deployment script will:
1. ✅ Check prerequisites (Phase 2 network stack exists)
2. ✅ Package Lambda functions with platform-specific dependencies (`manylinux2014_x86_64`)
3. ✅ Upload Lambda code to S3 with encryption
4. ✅ Deploy Redshift cluster (~10-15 minutes)
5. ✅ Deploy Lambda functions in VPC
6. ✅ Deploy Step Functions workflow with daily schedule

**Important Notes:**
- You'll be prompted for a Redshift master password (8-64 alphanumeric characters)
- The script is idempotent - it will skip stacks that already exist
- Lambda packages are built with correct platform binaries for AWS Lambda runtime

**Troubleshooting Common Deployment Issues:**

<details>
<summary>Issue: "No export named medrobotics-processed-bucket found"</summary>

**Cause:** Mismatch between export names in Phase 2 and imports in Phase 4.

**Solution:** This has been fixed in the templates. Phase 2 exports `medrobotics-processed-data-bucket` and Phase 4 correctly imports it.
</details>

<details>
<summary>Issue: Lambda fails with "No module named 'psycopg2._psycopg'"</summary>

**Cause:** Lambda package was built on local machine without Lambda-compatible binaries.

**Solution:** The deploy script now uses `--platform manylinux2014_x86_64 --only-binary=:all: --python-version 3.11` to ensure compatibility.

If you need to rebuild manually:
```bash
cd etl-functions
rm -rf build *.zip
pip install -r requirements.txt -t build/rds_etl/ \
    --platform manylinux2014_x86_64 --only-binary=:all: --python-version 3.11 --upgrade
```
</details>

<details>
<summary>Issue: S3 upload fails with "AccessDenied"</summary>

**Cause:** S3 bucket requires server-side encryption on all uploads.

**Solution:** The deploy script now includes `--sse AES256` flag on all S3 uploads. This is also configured in Phase 3 data ingestion service.
</details>

### Step 2: Initialize Redshift Database

The Redshift database must be initialized with schema and dimension data before running ETL. Since Redshift is in a private subnet, you must connect through the bastion host.

#### Connect to Bastion Host

**Note:** By default, the Phase 2 bastion host is deployed without an SSH key pair. Use AWS Systems Manager Session Manager to connect.

```bash
# Start SSM session to bastion host
aws ssm start-session --target $(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=medrobotics-bastion" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text) \
    --region us-east-1

# You should now see a shell prompt like:
# sh-5.2$
```

**Alternative: If you added an SSH key pair to your bastion:**
```bash
# Get bastion public IP
BASTION_IP=$(aws cloudformation describe-stacks \
    --stack-name medrobotics-bastion \
    --query 'Stacks[0].Outputs[?OutputKey==`BastionPublicIP`].OutputValue' \
    --output text \
    --region us-east-1)

# SSH to bastion
ssh -i ~/.ssh/your-key.pem ec2-user@$BASTION_IP
```

#### Set Up Connection Variables (on bastion):

```bash
# Get Redshift endpoint first (from local machine)
aws cloudformation describe-stacks --stack-name medrobotics-redshift \
    --query 'Stacks[0].Outputs[?OutputKey==`ClusterEndpoint`].OutputValue' \
    --output text --region us-east-1
# Example output: medrobotics-redshift.cvh3x8fpo9x6.us-east-1.redshift.amazonaws.com

# Now on the bastion, set these variables
export PGPASSWORD='YourRedshiftPassword'  # Use the password you set during deployment
export REDSHIFT_HOST='medrobotics-redshift.cvh3x8fpo9x6.us-east-1.redshift.amazonaws.com'  # Use actual endpoint

# Verify psql is installed
which psql
# Should output: /usr/bin/psql

# Test connection
psql -h $REDSHIFT_HOST -U dwadmin -d medrobotics_dw -p 5439 -c "SELECT version();"
# Should return: PostgreSQL 8.0.2 on ... compiled by ... Redshift
```

#### Create SQL Files on Bastion

Since there's no SSH key to use `scp`, create the SQL files directly on the bastion using heredocs:

**1. Create the table creation script:**

```bash
cd ~
cat > 01-create-tables.sql << 'EOF'
-- Drop existing tables
DROP TABLE IF EXISTS fact_procedure_telemetry CASCADE;
DROP TABLE IF EXISTS fact_procedures CASCADE;
DROP TABLE IF EXISTS dim_robots CASCADE;
DROP TABLE IF EXISTS dim_surgeons CASCADE;
DROP TABLE IF EXISTS dim_facilities CASCADE;
DROP TABLE IF EXISTS dim_date CASCADE;
DROP TABLE IF EXISTS dim_time CASCADE;

-- Create dim_date
CREATE TABLE dim_date (
    date_key INTEGER NOT NULL PRIMARY KEY,
    date DATE NOT NULL,
    year SMALLINT NOT NULL,
    quarter SMALLINT NOT NULL,
    month SMALLINT NOT NULL,
    month_name VARCHAR(10) NOT NULL,
    week SMALLINT NOT NULL,
    day_of_month SMALLINT NOT NULL,
    day_of_week SMALLINT NOT NULL,
    day_name VARCHAR(10) NOT NULL,
    is_weekend BOOLEAN NOT NULL,
    is_holiday BOOLEAN DEFAULT FALSE,
    fiscal_year SMALLINT NOT NULL,
    fiscal_quarter SMALLINT NOT NULL
) DISTSTYLE ALL SORTKEY (date_key);

-- Create dim_time
CREATE TABLE dim_time (
    time_key INTEGER NOT NULL PRIMARY KEY,
    time_value TIME NOT NULL,
    hour SMALLINT NOT NULL,
    minute SMALLINT NOT NULL,
    second SMALLINT NOT NULL,
    hour_12 SMALLINT NOT NULL,
    am_pm VARCHAR(2) NOT NULL,
    time_of_day VARCHAR(20) NOT NULL,
    business_hours BOOLEAN NOT NULL
) DISTSTYLE ALL SORTKEY (time_key);

-- Create dim_facilities
CREATE TABLE dim_facilities (
    facility_key INTEGER IDENTITY(1,1) PRIMARY KEY,
    facility_id VARCHAR(50) NOT NULL,
    facility_name VARCHAR(200) NOT NULL,
    city VARCHAR(100),
    state VARCHAR(50),
    country VARCHAR(50),
    facility_type VARCHAR(50),
    bed_count INTEGER,
    effective_date DATE NOT NULL,
    expiration_date DATE,
    is_current BOOLEAN NOT NULL DEFAULT TRUE
) DISTSTYLE ALL SORTKEY (facility_id, effective_date);

-- Create dim_surgeons
CREATE TABLE dim_surgeons (
    surgeon_key INTEGER IDENTITY(1,1) PRIMARY KEY,
    surgeon_id VARCHAR(50) NOT NULL,
    surgeon_name VARCHAR(200) NOT NULL,
    specialization VARCHAR(100),
    years_experience INTEGER,
    certification_level VARCHAR(50),
    effective_date DATE NOT NULL,
    expiration_date DATE,
    is_current BOOLEAN NOT NULL DEFAULT TRUE
) DISTSTYLE ALL SORTKEY (surgeon_id, effective_date);

-- Create dim_robots
CREATE TABLE dim_robots (
    robot_key INTEGER IDENTITY(1,1) PRIMARY KEY,
    robot_id VARCHAR(50) NOT NULL,
    robot_serial_number VARCHAR(100) NOT NULL,
    robot_model VARCHAR(100) NOT NULL,
    manufacturer VARCHAR(100),
    facility_key INTEGER,
    install_date DATE,
    software_version VARCHAR(50),
    hardware_revision VARCHAR(50),
    status VARCHAR(50),
    last_maintenance_date DATE,
    total_procedures_count INTEGER DEFAULT 0,
    total_operating_hours DECIMAL(10,2) DEFAULT 0,
    effective_date DATE NOT NULL,
    expiration_date DATE,
    is_current BOOLEAN NOT NULL DEFAULT TRUE
) DISTSTYLE KEY DISTKEY (robot_key) SORTKEY (robot_id, effective_date);

-- Create fact_procedures
CREATE TABLE fact_procedures (
    procedure_key BIGINT IDENTITY(1,1) PRIMARY KEY,
    procedure_id VARCHAR(100) NOT NULL,
    robot_key INTEGER NOT NULL,
    surgeon_key INTEGER NOT NULL,
    facility_key INTEGER NOT NULL,
    start_date_key INTEGER NOT NULL,
    start_time_key INTEGER NOT NULL,
    end_date_key INTEGER,
    end_time_key INTEGER,
    procedure_type VARCHAR(100) NOT NULL,
    procedure_category VARCHAR(50) NOT NULL,
    patient_id VARCHAR(100),
    patient_age SMALLINT,
    patient_gender VARCHAR(10),
    duration_minutes INTEGER,
    complexity_score DECIMAL(3,1),
    success_status VARCHAR(50),
    blood_loss_ml INTEGER,
    complication_level VARCHAR(50),
    hospital_stay_days INTEGER,
    patient_satisfaction_score DECIMAL(3,1),
    readmission_30day BOOLEAN,
    status VARCHAR(50) NOT NULL DEFAULT 'completed',
    created_at TIMESTAMP NOT NULL DEFAULT GETDATE(),
    updated_at TIMESTAMP
) DISTSTYLE KEY DISTKEY (robot_key) SORTKEY (start_date_key, robot_key);

-- Create fact_procedure_telemetry
CREATE TABLE fact_procedure_telemetry (
    telemetry_key BIGINT IDENTITY(1,1) PRIMARY KEY,
    procedure_key BIGINT NOT NULL,
    timestamp_key INTEGER NOT NULL,
    sample_timestamp TIMESTAMP NOT NULL,
    arm_position_x DECIMAL(10,4),
    arm_position_y DECIMAL(10,4),
    arm_position_z DECIMAL(10,4),
    arm_rotation_x DECIMAL(10,4),
    arm_rotation_y DECIMAL(10,4),
    arm_rotation_z DECIMAL(10,4),
    force_feedback DECIMAL(10,4),
    tool_type VARCHAR(100),
    tool_active BOOLEAN,
    camera_zoom DECIMAL(5,2),
    lighting_level INTEGER,
    system_temperature DECIMAL(5,2),
    motor_current DECIMAL(8,4),
    network_latency_ms INTEGER,
    video_fps INTEGER,
    created_at TIMESTAMP NOT NULL DEFAULT GETDATE()
) DISTSTYLE KEY DISTKEY (procedure_key) SORTKEY (procedure_key, sample_timestamp);
EOF

echo "Created 01-create-tables.sql"
```

**2. Create the dimension population script:**

```bash
cat > 02-populate-dimensions.sql << 'EOF'
-- Populate dim_date (10 years: 2020-2030)
INSERT INTO dim_date (
    date_key, date, year, quarter, month, month_name, week,
    day_of_month, day_of_week, day_name, is_weekend, is_holiday,
    fiscal_year, fiscal_quarter
)
SELECT
    CAST(TO_CHAR(d, 'YYYYMMDD') AS INTEGER) AS date_key,
    d AS date,
    EXTRACT(YEAR FROM d) AS year,
    EXTRACT(QUARTER FROM d) AS quarter,
    EXTRACT(MONTH FROM d) AS month,
    TO_CHAR(d, 'Month') AS month_name,
    EXTRACT(WEEK FROM d) AS week,
    EXTRACT(DAY FROM d) AS day_of_month,
    EXTRACT(DOW FROM d) AS day_of_week,
    TO_CHAR(d, 'Day') AS day_name,
    CASE WHEN EXTRACT(DOW FROM d) IN (0, 6) THEN TRUE ELSE FALSE END AS is_weekend,
    FALSE AS is_holiday,
    CASE WHEN EXTRACT(MONTH FROM d) >= 10 THEN EXTRACT(YEAR FROM d) + 1 ELSE EXTRACT(YEAR FROM d) END AS fiscal_year,
    CASE
        WHEN EXTRACT(MONTH FROM d) IN (10, 11, 12) THEN 1
        WHEN EXTRACT(MONTH FROM d) IN (1, 2, 3) THEN 2
        WHEN EXTRACT(MONTH FROM d) IN (4, 5, 6) THEN 3
        ELSE 4
    END AS fiscal_quarter
FROM (
    SELECT '2020-01-01'::DATE + (seq - 1) AS d
    FROM (
        SELECT ROW_NUMBER() OVER (ORDER BY 1) AS seq
        FROM pg_catalog.pg_class c1
        CROSS JOIN pg_catalog.pg_class c2
        LIMIT 3653
    )
) dates;

-- Mark holidays
UPDATE dim_date SET is_holiday = TRUE WHERE month = 1 AND day_of_month = 1;
UPDATE dim_date SET is_holiday = TRUE WHERE month = 7 AND day_of_month = 4;
UPDATE dim_date SET is_holiday = TRUE WHERE month = 12 AND day_of_month = 25;

-- Populate dim_time (1-minute granularity)
INSERT INTO dim_time (
    time_key, time_value, hour, minute, second, hour_12, am_pm, time_of_day, business_hours
)
SELECT
    (hour * 10000 + minute * 100) AS time_key,
    (hour::TEXT || ':' || LPAD(minute::TEXT, 2, '0') || ':00')::TIME AS time_value,
    hour, minute, 0 AS second,
    CASE WHEN hour = 0 THEN 12 WHEN hour > 12 THEN hour - 12 ELSE hour END AS hour_12,
    CASE WHEN hour < 12 THEN 'AM' ELSE 'PM' END AS am_pm,
    CASE
        WHEN hour >= 5 AND hour < 12 THEN 'Morning'
        WHEN hour >= 12 AND hour < 17 THEN 'Afternoon'
        WHEN hour >= 17 AND hour < 21 THEN 'Evening'
        ELSE 'Night'
    END AS time_of_day,
    CASE WHEN hour >= 8 AND hour < 18 THEN TRUE ELSE FALSE END AS business_hours
FROM (
    SELECT h AS hour, m AS minute
    FROM (
        SELECT ROW_NUMBER() OVER (ORDER BY 1) - 1 AS h
        FROM pg_catalog.pg_class LIMIT 24
    ) hours
    CROSS JOIN (
        SELECT ROW_NUMBER() OVER (ORDER BY 1) - 1 AS m
        FROM pg_catalog.pg_class LIMIT 60
    ) minutes
) times;

-- Populate sample facilities
INSERT INTO dim_facilities (
    facility_id, facility_name, city, state, country, facility_type, bed_count,
    effective_date, expiration_date, is_current
)
VALUES
    ('FAC-001', 'Memorial Medical Center', 'Boston', 'MA', 'USA', 'Teaching Hospital', 850, '2020-01-01', NULL, TRUE),
    ('FAC-002', 'St. Mary''s Hospital', 'New York', 'NY', 'USA', 'Private Hospital', 600, '2020-01-01', NULL, TRUE),
    ('FAC-003', 'Bay Area Surgical Institute', 'San Francisco', 'CA', 'USA', 'Specialty Center', 400, '2020-01-01', NULL, TRUE),
    ('FAC-004', 'Texas Medical Complex', 'Houston', 'TX', 'USA', 'Teaching Hospital', 900, '2020-01-01', NULL, TRUE),
    ('FAC-005', 'Pacific Northwest Regional', 'Seattle', 'WA', 'USA', 'Regional Hospital', 550, '2020-01-01', NULL, TRUE);

-- Vacuum and analyze
VACUUM DELETE ONLY dim_date;
VACUUM DELETE ONLY dim_time;
VACUUM DELETE ONLY dim_facilities;
ANALYZE dim_date;
ANALYZE dim_time;
ANALYZE dim_facilities;
EOF

echo "Created 02-populate-dimensions.sql"
```

#### Run SQL Initialization (on bastion):

```bash
# 1. Create tables and schema
psql -h $REDSHIFT_HOST -U dwadmin -d medrobotics_dw -p 5439 -f ./01-create-tables.sql

# Expected output: CREATE TABLE for each table
# Note: Errors about "CREATE INDEX" not supported are EXPECTED and can be ignored
#       Redshift uses SORTKEY/DISTKEY instead of traditional indexes

# 2. Populate dimension tables
psql -h $REDSHIFT_HOST -U dwadmin -d medrobotics_dw -p 5439 -f ./02-populate-dimensions.sql

# This will:
# - Generate 3,653 date records (10 years: 2020-2030)
# - Generate 1,440 time records (24 hours × 60 minutes)
# - Insert 10 sample facilities

# 3. Verify tables were created
psql -h $REDSHIFT_HOST -U dwadmin -d medrobotics_dw -p 5439 -c "\dt"

# You should see:
# dim_date, dim_time, dim_facilities, dim_surgeons, dim_robots
# fact_procedures, fact_procedure_telemetry
```

**Important Notes:**
- ⚠️ The SQL file contains `ENCODE LZO` specifications. BOOLEAN columns cannot have explicit encoding in Redshift (this has been fixed in the provided SQL files)
- ⚠️ The populate dimensions script generates date/time data using system catalog tables (`pg_catalog.pg_class`), not empty dimension tables
- ⚠️ The Redshift password must match what's stored in AWS Secrets Manager (`medrobotics-redshift-secret`)

**Troubleshooting SQL Initialization:**

<details>
<summary>Error: "invalid encoding type specified for column 'is_weekend'"</summary>

**Cause:** Redshift doesn't support explicit encoding (ENCODE LZO) for BOOLEAN columns.

**Solution:** The SQL files have been updated to remove `ENCODE LZO` from all BOOLEAN columns. Use the latest version from the repository.
</details>

<details>
<summary>Error: "password authentication failed for user 'dwadmin'"</summary>

**Cause:** Mismatch between Redshift master password and Secrets Manager.

**Solution:** Update the Redshift master password or update Secrets Manager:
```bash
# Update Redshift password
aws redshift modify-cluster \
    --cluster-identifier medrobotics-redshift \
    --master-user-password "YourNewPassword" \
    --region us-east-1

# Update secret
aws secretsmanager update-secret \
    --secret-id medrobotics-redshift-secret \
    --secret-string '{"username":"dwadmin","password":"YourNewPassword"}' \
    --region us-east-1
```
</details>

### Step 3: Create Analytical Views (Optional but Recommended)

The analytical views provide pre-built queries for common reporting needs. First, create the SQL file on the bastion host:

<details>
<summary>Click to expand: Create queries/01-create-views.sql file</summary>

```bash
# On bastion host - create the queries directory and views file
mkdir -p queries
cat > queries/01-create-views.sql << 'EOF'
-- Medical Robotics Data Platform - Redshift Analytical Views
-- Pre-built views for common analytical queries

-- ============================================================================
-- ROBOT UTILIZATION VIEWS
-- ============================================================================

-- View: Robot Utilization Summary
CREATE OR REPLACE VIEW vw_robot_utilization AS
SELECT
    r.robot_id,
    r.robot_serial_number,
    r.robot_model,
    f.facility_name,
    f.city,
    f.state,
    COUNT(DISTINCT p.procedure_key) as total_procedures,
    SUM(p.duration_minutes) / 60.0 as total_operating_hours,
    AVG(p.duration_minutes) as avg_procedure_duration_minutes,
    AVG(p.complexity_score) as avg_complexity,
    MIN(d.date) as first_procedure_date,
    MAX(d.date) as last_procedure_date,
    DATEDIFF(day, MIN(d.date), MAX(d.date)) + 1 as days_in_operation,
    COUNT(DISTINCT p.procedure_key)::FLOAT /
        NULLIF(DATEDIFF(day, MIN(d.date), MAX(d.date)) + 1, 0) as procedures_per_day
FROM dim_robots r
INNER JOIN fact_procedures p ON r.robot_key = p.robot_key
INNER JOIN dim_facilities f ON r.facility_key = f.facility_key
INNER JOIN dim_date d ON p.start_date_key = d.date_key
WHERE r.is_current = TRUE
  AND f.is_current = TRUE
GROUP BY r.robot_id, r.robot_serial_number, r.robot_model,
         f.facility_name, f.city, f.state;

-- View: Monthly Robot Utilization Trend
CREATE OR REPLACE VIEW vw_robot_utilization_monthly AS
SELECT
    r.robot_id,
    r.robot_model,
    f.facility_name,
    d.year,
    d.month,
    d.month_name,
    COUNT(DISTINCT p.procedure_key) as procedure_count,
    SUM(p.duration_minutes) / 60.0 as operating_hours,
    AVG(p.duration_minutes) as avg_duration,
    AVG(p.complexity_score) as avg_complexity
FROM dim_robots r
INNER JOIN fact_procedures p ON r.robot_key = p.robot_key
INNER JOIN dim_facilities f ON r.facility_key = f.facility_key
INNER JOIN dim_date d ON p.start_date_key = d.date_key
WHERE r.is_current = TRUE
GROUP BY r.robot_id, r.robot_model, f.facility_name,
         d.year, d.month, d.month_name;

-- ============================================================================
-- PROCEDURE OUTCOME VIEWS
-- ============================================================================

-- View: Procedure Outcomes Summary
CREATE OR REPLACE VIEW vw_procedure_outcomes AS
SELECT
    p.procedure_type,
    p.procedure_category,
    COUNT(*) as total_procedures,
    SUM(CASE WHEN p.success_status = 'Successful' THEN 1 ELSE 0 END) as successful_count,
    SUM(CASE WHEN p.success_status = 'Successful' THEN 1 ELSE 0 END)::FLOAT /
        NULLIF(COUNT(*), 0) * 100 as success_rate,
    AVG(p.duration_minutes) as avg_duration_minutes,
    AVG(p.blood_loss_ml) as avg_blood_loss_ml,
    AVG(p.hospital_stay_days) as avg_hospital_stay_days,
    AVG(p.patient_satisfaction_score) as avg_satisfaction_score,
    SUM(CASE WHEN p.complication_level IN ('Moderate', 'Severe') THEN 1 ELSE 0 END) as complication_count,
    SUM(CASE WHEN p.readmission_30day = TRUE THEN 1 ELSE 0 END) as readmission_count,
    SUM(CASE WHEN p.readmission_30day = TRUE THEN 1 ELSE 0 END)::FLOAT /
        NULLIF(COUNT(*), 0) * 100 as readmission_rate
FROM fact_procedures p
WHERE p.status = 'completed'
GROUP BY p.procedure_type, p.procedure_category;

-- View: Outcomes by Robot Model
CREATE OR REPLACE VIEW vw_outcomes_by_robot_model AS
SELECT
    r.robot_model,
    r.manufacturer,
    COUNT(DISTINCT p.procedure_key) as total_procedures,
    AVG(p.complexity_score) as avg_complexity,
    SUM(CASE WHEN p.success_status = 'Successful' THEN 1 ELSE 0 END)::FLOAT /
        NULLIF(COUNT(*), 0) * 100 as success_rate,
    AVG(p.duration_minutes) as avg_duration,
    AVG(p.blood_loss_ml) as avg_blood_loss,
    AVG(p.patient_satisfaction_score) as avg_satisfaction,
    SUM(CASE WHEN p.complication_level = 'None' THEN 1 ELSE 0 END)::FLOAT /
        NULLIF(COUNT(*), 0) * 100 as no_complication_rate
FROM dim_robots r
INNER JOIN fact_procedures p ON r.robot_key = p.robot_key
WHERE r.is_current = TRUE
  AND p.status = 'completed'
GROUP BY r.robot_model, r.manufacturer
ORDER BY total_procedures DESC;

-- ============================================================================
-- SURGEON PERFORMANCE VIEWS
-- ============================================================================

-- View: Surgeon Performance Summary
CREATE OR REPLACE VIEW vw_surgeon_performance AS
SELECT
    s.surgeon_id,
    s.surgeon_name,
    s.specialization,
    s.years_experience,
    COUNT(DISTINCT p.procedure_key) as total_procedures,
    AVG(p.complexity_score) as avg_complexity_score,
    SUM(CASE WHEN p.success_status = 'Successful' THEN 1 ELSE 0 END)::FLOAT /
        NULLIF(COUNT(*), 0) * 100 as success_rate,
    AVG(p.duration_minutes) as avg_procedure_duration,
    AVG(p.blood_loss_ml) as avg_blood_loss,
    AVG(p.patient_satisfaction_score) as avg_patient_satisfaction,
    SUM(CASE WHEN p.complication_level = 'None' THEN 1 ELSE 0 END)::FLOAT /
        NULLIF(COUNT(*), 0) * 100 as no_complication_rate,
    SUM(CASE WHEN p.readmission_30day = FALSE OR p.readmission_30day IS NULL THEN 1 ELSE 0 END)::FLOAT /
        NULLIF(COUNT(*), 0) * 100 as no_readmission_rate
FROM dim_surgeons s
INNER JOIN fact_procedures p ON s.surgeon_key = p.surgeon_key
WHERE s.is_current = TRUE
  AND p.status = 'completed'
GROUP BY s.surgeon_id, s.surgeon_name, s.specialization, s.years_experience;

-- View: Surgeon Procedure Volume by Category
CREATE OR REPLACE VIEW vw_surgeon_procedure_categories AS
SELECT
    s.surgeon_name,
    p.procedure_category,
    COUNT(*) as procedure_count,
    AVG(p.complexity_score) as avg_complexity,
    AVG(p.duration_minutes) as avg_duration,
    SUM(CASE WHEN p.success_status = 'Successful' THEN 1 ELSE 0 END)::FLOAT /
        NULLIF(COUNT(*), 0) * 100 as success_rate
FROM dim_surgeons s
INNER JOIN fact_procedures p ON s.surgeon_key = p.surgeon_key
WHERE s.is_current = TRUE
  AND p.status = 'completed'
GROUP BY s.surgeon_name, p.procedure_category;

-- ============================================================================
-- FACILITY ANALYTICS VIEWS
-- ============================================================================

-- View: Facility Performance
CREATE OR REPLACE VIEW vw_facility_performance AS
SELECT
    f.facility_id,
    f.facility_name,
    f.city,
    f.state,
    f.facility_type,
    COUNT(DISTINCT r.robot_key) as robot_count,
    COUNT(DISTINCT p.procedure_key) as total_procedures,
    COUNT(DISTINCT p.surgeon_key) as surgeon_count,
    AVG(p.duration_minutes) as avg_procedure_duration,
    SUM(CASE WHEN p.success_status = 'Successful' THEN 1 ELSE 0 END)::FLOAT /
        NULLIF(COUNT(*), 0) * 100 as success_rate,
    AVG(p.patient_satisfaction_score) as avg_patient_satisfaction,
    AVG(p.hospital_stay_days) as avg_hospital_stay
FROM dim_facilities f
INNER JOIN dim_robots r ON f.facility_key = r.facility_key AND r.is_current = TRUE
INNER JOIN fact_procedures p ON r.robot_key = p.robot_key
WHERE f.is_current = TRUE
  AND p.status = 'completed'
GROUP BY f.facility_id, f.facility_name, f.city, f.state, f.facility_type;

-- ============================================================================
-- TIME-BASED ANALYTICS VIEWS
-- ============================================================================

-- View: Daily Procedure Volume
CREATE OR REPLACE VIEW vw_daily_procedure_volume AS
SELECT
    d.date,
    d.year,
    d.month,
    d.day_name,
    d.is_weekend,
    COUNT(DISTINCT p.procedure_key) as procedure_count,
    AVG(p.duration_minutes) as avg_duration,
    SUM(p.duration_minutes) / 60.0 as total_operating_hours
FROM dim_date d
INNER JOIN fact_procedures p ON d.date_key = p.start_date_key
WHERE p.status = 'completed'
GROUP BY d.date, d.year, d.month, d.day_name, d.is_weekend
ORDER BY d.date;

-- View: Procedures by Time of Day
CREATE OR REPLACE VIEW vw_procedures_by_time_of_day AS
SELECT
    t.time_of_day,
    t.business_hours,
    COUNT(DISTINCT p.procedure_key) as procedure_count,
    AVG(p.duration_minutes) as avg_duration,
    AVG(p.complexity_score) as avg_complexity,
    SUM(CASE WHEN p.success_status = 'Successful' THEN 1 ELSE 0 END)::FLOAT /
        NULLIF(COUNT(*), 0) * 100 as success_rate
FROM dim_time t
INNER JOIN fact_procedures p ON t.time_key = p.start_time_key
WHERE p.status = 'completed'
GROUP BY t.time_of_day, t.business_hours
ORDER BY procedure_count DESC;

-- ============================================================================
-- PATIENT DEMOGRAPHICS VIEWS
-- ============================================================================

-- View: Outcomes by Patient Demographics
CREATE OR REPLACE VIEW vw_outcomes_by_demographics AS
SELECT
    p.patient_gender,
    CASE
        WHEN p.patient_age < 30 THEN '< 30'
        WHEN p.patient_age BETWEEN 30 AND 49 THEN '30-49'
        WHEN p.patient_age BETWEEN 50 AND 64 THEN '50-64'
        WHEN p.patient_age >= 65 THEN '65+'
        ELSE 'Unknown'
    END as age_group,
    COUNT(*) as procedure_count,
    AVG(p.complexity_score) as avg_complexity,
    SUM(CASE WHEN p.success_status = 'Successful' THEN 1 ELSE 0 END)::FLOAT /
        NULLIF(COUNT(*), 0) * 100 as success_rate,
    AVG(p.duration_minutes) as avg_duration,
    AVG(p.blood_loss_ml) as avg_blood_loss,
    AVG(p.hospital_stay_days) as avg_hospital_stay,
    AVG(p.patient_satisfaction_score) as avg_satisfaction
FROM fact_procedures p
WHERE p.status = 'completed'
  AND p.patient_age IS NOT NULL
GROUP BY p.patient_gender,
         CASE
            WHEN p.patient_age < 30 THEN '< 30'
            WHEN p.patient_age BETWEEN 30 AND 49 THEN '30-49'
            WHEN p.patient_age BETWEEN 50 AND 64 THEN '50-64'
            WHEN p.patient_age >= 65 THEN '65+'
            ELSE 'Unknown'
         END;

-- ============================================================================
-- TELEMETRY ANALYTICS VIEWS
-- ============================================================================

-- View: Telemetry System Health Summary
CREATE OR REPLACE VIEW vw_telemetry_system_health AS
SELECT
    p.procedure_id,
    r.robot_model,
    f.facility_name,
    d.date,
    COUNT(*) as telemetry_sample_count,
    AVG(t.system_temperature) as avg_temperature,
    MAX(t.system_temperature) as max_temperature,
    AVG(t.motor_current) as avg_motor_current,
    MAX(t.motor_current) as max_motor_current,
    AVG(t.network_latency_ms) as avg_network_latency,
    MAX(t.network_latency_ms) as max_network_latency,
    AVG(t.video_fps) as avg_video_fps,
    MIN(t.video_fps) as min_video_fps
FROM fact_procedure_telemetry t
INNER JOIN fact_procedures p ON t.procedure_key = p.procedure_key
INNER JOIN dim_robots r ON p.robot_key = r.robot_key
INNER JOIN dim_facilities f ON p.facility_key = f.facility_key
INNER JOIN dim_date d ON p.start_date_key = d.date_key
WHERE r.is_current = TRUE
  AND f.is_current = TRUE
GROUP BY p.procedure_id, r.robot_model, f.facility_name, d.date;
EOF
```
</details>

Now execute the SQL file to create all analytical views:

```bash
# On bastion host
psql -h $REDSHIFT_HOST -U dwadmin -d medrobotics_dw -p 5439 -f queries/01-create-views.sql

# This creates views like:
# - vw_robot_utilization
# - vw_surgeon_performance
# - vw_facility_performance
# - vw_procedure_outcomes
# - vw_telemetry_system_health
# etc.
```

### Step 4: Run Initial ETL

Now that the database is initialized, run the ETL pipeline to load data from RDS and S3:

```bash
# From your local machine in phase4-redshift directory
cd scripts
./run-etl.sh
```

The ETL will:
1. ✅ Load dimension data (surgeons, robots, facilities) from RDS
2. ✅ Load procedure facts from RDS
3. ✅ Load telemetry data from S3

**Monitor ETL execution:**
```bash
# The script will show progress like:
# [INFO] Execution started: medrobotics-etl-20251030-120000
# [INFO] Monitoring execution status...
# .....
# [SUCCESS] ETL execution completed successfully
```

**View detailed logs:**
```bash
# RDS ETL Lambda logs
aws logs tail /aws/lambda/medrobotics-rds-to-redshift-etl --follow --region us-east-1

# Telemetry ETL Lambda logs
aws logs tail /aws/lambda/medrobotics-telemetry-etl --follow --region us-east-1

# Step Functions execution history
aws stepfunctions list-executions \
    --state-machine-arn $(aws cloudformation describe-stacks \
        --stack-name medrobotics-step-functions \
        --query 'Stacks[0].Outputs[?OutputKey==`StateMachineArn`].OutputValue' \
        --output text --region us-east-1) \
    --max-results 5 --region us-east-1
```

**Troubleshooting ETL:**

<details>
<summary>Error: "connection to server failed: FATAL: password authentication failed"</summary>

**Solution:** Ensure Redshift password in Secrets Manager matches the actual password (see Step 2 troubleshooting).
</details>

<details>
<summary>Error: "relation 'dim_surgeons' does not exist"</summary>

**Solution:** You skipped Step 2. Run the SQL initialization scripts first.
</details>

### Step 5: Verify Data

Connect to Redshift and verify data was loaded:

```bash
# On bastion or via psql
export PGPASSWORD='YourRedshiftPassword'
psql -h $REDSHIFT_HOST -U dwadmin -d medrobotics_dw -p 5439
```

```sql
-- Check record counts
SELECT 'dim_date' as table_name, COUNT(*) as count FROM dim_date
UNION ALL
SELECT 'dim_time', COUNT(*) FROM dim_time
UNION ALL
SELECT 'dim_facilities', COUNT(*) FROM dim_facilities WHERE is_current = TRUE
UNION ALL
SELECT 'dim_surgeons', COUNT(*) FROM dim_surgeons WHERE is_current = TRUE
UNION ALL
SELECT 'dim_robots', COUNT(*) FROM dim_robots WHERE is_current = TRUE
UNION ALL
SELECT 'fact_procedures', COUNT(*) FROM fact_procedures
UNION ALL
SELECT 'fact_procedure_telemetry', COUNT(*) FROM fact_procedure_telemetry
ORDER BY table_name;

-- Expected output:
-- dim_date: 3653 rows (10 years)
-- dim_time: 1440 rows (24h × 60m)
-- dim_facilities: 10+ rows
-- dim_surgeons: varies (from RDS)
-- dim_robots: varies (from RDS)
-- fact_procedures: varies (from RDS)
-- fact_procedure_telemetry: varies (from S3)

-- Test analytical views
SELECT * FROM vw_robot_utilization
ORDER BY total_procedures DESC
LIMIT 10;

-- Quick data quality check
SELECT
    COUNT(*) as total_procedures,
    COUNT(DISTINCT robot_key) as unique_robots,
    MIN(start_date_key) as earliest_date,
    MAX(start_date_key) as latest_date
FROM fact_procedures;
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
