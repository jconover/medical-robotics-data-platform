#!/bin/bash
# Setup Database Schema on RDS
# This script is automatically deployed to the bastion host at /home/ec2-user/setup-schema.sh
# Usage: ./setup-schema.sh <path-to-sql-file>

# Get RDS endpoint from CloudFormation
RDS_ENDPOINT=$(aws cloudformation describe-stacks \
  --stack-name medrobotics-rds \
  --region us-east-1 \
  --query 'Stacks[0].Outputs[?OutputKey==`DBEndpoint`].OutputValue' \
  --output text)

echo "RDS Endpoint: $RDS_ENDPOINT"
echo "Setting up database schema..."

# Check if schema file is provided
if [ -z "$1" ]; then
  echo ""
  echo "Usage: ./setup-schema.sh <path-to-sql-file>"
  echo ""
  echo "Examples:"
  echo "  ./setup-schema.sh /tmp/01-create-tables.sql"
  echo "  ./setup-schema.sh /tmp/02-load-sample-data.sql"
  echo ""
  exit 1
fi

if [ ! -f "$1" ]; then
  echo "Error: File '$1' not found!"
  exit 1
fi

echo "Running SQL file: $1"
echo ""

# Run the SQL file
psql -h $RDS_ENDPOINT -U dbadmin -d medrobotics -f "$1"

echo ""
echo "Schema setup complete!"
