"""
Generate fake surgical robot data.
"""

import csv
import random
import uuid
from datetime import datetime, timedelta
from config import (
    NUM_ROBOTS, NUM_FACILITIES, ROBOT_MODELS, FACILITY_NAMES,
    DATA_START_DATE, ROBOTS_CSV, OUTPUT_DIR
)
import os


def generate_robots():
    """Generate surgical robot records."""
    robots = []

    # Ensure output directory exists
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    for i in range(NUM_ROBOTS):
        robot_id = str(uuid.uuid4())
        model, manufacturer = random.choice(ROBOT_MODELS)

        # Generate serial number
        serial_number = f"{manufacturer[:3].upper()}-{random.randint(10000, 99999)}"

        # Random facility
        facility_idx = i % NUM_FACILITIES
        facility_id = f"FAC-{facility_idx:03d}"
        facility_name = FACILITY_NAMES[facility_idx]

        # Installation date (random within the past 5 years before data start)
        install_days_ago = random.randint(365 * 2, 365 * 5)
        installation_date = DATA_START_DATE - timedelta(days=install_days_ago)

        # Status (most operational, some in maintenance)
        status = random.choices(
            ["operational", "maintenance", "retired"],
            weights=[0.85, 0.12, 0.03],
            k=1
        )[0]

        # Last maintenance (within last 90 days for operational robots)
        if status == "operational":
            last_maintenance = DATA_START_DATE - timedelta(days=random.randint(1, 90))
        else:
            last_maintenance = DATA_START_DATE - timedelta(days=random.randint(1, 30))

        # Total procedures (cumulative)
        total_procedures = random.randint(100, 2000)

        # Firmware version
        major = random.randint(2, 5)
        minor = random.randint(0, 9)
        patch = random.randint(0, 20)
        firmware_version = f"{major}.{minor}.{patch}"

        # Timestamps
        created_at = installation_date
        updated_at = DATA_START_DATE

        robot = {
            "robot_id": robot_id,
            "robot_serial_number": serial_number,
            "robot_model": model,
            "manufacturer": manufacturer,
            "installation_date": installation_date.strftime("%Y-%m-%d"),
            "facility_id": facility_id,
            "facility_name": facility_name,
            "status": status,
            "last_maintenance_date": last_maintenance.strftime("%Y-%m-%d"),
            "total_procedures": total_procedures,
            "firmware_version": firmware_version,
            "created_at": created_at.strftime("%Y-%m-%d %H:%M:%S"),
            "updated_at": updated_at.strftime("%Y-%m-%d %H:%M:%S"),
        }

        robots.append(robot)

    # Write to CSV
    fieldnames = [
        "robot_id", "robot_serial_number", "robot_model", "manufacturer",
        "installation_date", "facility_id", "facility_name", "status",
        "last_maintenance_date", "total_procedures", "firmware_version",
        "created_at", "updated_at"
    ]

    with open(ROBOTS_CSV, 'w', newline='') as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(robots)

    print(f"Generated {len(robots)} surgical robots")
    print(f"Output: {ROBOTS_CSV}")

    return robots


if __name__ == "__main__":
    robots = generate_robots()

    # Print sample
    print("\nSample robot:")
    print(robots[0])
