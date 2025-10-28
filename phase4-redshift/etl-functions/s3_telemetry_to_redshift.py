"""
Medical Robotics Data Platform - S3 Telemetry to Redshift ETL
Processes telemetry data from S3 and loads into Redshift
Uses batch processing for high-volume telemetry data
"""

import os
import json
import boto3
import psycopg2
from datetime import datetime
from psycopg2.extras import RealDictCursor

# Environment variables
REDSHIFT_HOST = os.environ.get('REDSHIFT_HOST')
REDSHIFT_PORT = os.environ.get('REDSHIFT_PORT', '5439')
REDSHIFT_DBNAME = os.environ.get('REDSHIFT_DBNAME', 'medrobotics_dw')
REDSHIFT_USER = os.environ.get('REDSHIFT_USER', 'dwadmin')
REDSHIFT_SECRET_ARN = os.environ.get('REDSHIFT_SECRET_ARN')

S3_RAW_BUCKET = os.environ.get('S3_RAW_BUCKET')
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


def process_telemetry_files(s3_prefix, batch_date):
    """
    Process telemetry files from S3 raw bucket
    Transforms and loads into Redshift
    """
    print(f"Processing telemetry files from {s3_prefix}")

    # List telemetry files in S3
    response = s3_client.list_objects_v2(
        Bucket=S3_RAW_BUCKET,
        Prefix=s3_prefix,
        MaxKeys=1000
    )

    if 'Contents' not in response:
        print("No telemetry files found")
        return 0

    files = [obj['Key'] for obj in response['Contents'] if obj['Key'].endswith('.json')]
    print(f"Found {len(files)} telemetry files")

    if not files:
        return 0

    # Process files and consolidate into CSV
    telemetry_records = []
    files_processed = 0

    for file_key in files[:100]:  # Process max 100 files per batch
        try:
            # Download and parse JSON
            obj = s3_client.get_object(Bucket=S3_RAW_BUCKET, Key=file_key)
            telemetry_data = json.loads(obj['Body'].read().decode('utf-8'))

            # Handle both single record and array formats
            if isinstance(telemetry_data, list):
                records = telemetry_data
            else:
                records = [telemetry_data]

            # Transform each telemetry record
            for record in records:
                transformed = transform_telemetry_record(record)
                if transformed:
                    telemetry_records.append(transformed)

            files_processed += 1

        except Exception as e:
            print(f"Error processing file {file_key}: {str(e)}")
            continue

    print(f"Processed {files_processed} files with {len(telemetry_records)} telemetry records")

    if not telemetry_records:
        return 0

    # Export consolidated CSV to staging bucket
    csv_content = create_telemetry_csv(telemetry_records)
    staging_key = f"etl-staging/telemetry/{batch_date}/telemetry_{datetime.now().strftime('%H%M%S')}.csv"

    s3_client.put_object(
        Bucket=S3_STAGING_BUCKET,
        Key=staging_key,
        Body=csv_content.encode('utf-8')
    )

    s3_path = f"s3://{S3_STAGING_BUCKET}/{staging_key}"
    print(f"Exported to {s3_path}")

    # Load into Redshift
    load_telemetry_to_redshift(s3_path, len(telemetry_records))

    return len(telemetry_records)


def transform_telemetry_record(record):
    """Transform raw telemetry JSON to flat CSV format"""
    try:
        # Extract timestamp
        timestamp = record.get('timestamp')
        if not timestamp:
            return None

        # Parse timestamp to get time key
        ts_obj = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
        time_key = ts_obj.hour * 10000 + ts_obj.minute * 100

        transformed = {
            'procedure_id': record.get('procedure_id'),
            'timestamp_key': time_key,
            'sample_timestamp': timestamp,
            'arm_position_x': record.get('arm_position', {}).get('x'),
            'arm_position_y': record.get('arm_position', {}).get('y'),
            'arm_position_z': record.get('arm_position', {}).get('z'),
            'arm_rotation_x': record.get('arm_rotation', {}).get('x'),
            'arm_rotation_y': record.get('arm_rotation', {}).get('y'),
            'arm_rotation_z': record.get('arm_rotation', {}).get('z'),
            'force_feedback': record.get('force_feedback'),
            'tool_type': record.get('tool_type'),
            'tool_active': 'true' if record.get('tool_active') else 'false',
            'camera_zoom': record.get('camera_zoom'),
            'lighting_level': record.get('lighting_level'),
            'system_temperature': record.get('system_metrics', {}).get('temperature'),
            'motor_current': record.get('system_metrics', {}).get('motor_current'),
            'network_latency_ms': record.get('system_metrics', {}).get('network_latency_ms'),
            'video_fps': record.get('system_metrics', {}).get('video_fps')
        }

        return transformed

    except Exception as e:
        print(f"Error transforming record: {str(e)}")
        return None


def create_telemetry_csv(records):
    """Create pipe-delimited CSV from telemetry records"""
    import csv
    from io import StringIO

    csv_buffer = StringIO()
    fieldnames = [
        'procedure_id', 'timestamp_key', 'sample_timestamp',
        'arm_position_x', 'arm_position_y', 'arm_position_z',
        'arm_rotation_x', 'arm_rotation_y', 'arm_rotation_z',
        'force_feedback', 'tool_type', 'tool_active',
        'camera_zoom', 'lighting_level', 'system_temperature',
        'motor_current', 'network_latency_ms', 'video_fps'
    ]

    writer = csv.DictWriter(
        csv_buffer,
        fieldnames=fieldnames,
        delimiter='|',
        extrasaction='ignore'
    )

    writer.writerows(records)
    return csv_buffer.getvalue()


def load_telemetry_to_redshift(s3_path, record_count):
    """Load telemetry CSV from S3 into Redshift using COPY"""
    print(f"Loading {record_count} telemetry records into Redshift...")

    conn = get_redshift_connection()

    try:
        cursor = conn.cursor()

        # Create temp staging table
        cursor.execute("""
            CREATE TEMP TABLE staging_telemetry (
                procedure_id VARCHAR(100),
                timestamp_key INTEGER,
                sample_timestamp TIMESTAMP,
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
                video_fps INTEGER
            )
        """)

        # COPY command to load from S3
        copy_command = f"""
            COPY staging_telemetry
            FROM '{s3_path}'
            IAM_ROLE '{REDSHIFT_IAM_ROLE}'
            DELIMITER '|'
            REMOVEQUOTES
            EMPTYASNULL
            TIMEFORMAT 'YYYY-MM-DD HH:MI:SS'
        """
        cursor.execute(copy_command)

        # Insert into fact table with procedure key lookup
        cursor.execute("""
            INSERT INTO fact_procedure_telemetry (
                procedure_key,
                timestamp_key,
                sample_timestamp,
                arm_position_x,
                arm_position_y,
                arm_position_z,
                arm_rotation_x,
                arm_rotation_y,
                arm_rotation_z,
                force_feedback,
                tool_type,
                tool_active,
                camera_zoom,
                lighting_level,
                system_temperature,
                motor_current,
                network_latency_ms,
                video_fps
            )
            SELECT
                fp.procedure_key,
                st.timestamp_key,
                st.sample_timestamp,
                st.arm_position_x,
                st.arm_position_y,
                st.arm_position_z,
                st.arm_rotation_x,
                st.arm_rotation_y,
                st.arm_rotation_z,
                st.force_feedback,
                st.tool_type,
                st.tool_active,
                st.camera_zoom,
                st.lighting_level,
                st.system_temperature,
                st.motor_current,
                st.network_latency_ms,
                st.video_fps
            FROM staging_telemetry st
            INNER JOIN fact_procedures fp ON st.procedure_id = fp.procedure_id
            WHERE NOT EXISTS (
                SELECT 1
                FROM fact_procedure_telemetry fpt
                WHERE fpt.procedure_key = fp.procedure_key
                  AND fpt.sample_timestamp = st.sample_timestamp
            );
        """)

        rows_inserted = cursor.rowcount
        conn.commit()

        print(f"Successfully loaded {rows_inserted} telemetry records")
        return rows_inserted

    except Exception as e:
        print(f"Error loading telemetry to Redshift: {str(e)}")
        conn.rollback()
        raise
    finally:
        conn.close()


def lambda_handler(event, context):
    """Lambda handler for telemetry ETL"""

    # Get parameters from event
    batch_date = event.get('batch_date', datetime.now().strftime('%Y%m%d'))
    s3_prefix = event.get('s3_prefix', f'telemetry/')

    print(f"Starting telemetry ETL for batch_date: {batch_date}")

    results = {
        'status': 'success',
        'timestamp': datetime.now().isoformat(),
        'batch_date': batch_date,
        'records_loaded': 0
    }

    try:
        # Process telemetry files
        records_loaded = process_telemetry_files(s3_prefix, batch_date)
        results['records_loaded'] = records_loaded

        return results

    except Exception as e:
        print(f"Telemetry ETL failed: {str(e)}")
        results['status'] = 'failed'
        results['error'] = str(e)
        raise
