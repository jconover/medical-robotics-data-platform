-- Medical Robotics Data Platform - PostgreSQL Schema
-- Creates tables for surgical robots, procedures, outcomes, and maintenance logs

-- Drop tables if they exist (for clean re-runs)
DROP TABLE IF EXISTS procedure_outcomes CASCADE;
DROP TABLE IF EXISTS surgical_procedures CASCADE;
DROP TABLE IF EXISTS robot_maintenance_logs CASCADE;
DROP TABLE IF EXISTS surgical_robots CASCADE;

-- Create surgical_robots table
CREATE TABLE surgical_robots (
    robot_id UUID PRIMARY KEY,
    robot_serial_number VARCHAR(50) UNIQUE NOT NULL,
    robot_model VARCHAR(100) NOT NULL,
    manufacturer VARCHAR(100) NOT NULL,
    installation_date DATE NOT NULL,
    facility_id VARCHAR(50) NOT NULL,
    facility_name VARCHAR(200) NOT NULL,
    status VARCHAR(20) NOT NULL CHECK (status IN ('operational', 'maintenance', 'retired')),
    last_maintenance_date DATE,
    total_procedures INTEGER DEFAULT 0,
    firmware_version VARCHAR(20),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for surgical_robots
CREATE INDEX idx_robots_facility ON surgical_robots(facility_id);
CREATE INDEX idx_robots_status ON surgical_robots(status);
CREATE INDEX idx_robots_model ON surgical_robots(robot_model);

-- Create robot_maintenance_logs table
CREATE TABLE robot_maintenance_logs (
    maintenance_id UUID PRIMARY KEY,
    robot_id UUID NOT NULL REFERENCES surgical_robots(robot_id) ON DELETE CASCADE,
    maintenance_date DATE NOT NULL,
    maintenance_type VARCHAR(50) NOT NULL CHECK (maintenance_type IN ('routine', 'emergency', 'upgrade', 'calibration')),
    technician_id VARCHAR(50) NOT NULL,
    technician_name VARCHAR(200) NOT NULL,
    issues_found TEXT,
    actions_taken TEXT,
    parts_replaced TEXT,
    downtime_hours DECIMAL(6,2),
    next_maintenance_date DATE,
    cost DECIMAL(10,2),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for robot_maintenance_logs
CREATE INDEX idx_maintenance_robot ON robot_maintenance_logs(robot_id);
CREATE INDEX idx_maintenance_date ON robot_maintenance_logs(maintenance_date);
CREATE INDEX idx_maintenance_type ON robot_maintenance_logs(maintenance_type);

-- Create surgical_procedures table
CREATE TABLE surgical_procedures (
    procedure_id UUID PRIMARY KEY,
    robot_id UUID NOT NULL REFERENCES surgical_robots(robot_id) ON DELETE CASCADE,
    procedure_type VARCHAR(100) NOT NULL,
    procedure_category VARCHAR(50) NOT NULL,
    start_time TIMESTAMP NOT NULL,
    end_time TIMESTAMP NOT NULL,
    duration_minutes INTEGER NOT NULL,
    surgeon_id VARCHAR(50) NOT NULL,
    surgeon_name VARCHAR(200) NOT NULL,
    patient_id VARCHAR(50) NOT NULL,
    patient_age INTEGER NOT NULL CHECK (patient_age >= 0 AND patient_age <= 120),
    patient_gender VARCHAR(20),
    complexity_score DECIMAL(3,2) CHECK (complexity_score >= 1.0 AND complexity_score <= 5.0),
    status VARCHAR(20) NOT NULL CHECK (status IN ('completed', 'in_progress', 'aborted', 'cancelled')),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT check_end_after_start CHECK (end_time >= start_time)
);

-- Create indexes for surgical_procedures
CREATE INDEX idx_procedures_robot ON surgical_procedures(robot_id);
CREATE INDEX idx_procedures_start_time ON surgical_procedures(start_time);
CREATE INDEX idx_procedures_category ON surgical_procedures(procedure_category);
CREATE INDEX idx_procedures_surgeon ON surgical_procedures(surgeon_id);
CREATE INDEX idx_procedures_status ON surgical_procedures(status);

-- Create procedure_outcomes table
CREATE TABLE procedure_outcomes (
    outcome_id UUID PRIMARY KEY,
    procedure_id UUID UNIQUE NOT NULL REFERENCES surgical_procedures(procedure_id) ON DELETE CASCADE,
    success_status VARCHAR(20) NOT NULL CHECK (success_status IN ('successful', 'complicated', 'failed')),
    blood_loss_ml INTEGER CHECK (blood_loss_ml >= 0),
    complications TEXT,
    hospital_stay_days INTEGER CHECK (hospital_stay_days >= 0),
    readmission_30day BOOLEAN DEFAULT FALSE,
    patient_satisfaction_score INTEGER CHECK (patient_satisfaction_score >= 1 AND patient_satisfaction_score <= 10),
    surgeon_notes TEXT,
    recovery_score INTEGER CHECK (recovery_score >= 1 AND recovery_score <= 100),
    follow_up_required BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for procedure_outcomes
CREATE INDEX idx_outcomes_procedure ON procedure_outcomes(procedure_id);
CREATE INDEX idx_outcomes_success ON procedure_outcomes(success_status);
CREATE INDEX idx_outcomes_readmission ON procedure_outcomes(readmission_30day);

-- Create updated_at trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for updated_at columns
CREATE TRIGGER update_robots_updated_at
    BEFORE UPDATE ON surgical_robots
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_outcomes_updated_at
    BEFORE UPDATE ON procedure_outcomes
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Create views for common queries
CREATE VIEW vw_robot_utilization AS
SELECT
    r.robot_id,
    r.robot_serial_number,
    r.robot_model,
    r.facility_name,
    r.status,
    COUNT(p.procedure_id) as procedure_count,
    AVG(p.duration_minutes) as avg_procedure_duration,
    MAX(p.start_time) as last_procedure_date
FROM surgical_robots r
LEFT JOIN surgical_procedures p ON r.robot_id = p.robot_id
GROUP BY r.robot_id, r.robot_serial_number, r.robot_model, r.facility_name, r.status;

CREATE VIEW vw_procedure_outcomes_summary AS
SELECT
    p.procedure_id,
    p.procedure_type,
    p.procedure_category,
    p.start_time,
    p.duration_minutes,
    p.complexity_score,
    r.robot_model,
    r.facility_name,
    o.success_status,
    o.blood_loss_ml,
    o.hospital_stay_days,
    o.patient_satisfaction_score
FROM surgical_procedures p
JOIN surgical_robots r ON p.robot_id = r.robot_id
LEFT JOIN procedure_outcomes o ON p.procedure_id = o.procedure_id
WHERE p.status = 'completed';

CREATE VIEW vw_maintenance_costs AS
SELECT
    r.robot_id,
    r.robot_serial_number,
    r.robot_model,
    r.facility_name,
    COUNT(m.maintenance_id) as maintenance_count,
    SUM(m.cost) as total_cost,
    AVG(m.cost) as avg_cost,
    SUM(m.downtime_hours) as total_downtime_hours
FROM surgical_robots r
LEFT JOIN robot_maintenance_logs m ON r.robot_id = m.robot_id
GROUP BY r.robot_id, r.robot_serial_number, r.robot_model, r.facility_name;

-- Grant permissions (adjust as needed for your application user)
-- GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_user;
-- GRANT SELECT ON ALL TABLES IN SCHEMA public TO readonly_user;
