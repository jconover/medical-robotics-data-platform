## Phase 3: Container Infrastructure (ECS)

## Overview

Phase 3 deploys containerized microservices on AWS ECS (Elastic Container Service) using Fargate. Two services are deployed: a data ingestion service and an API service for querying surgical robotics data.

## Architecture

```
Internet → ALB → ECS Services (Private Subnets) → RDS/S3
                   ↓
            - Data Ingestion (Port 8080)
            - API Service (Port 5000)
```

## Components

### 1. ECS Cluster (`01-ecs-cluster.yaml`)
- Fargate and Fargate Spot capacity providers
- Container Insights enabled
- CloudWatch log groups for each service

### 2. Application Load Balancer (`02-alb.yaml`)
- Internet-facing ALB in public subnets
- Path-based routing:
  - `/api/*` → API Service
  - `/ingest/*` → Data Ingestion
- Health checks on `/health` endpoints

### 3. Microservices

#### Data Ingestion Service
- **Purpose**: Receives telemetry data and stores in S3/RDS
- **Port**: 8080
- **Endpoints**:
  - `POST /ingest/telemetry` - Ingest robot telemetry
  - `POST /ingest/procedure` - Ingest procedure data
  - `POST /ingest/batch` - Batch ingestion
  - `GET /ingest/stats` - Ingestion statistics
  - `GET /health` - Health check

#### API Service
- **Purpose**: Query surgical robotics data
- **Port**: 5000
- **Endpoints**:
  - `GET /api/robots` - List all robots
  - `GET /api/robots/{id}` - Get robot details
  - `GET /api/procedures` - List procedures
  - `GET /api/procedures/{id}` - Get procedure details
  - `GET /api/outcomes` - List outcomes
  - `GET /api/analytics/*` - Analytics endpoints
  - `GET /health` - Health check

### 4. Auto Scaling
- CPU-based auto scaling (target: 70%)
- Data Ingestion: 1-5 tasks
- API Service: 1-10 tasks

## Project Structure

```
phase3-ecs/
├── cloudformation/
│   ├── 01-ecs-cluster.yaml            # ECS cluster
│   ├── 02-alb.yaml                    # Application Load Balancer
│   ├── 03-ecs-task-definitions.yaml   # Task definitions
│   └── 04-ecs-services.yaml           # ECS services
├── services/
│   ├── data-ingestion/
│   │   ├── app.py                     # Flask application
│   │   ├── Dockerfile                 # Docker image
│   │   └── requirements.txt           # Python dependencies
│   └── api-service/
│       ├── app.py                     # Flask application
│       ├── Dockerfile                 # Docker image
│       └── requirements.txt           # Python dependencies
├── scripts/
│   ├── build-and-push.sh              # Build & push images to ECR
│   └── deploy-ecs.sh                  # Deploy ECS infrastructure
└── README.md                          # This file
```

## Prerequisites

- Phase 2 infrastructure deployed
- Docker installed locally
- AWS CLI configured
- RDS database password

## Deployment

### Step 1: Build and Push Docker Images

```bash
cd phase3-ecs/scripts

export ENVIRONMENT_NAME="medrobotics"
export AWS_REGION="us-east-1"

# Build and push images to ECR
./build-and-push.sh
```

This creates ECR repositories and pushes:
- `medrobotics-data-ingestion:latest`
- `medrobotics-api-service:latest`

### Step 2: Deploy ECS Infrastructure

```bash
export RDS_PASSWORD="YourSecurePassword123"

# Deploy ECS cluster, ALB, and services
./deploy-ecs.sh
```

Deployment order:
1. ECS Cluster with CloudWatch logs
2. Application Load Balancer
3. ECS Task Definitions
4. ECS Services with auto scaling

### Step 3: Verify Deployment

```bash
# Get ALB URL
ALB_URL=$(aws cloudformation describe-stacks \
  --stack-name medrobotics-alb \
  --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerURL`].OutputValue' \
  --output text)

# Test health endpoints
curl $ALB_URL/api/health
curl $ALB_URL/ingest/health

# Query robots (requires data in RDS)
curl $ALB_URL/api/robots
```

## Testing the Services

### Test Data Ingestion

```bash
# Ingest telemetry data
curl -X POST $ALB_URL/ingest/telemetry \
  -H "Content-Type: application/json" \
  -d '{
    "procedure_id": "test-123",
    "robot_id": "robot-1",
    "timestamp": "2025-10-27T10:00:00",
    "arm_position_x": 100.5,
    "arm_position_y": 200.3,
    "arm_position_z": 150.2
  }'

# Check ingestion stats
curl $ALB_URL/ingest/stats
```

### Test API Service

```bash
# Get all robots
curl $ALB_URL/api/robots

# Get procedures (with filters)
curl "$ALB_URL/api/procedures?category=urological&limit=10"

# Get analytics
curl $ALB_URL/api/analytics/robot-utilization
curl $ALB_URL/api/analytics/outcomes-summary
```

## Monitoring

### View Logs

```bash
# Data Ingestion logs
aws logs tail /aws/ecs/medrobotics/data-ingestion --follow

# API Service logs
aws logs tail /aws/ecs/medrobotics/api-service --follow
```

### Check Service Status

```bash
# List running tasks
aws ecs list-tasks \
  --cluster medrobotics-cluster \
  --service-name medrobotics-api-service

# Describe service
aws ecs describe-services \
  --cluster medrobotics-cluster \
  --services medrobotics-api-service
```

### CloudWatch Dashboard

Navigate to CloudWatch in AWS Console:
- Dashboard: `medrobotics-ecs-monitoring`
- Metrics: CPU, Memory, Task Count

## Updating Services

### Rebuild and Redeploy

```bash
# Make changes to app.py
cd services/data-ingestion
# Edit app.py

# Rebuild and push
cd ../../scripts
./build-and-push.sh

# Force new deployment
aws ecs update-service \
  --cluster medrobotics-cluster \
  --service medrobotics-data-ingestion \
  --force-new-deployment
```

## Cost Estimation

**Monthly costs (us-east-1)**:

| Service | Configuration | Monthly Cost |
|---------|--------------|--------------|
| Fargate (2 tasks) | 0.5 vCPU, 1GB each | ~$30 |
| ALB | Standard | ~$20 |
| Data Transfer | Minimal | ~$5 |
| CloudWatch Logs | 1 GB | ~$1 |
| **Total** | | **~$56/month** |

**Combined with Phase 2**: ~$137/month

## Troubleshooting

### Services Not Starting

```bash
# Check task failures
aws ecs describe-tasks \
  --cluster medrobotics-cluster \
  --tasks $(aws ecs list-tasks --cluster medrobotics-cluster --query 'taskArns[0]' --output text)

# View stopped tasks
aws ecs list-tasks --cluster medrobotics-cluster --desired-status STOPPED
```

### Health Check Failures

- Verify security groups allow ALB → ECS traffic
- Check container logs for errors
- Ensure RDS password is correct
- Verify database connectivity from ECS tasks

### Can't Access ALB

- Check ALB is in public subnets
- Verify security group allows inbound port 80
- DNS propagation may take a few minutes

## Cleanup

```bash
# Delete ECS services (stops all tasks)
aws cloudformation delete-stack --stack-name medrobotics-ecs-services

# Delete task definitions
aws cloudformation delete-stack --stack-name medrobotics-ecs-tasks

# Delete ALB
aws cloudformation delete-stack --stack-name medrobotics-alb

# Delete ECS cluster
aws cloudformation delete-stack --stack-name medrobotics-ecs-cluster

# Delete ECR images
aws ecr delete-repository --repository-name medrobotics-data-ingestion --force
aws ecr delete-repository --repository-name medrobotics-api-service --force
```

## Next Steps

After completing Phase 3:

1. **Phase 4**: Deploy Redshift data warehouse
2. **Phase 5**: Migrate to EKS (Kubernetes)
3. **Phase 6**: Add CI/CD pipeline

## Additional Resources

- [ECS Documentation](https://docs.aws.amazon.com/ecs/)
- [Fargate Pricing](https://aws.amazon.com/fargate/pricing/)
- [Flask Documentation](https://flask.palletsprojects.com/)

## License

This project is for educational and portfolio purposes.
