# Phase 5: Kubernetes (EKS) Migration

## Overview

Phase 5 migrates the containerized microservices from ECS (Phase 3) to Amazon EKS (Elastic Kubernetes Service), providing enterprise-grade container orchestration with advanced features like horizontal pod autoscaling, rolling updates, service mesh readiness, and comprehensive monitoring.

## Why EKS over ECS?

| Feature | ECS | EKS |
|---------|-----|-----|
| **Portability** | AWS-specific | Kubernetes standard (run anywhere) |
| **Ecosystem** | Limited | Vast (Helm, Operators, CNCF tools) |
| **Auto-scaling** | Basic | Advanced (HPA, VPA, Cluster Autoscaler) |
| **Service Mesh** | AWS App Mesh only | Istio, Linkerd, Consul |
| **Monitoring** | CloudWatch | Prometheus, Grafana, + CloudWatch |
| **GitOps** | Manual | ArgoCD, Flux |
| **Multi-cloud** | No | Yes |

## Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                          Internet                               │
└────────────────────────┬───────────────────────────────────────┘
                         │
                         ▼
┌────────────────────────────────────────────────────────────────┐
│              AWS Application Load Balancer (ALB)                │
│              (Managed by AWS Load Balancer Controller)          │
│                                                                 │
│   Routing:                                                      │
│   • /api/*     → api-service:5000                              │
│   • /ingest/*  → data-ingestion:8080                           │
└────────────────────────┬───────────────────────────────────────┘
                         │
                         ▼
┌────────────────────────────────────────────────────────────────┐
│                      Kubernetes Ingress                         │
│                   (ingress-nginx / ALB Ingress)                 │
└──────────┬─────────────────────────┬───────────────────────────┘
           │                         │
           ▼                         ▼
┌─────────────────────┐    ┌─────────────────────────┐
│  API Service        │    │  Data Ingestion Service │
│  (ClusterIP)        │    │  (ClusterIP)            │
│  Port: 5000         │    │  Port: 8080             │
└──────┬──────────────┘    └──────┬──────────────────┘
       │                          │
       ▼                          ▼
┌────────────────────────────────────────────────────────────────┐
│                      EKS Worker Nodes                           │
│                    (Auto Scaling Group)                         │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Node 1 (t3.medium)                                       │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │  │
│  │  │ API Pod 1    │  │ Ingestion 1  │  │ Prometheus   │  │  │
│  │  │ CPU: 250m    │  │ CPU: 250m    │  │              │  │  │
│  │  │ Mem: 512Mi   │  │ Mem: 512Mi   │  │              │  │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘  │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Node 2 (t3.medium)                                       │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │  │
│  │  │ API Pod 2    │  │ Ingestion 2  │  │ Grafana      │  │  │
│  │  │              │  │              │  │              │  │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘  │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Node 3 (t3.medium)                                       │  │
│  │  ┌──────────────┐  ┌──────────────┐                     │  │
│  │  │ API Pod 3    │  │ Kube System  │                     │  │
│  │  │              │  │ Pods         │                     │  │
│  │  └──────────────┘  └──────────────┘                     │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────┘
           │                          │
           ▼                          ▼
┌─────────────────────┐    ┌─────────────────────────┐
│  RDS PostgreSQL     │    │  S3 Buckets             │
│  (from Phase 2)     │    │  (from Phase 2)         │
└─────────────────────┘    └─────────────────────────┘
```

## Components

### 1. EKS Cluster

**CloudFormation:** `cloudformation/01-eks-cluster.yaml`

- **Control Plane:** Managed by AWS (HA across 3 AZs)
- **Kubernetes Version:** 1.28 (configurable)
- **Worker Nodes:** 3x t3.medium (2 vCPU, 4GB RAM each)
- **Auto Scaling:** Min 2, Max 6 nodes
- **Networking:** VPC CNI plugin for pod networking
- **IRSA:** IAM Roles for Service Accounts enabled
- **Logging:** All control plane logs to CloudWatch
- **Encryption:** Secrets encrypted with KMS

**Features:**
- Private subnets for worker nodes
- Public endpoint with IP restrictions
- Managed node group with auto-updates
- Container Insights for monitoring
- OIDC provider for workload identity

### 2. Kubernetes Manifests

**Location:** `kubernetes/manifests/`

#### Namespace (`namespace.yaml`)
- Logical isolation for medical robotics apps
- Resource quotas and limits (optional)
- Network policies (optional)

#### Service Account (`serviceaccount.yaml`)
- IRSA annotation for AWS permissions
- RBAC roles for ConfigMap/Secret access
- Pod-level security permissions

#### Deployments
- **API Service** (`api-service-deployment.yaml`)
  - 3 replicas (anti-affinity spread)
  - Rolling update strategy (maxUnavailable: 0)
  - Liveness/readiness probes on /health
  - Resource requests/limits
  - Security context (non-root, drop capabilities)

- **Data Ingestion** (`data-ingestion-deployment.yaml`)
  - 2 replicas
  - Same best practices as API service
  - Optimized for write-heavy workload

#### Services
- ClusterIP for internal communication
- Session affinity disabled
- Health check annotations

#### Horizontal Pod Autoscaler (`hpa.yaml`)
- **API Service:** 3-15 replicas
- **Data Ingestion:** 2-10 replicas
- Metrics: CPU (70%), Memory (80%)
- Scale-up: Aggressive (double pods every 30s)
- Scale-down: Conservative (50% every 60s, 5min stabilization)

#### Ingress (`ingress.yaml`)
- AWS ALB Ingress Controller
- Path-based routing (/api, /ingest)
- Health checks every 15s
- Internet-facing scheme
- IP target type for better performance

### 3. Helm Charts

**Location:** `kubernetes/helm-charts/`

Helm charts for easier deployment and configuration management:

#### API Service Chart
```bash
helm install api-service ./helm-charts/api-service \
  --namespace medrobotics \
  --set image.tag=v1.2.3 \
  --set autoscaling.minReplicas=5
```

**Features:**
- Parameterized deployments
- Environment-specific values files
- Automated rollbacks
- Release versioning

**values.yaml** allows customization of:
- Replica counts
- Resource limits
- Autoscaling thresholds
- Image tags
- Environment variables

#### Data Ingestion Chart
Similar structure to API service with ingestion-specific defaults.

### 4. Monitoring Stack

**Location:** `kubernetes/monitoring/`

#### Prometheus + Grafana (Kube-Prometheus-Stack)
- **Prometheus:** Metrics collection and storage
  - 15-day retention
  - 50GB persistent volume
  - Service discovery for pods
  - Alert rules for critical metrics

- **Grafana:** Visualization and dashboards
  - Pre-configured dashboards:
    - Kubernetes Cluster Overview
    - Pod Resource Usage
    - Node Exporter Metrics
  - Admin password: changeme (change in production!)
  - Persistent storage for dashboards

- **AlertManager:** Alert routing and silencing
  - Configured for critical alerts
  - Extensible to SNS, PagerDuty, Slack

- **Node Exporter:** Host-level metrics
- **Kube-State-Metrics:** Kubernetes object metrics

#### ServiceMonitors (`servicemonitor.yaml`)
Automatic scraping of application metrics:
- Scrape /metrics endpoint every 30s
- Automatic pod discovery
- Labels for filtering

**Custom Metrics (Future):**
Add Prometheus client libraries to Flask apps:
```python
from prometheus_client import Counter, Histogram

request_count = Counter('http_requests_total', 'Total HTTP requests')
request_duration = Histogram('http_request_duration_seconds', 'HTTP request duration')
```

### 5. AWS Load Balancer Controller

Manages ALBs via Kubernetes Ingress resources:
- Automatic ALB creation/deletion
- Target group health checks
- SSL/TLS termination (if configured)
- WAF integration (if configured)

## Deployment

### Prerequisites

1. **Tools Installed:**
   ```bash
   aws --version        # AWS CLI v2
   kubectl version      # v1.28+
   helm version         # v3.0+
   eksctl version       # 0.150+
   ```

2. **Phase 2 Infrastructure Deployed:**
   - VPC, subnets, security groups
   - RDS PostgreSQL
   - S3 buckets

3. **AWS Permissions:**
   - EKS full access
   - EC2 full access
   - IAM role creation
   - CloudFormation

### Step 1: Deploy EKS Cluster

```bash
cd phase5-eks
./scripts/deploy.sh
```

This automated script will:
1. ✅ Check prerequisites
2. ✅ Deploy EKS cluster (15-20 minutes)
3. ✅ Configure kubectl
4. ✅ Install AWS Load Balancer Controller
5. ✅ Deploy application workloads
6. ✅ Install monitoring stack

### Step 2: Verify Deployment

```bash
# Check cluster
kubectl cluster-info
kubectl get nodes

# Check pods
kubectl get pods -n medrobotics
kubectl get pods -n monitoring

# Check services
kubectl get svc -n medrobotics
kubectl get ingress -n medrobotics

# Check HPA
kubectl get hpa -n medrobotics
```

Expected output:
```
NAME              READY   STATUS    RESTARTS   AGE
api-service-xxx   1/1     Running   0          2m
api-service-yyy   1/1     Running   0          2m
api-service-zzz   1/1     Running   0          2m
data-ingestion-xxx 1/1   Running   0          2m
data-ingestion-yyy 1/1   Running   0          2m
```

### Step 3: Test Application

```bash
# Get ALB DNS
ALB_DNS=$(kubectl get ingress medrobotics-ingress -n medrobotics \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Test API service
curl http://$ALB_DNS/api/health

# Test data ingestion
curl http://$ALB_DNS/ingest/health

# Test API endpoint
curl http://$ALB_DNS/api/robots | jq
```

### Step 4: Access Grafana

```bash
# Port forward Grafana
kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80

# Open browser
open http://localhost:3000
# Login: admin / changeme
```

## Operations

### Scaling

**Manual Scaling:**
```bash
# Scale deployment
kubectl scale deployment api-service -n medrobotics --replicas=10

# Scale nodes
aws eks update-nodegroup-config \
  --cluster-name medrobotics-cluster \
  --nodegroup-name medrobotics-nodegroup \
  --scaling-config minSize=5,maxSize=10,desiredSize=5
```

**Auto Scaling:**
- HPA automatically scales pods based on CPU/memory
- Cluster Autoscaler scales nodes based on pending pods

**Testing Auto-Scale:**
```bash
# Generate load
kubectl run -it --rm load-generator --image=busybox /bin/sh
# Inside pod:
while true; do wget -q -O- http://api-service.medrobotics:5000/api/robots; done
```

Watch HPA scale up:
```bash
kubectl get hpa -n medrobotics --watch
```

### Rolling Updates

Update image version:
```bash
kubectl set image deployment/api-service \
  api-service=<AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/medrobotics-api-service:v2.0.0 \
  -n medrobotics

# Watch rollout
kubectl rollout status deployment/api-service -n medrobotics
```

Rollback if issues:
```bash
kubectl rollout undo deployment/api-service -n medrobotics
```

### Monitoring

**View Logs:**
```bash
# Real-time logs
kubectl logs -f deployment/api-service -n medrobotics

# Logs from all pods
kubectl logs -l app=api-service -n medrobotics --tail=100

# Previous container logs (if crashed)
kubectl logs api-service-xxx -n medrobotics --previous
```

**Exec into Pod:**
```bash
kubectl exec -it deployment/api-service -n medrobotics -- /bin/sh
```

**Check Events:**
```bash
kubectl get events -n medrobotics --sort-by='.lastTimestamp'
```

**Describe Resources:**
```bash
kubectl describe pod api-service-xxx -n medrobotics
kubectl describe hpa api-service-hpa -n medrobotics
```

### Troubleshooting

**Pods Not Starting:**
```bash
# Check pod status
kubectl get pods -n medrobotics

# Describe pod for events
kubectl describe pod <pod-name> -n medrobotics

# Common issues:
# - ImagePullBackOff: Check ECR permissions
# - CrashLoopBackOff: Check logs for application errors
# - Pending: Check node resources
```

**Ingress Not Working:**
```bash
# Check ingress
kubectl describe ingress medrobotics-ingress -n medrobotics

# Check ALB controller logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller

# Verify security groups allow ALB -> Pods traffic
```

**HPA Not Scaling:**
```bash
# Check metrics server
kubectl top nodes
kubectl top pods -n medrobotics

# If metrics not available, install metrics-server:
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

## Cost Estimate

**Monthly costs (us-east-1):**

| Resource | Configuration | Monthly Cost |
|----------|--------------|--------------|
| EKS Control Plane | Managed | $73 |
| EC2 Worker Nodes | 3x t3.medium (24/7) | $100 |
| EBS Volumes | 3x 20GB gp3 | $6 |
| Application Load Balancer | 1 ALB | $20 |
| Data Transfer | ~50GB | $5 |
| CloudWatch Logs | ~10GB | $5 |
| **Total** | | **~$209/month** |

**Cost Optimization:**
- Use Spot instances for non-critical workloads (60-90% savings)
- Right-size node instances based on actual usage
- Use Cluster Autoscaler to scale down during off-hours
- Archive old CloudWatch logs
- Use Savings Plans or Reserved Instances (up to 72% savings)

## Cleanup

To delete all Phase 5 resources:

```bash
./scripts/cleanup.sh
```

This will:
1. Delete monitoring stack
2. Delete application workloads
3. Delete ALB (via Ingress deletion)
4. Delete ALB controller
5. Delete EKS cluster
6. Clean up IAM policies
7. Remove kubectl context

**Manual cleanup may be needed for:**
- Orphaned ENIs
- CloudWatch log groups
- ECR images

## Advanced Topics

### Service Mesh (Future Enhancement)

Add Istio for:
- mTLS between services
- Traffic management (canary, blue/green)
- Observability (distributed tracing)
- Circuit breaking

```bash
istioctl install --set profile=demo
kubectl label namespace medrobotics istio-injection=enabled
```

### GitOps with ArgoCD

Automate deployments from Git:
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### Secrets Management

Use External Secrets Operator to sync from AWS Secrets Manager:
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: rds-credentials
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secretsmanager
    kind: SecretStore
  target:
    name: rds-credentials
  data:
  - secretKey: password
    remoteRef:
      key: medrobotics-rds-secret
      property: password
```

## Comparison: ECS vs EKS

### What We Gained

✅ **Portability:** Can run on any Kubernetes cluster (on-prem, other clouds)
✅ **Ecosystem:** Access to 1000s of Helm charts and operators
✅ **Advanced Scaling:** HPA with custom metrics, VPA, Cluster Autoscaler
✅ **Better Monitoring:** Prometheus/Grafana + native Kubernetes metrics
✅ **GitOps Ready:** ArgoCD, Flux integration
✅ **Service Mesh:** Istio, Linkerd support
✅ **Declarative:** Everything is YAML (versioned, reviewable)

### What We Lost

❌ **Simplicity:** More complex than ECS
❌ **AWS Integration:** Need extra controllers (ALB, EBS CSI)
❌ **Managed Updates:** More hands-on with Kubernetes upgrades
❌ **Cost:** EKS control plane costs $73/month

### When to Use Each

**Use ECS if:**
- AWS-only workloads
- Simple microservices
- Want AWS-managed everything
- Small team

**Use EKS if:**
- Need Kubernetes standard
- Advanced orchestration needs
- Multi-cloud strategy
- Large, complex applications
- DevOps/SRE team available

## Files Structure

```
phase5-eks/
├── cloudformation/
│   └── 01-eks-cluster.yaml           # EKS cluster + node group
├── kubernetes/
│   ├── manifests/
│   │   ├── namespace.yaml
│   │   ├── serviceaccount.yaml
│   │   ├── configmap.yaml
│   │   ├── secret.yaml
│   │   ├── api-service-deployment.yaml
│   │   ├── data-ingestion-deployment.yaml
│   │   ├── hpa.yaml
│   │   └── ingress.yaml
│   ├── helm-charts/
│   │   ├── api-service/
│   │   │   ├── Chart.yaml
│   │   │   ├── values.yaml
│   │   │   └── templates/
│   │   │       ├── deployment.yaml
│   │   │       ├── service.yaml
│   │   │       ├── hpa.yaml
│   │   │       └── _helpers.tpl
│   │   └── data-ingestion/
│   │       └── ... (similar structure)
│   └── monitoring/
│       ├── prometheus-values.yaml
│       └── servicemonitor.yaml
├── scripts/
│   ├── deploy.sh                      # Deployment automation
│   └── cleanup.sh                     # Cleanup automation
└── README.md                          # This file
```

## Next Steps

**Phase 6: CI/CD Pipeline**
- GitHub Actions workflows
- Automated testing
- Container image building
- Automated deployment to EKS
- GitOps with ArgoCD

## Support

For issues or questions:
1. Check CloudWatch Logs
2. Review Kubernetes events
3. Check pod logs
4. Verify security groups and IAM roles

## License

This project is part of a DevOps portfolio demonstration.
