"""
Generate fake robot maintenance log data.
"""

import csv
import random
import uuid
from datetime import datetime, timedelta
from config import (
    NUM_MAINTENANCE_LOGS, MAINTENANCE_TYPES, TECHNICIAN_FIRST_NAMES,
    TECHNICIAN_LAST_NAMES, DATA_START_DATE, DATA_END_DATE,
    ROBOTS_CSV, MAINTENANCE_CSV, OUTPUT_DIR
)
import os


def load_robots():
    """Load robot data from CSV."""
    robots = []
    with open(ROBOTS_CSV, 'r') as csvfile:
        reader = csv.DictReader(csvfile)
        for row in reader:
            robots.append(row)
    return robots


def generate_maintenance_logs():
    """Generate robot maintenance log records."""
    robots = load_robots()
    if not robots:
        raise Exception("No robots found. Please run generate_robots.py first.")

    maintenance_logs = []

    # Ensure output directory exists
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # Generate technicians
    technicians = []
    for i in range(20):
        technician_id = f"TECH-{i:04d}"
        technician_name = f"{random.choice(TECHNICIAN_FIRST_NAMES)} {random.choice(TECHNICIAN_LAST_NAMES)}"
        technicians.append({"technician_id": technician_id, "technician_name": technician_name})

    for i in range(NUM_MAINTENANCE_LOGS):
        maintenance_id = str(uuid.uuid4())

        # Random robot
        robot = random.choice(robots)
        robot_id = robot['robot_id']

        # Random maintenance date within data range
        time_range = (DATA_END_DATE - DATA_START_DATE).days
        random_days = random.randint(0, time_range)
        maintenance_date = DATA_START_DATE + timedelta(days=random_days)

        # Maintenance type
        maintenance_type = random.choice(MAINTENANCE_TYPES)

        # Random technician
        technician = random.choice(technicians)

        # Issues and actions based on maintenance type
        if maintenance_type == "routine":
            issues_options = [
                "No issues found",
                "Normal wear on actuators",
                "Calibration drift detected",
                "Minor sensor degradation",
            ]
            actions_options = [
                "Performed standard preventive maintenance",
                "Cleaned and lubricated all moving parts",
                "Calibrated sensors and actuators",
                "Updated firmware to latest version",
                "Replaced air filters",
            ]
        elif maintenance_type == "emergency":
            issues_options = [
                "Arm motor failure",
                "Hydraulic system leak",
                "Control system malfunction",
                "Camera system failure",
                "Emergency stop triggered unexpectedly",
            ]
            actions_options = [
                "Replaced failed motor assembly",
                "Repaired hydraulic seal",
                "Reset control system and ran diagnostics",
                "Replaced camera module",
                "Investigated and cleared emergency stop system",
            ]
        elif maintenance_type == "upgrade":
            issues_options = [
                "Scheduled hardware upgrade",
                "Software enhancement required",
                "Performance optimization requested",
            ]
            actions_options = [
                "Installed new control module",
                "Upgraded to latest software version",
                "Added enhanced visualization system",
                "Installed improved haptic feedback system",
            ]
        else:  # calibration
            issues_options = [
                "Regular calibration schedule",
                "Accuracy verification required",
                "Post-repair calibration",
            ]
            actions_options = [
                "Performed full system calibration",
                "Verified all sensor accuracies",
                "Calibrated camera and arm alignment",
                "Validated positioning accuracy",
            ]

        issues_found = random.choice(issues_options)
        num_actions = random.randint(1, 3)
        actions_taken = "; ".join(random.sample(actions_options, min(num_actions, len(actions_options))))

        # Parts replaced (if emergency or sometimes routine)
        parts_options = [
            "None",
            "Actuator assembly",
            "Sensor module",
            "Camera unit",
            "Hydraulic seal kit",
            "Control board",
            "Power supply unit",
            "Gripper assembly",
        ]

        if maintenance_type == "emergency":
            parts_replaced = random.choice([p for p in parts_options if p != "None"])
        elif maintenance_type == "routine" and random.random() < 0.3:
            parts_replaced = random.choice(parts_options)
        else:
            parts_replaced = "None"

        # Downtime (emergency has most, routine has least)
        if maintenance_type == "emergency":
            downtime_hours = round(random.uniform(4, 24), 2)
        elif maintenance_type == "upgrade":
            downtime_hours = round(random.uniform(2, 12), 2)
        elif maintenance_type == "calibration":
            downtime_hours = round(random.uniform(1, 4), 2)
        else:  # routine
            downtime_hours = round(random.uniform(0.5, 3), 2)

        # Next maintenance date (30-90 days out)
        next_maintenance_date = maintenance_date + timedelta(days=random.randint(30, 90))

        # Cost (varies by type and parts)
        base_cost = {
            "routine": random.uniform(500, 2000),
            "emergency": random.uniform(5000, 25000),
            "upgrade": random.uniform(10000, 50000),
            "calibration": random.uniform(1000, 5000),
        }
        cost = round(base_cost[maintenance_type], 2)

        if parts_replaced != "None":
            cost += random.uniform(2000, 15000)
            cost = round(cost, 2)

        # Timestamps
        created_at = maintenance_date

        maintenance_log = {
            "maintenance_id": maintenance_id,
            "robot_id": robot_id,
            "maintenance_date": maintenance_date.strftime("%Y-%m-%d"),
            "maintenance_type": maintenance_type,
            "technician_id": technician['technician_id'],
            "technician_name": technician['technician_name'],
            "issues_found": issues_found,
            "actions_taken": actions_taken,
            "parts_replaced": parts_replaced,
            "downtime_hours": downtime_hours,
            "next_maintenance_date": next_maintenance_date.strftime("%Y-%m-%d"),
            "cost": cost,
            "created_at": created_at.strftime("%Y-%m-%d %H:%M:%S"),
        }

        maintenance_logs.append(maintenance_log)

    # Sort by maintenance date
    maintenance_logs.sort(key=lambda x: x['maintenance_date'])

    # Write to CSV
    fieldnames = [
        "maintenance_id", "robot_id", "maintenance_date", "maintenance_type",
        "technician_id", "technician_name", "issues_found", "actions_taken",
        "parts_replaced", "downtime_hours", "next_maintenance_date", "cost",
        "created_at"
    ]

    with open(MAINTENANCE_CSV, 'w', newline='') as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(maintenance_logs)

    print(f"Generated {len(maintenance_logs)} maintenance logs")
    print(f"Output: {MAINTENANCE_CSV}")

    return maintenance_logs


if __name__ == "__main__":
    logs = generate_maintenance_logs()

    # Print sample
    print("\nSample maintenance log:")
    print(logs[0])

    # Print statistics
    print(f"\nMaintenance type statistics:")
    types = {}
    for log in logs:
        mtype = log['maintenance_type']
        types[mtype] = types.get(mtype, 0) + 1

    for mtype, count in sorted(types.items()):
        percentage = (count / len(logs)) * 100
        print(f"  {mtype}: {count} ({percentage:.1f}%)")

    # Cost statistics
    total_cost = sum(float(log['cost']) for log in logs)
    avg_cost = total_cost / len(logs)
    print(f"\nCost statistics:")
    print(f"  Total: ${total_cost:,.2f}")
    print(f"  Average: ${avg_cost:,.2f}")
