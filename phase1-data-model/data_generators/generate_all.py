"""
Master script to generate all fake medical robotics data.
Run this script to generate all data files in the correct order.
"""

import time
import os

print("=" * 60)
print("Medical Robotics Surgery Data Platform")
print("Data Generation - Phase 1")
print("=" * 60)
print()

# Ensure sample_data directory exists
os.makedirs("sample_data", exist_ok=True)

start_time = time.time()

# Step 1: Generate robots
print("Step 1/5: Generating surgical robots...")
print("-" * 60)
from generate_robots import generate_robots
robots = generate_robots()
print()

# Step 2: Generate maintenance logs
print("Step 2/5: Generating maintenance logs...")
print("-" * 60)
from generate_maintenance import generate_maintenance_logs
maintenance = generate_maintenance_logs()
print()

# Step 3: Generate procedures
print("Step 3/5: Generating surgical procedures...")
print("-" * 60)
from generate_procedures import generate_procedures
procedures = generate_procedures()
print()

# Step 4: Generate outcomes
print("Step 4/5: Generating procedure outcomes...")
print("-" * 60)
from generate_outcomes import generate_outcomes
outcomes = generate_outcomes()
print()

# Step 5: Generate telemetry
print("Step 5/5: Generating procedure telemetry...")
print("-" * 60)
from generate_telemetry import generate_all_telemetry
telemetry = generate_all_telemetry()
print()

end_time = time.time()
elapsed = end_time - start_time

print("=" * 60)
print("Data Generation Complete!")
print("=" * 60)
print(f"Total time: {elapsed:.2f} seconds")
print()
print("Generated files:")
print(f"  - sample_data/surgical_robots.csv ({len(robots)} records)")
print(f"  - sample_data/robot_maintenance_logs.csv ({len(maintenance)} records)")
print(f"  - sample_data/surgical_procedures.csv ({len(procedures)} records)")
print(f"  - sample_data/procedure_outcomes.csv ({len(outcomes)} records)")
print(f"  - sample_data/procedure_telemetry.json ({len(telemetry):,} records)")
print()

# Calculate total data size
total_size = 0
for filename in ['surgical_robots.csv', 'robot_maintenance_logs.csv',
                 'surgical_procedures.csv', 'procedure_outcomes.csv',
                 'procedure_telemetry.json']:
    filepath = f'sample_data/{filename}'
    if os.path.exists(filepath):
        total_size += os.path.getsize(filepath)

total_size_mb = total_size / (1024 * 1024)
print(f"Total data size: {total_size_mb:.2f} MB")
print()
print("Next steps:")
print("  1. Review the generated data in the sample_data/ directory")
print("  2. Proceed to Phase 2: Core Infrastructure (CloudFormation)")
print("=" * 60)
