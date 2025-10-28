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

-- Grant select permissions to appropriate users/roles
-- GRANT SELECT ON ALL TABLES IN SCHEMA public TO analytics_users;
