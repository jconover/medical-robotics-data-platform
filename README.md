# Medical Robotics Surgery Data Platform

A comprehensive DevOps portfolio project demonstrating AWS infrastructure, data engineering, and modern cloud practices using a realistic medical robotics scenario.

## Project Overview

This project simulates a **medical robotics data platform** that collects, stores, and analyzes data from surgical robots performing minimally invasive procedures. It showcases:

- Infrastructure as Code (CloudFormation)
- Container orchestration (ECS & EKS)
- Data engineering pipelines
- Cloud-native AWS services
- DevOps best practices
- Data warehousing and analytics

## Architecture

The platform ingests data from surgical robots and processes it through multiple AWS services:

```
Surgical Robots (Simulated)
    ↓
[Data Ingestion Service - ECS/EKS]
    ↓
[RDS PostgreSQL] ← Transactional data
[S3 Data Lake]   ← High-volume telemetry
    ↓
[ETL Pipeline]
    ↓
[Redshift Data Warehouse] ← Analytics
```

## Technologies Used

### AWS Services
- **VPC**: Network isolation and security
- **RDS (PostgreSQL)**: Operational database for procedures, robots, outcomes
- **S3**: Data lake for high-volume telemetry and raw data
- **Redshift**: Data warehouse for analytics and business intelligence
- **ECS**: Container orchestration for data services
- **EKS**: Kubernetes orchestration (alternative deployment)
- **CloudFormation**: Infrastructure as Code
- **IAM**: Security and access management
- **CloudWatch**: Monitoring and logging

### Development Tools
- Python (data generation, ETL)
- Docker (containerization)
- Kubernetes (orchestration)
- Git (version control)

## Project Phases

### ✅ Phase 1: Data Model & Generation
**Status**: Complete

- Comprehensive data model design
- Python data generators for realistic fake data
- 5 entity types: robots, procedures, telemetry, outcomes, maintenance
- ~460,000 telemetry records, 5,000 procedures, 50 robots

[📁 View Phase 1](./phase1-data-model/)

### ✅ Phase 2: Core Infrastructure (CloudFormation)
**Status**: Complete

- VPC with public, private, and data subnets across 2 AZs
- Security groups for ALB, ECS, RDS, Redshift, and bastion
- S3 data lake (raw, processed, analytics, logs, backups)
- IAM roles for ECS, Lambda, Redshift, and data pipelines
- RDS PostgreSQL database with automated backups
- SQL schemas and deployment automation scripts

[📁 View Phase 2](./phase2-infrastructure/)

### ✅ Phase 3: Container Infrastructure (ECS)
**Status**: Complete

- ECS Fargate cluster with Container Insights
- Data ingestion service (Flask + Docker)
- API service for querying data (Flask + Docker)
- Application Load Balancer with path-based routing
- Auto-scaling based on CPU utilization
- CloudWatch logs and monitoring dashboard
- Build and deployment automation scripts

[📁 View Phase 3](./phase3-ecs/)

### 🚧 Phase 4: Data Warehouse (Redshift)
**Status**: Planned

- Redshift cluster setup
- ETL pipeline (RDS/S3 → Redshift)
- Analytics schemas and tables
- Sample queries and reports
- Performance optimization

### 🚧 Phase 5: Kubernetes Migration (EKS)
**Status**: Planned

- EKS cluster setup
- Migrate services from ECS to EKS
- Helm charts for deployment
- Kubernetes monitoring and scaling
- Compare ECS vs EKS approaches

### 🚧 Phase 6: Advanced Features
**Status**: Planned

- CI/CD pipeline (CodePipeline or GitHub Actions)
- Infrastructure testing
- Cost optimization strategies
- Grafana dashboards
- Complete documentation and architecture diagrams

## Data Model

The platform tracks surgical robot operations with five core entities:

1. **surgical_robots**: Robot inventory (model, manufacturer, facility, status)
2. **surgical_procedures**: Individual surgeries (type, duration, surgeon, patient)
3. **procedure_telemetry**: Real-time sensor data (arm position, force feedback, camera)
4. **procedure_outcomes**: Post-op results (success, complications, recovery)
5. **robot_maintenance_logs**: Service records (maintenance type, downtime, cost)

See [Phase 1 Data Model](./phase1-data-model/data_model/schema.md) for complete details.

## Getting Started

### Phase 1: Generate Sample Data

```bash
cd phase1-data-model

# Install dependencies
pip install -r requirements.txt

# Generate all data
cd data_generators
python generate_all.py

# Review generated data
ls -lh sample_data/
```

This creates ~50-60 MB of realistic medical robotics data.

### Future Phases

Additional setup instructions will be added as each phase is completed.

## Sample Data Statistics

Generated data includes:
- **50 surgical robots** across 10 hospital facilities
- **5,000 surgical procedures** over 2 years (2023-2024)
- **460,000 telemetry records** (100 samples per procedure)
- **5,000 procedure outcomes** with complications and recovery metrics
- **200 maintenance logs** with service history

## Use Cases Demonstrated

This project demonstrates real-world DevOps scenarios:

1. **Multi-tier data storage**: Choosing appropriate storage (RDS, S3, Redshift) based on data characteristics
2. **Infrastructure as Code**: Reproducible, version-controlled infrastructure
3. **Container orchestration**: Comparing ECS and EKS for different use cases
4. **Data pipeline engineering**: ETL processes for analytics
5. **Security best practices**: VPC design, IAM policies, encryption
6. **Cost optimization**: Appropriate service sizing and resource management
7. **Monitoring and observability**: CloudWatch, logging, alerting

## Why Medical Robotics?

Medical robotics provides a compelling use case because:

- **Realistic complexity**: Requires multiple data types and storage strategies
- **High data volume**: Telemetry data demonstrates handling large datasets
- **Compliance considerations**: Shows understanding of sensitive data handling
- **Business value**: Analytics drive procedure improvements and robot maintenance
- **Interesting domain**: Makes portfolio projects more engaging

**Note**: All data is completely synthetic and fictional. No real patient information is used.

## Project Goals

- Demonstrate comprehensive AWS knowledge
- Show DevOps best practices and automation
- Display data engineering skills
- Create production-quality infrastructure code
- Build a portfolio piece that stands out

## Future Enhancements

Potential additions:
- Real-time streaming with Kinesis
- Machine learning for predictive maintenance
- Lambda functions for serverless processing
- API Gateway for external access
- DynamoDB for session management
- SNS/SQS for event-driven architecture

## Contributing

This is a personal portfolio project, but suggestions and feedback are welcome via issues.

## License

This project is for educational and portfolio demonstration purposes.

## Contact

**Justin** - Portfolio Project: justinconover.io

---

**Current Status**: Phase 3 Complete ✅
**Last Updated**: 2025-10-27
