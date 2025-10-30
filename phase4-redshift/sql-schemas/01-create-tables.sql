-- Medical Robotics Data Platform - Redshift Data Warehouse Schema
-- This schema is optimized for analytical queries on surgical robotics data

-- Drop existing tables (for clean deployment)
DROP TABLE IF EXISTS fact_procedure_telemetry CASCADE;
DROP TABLE IF EXISTS fact_procedures CASCADE;
DROP TABLE IF EXISTS dim_robots CASCADE;
DROP TABLE IF EXISTS dim_surgeons CASCADE;
DROP TABLE IF EXISTS dim_facilities CASCADE;
DROP TABLE IF EXISTS dim_date CASCADE;
DROP TABLE IF EXISTS dim_time CASCADE;

-- ============================================================================
-- DIMENSION TABLES
-- ============================================================================

-- Dimension: Date
-- Pre-populated date dimension for fast date-based queries
CREATE TABLE dim_date (
    date_key INTEGER NOT NULL PRIMARY KEY ENCODE RAW,
    date DATE NOT NULL ENCODE LZO,
    year SMALLINT NOT NULL ENCODE LZO,
    quarter SMALLINT NOT NULL ENCODE LZO,
    month SMALLINT NOT NULL ENCODE LZO,
    month_name VARCHAR(10) NOT NULL ENCODE LZO,
    week SMALLINT NOT NULL ENCODE LZO,
    day_of_month SMALLINT NOT NULL ENCODE LZO,
    day_of_week SMALLINT NOT NULL ENCODE LZO,
    day_name VARCHAR(10) NOT NULL ENCODE LZO,
    is_weekend BOOLEAN NOT NULL,
    is_holiday BOOLEAN DEFAULT FALSE,
    fiscal_year SMALLINT NOT NULL ENCODE LZO,
    fiscal_quarter SMALLINT NOT NULL ENCODE LZO
)
DISTSTYLE ALL
SORTKEY (date_key);

-- Dimension: Time
-- Pre-populated time dimension for time-of-day analysis
CREATE TABLE dim_time (
    time_key INTEGER NOT NULL PRIMARY KEY ENCODE RAW,
    time_value TIME NOT NULL ENCODE LZO,
    hour SMALLINT NOT NULL ENCODE LZO,
    minute SMALLINT NOT NULL ENCODE LZO,
    second SMALLINT NOT NULL ENCODE LZO,
    hour_12 SMALLINT NOT NULL ENCODE LZO,
    am_pm VARCHAR(2) NOT NULL ENCODE LZO,
    time_of_day VARCHAR(20) NOT NULL ENCODE LZO, -- Morning, Afternoon, Evening, Night
    business_hours BOOLEAN NOT NULL
)
DISTSTYLE ALL
SORTKEY (time_key);

-- Dimension: Facilities
-- Slowly Changing Dimension Type 2 (SCD2) for facility information
CREATE TABLE dim_facilities (
    facility_key INTEGER IDENTITY(1,1) PRIMARY KEY ENCODE RAW,
    facility_id VARCHAR(50) NOT NULL ENCODE LZO,
    facility_name VARCHAR(200) NOT NULL ENCODE LZO,
    city VARCHAR(100) ENCODE LZO,
    state VARCHAR(50) ENCODE LZO,
    country VARCHAR(50) ENCODE LZO,
    facility_type VARCHAR(50) ENCODE LZO, -- Teaching Hospital, Private Hospital, etc.
    bed_count INTEGER ENCODE LZO,
    -- SCD2 fields
    effective_date DATE NOT NULL ENCODE LZO,
    expiration_date DATE ENCODE LZO,
    is_current BOOLEAN NOT NULL DEFAULT TRUE
)
DISTSTYLE ALL
SORTKEY (facility_id, effective_date);

-- Dimension: Surgeons
-- SCD2 for surgeon information
CREATE TABLE dim_surgeons (
    surgeon_key INTEGER IDENTITY(1,1) PRIMARY KEY ENCODE RAW,
    surgeon_id VARCHAR(50) NOT NULL ENCODE LZO,
    surgeon_name VARCHAR(200) NOT NULL ENCODE LZO,
    specialization VARCHAR(100) ENCODE LZO,
    years_experience INTEGER ENCODE LZO,
    certification_level VARCHAR(50) ENCODE LZO,
    -- SCD2 fields
    effective_date DATE NOT NULL ENCODE LZO,
    expiration_date DATE ENCODE LZO,
    is_current BOOLEAN NOT NULL DEFAULT TRUE
)
DISTSTYLE ALL
SORTKEY (surgeon_id, effective_date);

-- Dimension: Robots
-- SCD2 for robot information with detailed attributes
CREATE TABLE dim_robots (
    robot_key INTEGER IDENTITY(1,1) PRIMARY KEY ENCODE RAW,
    robot_id VARCHAR(50) NOT NULL ENCODE LZO,
    robot_serial_number VARCHAR(100) NOT NULL ENCODE LZO,
    robot_model VARCHAR(100) NOT NULL ENCODE LZO,
    manufacturer VARCHAR(100) ENCODE LZO,
    facility_key INTEGER ENCODE LZO,
    install_date DATE ENCODE LZO,
    software_version VARCHAR(50) ENCODE LZO,
    hardware_revision VARCHAR(50) ENCODE LZO,
    status VARCHAR(50) ENCODE LZO, -- active, maintenance, retired
    last_maintenance_date DATE ENCODE LZO,
    total_procedures_count INTEGER DEFAULT 0 ENCODE LZO,
    total_operating_hours DECIMAL(10,2) DEFAULT 0 ENCODE LZO,
    -- SCD2 fields
    effective_date DATE NOT NULL ENCODE LZO,
    expiration_date DATE ENCODE LZO,
    is_current BOOLEAN NOT NULL DEFAULT TRUE
)
DISTSTYLE KEY
DISTKEY (robot_key)
SORTKEY (robot_id, effective_date);

-- ============================================================================
-- FACT TABLES
-- ============================================================================

-- Fact: Procedures
-- Grain: One row per surgical procedure
CREATE TABLE fact_procedures (
    procedure_key BIGINT IDENTITY(1,1) PRIMARY KEY ENCODE RAW,
    procedure_id VARCHAR(100) NOT NULL ENCODE LZO,

    -- Foreign Keys to Dimensions
    robot_key INTEGER NOT NULL ENCODE LZO,
    surgeon_key INTEGER NOT NULL ENCODE LZO,
    facility_key INTEGER NOT NULL ENCODE LZO,
    start_date_key INTEGER NOT NULL ENCODE LZO,
    start_time_key INTEGER NOT NULL ENCODE LZO,
    end_date_key INTEGER ENCODE LZO,
    end_time_key INTEGER ENCODE LZO,

    -- Degenerate Dimensions (attributes without own dimension table)
    procedure_type VARCHAR(100) NOT NULL ENCODE LZO,
    procedure_category VARCHAR(50) NOT NULL ENCODE LZO,
    patient_id VARCHAR(100) ENCODE LZO,
    patient_age SMALLINT ENCODE LZO,
    patient_gender VARCHAR(10) ENCODE LZO,

    -- Measures (Facts)
    duration_minutes INTEGER ENCODE LZO,
    complexity_score DECIMAL(3,1) ENCODE LZO,

    -- Outcome Measures
    success_status VARCHAR(50) ENCODE LZO,
    blood_loss_ml INTEGER ENCODE LZO,
    complication_level VARCHAR(50) ENCODE LZO,
    hospital_stay_days INTEGER ENCODE LZO,
    patient_satisfaction_score DECIMAL(3,1) ENCODE LZO,
    readmission_30day BOOLEAN,

    -- Metadata
    status VARCHAR(50) NOT NULL DEFAULT 'completed' ENCODE LZO,
    created_at TIMESTAMP NOT NULL DEFAULT GETDATE() ENCODE LZO,
    updated_at TIMESTAMP ENCODE LZO,

    -- Constraints
    FOREIGN KEY (robot_key) REFERENCES dim_robots(robot_key),
    FOREIGN KEY (surgeon_key) REFERENCES dim_surgeons(surgeon_key),
    FOREIGN KEY (facility_key) REFERENCES dim_facilities(facility_key),
    FOREIGN KEY (start_date_key) REFERENCES dim_date(date_key),
    FOREIGN KEY (start_time_key) REFERENCES dim_time(time_key)
)
DISTSTYLE KEY
DISTKEY (robot_key)
SORTKEY (start_date_key, robot_key);

-- Fact: Procedure Telemetry
-- Grain: One row per telemetry sample during a procedure
CREATE TABLE fact_procedure_telemetry (
    telemetry_key BIGINT IDENTITY(1,1) PRIMARY KEY ENCODE RAW,
    procedure_key BIGINT NOT NULL ENCODE LZO,

    -- Time dimension
    timestamp_key INTEGER NOT NULL ENCODE LZO,
    sample_timestamp TIMESTAMP NOT NULL ENCODE LZO,

    -- Telemetry Measures
    arm_position_x DECIMAL(10,4) ENCODE LZO,
    arm_position_y DECIMAL(10,4) ENCODE LZO,
    arm_position_z DECIMAL(10,4) ENCODE LZO,
    arm_rotation_x DECIMAL(10,4) ENCODE LZO,
    arm_rotation_y DECIMAL(10,4) ENCODE LZO,
    arm_rotation_z DECIMAL(10,4) ENCODE LZO,
    force_feedback DECIMAL(10,4) ENCODE LZO,
    tool_type VARCHAR(100) ENCODE LZO,
    tool_active BOOLEAN,
    camera_zoom DECIMAL(5,2) ENCODE LZO,
    lighting_level INTEGER ENCODE LZO,

    -- System Metrics
    system_temperature DECIMAL(5,2) ENCODE LZO,
    motor_current DECIMAL(8,4) ENCODE LZO,
    network_latency_ms INTEGER ENCODE LZO,
    video_fps INTEGER ENCODE LZO,

    -- Metadata
    created_at TIMESTAMP NOT NULL DEFAULT GETDATE() ENCODE LZO,

    -- Constraints
    FOREIGN KEY (procedure_key) REFERENCES fact_procedures(procedure_key),
    FOREIGN KEY (timestamp_key) REFERENCES dim_time(time_key)
)
DISTSTYLE KEY
DISTKEY (procedure_key)
SORTKEY (procedure_key, sample_timestamp);

-- ============================================================================
-- INDEXES
-- ============================================================================

-- Additional indexes for common query patterns
-- Note: Redshift uses sort keys and dist keys primarily, but these help query planning

-- Index for surgeon performance queries
CREATE INDEX idx_procedures_surgeon ON fact_procedures(surgeon_key, start_date_key);

-- Index for facility utilization queries
CREATE INDEX idx_procedures_facility ON fact_procedures(facility_key, start_date_key);

-- Index for procedure outcome analysis
CREATE INDEX idx_procedures_outcome ON fact_procedures(success_status, complication_level);

-- Index for time-based telemetry queries
CREATE INDEX idx_telemetry_timestamp ON fact_procedure_telemetry(sample_timestamp);

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE dim_date IS 'Date dimension for time-based analysis';
COMMENT ON TABLE dim_time IS 'Time dimension for time-of-day analysis';
COMMENT ON TABLE dim_facilities IS 'Facility dimension with SCD2 support';
COMMENT ON TABLE dim_surgeons IS 'Surgeon dimension with SCD2 support';
COMMENT ON TABLE dim_robots IS 'Robot dimension with SCD2 support';
COMMENT ON TABLE fact_procedures IS 'Fact table storing surgical procedure details and outcomes';
COMMENT ON TABLE fact_procedure_telemetry IS 'Fact table storing high-frequency telemetry data from procedures';
