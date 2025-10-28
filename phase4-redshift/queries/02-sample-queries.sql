-- Medical Robotics Data Platform - Sample Analytical Queries
-- Common business intelligence queries for surgical robotics analytics

-- ============================================================================
-- EXECUTIVE DASHBOARD QUERIES
-- ============================================================================

-- Query 1: Overall Platform Metrics (Last 30 Days)
SELECT
    COUNT(DISTINCT p.procedure_key) as total_procedures,
    COUNT(DISTINCT r.robot_key) as active_robots,
    COUNT(DISTINCT s.surgeon_key) as active_surgeons,
    COUNT(DISTINCT f.facility_key) as active_facilities,
    ROUND(AVG(p.duration_minutes), 2) as avg_procedure_duration_min,
    ROUND(SUM(p.duration_minutes) / 60.0, 2) as total_operating_hours,
    ROUND(AVG(p.patient_satisfaction_score), 2) as avg_patient_satisfaction,
    ROUND(
        SUM(CASE WHEN p.success_status = 'Successful' THEN 1 ELSE 0 END)::FLOAT /
        NULLIF(COUNT(*), 0) * 100, 2
    ) as success_rate_pct
FROM fact_procedures p
INNER JOIN dim_robots r ON p.robot_key = r.robot_key AND r.is_current = TRUE
INNER JOIN dim_surgeons s ON p.surgeon_key = s.surgeon_key AND s.is_current = TRUE
INNER JOIN dim_facilities f ON p.facility_key = f.facility_key AND f.is_current = TRUE
INNER JOIN dim_date d ON p.start_date_key = d.date_key
WHERE d.date >= CURRENT_DATE - INTERVAL '30 days'
  AND p.status = 'completed';


-- Query 2: Top 10 Most Utilized Robots
SELECT
    r.robot_id,
    r.robot_serial_number,
    r.robot_model,
    f.facility_name,
    COUNT(*) as procedure_count,
    ROUND(SUM(p.duration_minutes) / 60.0, 2) as operating_hours,
    ROUND(AVG(p.complexity_score), 2) as avg_complexity,
    ROUND(
        SUM(CASE WHEN p.success_status = 'Successful' THEN 1 ELSE 0 END)::FLOAT /
        NULLIF(COUNT(*), 0) * 100, 2
    ) as success_rate_pct
FROM dim_robots r
INNER JOIN fact_procedures p ON r.robot_key = p.robot_key
INNER JOIN dim_facilities f ON r.facility_key = f.facility_key AND f.is_current = TRUE
WHERE r.is_current = TRUE
  AND p.status = 'completed'
GROUP BY r.robot_id, r.robot_serial_number, r.robot_model, f.facility_name
ORDER BY procedure_count DESC
LIMIT 10;


-- Query 3: Monthly Procedure Volume Trend (Last 12 Months)
SELECT
    TO_CHAR(d.date, 'YYYY-MM') as year_month,
    d.year,
    d.month_name,
    COUNT(*) as procedure_count,
    ROUND(AVG(p.duration_minutes), 2) as avg_duration,
    ROUND(SUM(p.duration_minutes) / 60.0, 2) as total_hours,
    ROUND(
        SUM(CASE WHEN p.success_status = 'Successful' THEN 1 ELSE 0 END)::FLOAT /
        NULLIF(COUNT(*), 0) * 100, 2
    ) as success_rate_pct
FROM fact_procedures p
INNER JOIN dim_date d ON p.start_date_key = d.date_key
WHERE d.date >= CURRENT_DATE - INTERVAL '12 months'
  AND p.status = 'completed'
GROUP BY TO_CHAR(d.date, 'YYYY-MM'), d.year, d.month_name
ORDER BY year_month;


-- ============================================================================
-- CLINICAL OUTCOMES ANALYSIS
-- ============================================================================

-- Query 4: Complication Rates by Procedure Type
SELECT
    p.procedure_type,
    p.procedure_category,
    COUNT(*) as total_procedures,
    SUM(CASE WHEN p.complication_level = 'None' THEN 1 ELSE 0 END) as no_complications,
    SUM(CASE WHEN p.complication_level = 'Minor' THEN 1 ELSE 0 END) as minor_complications,
    SUM(CASE WHEN p.complication_level = 'Moderate' THEN 1 ELSE 0 END) as moderate_complications,
    SUM(CASE WHEN p.complication_level = 'Severe' THEN 1 ELSE 0 END) as severe_complications,
    ROUND(
        SUM(CASE WHEN p.complication_level IN ('Moderate', 'Severe') THEN 1 ELSE 0 END)::FLOAT /
        NULLIF(COUNT(*), 0) * 100, 2
    ) as serious_complication_rate_pct
FROM fact_procedures p
WHERE p.status = 'completed'
GROUP BY p.procedure_type, p.procedure_category
ORDER BY total_procedures DESC;


-- Query 5: Patient Outcomes by Robot Model
SELECT
    r.robot_model,
    r.manufacturer,
    COUNT(*) as procedure_count,
    ROUND(AVG(p.duration_minutes), 2) as avg_duration_min,
    ROUND(AVG(p.blood_loss_ml), 2) as avg_blood_loss_ml,
    ROUND(AVG(p.hospital_stay_days), 2) as avg_hospital_stay_days,
    ROUND(AVG(p.patient_satisfaction_score), 2) as avg_satisfaction,
    ROUND(
        SUM(CASE WHEN p.readmission_30day = TRUE THEN 1 ELSE 0 END)::FLOAT /
        NULLIF(COUNT(*), 0) * 100, 2
    ) as readmission_rate_pct,
    ROUND(
        SUM(CASE WHEN p.success_status = 'Successful' THEN 1 ELSE 0 END)::FLOAT /
        NULLIF(COUNT(*), 0) * 100, 2
    ) as success_rate_pct
FROM dim_robots r
INNER JOIN fact_procedures p ON r.robot_key = p.robot_key
WHERE r.is_current = TRUE
  AND p.status = 'completed'
GROUP BY r.robot_model, r.manufacturer
HAVING COUNT(*) >= 10  -- Only models with 10+ procedures
ORDER BY procedure_count DESC;


-- Query 6: Readmission Analysis by Procedure Category
SELECT
    p.procedure_category,
    COUNT(*) as total_procedures,
    SUM(CASE WHEN p.readmission_30day = TRUE THEN 1 ELSE 0 END) as readmission_count,
    ROUND(
        SUM(CASE WHEN p.readmission_30day = TRUE THEN 1 ELSE 0 END)::FLOAT /
        NULLIF(COUNT(*), 0) * 100, 2
    ) as readmission_rate_pct,
    ROUND(AVG(CASE WHEN p.readmission_30day = TRUE THEN p.hospital_stay_days END), 2) as avg_stay_with_readmission,
    ROUND(AVG(CASE WHEN p.readmission_30day = FALSE THEN p.hospital_stay_days END), 2) as avg_stay_no_readmission
FROM fact_procedures p
WHERE p.status = 'completed'
GROUP BY p.procedure_category
ORDER BY readmission_rate_pct DESC;


-- ============================================================================
-- SURGEON PERFORMANCE ANALYSIS
-- ============================================================================

-- Query 7: Top Performing Surgeons (Minimum 20 procedures)
SELECT
    s.surgeon_name,
    s.specialization,
    s.years_experience,
    COUNT(*) as procedure_count,
    ROUND(AVG(p.complexity_score), 2) as avg_complexity,
    ROUND(AVG(p.duration_minutes), 2) as avg_duration_min,
    ROUND(
        SUM(CASE WHEN p.success_status = 'Successful' THEN 1 ELSE 0 END)::FLOAT /
        NULLIF(COUNT(*), 0) * 100, 2
    ) as success_rate_pct,
    ROUND(AVG(p.patient_satisfaction_score), 2) as avg_satisfaction,
    ROUND(
        SUM(CASE WHEN p.complication_level = 'None' THEN 1 ELSE 0 END)::FLOAT /
        NULLIF(COUNT(*), 0) * 100, 2
    ) as no_complication_rate_pct
FROM dim_surgeons s
INNER JOIN fact_procedures p ON s.surgeon_key = p.surgeon_key
WHERE s.is_current = TRUE
  AND p.status = 'completed'
GROUP BY s.surgeon_name, s.specialization, s.years_experience
HAVING COUNT(*) >= 20
ORDER BY success_rate_pct DESC, avg_satisfaction DESC
LIMIT 20;


-- Query 8: Surgeon Experience vs Outcomes Correlation
SELECT
    CASE
        WHEN s.years_experience < 5 THEN '0-4 years'
        WHEN s.years_experience BETWEEN 5 AND 9 THEN '5-9 years'
        WHEN s.years_experience BETWEEN 10 AND 14 THEN '10-14 years'
        WHEN s.years_experience >= 15 THEN '15+ years'
    END as experience_group,
    COUNT(DISTINCT s.surgeon_key) as surgeon_count,
    COUNT(*) as procedure_count,
    ROUND(AVG(p.duration_minutes), 2) as avg_duration,
    ROUND(
        SUM(CASE WHEN p.success_status = 'Successful' THEN 1 ELSE 0 END)::FLOAT /
        NULLIF(COUNT(*), 0) * 100, 2
    ) as success_rate_pct,
    ROUND(AVG(p.patient_satisfaction_score), 2) as avg_satisfaction,
    ROUND(AVG(p.complexity_score), 2) as avg_complexity
FROM dim_surgeons s
INNER JOIN fact_procedures p ON s.surgeon_key = p.surgeon_key
WHERE s.is_current = TRUE
  AND p.status = 'completed'
GROUP BY CASE
    WHEN s.years_experience < 5 THEN '0-4 years'
    WHEN s.years_experience BETWEEN 5 AND 9 THEN '5-9 years'
    WHEN s.years_experience BETWEEN 10 AND 14 THEN '10-14 years'
    WHEN s.years_experience >= 15 THEN '15+ years'
END
ORDER BY experience_group;


-- ============================================================================
-- FACILITY BENCHMARKING
-- ============================================================================

-- Query 9: Facility Performance Comparison
SELECT
    f.facility_name,
    f.city,
    f.state,
    f.facility_type,
    COUNT(DISTINCT r.robot_key) as robot_count,
    COUNT(*) as procedure_count,
    ROUND(AVG(p.duration_minutes), 2) as avg_duration,
    ROUND(
        SUM(CASE WHEN p.success_status = 'Successful' THEN 1 ELSE 0 END)::FLOAT /
        NULLIF(COUNT(*), 0) * 100, 2
    ) as success_rate_pct,
    ROUND(AVG(p.hospital_stay_days), 2) as avg_hospital_stay,
    ROUND(AVG(p.patient_satisfaction_score), 2) as avg_satisfaction
FROM dim_facilities f
INNER JOIN dim_robots r ON f.facility_key = r.facility_key AND r.is_current = TRUE
INNER JOIN fact_procedures p ON r.robot_key = p.robot_key
WHERE f.is_current = TRUE
  AND p.status = 'completed'
GROUP BY f.facility_name, f.city, f.state, f.facility_type
ORDER BY procedure_count DESC;


-- Query 10: Facility Utilization Efficiency
-- Compare actual operating hours vs potential capacity
SELECT
    f.facility_name,
    COUNT(DISTINCT r.robot_key) as robot_count,
    COUNT(DISTINCT d.date) as operating_days,
    COUNT(*) as procedure_count,
    ROUND(SUM(p.duration_minutes) / 60.0, 2) as actual_operating_hours,
    -- Assume 8 hours/day capacity per robot
    (COUNT(DISTINCT r.robot_key) * COUNT(DISTINCT d.date) * 8) as potential_capacity_hours,
    ROUND(
        (SUM(p.duration_minutes) / 60.0) /
        NULLIF((COUNT(DISTINCT r.robot_key) * COUNT(DISTINCT d.date) * 8), 0) * 100, 2
    ) as utilization_rate_pct
FROM dim_facilities f
INNER JOIN dim_robots r ON f.facility_key = r.facility_key AND r.is_current = TRUE
INNER JOIN fact_procedures p ON r.robot_key = p.robot_key
INNER JOIN dim_date d ON p.start_date_key = d.date_key
WHERE f.is_current = TRUE
  AND p.status = 'completed'
  AND d.date >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY f.facility_name
ORDER BY utilization_rate_pct DESC;


-- ============================================================================
-- TELEMETRY ANALYSIS
-- ============================================================================

-- Query 11: Robot System Health During Procedures
SELECT
    r.robot_id,
    r.robot_model,
    COUNT(DISTINCT t.procedure_key) as procedure_count,
    ROUND(AVG(t.system_temperature), 2) as avg_temperature,
    ROUND(MAX(t.system_temperature), 2) as max_temperature,
    ROUND(AVG(t.motor_current), 4) as avg_motor_current,
    ROUND(AVG(t.network_latency_ms), 2) as avg_network_latency,
    ROUND(AVG(t.video_fps), 2) as avg_video_fps,
    -- Count procedures with system warnings
    SUM(CASE
        WHEN t.system_temperature > 75 OR
             t.network_latency_ms > 100 OR
             t.video_fps < 25
        THEN 1 ELSE 0
    END) as warning_count
FROM fact_procedure_telemetry t
INNER JOIN fact_procedures p ON t.procedure_key = p.procedure_key
INNER JOIN dim_robots r ON p.robot_key = r.robot_key
WHERE r.is_current = TRUE
GROUP BY r.robot_id, r.robot_model
HAVING COUNT(DISTINCT t.procedure_key) >= 5
ORDER BY warning_count DESC, procedure_count DESC;


-- ============================================================================
-- TIME PATTERN ANALYSIS
-- ============================================================================

-- Query 12: Procedure Volume by Day of Week
SELECT
    d.day_name,
    d.day_of_week,
    COUNT(*) as procedure_count,
    ROUND(AVG(p.duration_minutes), 2) as avg_duration,
    ROUND(
        SUM(CASE WHEN p.success_status = 'Successful' THEN 1 ELSE 0 END)::FLOAT /
        NULLIF(COUNT(*), 0) * 100, 2
    ) as success_rate_pct
FROM fact_procedures p
INNER JOIN dim_date d ON p.start_date_key = d.date_key
WHERE p.status = 'completed'
  AND d.date >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY d.day_name, d.day_of_week
ORDER BY d.day_of_week;


-- Query 13: Procedure Success Rate by Time of Day
SELECT
    t.time_of_day,
    COUNT(*) as procedure_count,
    ROUND(AVG(p.duration_minutes), 2) as avg_duration,
    ROUND(AVG(p.complexity_score), 2) as avg_complexity,
    ROUND(
        SUM(CASE WHEN p.success_status = 'Successful' THEN 1 ELSE 0 END)::FLOAT /
        NULLIF(COUNT(*), 0) * 100, 2
    ) as success_rate_pct,
    ROUND(AVG(p.patient_satisfaction_score), 2) as avg_satisfaction
FROM fact_procedures p
INNER JOIN dim_time t ON p.start_time_key = t.time_key
WHERE p.status = 'completed'
GROUP BY t.time_of_day
ORDER BY
    CASE t.time_of_day
        WHEN 'Morning' THEN 1
        WHEN 'Afternoon' THEN 2
        WHEN 'Evening' THEN 3
        WHEN 'Night' THEN 4
    END;


-- ============================================================================
-- ADVANCED ANALYTICS
-- ============================================================================

-- Query 14: Year-over-Year Growth Analysis
SELECT
    d1.year as year,
    d1.quarter,
    COUNT(*) as procedure_count,
    ROUND(SUM(p.duration_minutes) / 60.0, 2) as operating_hours,
    LAG(COUNT(*)) OVER (ORDER BY d1.year, d1.quarter) as prev_period_count,
    ROUND(
        (COUNT(*)::FLOAT - LAG(COUNT(*)) OVER (ORDER BY d1.year, d1.quarter)) /
        NULLIF(LAG(COUNT(*)) OVER (ORDER BY d1.year, d1.quarter), 0) * 100, 2
    ) as growth_rate_pct
FROM fact_procedures p
INNER JOIN dim_date d1 ON p.start_date_key = d1.date_key
WHERE p.status = 'completed'
GROUP BY d1.year, d1.quarter
ORDER BY d1.year, d1.quarter;


-- Query 15: Cohort Analysis - Patient Outcomes by Age Group
SELECT
    CASE
        WHEN p.patient_age < 30 THEN 'Under 30'
        WHEN p.patient_age BETWEEN 30 AND 49 THEN '30-49'
        WHEN p.patient_age BETWEEN 50 AND 64 THEN '50-64'
        WHEN p.patient_age >= 65 THEN '65+'
    END as age_group,
    p.procedure_category,
    COUNT(*) as procedure_count,
    ROUND(AVG(p.complexity_score), 2) as avg_complexity,
    ROUND(AVG(p.duration_minutes), 2) as avg_duration,
    ROUND(AVG(p.blood_loss_ml), 2) as avg_blood_loss,
    ROUND(AVG(p.hospital_stay_days), 2) as avg_hospital_stay,
    ROUND(
        SUM(CASE WHEN p.success_status = 'Successful' THEN 1 ELSE 0 END)::FLOAT /
        NULLIF(COUNT(*), 0) * 100, 2
    ) as success_rate_pct
FROM fact_procedures p
WHERE p.status = 'completed'
  AND p.patient_age IS NOT NULL
GROUP BY
    CASE
        WHEN p.patient_age < 30 THEN 'Under 30'
        WHEN p.patient_age BETWEEN 30 AND 49 THEN '30-49'
        WHEN p.patient_age BETWEEN 50 AND 64 THEN '50-64'
        WHEN p.patient_age >= 65 THEN '65+'
    END,
    p.procedure_category
ORDER BY age_group, procedure_category;
