-- Medical Robotics Data Platform - Load Sample Data
-- This script provides examples of loading data from CSV files

-- Note: Adjust file paths to match your S3 bucket or local filesystem
-- For S3, you'll need the aws_s3 extension and appropriate IAM permissions

-- Example: Load data from local CSV files
-- Replace '/path/to/' with actual paths from phase1-data-model/data_generators/sample_data/

-- Load surgical_robots
-- COPY surgical_robots(
--     robot_id,
--     robot_serial_number,
--     robot_model,
--     manufacturer,
--     installation_date,
--     facility_id,
--     facility_name,
--     status,
--     last_maintenance_date,
--     total_procedures,
--     firmware_version,
--     created_at,
--     updated_at
-- )
-- FROM '/path/to/surgical_robots.csv'
-- DELIMITER ','
-- CSV HEADER;

-- Load robot_maintenance_logs
-- COPY robot_maintenance_logs(
--     maintenance_id,
--     robot_id,
--     maintenance_date,
--     maintenance_type,
--     technician_id,
--     technician_name,
--     issues_found,
--     actions_taken,
--     parts_replaced,
--     downtime_hours,
--     next_maintenance_date,
--     cost,
--     created_at
-- )
-- FROM '/path/to/robot_maintenance_logs.csv'
-- DELIMITER ','
--CSV HEADER;

-- Load surgical_procedures
-- COPY surgical_procedures(
--     procedure_id,
--     robot_id,
--     procedure_type,
--     procedure_category,
--     start_time,
--     end_time,
--     duration_minutes,
--     surgeon_id,
--     surgeon_name,
--     patient_id,
--     patient_age,
--     patient_gender,
--     complexity_score,
--     status,
--     created_at
-- )
-- FROM '/path/to/surgical_procedures.csv'
-- DELIMITER ','
-- CSV HEADER;

-- Load procedure_outcomes
-- COPY procedure_outcomes(
--     outcome_id,
--     procedure_id,
--     success_status,
--     blood_loss_ml,
--     complications,
--     hospital_stay_days,
--     readmission_30day,
--     patient_satisfaction_score,
--     surgeon_notes,
--     recovery_score,
--     follow_up_required,
--     created_at,
--     updated_at
-- )
-- FROM '/path/to/procedure_outcomes.csv'
-- DELIMITER ','
-- CSV HEADER;

-- Verify loaded data
SELECT 'surgical_robots' as table_name, COUNT(*) as row_count FROM surgical_robots
UNION ALL
SELECT 'robot_maintenance_logs', COUNT(*) FROM robot_maintenance_logs
UNION ALL
SELECT 'surgical_procedures', COUNT(*) FROM surgical_procedures
UNION ALL
SELECT 'procedure_outcomes', COUNT(*) FROM procedure_outcomes;

-- Sample queries to verify data integrity
SELECT
    r.robot_model,
    COUNT(DISTINCT r.robot_id) as robot_count,
    COUNT(p.procedure_id) as total_procedures
FROM surgical_robots r
LEFT JOIN surgical_procedures p ON r.robot_id = p.robot_id
GROUP BY r.robot_model
ORDER BY total_procedures DESC;

SELECT
    procedure_category,
    COUNT(*) as procedure_count,
    AVG(duration_minutes) as avg_duration,
    AVG(complexity_score) as avg_complexity
FROM surgical_procedures
WHERE status = 'completed'
GROUP BY procedure_category
ORDER BY procedure_count DESC;

SELECT
    success_status,
    COUNT(*) as outcome_count,
    AVG(blood_loss_ml) as avg_blood_loss,
    AVG(hospital_stay_days) as avg_stay,
    AVG(patient_satisfaction_score) as avg_satisfaction
FROM procedure_outcomes
GROUP BY success_status
ORDER BY outcome_count DESC;
