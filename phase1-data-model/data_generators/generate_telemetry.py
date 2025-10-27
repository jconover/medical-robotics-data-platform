"""
Generate fake procedure telemetry data (high-frequency sensor data).
This generates JSON format suitable for S3 storage.
"""

import csv
import json
import random
import uuid
from datetime import datetime, timedelta
from config import (
    TELEMETRY_SAMPLES_PER_PROCEDURE, SURGICAL_TOOLS,
    PROCEDURES_CSV, TELEMETRY_JSON, OUTPUT_DIR
)
import os


def load_procedures():
    """Load completed procedures from CSV."""
    procedures = []
    with open(PROCEDURES_CSV, 'r') as csvfile:
        reader = csv.DictReader(csvfile)
        for row in reader:
            # Only generate telemetry for completed procedures
            if row['status'] == 'completed':
                procedures.append(row)
    return procedures


def generate_telemetry_for_procedure(procedure):
    """Generate telemetry samples for a single procedure."""
    telemetry_records = []

    procedure_id = procedure['procedure_id']
    start_time = datetime.strptime(procedure['start_time'], "%Y-%m-%d %H:%M:%S")
    end_time = datetime.strptime(procedure['end_time'], "%Y-%m-%d %H:%M:%S")
    duration_seconds = (end_time - start_time).total_seconds()

    # Calculate interval between samples
    interval_seconds = duration_seconds / TELEMETRY_SAMPLES_PER_PROCEDURE

    # Initialize random walk for positions (robotic arm movement)
    current_x = random.uniform(0, 500)  # mm
    current_y = random.uniform(0, 500)
    current_z = random.uniform(0, 300)
    current_rotation = random.uniform(0, 360)

    # Tool changes during procedure
    current_tool = random.choice(SURGICAL_TOOLS)
    tool_change_interval = TELEMETRY_SAMPLES_PER_PROCEDURE // random.randint(3, 7)

    for i in range(TELEMETRY_SAMPLES_PER_PROCEDURE):
        timestamp = start_time + timedelta(seconds=i * interval_seconds)

        # Simulate arm movement (random walk with limits)
        current_x += random.uniform(-10, 10)
        current_y += random.uniform(-10, 10)
        current_z += random.uniform(-5, 5)
        current_rotation += random.uniform(-15, 15)

        # Keep within bounds
        current_x = max(0, min(500, current_x))
        current_y = max(0, min(500, current_y))
        current_z = max(0, min(300, current_z))
        current_rotation = current_rotation % 360

        # Tool changes
        if i > 0 and i % tool_change_interval == 0:
            current_tool = random.choice(SURGICAL_TOOLS)

        # Grip pressure (varies by tool)
        if current_tool in ["Grasper", "Forceps", "Needle Driver"]:
            grip_pressure = random.uniform(0.5, 5.0)
        else:
            grip_pressure = 0.0

        # Tremor compensation (surgeon's hand tremor filtered out)
        tremor_compensation = random.uniform(2, 15)

        # Camera parameters
        camera_zoom = random.uniform(1.0, 10.0)
        camera_angle = random.uniform(-30, 30)

        # Force feedback (resistance from tissue)
        force_x = random.uniform(-2.0, 2.0)
        force_y = random.uniform(-2.0, 2.0)
        force_z = random.uniform(-5.0, 5.0)

        # System parameters
        system_temp = random.uniform(20, 35)  # Celsius
        power_consumption = random.uniform(150, 400)  # Watts

        telemetry = {
            "telemetry_id": str(uuid.uuid4()),
            "procedure_id": procedure_id,
            "timestamp": timestamp.strftime("%Y-%m-%d %H:%M:%S.%f")[:-3],
            "arm_position_x": round(current_x, 4),
            "arm_position_y": round(current_y, 4),
            "arm_position_z": round(current_z, 4),
            "arm_rotation": round(current_rotation, 2),
            "tool_type": current_tool,
            "grip_pressure": round(grip_pressure, 2),
            "tremor_compensation": round(tremor_compensation, 2),
            "camera_zoom": round(camera_zoom, 2),
            "camera_angle": round(camera_angle, 2),
            "force_feedback_x": round(force_x, 4),
            "force_feedback_y": round(force_y, 4),
            "force_feedback_z": round(force_z, 4),
            "system_temperature": round(system_temp, 2),
            "power_consumption": round(power_consumption, 2),
        }

        telemetry_records.append(telemetry)

    return telemetry_records


def generate_all_telemetry():
    """Generate telemetry for all completed procedures."""
    procedures = load_procedures()
    if not procedures:
        raise Exception("No completed procedures found. Please run generate_procedures.py first.")

    all_telemetry = []

    print(f"Generating telemetry for {len(procedures)} procedures...")
    print(f"Samples per procedure: {TELEMETRY_SAMPLES_PER_PROCEDURE}")
    print(f"Total expected samples: {len(procedures) * TELEMETRY_SAMPLES_PER_PROCEDURE:,}")

    for idx, procedure in enumerate(procedures):
        telemetry = generate_telemetry_for_procedure(procedure)
        all_telemetry.extend(telemetry)

        if (idx + 1) % 500 == 0:
            print(f"  Processed {idx + 1}/{len(procedures)} procedures...")

    # Ensure output directory exists
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # Write to JSON file (newline-delimited JSON for easy streaming)
    with open(TELEMETRY_JSON, 'w') as jsonfile:
        for record in all_telemetry:
            jsonfile.write(json.dumps(record) + '\n')

    print(f"\nGenerated {len(all_telemetry):,} telemetry records")
    print(f"Output: {TELEMETRY_JSON}")

    return all_telemetry


if __name__ == "__main__":
    telemetry = generate_all_telemetry()

    # Print sample
    print("\nSample telemetry record:")
    print(json.dumps(telemetry[0], indent=2))

    # File size
    import os
    file_size_mb = os.path.getsize(TELEMETRY_JSON) / (1024 * 1024)
    print(f"\nFile size: {file_size_mb:.2f} MB")
