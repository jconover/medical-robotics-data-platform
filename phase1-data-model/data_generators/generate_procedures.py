"""
Generate fake surgical procedure data.
"""

import csv
import random
import uuid
from datetime import datetime, timedelta
from config import (
    NUM_PROCEDURES, PROCEDURE_TYPES, SURGEON_FIRST_NAMES, SURGEON_LAST_NAMES,
    DATA_START_DATE, DATA_END_DATE, PROCEDURES_CSV, ROBOTS_CSV, OUTPUT_DIR
)
import os


def load_robots():
    """Load robot data from CSV."""
    robots = []
    with open(ROBOTS_CSV, 'r') as csvfile:
        reader = csv.DictReader(csvfile)
        for row in reader:
            # Only use operational robots
            if row['status'] == 'operational':
                robots.append(row)
    return robots


def generate_procedures():
    """Generate surgical procedure records."""
    # Load robots first
    robots = load_robots()
    if not robots:
        raise Exception("No robots found. Please run generate_robots.py first.")

    procedures = []

    # Ensure output directory exists
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # Generate surgeons
    surgeons = []
    for i in range(50):
        surgeon_id = f"SURG-{i:04d}"
        surgeon_name = f"Dr. {random.choice(SURGEON_FIRST_NAMES)} {random.choice(SURGEON_LAST_NAMES)}"
        surgeons.append({"surgeon_id": surgeon_id, "surgeon_name": surgeon_name})

    for i in range(NUM_PROCEDURES):
        procedure_id = str(uuid.uuid4())

        # Random robot
        robot = random.choice(robots)
        robot_id = robot['robot_id']

        # Random procedure category and type
        category = random.choice(list(PROCEDURE_TYPES.keys()))
        procedure_type = random.choice(PROCEDURE_TYPES[category])

        # Random start time within date range
        time_range = (DATA_END_DATE - DATA_START_DATE).days
        random_days = random.randint(0, time_range)
        start_time = DATA_START_DATE + timedelta(days=random_days)

        # Add random hour (procedures typically happen 7am-5pm)
        hour = random.randint(7, 17)
        minute = random.randint(0, 59)
        start_time = start_time.replace(hour=hour, minute=minute, second=0)

        # Duration (30 minutes to 8 hours, varies by complexity)
        complexity_score = round(random.uniform(1.0, 5.0), 2)
        base_duration = random.randint(30, 480)
        # More complex procedures take longer
        duration_minutes = int(base_duration * (1 + (complexity_score - 1) * 0.2))

        end_time = start_time + timedelta(minutes=duration_minutes)

        # Random surgeon
        surgeon = random.choice(surgeons)

        # Patient info (anonymized)
        patient_id = f"PAT-{random.randint(100000, 999999)}"
        patient_age = random.randint(18, 85)
        patient_gender = random.choice(["Male", "Female", "Other"])

        # Status (most completed)
        status = random.choices(
            ["completed", "in_progress", "aborted", "cancelled"],
            weights=[0.92, 0.02, 0.03, 0.03],
            k=1
        )[0]

        # Created timestamp
        created_at = start_time

        procedure = {
            "procedure_id": procedure_id,
            "robot_id": robot_id,
            "procedure_type": procedure_type,
            "procedure_category": category,
            "start_time": start_time.strftime("%Y-%m-%d %H:%M:%S"),
            "end_time": end_time.strftime("%Y-%m-%d %H:%M:%S"),
            "duration_minutes": duration_minutes,
            "surgeon_id": surgeon['surgeon_id'],
            "surgeon_name": surgeon['surgeon_name'],
            "patient_id": patient_id,
            "patient_age": patient_age,
            "patient_gender": patient_gender,
            "complexity_score": complexity_score,
            "status": status,
            "created_at": created_at.strftime("%Y-%m-%d %H:%M:%S"),
        }

        procedures.append(procedure)

    # Sort by start time
    procedures.sort(key=lambda x: x['start_time'])

    # Write to CSV
    fieldnames = [
        "procedure_id", "robot_id", "procedure_type", "procedure_category",
        "start_time", "end_time", "duration_minutes", "surgeon_id", "surgeon_name",
        "patient_id", "patient_age", "patient_gender", "complexity_score",
        "status", "created_at"
    ]

    with open(PROCEDURES_CSV, 'w', newline='') as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(procedures)

    print(f"Generated {len(procedures)} surgical procedures")
    print(f"Output: {PROCEDURES_CSV}")

    return procedures


if __name__ == "__main__":
    procedures = generate_procedures()

    # Print sample
    print("\nSample procedure:")
    print(procedures[0])

    # Print statistics
    print(f"\nProcedure statistics:")
    categories = {}
    for proc in procedures:
        cat = proc['procedure_category']
        categories[cat] = categories.get(cat, 0) + 1

    for cat, count in sorted(categories.items()):
        print(f"  {cat}: {count}")
