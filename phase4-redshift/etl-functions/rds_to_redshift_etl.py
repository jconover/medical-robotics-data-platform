"""
Medical Robotics Data Platform - RDS to Redshift ETL
Extracts data from RDS PostgreSQL and loads into Redshift data warehouse
"""

import os
import json
import boto3
import psycopg2
from datetime import datetime, timedelta
from psycopg2.extras import RealDictCursor

# Environment variables
RDS_HOST = os.environ.get('RDS_HOST')
RDS_PORT = os.environ.get('RDS_PORT', '5432')
RDS_DBNAME = os.environ.get('RDS_DBNAME', 'medrobotics')
RDS_USER = os.environ.get('RDS_USER', 'dbadmin')
RDS_SECRET_ARN = os.environ.get('RDS_SECRET_ARN')

REDSHIFT_HOST = os.environ.get('REDSHIFT_HOST')
REDSHIFT_PORT = os.environ.get('REDSHIFT_PORT', '5439')
REDSHIFT_DBNAME = os.environ.get('REDSHIFT_DBNAME', 'medrobotics_dw')
REDSHIFT_USER = os.environ.get('REDSHIFT_USER', 'dwadmin')
REDSHIFT_SECRET_ARN = os.environ.get('REDSHIFT_SECRET_ARN')

S3_STAGING_BUCKET = os.environ.get('S3_STAGING_BUCKET')
REDSHIFT_IAM_ROLE = os.environ.get('REDSHIFT_IAM_ROLE')

# AWS clients
secretsmanager = boto3.client('secretsmanager')
s3_client = boto3.client('s3')


def get_secret(secret_arn):
    """Retrieve secret from AWS Secrets Manager"""
    try:
        response = secretsmanager.get_secret_value(SecretId=secret_arn)
        secret = json.loads(response['SecretString'])
        return secret['password']
    except Exception as e:
        print(f"Error retrieving secret: {str(e)}")
        raise


def get_rds_connection():
    """Create connection to RDS PostgreSQL"""
    password = get_secret(RDS_SECRET_ARN)
    return psycopg2.connect(
        host=RDS_HOST,
        port=RDS_PORT,
        database=RDS_DBNAME,
        user=RDS_USER,
        password=password,
        cursor_factory=RealDictCursor
    )


def get_redshift_connection():
    """Create connection to Redshift"""
    password = get_secret(REDSHIFT_SECRET_ARN)
    return psycopg2.connect(
        host=REDSHIFT_HOST,
        port=REDSHIFT_PORT,
        database=REDSHIFT_DBNAME,
        user=REDSHIFT_USER,
        password=password,
        cursor_factory=RealDictCursor
    )


def export_to_s3_csv(data, filename):
    """Export data to S3 as CSV for COPY command"""
    import csv
    from io import StringIO

    if not data:
        print(f"No data to export for {filename}")
        return None

    # Create CSV in memory
    csv_buffer = StringIO()
    writer = csv.DictWriter(csv_buffer, fieldnames=data[0].keys(), delimiter='|')
    # Don't write header - Redshift COPY doesn't need it
    writer.writerows(data)

    # Upload to S3
    s3_key = f"etl-staging/{datetime.now().strftime('%Y%m%d')}/{filename}"
    s3_client.put_object(
        Bucket=S3_STAGING_BUCKET,
        Key=s3_key,
        Body=csv_buffer.getvalue().encode('utf-8')
    )

    print(f"Exported {len(data)} rows to s3://{S3_STAGING_BUCKET}/{s3_key}")
    return f"s3://{S3_STAGING_BUCKET}/{s3_key}"


def load_dimension_surgeons():
    """Load surgeon dimension using SCD2"""
    print("Loading surgeon dimension...")

    rds_conn = get_rds_connection()
    rs_conn = get_redshift_connection()

    try:
        # Extract distinct surgeons from RDS
        rds_cursor = rds_conn.cursor()
        rds_cursor.execute("""
            SELECT DISTINCT
                surgeon_id,
                surgeon_name,
                'General Surgery' as specialization,
                EXTRACT(YEAR FROM AGE(CURRENT_DATE, MIN(start_time))) as years_experience,
                'Board Certified' as certification_level,
                MIN(start_time)::DATE as effective_date
            FROM surgical_procedures
            WHERE surgeon_id IS NOT NULL
            GROUP BY surgeon_id, surgeon_name
        """)
        surgeons = rds_cursor.fetchall()

        # Export to S3
        s3_path = export_to_s3_csv(surgeons, 'surgeons.csv')
        if not s3_path:
            return 0

        # Load into Redshift using COPY
        rs_cursor = rs_conn.cursor()

        # Create temp table
        rs_cursor.execute("""
            CREATE TEMP TABLE staging_surgeons (
                surgeon_id VARCHAR(50),
                surgeon_name VARCHAR(200),
                specialization VARCHAR(100),
                years_experience INTEGER,
                certification_level VARCHAR(50),
                effective_date DATE
            )
        """)

        # COPY data from S3
        copy_command = f"""
            COPY staging_surgeons
            FROM '{s3_path}'
            IAM_ROLE '{REDSHIFT_IAM_ROLE}'
            DELIMITER '|'
            REMOVEQUOTES
            EMPTYASNULL
            DATEFORMAT 'YYYY-MM-DD'
        """
        rs_cursor.execute(copy_command)

        # Merge into dimension (SCD2)
        rs_cursor.execute("""
            -- Expire changed records
            UPDATE dim_surgeons
            SET expiration_date = CURRENT_DATE - 1,
                is_current = FALSE
            WHERE is_current = TRUE
              AND surgeon_id IN (SELECT surgeon_id FROM staging_surgeons)
              AND (surgeon_name, specialization) NOT IN (
                  SELECT surgeon_name, specialization FROM staging_surgeons
              );

            -- Insert new and changed records
            INSERT INTO dim_surgeons (
                surgeon_id, surgeon_name, specialization, years_experience,
                certification_level, effective_date, expiration_date, is_current
            )
            SELECT
                s.surgeon_id,
                s.surgeon_name,
                s.specialization,
                s.years_experience,
                s.certification_level,
                s.effective_date,
                NULL,
                TRUE
            FROM staging_surgeons s
            LEFT JOIN dim_surgeons d ON s.surgeon_id = d.surgeon_id AND d.is_current = TRUE
            WHERE d.surgeon_key IS NULL
               OR (d.surgeon_name, d.specialization) <> (s.surgeon_name, s.specialization);
        """)

        row_count = rs_cursor.rowcount
        rs_conn.commit()

        print(f"Loaded {row_count} surgeon records")
        return row_count

    except Exception as e:
        print(f"Error loading surgeons: {str(e)}")
        rs_conn.rollback()
        raise
    finally:
        rds_conn.close()
        rs_conn.close()


def load_dimension_robots():
    """Load robot dimension using SCD2"""
    print("Loading robot dimension...")

    rds_conn = get_rds_connection()
    rs_conn = get_redshift_connection()

    try:
        # Extract robots from RDS
        rds_cursor = rds_conn.cursor()
        rds_cursor.execute("""
            SELECT
                r.robot_id,
                r.robot_serial_number,
                r.robot_model,
                r.manufacturer,
                r.facility_id,
                r.install_date,
                r.software_version,
                r.hardware_revision,
                r.status,
                r.last_maintenance_date,
                COUNT(p.procedure_id) as total_procedures_count,
                COALESCE(SUM(p.duration_minutes), 0) / 60.0 as total_operating_hours,
                r.install_date as effective_date
            FROM surgical_robots r
            LEFT JOIN surgical_procedures p ON r.robot_id = p.robot_id
            GROUP BY r.robot_id, r.robot_serial_number, r.robot_model,
                     r.manufacturer, r.facility_id, r.install_date,
                     r.software_version, r.hardware_revision, r.status,
                     r.last_maintenance_date
        """)
        robots = rds_cursor.fetchall()

        # Export to S3
        s3_path = export_to_s3_csv(robots, 'robots.csv')
        if not s3_path:
            return 0

        rs_cursor = rs_conn.cursor()

        # Create temp table
        rs_cursor.execute("""
            CREATE TEMP TABLE staging_robots (
                robot_id VARCHAR(50),
                robot_serial_number VARCHAR(100),
                robot_model VARCHAR(100),
                manufacturer VARCHAR(100),
                facility_id VARCHAR(50),
                install_date DATE,
                software_version VARCHAR(50),
                hardware_revision VARCHAR(50),
                status VARCHAR(50),
                last_maintenance_date DATE,
                total_procedures_count INTEGER,
                total_operating_hours DECIMAL(10,2),
                effective_date DATE
            )
        """)

        # COPY from S3
        copy_command = f"""
            COPY staging_robots
            FROM '{s3_path}'
            IAM_ROLE '{REDSHIFT_IAM_ROLE}'
            DELIMITER '|'
            REMOVEQUOTES
            EMPTYASNULL
            DATEFORMAT 'YYYY-MM-DD'
        """
        rs_cursor.execute(copy_command)

        # Get facility keys
        rs_cursor.execute("""
            -- Merge into dimension
            UPDATE dim_robots
            SET expiration_date = CURRENT_DATE - 1,
                is_current = FALSE
            WHERE is_current = TRUE
              AND robot_id IN (SELECT robot_id FROM staging_robots);

            INSERT INTO dim_robots (
                robot_id, robot_serial_number, robot_model, manufacturer,
                facility_key, install_date, software_version, hardware_revision,
                status, last_maintenance_date, total_procedures_count,
                total_operating_hours, effective_date, expiration_date, is_current
            )
            SELECT
                s.robot_id,
                s.robot_serial_number,
                s.robot_model,
                s.manufacturer,
                f.facility_key,
                s.install_date,
                s.software_version,
                s.hardware_revision,
                s.status,
                s.last_maintenance_date,
                s.total_procedures_count,
                s.total_operating_hours,
                s.effective_date,
                NULL,
                TRUE
            FROM staging_robots s
            LEFT JOIN dim_facilities f ON s.facility_id = f.facility_id AND f.is_current = TRUE;
        """)

        row_count = rs_cursor.rowcount
        rs_conn.commit()

        print(f"Loaded {row_count} robot records")
        return row_count

    except Exception as e:
        print(f"Error loading robots: {str(e)}")
        rs_conn.rollback()
        raise
    finally:
        rds_conn.close()
        rs_conn.close()


def load_fact_procedures(start_date=None, end_date=None):
    """Load procedure facts (incremental)"""
    print("Loading procedure facts...")

    # Default to yesterday if no dates provided
    if not start_date:
        start_date = (datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d')
    if not end_date:
        end_date = datetime.now().strftime('%Y-%m-%d')

    rds_conn = get_rds_connection()
    rs_conn = get_redshift_connection()

    try:
        # Extract procedures from RDS
        rds_cursor = rds_conn.cursor()
        rds_cursor.execute("""
            SELECT
                p.procedure_id,
                p.robot_id,
                p.surgeon_id,
                r.facility_id,
                TO_CHAR(p.start_time, 'YYYYMMDD')::INTEGER as start_date_key,
                EXTRACT(HOUR FROM p.start_time)::INTEGER * 10000 +
                EXTRACT(MINUTE FROM p.start_time)::INTEGER * 100 as start_time_key,
                TO_CHAR(p.end_time, 'YYYYMMDD')::INTEGER as end_date_key,
                EXTRACT(HOUR FROM p.end_time)::INTEGER * 10000 +
                EXTRACT(MINUTE FROM p.end_time)::INTEGER * 100 as end_time_key,
                p.procedure_type,
                p.procedure_category,
                p.patient_id,
                p.patient_age,
                p.patient_gender,
                p.duration_minutes,
                p.complexity_score,
                o.success_status,
                o.blood_loss_ml,
                o.complication_level,
                o.hospital_stay_days,
                o.patient_satisfaction_score,
                o.readmission_30day,
                p.status
            FROM surgical_procedures p
            LEFT JOIN surgical_robots r ON p.robot_id = r.robot_id
            LEFT JOIN procedure_outcomes o ON p.procedure_id = o.procedure_id
            WHERE p.start_time >= %s AND p.start_time < %s
        """, (start_date, end_date))
        procedures = rds_cursor.fetchall()

        # Export to S3
        s3_path = export_to_s3_csv(procedures, f'procedures_{start_date}_{end_date}.csv')
        if not s3_path:
            return 0

        rs_cursor = rs_conn.cursor()

        # Create temp table
        rs_cursor.execute("""
            CREATE TEMP TABLE staging_procedures (
                procedure_id VARCHAR(100),
                robot_id VARCHAR(50),
                surgeon_id VARCHAR(50),
                facility_id VARCHAR(50),
                start_date_key INTEGER,
                start_time_key INTEGER,
                end_date_key INTEGER,
                end_time_key INTEGER,
                procedure_type VARCHAR(100),
                procedure_category VARCHAR(50),
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
                status VARCHAR(50)
            )
        """)

        # COPY from S3
        copy_command = f"""
            COPY staging_procedures
            FROM '{s3_path}'
            IAM_ROLE '{REDSHIFT_IAM_ROLE}'
            DELIMITER '|'
            REMOVEQUOTES
            EMPTYASNULL
        """
        rs_cursor.execute(copy_command)

        # Insert into fact table
        rs_cursor.execute("""
            INSERT INTO fact_procedures (
                procedure_id, robot_key, surgeon_key, facility_key,
                start_date_key, start_time_key, end_date_key, end_time_key,
                procedure_type, procedure_category, patient_id, patient_age,
                patient_gender, duration_minutes, complexity_score,
                success_status, blood_loss_ml, complication_level,
                hospital_stay_days, patient_satisfaction_score,
                readmission_30day, status
            )
            SELECT
                s.procedure_id,
                r.robot_key,
                sg.surgeon_key,
                f.facility_key,
                s.start_date_key,
                s.start_time_key,
                s.end_date_key,
                s.end_time_key,
                s.procedure_type,
                s.procedure_category,
                s.patient_id,
                s.patient_age,
                s.patient_gender,
                s.duration_minutes,
                s.complexity_score,
                s.success_status,
                s.blood_loss_ml,
                s.complication_level,
                s.hospital_stay_days,
                s.patient_satisfaction_score,
                s.readmission_30day,
                s.status
            FROM staging_procedures s
            LEFT JOIN dim_robots r ON s.robot_id = r.robot_id AND r.is_current = TRUE
            LEFT JOIN dim_surgeons sg ON s.surgeon_id = sg.surgeon_id AND sg.is_current = TRUE
            LEFT JOIN dim_facilities f ON s.facility_id = f.facility_id AND f.is_current = TRUE
            WHERE NOT EXISTS (
                SELECT 1 FROM fact_procedures fp WHERE fp.procedure_id = s.procedure_id
            );
        """)

        row_count = rs_cursor.rowcount
        rs_conn.commit()

        print(f"Loaded {row_count} procedure records")
        return row_count

    except Exception as e:
        print(f"Error loading procedures: {str(e)}")
        rs_conn.rollback()
        raise
    finally:
        rds_conn.close()
        rs_conn.close()


def lambda_handler(event, context):
    """Lambda handler for ETL orchestration"""

    etl_type = event.get('etl_type', 'full')
    start_date = event.get('start_date')
    end_date = event.get('end_date')

    results = {
        'status': 'success',
        'timestamp': datetime.now().isoformat(),
        'etl_type': etl_type,
        'records_loaded': {}
    }

    try:
        if etl_type == 'full' or etl_type == 'dimensions':
            # Load dimensions
            results['records_loaded']['surgeons'] = load_dimension_surgeons()
            results['records_loaded']['robots'] = load_dimension_robots()

        if etl_type == 'full' or etl_type == 'procedures':
            # Load procedure facts
            results['records_loaded']['procedures'] = load_fact_procedures(start_date, end_date)

        return results

    except Exception as e:
        print(f"ETL failed: {str(e)}")
        results['status'] = 'failed'
        results['error'] = str(e)
        raise
