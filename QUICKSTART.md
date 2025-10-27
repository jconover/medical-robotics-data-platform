# Quick Start Guide

Get up and running with Phase 1 in under 5 minutes.

## Prerequisites

- Python 3.8+ installed
- pip package manager
- Terminal/command line access

## Step-by-Step

### 1. Clone or Navigate to Project

```bash
cd /path/to/medical-robotics-data-platform
```

### 2. Install Dependencies

```bash
cd phase1-data-model
pip install -r requirements.txt
```

### 3. Generate Data

```bash
cd data_generators
python generate_all.py
```

This will create approximately 460,000+ records across 5 datasets in about 10-30 seconds.

### 4. Verify Generated Data

```bash
ls -lh sample_data/
```

You should see:
- `surgical_robots.csv` (~5 KB)
- `robot_maintenance_logs.csv` (~30 KB)
- `surgical_procedures.csv` (~500 KB)
- `procedure_outcomes.csv` (~400 KB)
- `procedure_telemetry.json` (~50 MB)

### 5. Explore the Data

**View robots:**
```bash
head -n 5 sample_data/surgical_robots.csv
```

**View a procedure:**
```bash
head -n 2 sample_data/surgical_procedures.csv | tail -n 1
```

**View telemetry sample:**
```bash
head -n 1 sample_data/procedure_telemetry.json | python -m json.tool
```

**Count procedures by category:**
```bash
tail -n +2 sample_data/surgical_procedures.csv | cut -d',' -f4 | sort | uniq -c
```

## What You've Created

You now have a complete dataset representing:
- 50 surgical robots across 10 hospitals
- 5,000 surgical procedures spanning 2 years
- Real-time telemetry data from procedures
- Procedure outcomes and complications
- Maintenance history for robots

## Next Steps

1. **Review the data model**: `phase1-data-model/data_model/schema.md`
2. **Customize data generation**: Edit `data_generators/config.py`
3. **Prepare for Phase 2**: AWS infrastructure setup

## Customize Data Volume

Edit `phase1-data-model/data_generators/config.py`:

```python
NUM_ROBOTS = 100               # Increase robots
NUM_PROCEDURES = 10000         # More procedures
TELEMETRY_SAMPLES_PER_PROCEDURE = 50  # Reduce for smaller files
```

Then regenerate:
```bash
python generate_all.py
```

## Troubleshooting

**ModuleNotFoundError:**
```bash
pip install -r ../requirements.txt
```

**Permission denied:**
```bash
chmod +x generate_all.py
```

**Out of memory (telemetry generation):**
Reduce `TELEMETRY_SAMPLES_PER_PROCEDURE` in `config.py` to 50 or 25.

## Help

See the main [README.md](./README.md) for detailed documentation.
