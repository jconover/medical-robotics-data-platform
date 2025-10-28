"""
Medical Robotics Data Platform - Data Ingestion Service
Receives telemetry data and stores it in S3 and RDS
"""

import os
import json
import boto3
import psycopg2
from datetime import datetime
from flask import Flask, request, jsonify
from psycopg2.extras import execute_values

app = Flask(__name__)

# Environment variables
S3_RAW_BUCKET = os.environ.get('S3_RAW_BUCKET')
RDS_HOST = os.environ.get('RDS_HOST')
RDS_PORT = os.environ.get('RDS_PORT', '5432')
RDS_DBNAME = os.environ.get('RDS_DBNAME', 'medrobotics')
RDS_USER = os.environ.get('RDS_USER', 'dbadmin')
RDS_PASSWORD = os.environ.get('RDS_PASSWORD')

# AWS clients
s3_client = boto3.client('s3')

def get_db_connection():
    """Create database connection"""
    return psycopg2.connect(
        host=RDS_HOST,
        port=RDS_PORT,
        database=RDS_DBNAME,
        user=RDS_USER,
        password=RDS_PASSWORD
    )

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({'status': 'healthy', 'service': 'data-ingestion'}), 200

@app.route('/ingest/telemetry', methods=['POST'])
def ingest_telemetry():
    """
    Ingest telemetry data from surgical robots
    Stores raw JSON in S3 for later processing
    """
    try:
        data = request.get_json()

        if not data:
            return jsonify({'error': 'No data provided'}), 400

        # Validate required fields
        required_fields = ['procedure_id', 'timestamp', 'robot_id']
        for field in required_fields:
            if field not in data:
                return jsonify({'error': f'Missing required field: {field}'}), 400

        # Store in S3
        procedure_id = data['procedure_id']
        timestamp = datetime.now().strftime('%Y%m%d%H%M%S')
        s3_key = f"telemetry/{procedure_id}/{timestamp}.json"

        s3_client.put_object(
            Bucket=S3_RAW_BUCKET,
            Key=s3_key,
            Body=json.dumps(data),
            ContentType='application/json'
        )

        return jsonify({
            'status': 'success',
            'message': 'Telemetry data ingested',
            's3_key': s3_key
        }), 201

    except Exception as e:
        app.logger.error(f"Error ingesting telemetry: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/ingest/procedure', methods=['POST'])
def ingest_procedure():
    """
    Ingest surgical procedure data
    Stores in RDS database
    """
    try:
        data = request.get_json()

        if not data:
            return jsonify({'error': 'No data provided'}), 400

        # Insert into database
        conn = get_db_connection()
        cursor = conn.cursor()

        insert_query = """
        INSERT INTO surgical_procedures (
            procedure_id, robot_id, procedure_type, procedure_category,
            start_time, end_time, duration_minutes, surgeon_id, surgeon_name,
            patient_id, patient_age, patient_gender, complexity_score, status
        ) VALUES (
            %(procedure_id)s, %(robot_id)s, %(procedure_type)s, %(procedure_category)s,
            %(start_time)s, %(end_time)s, %(duration_minutes)s, %(surgeon_id)s, %(surgeon_name)s,
            %(patient_id)s, %(patient_age)s, %(patient_gender)s, %(complexity_score)s, %(status)s
        )
        ON CONFLICT (procedure_id) DO UPDATE SET
            status = EXCLUDED.status,
            end_time = EXCLUDED.end_time,
            duration_minutes = EXCLUDED.duration_minutes
        """

        cursor.execute(insert_query, data)
        conn.commit()
        cursor.close()
        conn.close()

        return jsonify({
            'status': 'success',
            'message': 'Procedure data ingested',
            'procedure_id': data.get('procedure_id')
        }), 201

    except Exception as e:
        app.logger.error(f"Error ingesting procedure: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/ingest/batch', methods=['POST'])
def ingest_batch():
    """
    Batch ingestion endpoint for multiple records
    """
    try:
        data = request.get_json()

        if not data or 'records' not in data:
            return jsonify({'error': 'No records provided'}), 400

        records = data['records']
        record_type = data.get('type', 'telemetry')

        # Store batch in S3
        timestamp = datetime.now().strftime('%Y%m%d%H%M%S')
        s3_key = f"batch/{record_type}/{timestamp}.json"

        s3_client.put_object(
            Bucket=S3_RAW_BUCKET,
            Key=s3_key,
            Body=json.dumps(records),
            ContentType='application/json'
        )

        return jsonify({
            'status': 'success',
            'message': f'Batch of {len(records)} records ingested',
            's3_key': s3_key,
            'count': len(records)
        }), 201

    except Exception as e:
        app.logger.error(f"Error ingesting batch: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/ingest/stats', methods=['GET'])
def ingestion_stats():
    """Get ingestion statistics"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT
                COUNT(*) as total_procedures,
                COUNT(DISTINCT robot_id) as unique_robots,
                MAX(start_time) as latest_procedure
            FROM surgical_procedures
        """)

        result = cursor.fetchone()
        cursor.close()
        conn.close()

        return jsonify({
            'total_procedures': result[0],
            'unique_robots': result[1],
            'latest_procedure': result[2].isoformat() if result[2] else None
        }), 200

    except Exception as e:
        app.logger.error(f"Error getting stats: {str(e)}")
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    # Run Flask app
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=False)
