"""
Configuration file for data generation.
Adjust these parameters to control the volume and characteristics of generated data.
"""

from datetime import datetime, timedelta

# Data volume configuration
NUM_ROBOTS = 50
NUM_FACILITIES = 10
NUM_PROCEDURES = 5000
TELEMETRY_SAMPLES_PER_PROCEDURE = 100  # High-frequency samples during surgery
NUM_MAINTENANCE_LOGS = 200

# Date ranges
DATA_START_DATE = datetime(2023, 1, 1)
DATA_END_DATE = datetime(2024, 12, 31)

# Robot models and manufacturers
ROBOT_MODELS = [
    ("DaVinci Xi", "Intuitive Surgical"),
    ("DaVinci X", "Intuitive Surgical"),
    ("DaVinci Si", "Intuitive Surgical"),
    ("Versius", "CMR Surgical"),
    ("ROSA Knee", "Zimmer Biomet"),
    ("ROSA Brain", "Zimmer Biomet"),
    ("Mako SmartRobotics", "Stryker"),
    ("Senhance", "Asensus Surgical"),
    ("Hugo RAS", "Medtronic"),
    ("Monarch Platform", "Auris Health"),
]

# Facility names (realistic hospital names)
FACILITY_NAMES = [
    "Johns Hopkins Hospital",
    "Mayo Clinic",
    "Massachusetts General Hospital",
    "Cleveland Clinic",
    "UCSF Medical Center",
    "NewYork-Presbyterian Hospital",
    "Cedars-Sinai Medical Center",
    "Stanford Health Care",
    "UCLA Medical Center",
    "Northwestern Memorial Hospital",
]

# Surgical procedure types by category
PROCEDURE_TYPES = {
    "urological": [
        "Radical Prostatectomy",
        "Partial Nephrectomy",
        "Radical Nephrectomy",
        "Pyeloplasty",
        "Radical Cystectomy",
    ],
    "gynecological": [
        "Hysterectomy",
        "Myomectomy",
        "Sacrocolpopexy",
        "Ovarian Cystectomy",
        "Endometriosis Resection",
    ],
    "cardiac": [
        "Mitral Valve Repair",
        "Coronary Artery Bypass",
        "Atrial Septal Defect Repair",
        "CABG",
    ],
    "thoracic": [
        "Lobectomy",
        "Thymectomy",
        "Esophagectomy",
        "Mediastinal Mass Resection",
    ],
    "general": [
        "Cholecystectomy",
        "Hernia Repair",
        "Colorectal Resection",
        "Gastric Bypass",
        "Fundoplication",
    ],
    "orthopedic": [
        "Total Knee Replacement",
        "Total Hip Replacement",
        "Spinal Fusion",
        "ACL Reconstruction",
    ],
}

# Surgical tools
SURGICAL_TOOLS = [
    "Grasper",
    "Scissors",
    "Cautery Hook",
    "Needle Driver",
    "Forceps",
    "Retractor",
    "Scalpel",
    "Clip Applier",
]

# Surgeon names (fake but realistic)
SURGEON_FIRST_NAMES = [
    "James", "Michael", "Robert", "John", "David", "William", "Richard", "Joseph",
    "Mary", "Patricia", "Jennifer", "Linda", "Elizabeth", "Barbara", "Susan", "Jessica",
]

SURGEON_LAST_NAMES = [
    "Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis",
    "Rodriguez", "Martinez", "Hernandez", "Lopez", "Gonzalez", "Wilson", "Anderson", "Thomas",
]

# Maintenance types
MAINTENANCE_TYPES = ["routine", "emergency", "upgrade", "calibration"]

# Technician names
TECHNICIAN_FIRST_NAMES = ["John", "Mike", "Steve", "Tom", "Dave", "Sarah", "Emily", "Lisa"]
TECHNICIAN_LAST_NAMES = ["Anderson", "Thompson", "Garcia", "Martinez", "Robinson", "Clark", "Lewis", "Walker"]

# Complications (for procedure outcomes)
COMPLICATIONS = [
    "none",
    "minor bleeding",
    "infection",
    "prolonged recovery",
    "organ injury",
    "adhesions",
    "nerve damage",
    "urinary retention",
    "ileus",
]

# File output paths
OUTPUT_DIR = "sample_data"
ROBOTS_CSV = f"{OUTPUT_DIR}/surgical_robots.csv"
PROCEDURES_CSV = f"{OUTPUT_DIR}/surgical_procedures.csv"
TELEMETRY_JSON = f"{OUTPUT_DIR}/procedure_telemetry.json"
OUTCOMES_CSV = f"{OUTPUT_DIR}/procedure_outcomes.csv"
MAINTENANCE_CSV = f"{OUTPUT_DIR}/robot_maintenance_logs.csv"
