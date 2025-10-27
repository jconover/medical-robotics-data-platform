# Phase 1: Data Model & Data Generation

## Overview

This phase establishes the foundational data model for a Medical Robotics Surgery Data Platform. It includes:

- Comprehensive data schema documentation
- Python scripts to generate realistic fake data
- Sample datasets for development and testing

## Project Structure

```
phase1-data-model/
├── data_model/
│   └── schema.md              # Complete data model documentation
├── data_generators/
│   ├── config.py              # Configuration and constants
│   ├── generate_robots.py     # Generate surgical robot data
│   ├── generate_procedures.py # Generate surgical procedure data
│   ├── generate_telemetry.py  # Generate telemetry sensor data
│   ├── generate_outcomes.py   # Generate procedure outcome data
│   ├── generate_maintenance.py # Generate maintenance log data
│   └── generate_all.py        # Master script to generate all data
├── sample_data/               # Generated CSV and JSON files
├── requirements.txt           # Python dependencies
└── README.md                  # This file
```

## Data Model

The platform tracks five main entities:

1. **surgical_robots** - Physical robotic surgical systems
2. **surgical_procedures** - Individual surgical operations performed
3. **procedure_telemetry** - High-frequency sensor data during procedures
4. **procedure_outcomes** - Post-procedure results and metrics
5. **robot_maintenance_logs** - Service and maintenance records

See `data_model/schema.md` for complete entity definitions and relationships.

## Data Distribution Strategy

### RDS (PostgreSQL)
- surgical_robots
- surgical_procedures
- procedure_outcomes
- robot_maintenance_logs

**Rationale**: Transactional data requiring ACID compliance and referential integrity.

### S3 (Data Lake)
- procedure_telemetry (JSON/Parquet format)
- Raw sensor logs
- Archived procedures

**Rationale**: High-volume time-series data requiring cost-effective storage.

### Redshift (Data Warehouse)
- Aggregated versions of all tables
- Analytics-optimized schemas
- Historical trend analysis

**Rationale**: OLAP queries and business intelligence workloads.

## Getting Started

### Prerequisites

- Python 3.8 or higher
- pip (Python package manager)

### Installation

1. Install Python dependencies:

```bash
cd phase1-data-model
pip install -r requirements.txt
```

### Generating Data

You can generate individual datasets or all data at once:

#### Generate All Data (Recommended)

```bash
cd data_generators
python generate_all.py
```

This will create all datasets in the correct order:
1. Surgical robots (50 robots)
2. Maintenance logs (200 logs)
3. Surgical procedures (5,000 procedures)
4. Procedure outcomes (5,000 outcomes)
5. Procedure telemetry (~460,000 records)

#### Generate Individual Datasets

```bash
cd data_generators

# Step 1: Generate robots first (required for other generators)
python generate_robots.py

# Step 2: Generate maintenance logs
python generate_maintenance.py

# Step 3: Generate procedures (requires robots)
python generate_procedures.py

# Step 4: Generate outcomes (requires procedures)
python generate_outcomes.py

# Step 5: Generate telemetry (requires procedures, WARNING: large file)
python generate_telemetry.py
```

### Configuration

Edit `data_generators/config.py` to customize:

- Number of robots, procedures, maintenance logs
- Date ranges for data generation
- Robot models and manufacturers
- Facility names
- Procedure types and categories
- Sample rates for telemetry data

Example:

```python
NUM_ROBOTS = 50                        # Number of robots to generate
NUM_PROCEDURES = 5000                  # Number of procedures
TELEMETRY_SAMPLES_PER_PROCEDURE = 100  # Telemetry samples per procedure
DATA_START_DATE = datetime(2023, 1, 1) # Data start date
DATA_END_DATE = datetime(2024, 12, 31) # Data end date
```

## Generated Data

After running the generators, you'll find the following files in `sample_data/`:

| File | Format | Records | Description |
|------|--------|---------|-------------|
| surgical_robots.csv | CSV | 50 | Robot inventory and metadata |
| robot_maintenance_logs.csv | CSV | 200 | Service and maintenance history |
| surgical_procedures.csv | CSV | 5,000 | Surgical procedures performed |
| procedure_outcomes.csv | CSV | 5,000 | Post-procedure results |
| procedure_telemetry.json | NDJSON | ~460,000 | High-frequency sensor data |

**Total data size**: ~50-60 MB

## Data Characteristics

### Realism Features

- **Temporal consistency**: Procedures occur during business hours, maintenance follows schedules
- **Referential integrity**: All foreign keys reference valid parent records
- **Statistical distributions**: Outcomes correlate with procedure complexity
- **Data variety**: 10 facilities, 10 robot models, 30+ procedure types
- **Edge cases**: Includes complications, equipment failures, emergency maintenance

### Sample Queries

See the generated data:

```bash
# View robots
head -n 5 sample_data/surgical_robots.csv

# Count procedures by type
cut -d',' -f3 sample_data/surgical_procedures.csv | sort | uniq -c

# View telemetry sample
head -n 3 sample_data/procedure_telemetry.json | python -m json.tool
```

## Next Steps

Once you've generated and reviewed the data:

1. **Review the data model**: Open `data_model/schema.md` to understand entity relationships
2. **Explore the sample data**: Check the files in `sample_data/` directory
3. **Proceed to Phase 2**: Set up AWS infrastructure with CloudFormation
   - VPC and networking
   - RDS PostgreSQL database
   - S3 buckets for data lake
   - Security groups and IAM roles

## Data Privacy & Compliance

**Important**: All generated data is completely fictional and synthetic. It includes:

- Randomized patient IDs (not real patients)
- Fake surgeon and technician names
- Simulated sensor readings
- No PHI (Protected Health Information)
- No PII (Personally Identifiable Information)

This data is safe for portfolio projects, demonstrations, and development purposes.

## Troubleshooting

### Import Errors

If you get import errors when running individual generators:

```bash
# Make sure you're in the data_generators directory
cd data_generators

# Run with Python module syntax
python -m generate_robots
```

### Missing Dependencies

```bash
pip install --upgrade -r requirements.txt
```

### Large Telemetry File

The telemetry JSON file can be large (~50MB). To reduce size:

1. Edit `config.py`
2. Reduce `TELEMETRY_SAMPLES_PER_PROCEDURE` (default: 100)
3. Or reduce `NUM_PROCEDURES`

## License

This project is for educational and portfolio purposes.
