## Deploy a Bastion Host

A bastion host is a jump server in your VPC that allows secure access to private resources.

**Features:**
- PostgreSQL 17 client (matches your RDS version)
- AWS Systems Manager Session Manager (no SSH keys needed)
- Pre-configured helper scripts for database access
- Elastic IP for consistent addressing

---

## Prerequisites

### Install AWS Systems Manager Session Manager Plugin

The Session Manager plugin is required to connect to the bastion host via SSM.

#### Ubuntu / Debian Linux
```bash
# Download the .deb package
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o "session-manager-plugin.deb"

# Install the package
sudo dpkg -i session-manager-plugin.deb

# Verify installation
session-manager-plugin --version
```

#### Amazon Linux / RHEL / CentOS / Fedora
```bash
# Download the .rpm package
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm" -o "session-manager-plugin.rpm"

# Install the package
sudo yum install -y session-manager-plugin.rpm

# Verify installation
session-manager-plugin --version
```

#### macOS
```bash
# Option 1: Using Homebrew (recommended)
brew install --cask session-manager-plugin

# Option 2: Manual installation
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac/sessionmanager-bundle.zip" -o "sessionmanager-bundle.zip"
unzip sessionmanager-bundle.zip
sudo ./sessionmanager-bundle/install -i /usr/local/sessionmanagerplugin -b /usr/local/bin/session-manager-plugin

# Verify installation
session-manager-plugin --version
```

#### Windows
**Option 1: Using PowerShell (Administrator)**
```powershell
# Download the installer
Invoke-WebRequest -Uri "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/windows/SessionManagerPluginSetup.exe" -OutFile "$env:TEMP\SessionManagerPluginSetup.exe"

# Run the installer
Start-Process -FilePath "$env:TEMP\SessionManagerPluginSetup.exe" -Wait

# Verify installation (open new PowerShell window)
session-manager-plugin
```

**Option 2: Manual Download**
1. Download: https://s3.amazonaws.com/session-manager-downloads/plugin/latest/windows/SessionManagerPluginSetup.exe
2. Run the installer
3. Restart your terminal/PowerShell

#### Verify Installation
After installation, verify the plugin is working:
```bash
session-manager-plugin

# Expected output:
# The Session Manager plugin was installed successfully. Use the AWS CLI to start a session.
```

**Troubleshooting:**
- If command not found, close and reopen your terminal
- Make sure AWS CLI v2 is installed: `aws --version`
- Ensure your PATH includes the installation directory

---

## Quick Deploy (5 minutes)

### Step 1: Deploy Bastion Host

```bash
cd phase2-infrastructure/cloudformation

# Deploy without SSH key (uses AWS Systems Manager only - RECOMMENDED)
aws cloudformation create-stack \
  --stack-name medrobotics-bastion \
  --template-body file://06-bastion-host.yaml \
  --parameters ParameterKey=EnvironmentName,ParameterValue=medrobotics \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1

# Wait for completion (~3 minutes)
aws cloudformation wait stack-create-complete \
  --stack-name medrobotics-bastion \
  --region us-east-1
```

### Step 2: Connect to Bastion

Get the instance ID:
```bash
BASTION_ID=$(aws cloudformation describe-stacks \
  --stack-name medrobotics-bastion \
  --query 'Stacks[0].Outputs[?OutputKey==`BastionInstanceId`].OutputValue' \
  --output text)

echo $BASTION_ID
```

Connect using AWS Systems Manager (no SSH key needed):
```bash
aws ssm start-session --target $BASTION_ID --region us-east-1
```

### Step 3: Connect to RDS from Bastion

Once inside the bastion host, you'll find pre-installed helper scripts in `/home/ec2-user/`:

**Option A: Use the helper script** (Recommended)
```bash
# Interactive connection (helper script auto-created on bastion)
./connect-to-rds.sh
```

**Option B: Manual connection**
```bash
# Get RDS endpoint
RDS_ENDPOINT=$(aws cloudformation describe-stacks \
  --stack-name medrobotics-rds \
  --region us-east-1 \
  --query 'Stacks[0].Outputs[?OutputKey==`DBEndpoint`].OutputValue' \
  --output text)

# Connect
psql -h $RDS_ENDPOINT -U dbadmin -d medrobotics
```

Enter your database password when prompted.

**Note:** The helper scripts (`connect-to-rds.sh` and `setup-schema.sh`) are automatically created on the bastion host during deployment. Reference copies are in `scripts/bastion-helpers/` for your review.

---

## Setting Up Database Schema

### Method 1: Upload SQL File to Bastion

From your **local machine**:
```bash
# Get bastion instance ID
BASTION_ID=$(aws cloudformation describe-stacks \
  --stack-name medrobotics-bastion \
  --query 'Stacks[0].Outputs[?OutputKey==`BastionInstanceId`].OutputValue' \
  --output text)

# Upload SQL schema file
aws s3 cp ../sql-schemas/01-create-tables.sql s3://medrobotics-logs-$(aws sts get-caller-identity --query Account --output text)/temp/

# Or upload directly via SSM Session Manager (see Method 2)
```

From **bastion host**:
```bash
# Download from S3
aws s3 cp s3://medrobotics-logs-$(aws sts get-caller-identity --query Account --output text)/temp/01-create-tables.sql /tmp/

# Get RDS endpoint
RDS_ENDPOINT=$(aws cloudformation describe-stacks \
  --stack-name medrobotics-rds \
  --region us-east-1 \
  --query 'Stacks[0].Outputs[?OutputKey==`DBEndpoint`].OutputValue' \
  --output text)

# Run schema setup
psql -h $RDS_ENDPOINT -U dbadmin -d medrobotics -f /tmp/01-create-tables.sql
```

### Method 2: Copy-Paste SQL Commands

1. Connect to bastion: `aws ssm start-session --target $BASTION_ID`
2. Start psql: `./connect-to-rds.sh`
3. Copy-paste SQL commands from your local `01-create-tables.sql` file
4. Or use `\i` command after uploading file

### Method 3: Use SSM Port Forwarding (Advanced)

Forward PostgreSQL port through SSM tunnel to your local machine:

```bash
# Forward RDS port 5432 to local port 5433
aws ssm start-session \
  --target $BASTION_ID \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"$RDS_ENDPOINT\"],\"portNumber\":[\"5432\"],\"localPortNumber\":[\"5433\"]}"
```

Then from **another terminal** on your local machine:
```bash
# Connect through the tunnel
psql -h localhost -p 5433 -U dbadmin -d medrobotics -f ../sql-schemas/01-create-tables.sql
```

---

## Verification

Once schema is created, verify tables:

```sql
-- List all tables
\dt

-- Check specific tables
SELECT * FROM surgical_robots LIMIT 5;
SELECT * FROM procedures LIMIT 5;
```

---

## Cost Considerations

**Bastion Host Cost:**
- t3.micro: ~$7.50/month (~$0.01/hour)
- Elastic IP: Free while attached, $0.005/hour if not attached

**To save costs:**
```bash
# Stop bastion when not in use
aws ec2 stop-instances --instance-ids $BASTION_ID

# Start when needed
aws ec2 start-instances --instance-ids $BASTION_ID

# Delete entirely if done
aws cloudformation delete-stack --stack-name medrobotics-bastion
```

---

## Security Best Practices

1. **Use SSM Session Manager** (no SSH keys or open ports)
2. **Limit SSH access** if using SSH key - edit security group to your IP only
3. **Delete bastion** when not actively using it
4. **Never commit database passwords** to git
5. **Rotate credentials** regularly via Secrets Manager

---

## Troubleshooting

### SSM Session Manager not working

**Problem:** `An error occurred (TargetNotConnected)`

**Solution:**
```bash
# Check SSM agent status
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$BASTION_ID" \
  --query "InstanceInformationList[*].[InstanceId,PingStatus]" \
  --output table

# Wait 2-3 minutes after instance launch for SSM agent to register
```

### Cannot resolve RDS hostname from bastion

**Problem:** DNS resolution fails

**Solution:**
```bash
# Check VPC DNS settings
aws ec2 describe-vpcs \
  --vpc-ids $(aws ec2 describe-instances --instance-ids $BASTION_ID --query 'Reservations[0].Instances[0].VpcId' --output text) \
  --query 'Vpcs[0].{DNS:EnableDnsSupport,Hostnames:EnableDnsHostnames}'

# Both should be true
```

### Database connection refused

**Problem:** `Connection refused` or `timeout`

**Solution:**
```bash
# Check security group allows bastion -> RDS
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=medrobotics-rds-sg" \
  --query 'SecurityGroups[0].IpPermissions'

# Should show bastion security group as source for port 5432
```

---

## Alternative: Temporary Public Access (NOT RECOMMENDED)

If you need quick access for testing only:

1. Temporarily modify RDS security group to allow your IP
2. Set `PubliclyAccessible: true` on RDS instance
3. Connect directly from local machine
4. **IMMEDIATELY revert changes after testing**

This is **strongly discouraged** for production or sensitive data.

---

## Next Steps

After setting up the schema:

1. Load sample data: `psql -h $RDS_ENDPOINT -U dbadmin -d medrobotics -f /tmp/02-load-sample-data.sql`
2. Verify data: `SELECT COUNT(*) FROM procedures;`
3. Continue to Phase 3 (ECS deployment)
4. Stop or delete bastion if not needed

---

## Reference

- [AWS Systems Manager Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [RDS Best Practices](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_BestPractices.html)
- [Bastion Host Architecture](https://aws.amazon.com/solutions/implementations/linux-bastion/)
