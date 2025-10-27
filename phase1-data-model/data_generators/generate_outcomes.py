"""
Generate fake procedure outcome data.
"""

import csv
import random
import uuid
from datetime import datetime, timedelta
from config import (
    COMPLICATIONS, PROCEDURES_CSV, OUTCOMES_CSV, OUTPUT_DIR
)
import os


def load_procedures():
    """Load completed procedures from CSV."""
    procedures = []
    with open(PROCEDURES_CSV, 'r') as csvfile:
        reader = csv.DictReader(csvfile)
        for row in reader:
            # Only generate outcomes for completed procedures
            if row['status'] == 'completed':
                procedures.append(row)
    return procedures


def generate_outcomes():
    """Generate procedure outcome records."""
    procedures = load_procedures()
    if not procedures:
        raise Exception("No completed procedures found. Please run generate_procedures.py first.")

    outcomes = []

    # Ensure output directory exists
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    for procedure in procedures:
        outcome_id = str(uuid.uuid4())
        procedure_id = procedure['procedure_id']

        # Success status (most successful)
        complexity = float(procedure['complexity_score'])
        # Higher complexity = higher chance of complications
        success_weights = [
            0.85 - (complexity - 1) * 0.05,  # successful
            0.12 + (complexity - 1) * 0.04,  # complicated
            0.03 + (complexity - 1) * 0.01   # failed
        ]
        success_status = random.choices(
            ["successful", "complicated", "failed"],
            weights=success_weights,
            k=1
        )[0]

        # Blood loss (varies by complexity and success)
        base_blood_loss = random.randint(50, 500)
        if success_status == "complicated":
            blood_loss_ml = int(base_blood_loss * random.uniform(1.5, 3.0))
        elif success_status == "failed":
            blood_loss_ml = int(base_blood_loss * random.uniform(2.0, 4.0))
        else:
            blood_loss_ml = base_blood_loss

        # Complications
        if success_status == "successful":
            complications = "none"
        elif success_status == "complicated":
            num_complications = random.randint(1, 2)
            complication_list = random.sample(
                [c for c in COMPLICATIONS if c != "none"],
                num_complications
            )
            complications = ", ".join(complication_list)
        else:  # failed
            num_complications = random.randint(2, 4)
            complication_list = random.sample(
                [c for c in COMPLICATIONS if c != "none"],
                num_complications
            )
            complications = ", ".join(complication_list)

        # Hospital stay (varies by success and complications)
        if success_status == "successful":
            hospital_stay_days = random.randint(1, 4)
        elif success_status == "complicated":
            hospital_stay_days = random.randint(3, 10)
        else:
            hospital_stay_days = random.randint(7, 21)

        # Readmission
        readmission_prob = 0.05 if success_status == "successful" else 0.25
        readmission_30day = random.random() < readmission_prob

        # Patient satisfaction (1-10)
        if success_status == "successful":
            patient_satisfaction = random.randint(7, 10)
        elif success_status == "complicated":
            patient_satisfaction = random.randint(4, 8)
        else:
            patient_satisfaction = random.randint(1, 5)

        # Surgeon notes
        notes_options = [
            "Procedure completed without incident.",
            "Patient tolerated procedure well.",
            "Minimal blood loss, excellent visualization.",
            "Standard procedure, no complications noted.",
            "Patient stable throughout procedure.",
        ]
        if success_status != "successful":
            notes_options = [
                "Complications noted and managed appropriately.",
                "Extended procedure time due to anatomical challenges.",
                "Additional intervention required.",
                "Patient transferred to ICU for monitoring.",
            ]
        surgeon_notes = random.choice(notes_options)

        # Recovery score (1-100)
        if success_status == "successful":
            recovery_score = random.randint(80, 100)
        elif success_status == "complicated":
            recovery_score = random.randint(50, 85)
        else:
            recovery_score = random.randint(20, 60)

        # Follow-up required
        follow_up_required = success_status != "successful" or random.random() < 0.3

        # Timestamps
        procedure_end = datetime.strptime(procedure['end_time'], "%Y-%m-%d %H:%M:%S")
        created_at = procedure_end + timedelta(hours=random.randint(1, 24))
        updated_at = created_at

        outcome = {
            "outcome_id": outcome_id,
            "procedure_id": procedure_id,
            "success_status": success_status,
            "blood_loss_ml": blood_loss_ml,
            "complications": complications,
            "hospital_stay_days": hospital_stay_days,
            "readmission_30day": readmission_30day,
            "patient_satisfaction_score": patient_satisfaction,
            "surgeon_notes": surgeon_notes,
            "recovery_score": recovery_score,
            "follow_up_required": follow_up_required,
            "created_at": created_at.strftime("%Y-%m-%d %H:%M:%S"),
            "updated_at": updated_at.strftime("%Y-%m-%d %H:%M:%S"),
        }

        outcomes.append(outcome)

    # Write to CSV
    fieldnames = [
        "outcome_id", "procedure_id", "success_status", "blood_loss_ml",
        "complications", "hospital_stay_days", "readmission_30day",
        "patient_satisfaction_score", "surgeon_notes", "recovery_score",
        "follow_up_required", "created_at", "updated_at"
    ]

    with open(OUTCOMES_CSV, 'w', newline='') as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(outcomes)

    print(f"Generated {len(outcomes)} procedure outcomes")
    print(f"Output: {OUTCOMES_CSV}")

    return outcomes


if __name__ == "__main__":
    outcomes = generate_outcomes()

    # Print sample
    print("\nSample outcome:")
    print(outcomes[0])

    # Print statistics
    print(f"\nOutcome statistics:")
    statuses = {}
    for outcome in outcomes:
        status = outcome['success_status']
        statuses[status] = statuses.get(status, 0) + 1

    for status, count in sorted(statuses.items()):
        percentage = (count / len(outcomes)) * 100
        print(f"  {status}: {count} ({percentage:.1f}%)")
