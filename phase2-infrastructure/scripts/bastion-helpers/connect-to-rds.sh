#!/bin/bash
# Connect to RDS PostgreSQL Database
# This script is automatically deployed to the bastion host at /home/ec2-user/connect-to-rds.sh
# You can also run these commands manually

# Get RDS endpoint from CloudFormation
RDS_ENDPOINT=$(aws cloudformation describe-stacks \
  --stack-name medrobotics-rds \
  --region us-east-1 \
  --query 'Stacks[0].Outputs[?OutputKey==`DBEndpoint`].OutputValue' \
  --output text)

echo "RDS Endpoint: $RDS_ENDPOINT"
echo "Connecting to PostgreSQL..."
echo "Default credentials: Username=dbadmin, Database=medrobotics"
echo ""

# Connect to PostgreSQL
psql -h $RDS_ENDPOINT -U dbadmin -d medrobotics
