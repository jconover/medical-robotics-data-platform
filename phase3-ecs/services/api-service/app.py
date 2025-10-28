"""
Medical Robotics Data Platform - API Service
Provides REST API for querying surgical robotics data
"""

import os
import json
import boto3
import psycopg2
from datetime import datetime, timedelta
from flask import Flask, request, jsonify
from psycopg2.extras import RealDictCursor

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
        password=RDS_PASSWORD,
        cursor_factory=RealDictCursor
    )

@app.route('/health', methods=['GET'])
@app.route('/api/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({'status': 'healthy', 'service': 'api-service'}), 200

@app.route('/api/robots', methods=['GET'])
def get_robots():
    """Get list of all surgical robots"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # Optional filters
        facility_id = request.args.get('facility_id')
        status = request.args.get('status')

        query = "SELECT * FROM surgical_robots WHERE 1=1"
        params = []

        if facility_id:
            query += " AND facility_id = %s"
            params.append(facility_id)

        if status:
            query += " AND status = %s"
            params.append(status)

        query += " ORDER BY facility_name, robot_serial_number"

        cursor.execute(query, params)
        robots = cursor.fetchall()

        cursor.close()
        conn.close()

        return jsonify({
            'count': len(robots),
            'robots': robots
        }), 200

    except Exception as e:
        app.logger.error(f"Error fetching robots: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/robots/<robot_id>', methods=['GET'])
def get_robot(robot_id):
    """Get details for a specific robot"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("SELECT * FROM surgical_robots WHERE robot_id = %s", (robot_id,))
        robot = cursor.fetchone()

        if not robot:
            cursor.close()
            conn.close()
            return jsonify({'error': 'Robot not found'}), 404

        # Get procedure count
        cursor.execute("""
            SELECT COUNT(*) as procedure_count
            FROM surgical_procedures
            WHERE robot_id = %s
        """, (robot_id,))
        procedure_count = cursor.fetchone()['procedure_count']

        cursor.close()
        conn.close()

        return jsonify({
            'robot': robot,
            'procedure_count': procedure_count
        }), 200

    except Exception as e:
        app.logger.error(f"Error fetching robot: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/procedures', methods=['GET'])
def get_procedures():
    """Get list of surgical procedures"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # Optional filters
        robot_id = request.args.get('robot_id')
        category = request.args.get('category')
        status = request.args.get('status', 'completed')
        limit = int(request.args.get('limit', 100))
        offset = int(request.args.get('offset', 0))

        query = "SELECT * FROM surgical_procedures WHERE 1=1"
        params = []

        if robot_id:
            query += " AND robot_id = %s"
            params.append(robot_id)

        if category:
            query += " AND procedure_category = %s"
            params.append(category)

        if status:
            query += " AND status = %s"
            params.append(status)

        query += " ORDER BY start_time DESC LIMIT %s OFFSET %s"
        params.extend([limit, offset])

        cursor.execute(query, params)
        procedures = cursor.fetchall()

        cursor.close()
        conn.close()

        return jsonify({
            'count': len(procedures),
            'limit': limit,
            'offset': offset,
            'procedures': procedures
        }), 200

    except Exception as e:
        app.logger.error(f"Error fetching procedures: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/procedures/<procedure_id>', methods=['GET'])
def get_procedure(procedure_id):
    """Get details for a specific procedure"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # Get procedure details
        cursor.execute("""
            SELECT p.*, r.robot_model, r.facility_name
            FROM surgical_procedures p
            JOIN surgical_robots r ON p.robot_id = r.robot_id
            WHERE p.procedure_id = %s
        """, (procedure_id,))
        procedure = cursor.fetchone()

        if not procedure:
            cursor.close()
            conn.close()
            return jsonify({'error': 'Procedure not found'}), 404

        # Get outcome if exists
        cursor.execute("""
            SELECT * FROM procedure_outcomes WHERE procedure_id = %s
        """, (procedure_id,))
        outcome = cursor.fetchone()

        cursor.close()
        conn.close()

        return jsonify({
            'procedure': procedure,
            'outcome': outcome
        }), 200

    except Exception as e:
        app.logger.error(f"Error fetching procedure: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/outcomes', methods=['GET'])
def get_outcomes():
    """Get procedure outcomes with optional filters"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        success_status = request.args.get('success_status')
        limit = int(request.args.get('limit', 100))

        query = """
            SELECT o.*, p.procedure_type, p.start_time
            FROM procedure_outcomes o
            JOIN surgical_procedures p ON o.procedure_id = p.procedure_id
            WHERE 1=1
        """
        params = []

        if success_status:
            query += " AND o.success_status = %s"
            params.append(success_status)

        query += " ORDER BY p.start_time DESC LIMIT %s"
        params.append(limit)

        cursor.execute(query, params)
        outcomes = cursor.fetchall()

        cursor.close()
        conn.close()

        return jsonify({
            'count': len(outcomes),
            'outcomes': outcomes
        }), 200

    except Exception as e:
        app.logger.error(f"Error fetching outcomes: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/analytics/robot-utilization', methods=['GET'])
def robot_utilization():
    """Get robot utilization analytics"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("SELECT * FROM vw_robot_utilization ORDER BY procedure_count DESC")
        utilization = cursor.fetchall()

        cursor.close()
        conn.close()

        return jsonify({
            'count': len(utilization),
            'utilization': utilization
        }), 200

    except Exception as e:
        app.logger.error(f"Error fetching utilization: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/analytics/outcomes-summary', methods=['GET'])
def outcomes_summary():
    """Get summary statistics for procedure outcomes"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT
                success_status,
                COUNT(*) as count,
                AVG(blood_loss_ml) as avg_blood_loss,
                AVG(hospital_stay_days) as avg_stay_days,
                AVG(patient_satisfaction_score) as avg_satisfaction
            FROM procedure_outcomes
            GROUP BY success_status
        """)
        summary = cursor.fetchall()

        cursor.close()
        conn.close()

        return jsonify({
            'summary': summary
        }), 200

    except Exception as e:
        app.logger.error(f"Error fetching outcomes summary: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/analytics/procedures-by-category', methods=['GET'])
def procedures_by_category():
    """Get procedure counts by category"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        days = int(request.args.get('days', 30))
        start_date = datetime.now() - timedelta(days=days)

        cursor.execute("""
            SELECT
                procedure_category,
                COUNT(*) as count,
                AVG(duration_minutes) as avg_duration,
                AVG(complexity_score) as avg_complexity
            FROM surgical_procedures
            WHERE start_time >= %s
            GROUP BY procedure_category
            ORDER BY count DESC
        """, (start_date,))
        categories = cursor.fetchall()

        cursor.close()
        conn.close()

        return jsonify({
            'days': days,
            'categories': categories
        }), 200

    except Exception as e:
        app.logger.error(f"Error fetching category stats: {str(e)}")
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    # Run Flask app
    port = int(os.environ.get('PORT', 5000))
    app.run(host='0.0.0.0', port=port, debug=False)
