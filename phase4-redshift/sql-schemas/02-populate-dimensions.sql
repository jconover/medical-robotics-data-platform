-- Medical Robotics Data Platform - Populate Dimension Tables
-- This script populates date, time, and reference dimension tables

-- ============================================================================
-- POPULATE DATE DIMENSION
-- ============================================================================

-- Generate dates for 10 years (2020-2030)
INSERT INTO dim_date (
    date_key,
    date,
    year,
    quarter,
    month,
    month_name,
    week,
    day_of_month,
    day_of_week,
    day_name,
    is_weekend,
    is_holiday,
    fiscal_year,
    fiscal_quarter
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
    FALSE AS is_holiday, -- Will update separately
    CASE
        WHEN EXTRACT(MONTH FROM d) >= 10 THEN EXTRACT(YEAR FROM d) + 1
        ELSE EXTRACT(YEAR FROM d)
    END AS fiscal_year,
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
        LIMIT 3653  -- 10 years + leap days
    )
) dates;

-- Update holidays (US Federal Holidays - can be customized)
-- New Year's Day
UPDATE dim_date
SET is_holiday = TRUE
WHERE month = 1 AND day_of_month = 1;

-- Independence Day
UPDATE dim_date
SET is_holiday = TRUE
WHERE month = 7 AND day_of_month = 4;

-- Christmas Day
UPDATE dim_date
SET is_holiday = TRUE
WHERE month = 12 AND day_of_month = 25;

-- Thanksgiving (4th Thursday of November - approximation)
UPDATE dim_date
SET is_holiday = TRUE
WHERE month = 11
  AND day_of_week = 4  -- Thursday
  AND day_of_month BETWEEN 22 AND 28;

-- ============================================================================
-- POPULATE TIME DIMENSION
-- ============================================================================

-- Generate all time values at 1-minute granularity (1440 rows)
INSERT INTO dim_time (
    time_key,
    time_value,
    hour,
    minute,
    second,
    hour_12,
    am_pm,
    time_of_day,
    business_hours
)
SELECT
    (hour * 10000 + minute * 100) AS time_key,
    (hour::TEXT || ':' || LPAD(minute::TEXT, 2, '0') || ':00')::TIME AS time_value,
    hour,
    minute,
    0 AS second,
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
        FROM pg_catalog.pg_class
        LIMIT 24
    ) hours
    CROSS JOIN (
        SELECT ROW_NUMBER() OVER (ORDER BY 1) - 1 AS m
        FROM pg_catalog.pg_class
        LIMIT 60
    ) minutes
) times;

-- ============================================================================
-- POPULATE FACILITIES DIMENSION
-- ============================================================================

-- Initial load of facilities (will be populated from ETL process)
-- This is just sample data structure - actual data comes from RDS

INSERT INTO dim_facilities (
    facility_id,
    facility_name,
    city,
    state,
    country,
    facility_type,
    bed_count,
    effective_date,
    expiration_date,
    is_current
)
VALUES
    ('FAC-001', 'Memorial Medical Center', 'Boston', 'MA', 'USA', 'Teaching Hospital', 850, '2020-01-01', NULL, TRUE),
    ('FAC-002', 'St. Mary''s Hospital', 'New York', 'NY', 'USA', 'Private Hospital', 600, '2020-01-01', NULL, TRUE),
    ('FAC-003', 'Bay Area Surgical Institute', 'San Francisco', 'CA', 'USA', 'Specialty Center', 400, '2020-01-01', NULL, TRUE),
    ('FAC-004', 'Texas Medical Complex', 'Houston', 'TX', 'USA', 'Teaching Hospital', 900, '2020-01-01', NULL, TRUE),
    ('FAC-005', 'Pacific Northwest Regional', 'Seattle', 'WA', 'USA', 'Regional Hospital', 550, '2020-01-01', NULL, TRUE),
    ('FAC-006', 'Midwest Surgical Center', 'Chicago', 'IL', 'USA', 'Private Hospital', 700, '2020-01-01', NULL, TRUE),
    ('FAC-007', 'Florida Advanced Care', 'Miami', 'FL', 'USA', 'Specialty Center', 450, '2020-01-01', NULL, TRUE),
    ('FAC-008', 'Mountain View Hospital', 'Denver', 'CO', 'USA', 'Regional Hospital', 500, '2020-01-01', NULL, TRUE),
    ('FAC-009', 'Atlanta Healthcare System', 'Atlanta', 'GA', 'USA', 'Teaching Hospital', 800, '2020-01-01', NULL, TRUE),
    ('FAC-010', 'Desert Medical Institute', 'Phoenix', 'AZ', 'USA', 'Private Hospital', 600, '2020-01-01', NULL, TRUE);

-- ============================================================================
-- VACUUM AND ANALYZE
-- ============================================================================

-- Reclaim space and update table statistics
VACUUM DELETE ONLY dim_date;
VACUUM DELETE ONLY dim_time;
VACUUM DELETE ONLY dim_facilities;

ANALYZE dim_date;
ANALYZE dim_time;
ANALYZE dim_facilities;
