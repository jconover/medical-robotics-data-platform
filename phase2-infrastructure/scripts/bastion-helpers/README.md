# Bastion Helper Scripts

These scripts are **automatically created** on the bastion host when it's deployed via CloudFormation. They're located in `/home/ec2-user/` on the bastion instance.

These copies are for reference only and show what commands will be available on the bastion.

## Scripts Available on Bastion Host

### 1. `connect-to-rds.sh`
Interactive PostgreSQL connection to RDS.

**Usage on bastion:**
```bash
./connect-to-rds.sh
# You'll be prompted for the database password
```

### 2. `setup-schema.sh`
Run a SQL file against the RDS database.

**Usage on bastion:**
```bash
./setup-schema.sh /tmp/01-create-tables.sql
./setup-schema.sh /tmp/02-load-sample-data.sql
```

## How to Use These Scripts

### Step 1: Deploy Bastion Host
```bash
cd ../../
./scripts/deploy-bastion.sh
```

### Step 2: Connect to Bastion
```bash
BASTION_ID=$(aws cloudformation describe-stacks \
  --stack-name medrobotics-bastion \
  --query 'Stacks[0].Outputs[?OutputKey==`BastionInstanceId`].OutputValue' \
  --output text)

aws ssm start-session --target $BASTION_ID --region us-east-1
```

### Step 3: Use the Helper Scripts
Once connected to the bastion:
```bash
# List available scripts
ls -la *.sh

# Expected output:
# -rwxr-xr-x 1 ec2-user ec2-user  XXX connect-to-rds.sh
# -rwxr-xr-x 1 ec2-user ec2-user  XXX setup-schema.sh

# Interactive connection
./connect-to-rds.sh

# Or run a SQL file
./setup-schema.sh /tmp/01-create-tables.sql
```

## Manual Commands (Without Helper Scripts)

If you prefer to run commands manually:

```bash
# Get RDS endpoint
RDS_ENDPOINT=$(aws cloudformation describe-stacks \
  --stack-name medrobotics-rds \
  --region us-east-1 \
  --query 'Stacks[0].Outputs[?OutputKey==`DBEndpoint`].OutputValue' \
  --output text)

# Interactive connection
psql -h $RDS_ENDPOINT -U dbadmin -d medrobotics

# Run SQL file
psql -h $RDS_ENDPOINT -U dbadmin -d medrobotics -f /tmp/01-create-tables.sql

# Single query
psql -h $RDS_ENDPOINT -U dbadmin -d medrobotics -c "SELECT version();"

# List tables
psql -h $RDS_ENDPOINT -U dbadmin -d medrobotics -c "\dt"
```

## Uploading SQL Files to Bastion

### Method 1: Via S3 (Recommended)
```bash
# From your local machine
aws s3 cp ../../sql-schemas/01-create-tables.sql s3://YOUR-BUCKET/temp/

# From bastion
aws s3 cp s3://YOUR-BUCKET/temp/01-create-tables.sql /tmp/
./setup-schema.sh /tmp/01-create-tables.sql
```

### Method 2: Copy-Paste
```bash
# From bastion
cat > /tmp/01-create-tables.sql << 'EOF'
# Paste your SQL content here
EOF

./setup-schema.sh /tmp/01-create-tables.sql
```

### Method 3: Port Forwarding (Advanced)
Run from your local machine to tunnel through bastion:

```bash
# Forward PostgreSQL port
aws ssm start-session \
  --target $BASTION_ID \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"$RDS_ENDPOINT\"],\"portNumber\":[\"5432\"],\"localPortNumber\":[\"5433\"]}"

# In another terminal on your local machine
psql -h localhost -p 5433 -U dbadmin -d medrobotics -f sql-schemas/01-create-tables.sql

psql -h localhost -p 5433 -U dbadmin -d medrobotics -f sql-schemas/02-load-sample-data.sql

```

## Troubleshooting

### "command not found: ./connect-to-rds.sh"
The bastion may still be initializing. Wait 2-3 minutes after deployment, then reconnect.

### "aws: command not found"
The UserData script is still running. Check status:
```bash
sudo tail -f /var/log/cloud-init-output.log
```

### "psql: command not found"
PostgreSQL client installation is in progress. Wait for UserData to complete.

### Connection refused
Check security groups:
```bash
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=medrobotics-rds-sg" \
  --query 'SecurityGroups[0].IpPermissions'
```

Should show the bastion security group as a source for port 5432.
