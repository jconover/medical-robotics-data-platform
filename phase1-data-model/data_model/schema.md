# Medical Robotics Surgery Data Platform - Data Model

## Overview
This data model represents a comprehensive medical robotics platform that tracks surgical robots, procedures, patient outcomes, and real-time telemetry data.

## Entity Relationships

```
surgical_robots (1) -----> (N) surgical_procedures
surgical_procedures (1) -----> (N) procedure_telemetry
surgical_procedures (1) -----> (1) procedure_outcomes
surgical_robots (1) -----> (N) robot_maintenance_logs
```

## Entities

### 1. surgical_robots
Represents the physical robotic surgical systems.

| Column | Type | Description |
|--------|------|-------------|
| robot_id | UUID | Primary key |
| robot_serial_number | VARCHAR(50) | Unique manufacturer serial number |
| robot_model | VARCHAR(100) | Model name (e.g., "DaVinci Xi", "Versius", "ROSA") |
| manufacturer | VARCHAR(100) | Robot manufacturer |
| installation_date | DATE | Date installed at facility |
| facility_id | VARCHAR(50) | Hospital/facility identifier |
| facility_name | VARCHAR(200) | Hospital/facility name |
| status | VARCHAR(20) | operational, maintenance, retired |
| last_maintenance_date | DATE | Last maintenance performed |
| total_procedures | INTEGER | Cumulative procedure count |
| firmware_version | VARCHAR(20) | Current firmware version |
| created_at | TIMESTAMP | Record creation timestamp |
| updated_at | TIMESTAMP | Record update timestamp |

### 2. surgical_procedures
Represents individual surgical procedures performed.

| Column | Type | Description |
|--------|------|-------------|
| procedure_id | UUID | Primary key |
| robot_id | UUID | Foreign key to surgical_robots |
| procedure_type | VARCHAR(100) | Type of surgery (e.g., "Prostatectomy", "Hysterectomy") |
| procedure_category | VARCHAR(50) | Category (urological, gynecological, cardiac, etc.) |
| start_time | TIMESTAMP | Procedure start time |
| end_time | TIMESTAMP | Procedure end time |
| duration_minutes | INTEGER | Total procedure duration |
| surgeon_id | VARCHAR(50) | Operating surgeon identifier |
| surgeon_name | VARCHAR(200) | Operating surgeon name |
| patient_id | VARCHAR(50) | Anonymized patient identifier |
| patient_age | INTEGER | Patient age at time of procedure |
| patient_gender | VARCHAR(20) | Patient gender |
| complexity_score | DECIMAL(3,2) | Procedure complexity (1.0-5.0) |
| status | VARCHAR(20) | completed, in_progress, aborted, cancelled |
| created_at | TIMESTAMP | Record creation timestamp |

### 3. procedure_telemetry
Real-time telemetry data captured during procedures (high-frequency data).

| Column | Type | Description |
|--------|------|-------------|
| telemetry_id | UUID | Primary key |
| procedure_id | UUID | Foreign key to surgical_procedures |
| timestamp | TIMESTAMP | Telemetry capture timestamp |
| arm_position_x | DECIMAL(10,4) | Robotic arm X coordinate (mm) |
| arm_position_y | DECIMAL(10,4) | Robotic arm Y coordinate (mm) |
| arm_position_z | DECIMAL(10,4) | Robotic arm Z coordinate (mm) |
| arm_rotation | DECIMAL(6,2) | Arm rotation angle (degrees) |
| tool_type | VARCHAR(50) | Attached surgical tool |
| grip_pressure | DECIMAL(6,2) | Gripper pressure (N) |
| tremor_compensation | DECIMAL(5,2) | Tremor compensation level (%) |
| camera_zoom | DECIMAL(4,2) | Camera zoom level |
| camera_angle | DECIMAL(6,2) | Camera angle (degrees) |
| force_feedback_x | DECIMAL(8,4) | Force feedback X axis (N) |
| force_feedback_y | DECIMAL(8,4) | Force feedback Y axis (N) |
| force_feedback_z | DECIMAL(8,4) | Force feedback Z axis (N) |
| system_temperature | DECIMAL(5,2) | System temperature (Celsius) |
| power_consumption | DECIMAL(8,2) | Instantaneous power (Watts) |

### 4. procedure_outcomes
Post-procedure outcomes and metrics.

| Column | Type | Description |
|--------|------|-------------|
| outcome_id | UUID | Primary key |
| procedure_id | UUID | Foreign key to surgical_procedures (unique) |
| success_status | VARCHAR(20) | successful, complicated, failed |
| blood_loss_ml | INTEGER | Estimated blood loss (milliliters) |
| complications | TEXT | Comma-separated complications list |
| hospital_stay_days | INTEGER | Length of hospital stay |
| readmission_30day | BOOLEAN | Readmitted within 30 days |
| patient_satisfaction_score | INTEGER | Patient satisfaction (1-10) |
| surgeon_notes | TEXT | Surgeon's post-op notes |
| recovery_score | INTEGER | Recovery assessment (1-100) |
| follow_up_required | BOOLEAN | Follow-up appointment needed |
| created_at | TIMESTAMP | Record creation timestamp |
| updated_at | TIMESTAMP | Record update timestamp |

### 5. robot_maintenance_logs
Maintenance and service records for robots.

| Column | Type | Description |
|--------|------|-------------|
| maintenance_id | UUID | Primary key |
| robot_id | UUID | Foreign key to surgical_robots |
| maintenance_date | DATE | Date of maintenance |
| maintenance_type | VARCHAR(50) | routine, emergency, upgrade, calibration |
| technician_id | VARCHAR(50) | Service technician identifier |
| technician_name | VARCHAR(200) | Service technician name |
| issues_found | TEXT | Issues discovered during maintenance |
| actions_taken | TEXT | Maintenance actions performed |
| parts_replaced | TEXT | Parts replaced during service |
| downtime_hours | DECIMAL(6,2) | Robot downtime duration |
| next_maintenance_date | DATE | Scheduled next maintenance |
| cost | DECIMAL(10,2) | Maintenance cost (USD) |
| created_at | TIMESTAMP | Record creation timestamp |

## Data Storage Strategy

### RDS (PostgreSQL)
- surgical_robots
- surgical_procedures
- procedure_outcomes
- robot_maintenance_logs

**Rationale**: Relational data requiring ACID compliance, complex queries, and referential integrity.

### S3 (Raw Data Lake)
- procedure_telemetry (as JSON/Parquet files)
- Raw sensor logs
- Archived procedures

**Rationale**: High-volume time-series data, cost-effective storage, supports analytics.

### Redshift (Data Warehouse)
- Aggregated versions of all tables
- Analytics-optimized schemas
- Historical trend data
- Business intelligence queries

**Rationale**: OLAP queries, complex analytics, historical reporting, data science workloads.

## Sample Data Volumes

For this portfolio project, we'll generate:
- 50 surgical robots across 10 facilities
- 5,000 surgical procedures over 2 years
- ~500,000 telemetry records (100 samples per procedure)
- 5,000 procedure outcomes
- 200 maintenance logs

## Data Generation Approach

1. Generate surgical robots first (foundational data)
2. Generate maintenance logs for robots
3. Generate surgical procedures tied to robots
4. Generate telemetry data for each procedure
5. Generate outcomes for each completed procedure
