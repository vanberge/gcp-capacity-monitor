# Universal GKE ComputeClass & Stockout Monitoring Dashboard

A project-wide, cluster-agnostic Google Cloud Operations monitoring package that tracks:
1. **Compute Engine / GKE Instance Stockouts** (`FailedScaleUp: GCE out of resources`, `ZONE_RESOURCE_POOL_EXHAUSTED`, `stockout`).
2. **Auto-Provisioned Nodes Broken Down by Machine Family** (`n4`, `n2`, `e2`, `n2d`, `t2d`, `c3d`, etc.).
3. **Comparative Trends** (Stockouts vs Successful Node Creations).
4. **Project-Wide Multi-Cluster Coverage** (Monitors all GKE clusters across the project).
5. **Raw Logging Details Pane** (Real-time autoscaler and GCE provisioning events).

---

## Why This Works Across Any Cluster & Any Machine Family

- **Dynamic Machine Family Extraction**:  
  The metric `gke_node_provisioning_successes` extracts `machine_family` dynamically using a regular expression (`.*-nap-([a-z0-9]+)-.*`) from Google Cloud audit logs. Whether a cluster uses `N4` with `AMD` fallbacks, or `N2` with `E2` fallbacks, the dashboard plots separate trend lines for each machine family automatically.
- **Project-Agnostic Log Queries**:  
  Queries utilize substring matching (`logName : "events"` and `logName : "cloudaudit.googleapis.com%2Factivity"`), eliminating hardcoded project numbers or cluster names.

---

## Repository Structure

```
.
├── dashboard.json                      # Cloud Monitoring dashboard template
├── metric-stockouts.yaml               # Stockout log-based metric definition
├── metric-provisioning-successes.yaml  # Node creation log-based metric definition
├── deploy.sh                           # Turnkey bash deployment script
├── terraform/                          # Optional Terraform module
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
├── .gitignore
└── README.md
```

---

## Deployment Options

### Option 1: Turnkey Bash Script (Cloud Shell or Local CLI)

Clone the repository and run:

```bash
git clone <YOUR_REPO_URL>
cd gke-computeclass-monitoring
./deploy.sh [TARGET_PROJECT_ID]
```

*(If `TARGET_PROJECT_ID` is omitted, the script automatically uses your currently active `gcloud` config project).*

### Option 2: Terraform / GitOps

If your team manages GCP infrastructure with Terraform:

```bash
cd terraform
terraform init
terraform apply -var="project_id=YOUR_PROJECT_ID"
```

---

## Prerequisites & Permissions

1. **GKE Node Auto-Provisioning / ComputeClasses**:
   - The cluster should have Node Auto-Provisioning or ComputeClasses enabled so that dynamic fallback node pools follow standard `nap-<machine-family>-...` naming conventions.
2. **IAM Roles**:
   - `roles/logging.configWriter` (to create the log-based metrics)
   - `roles/monitoring.editor` (to deploy the dashboard)

> [!NOTE]
> Google Cloud log-based metrics do not retroactively backfill past events. The line charts will begin plotting data as soon as autoscaling events occur after deployment. The **Details Pane (Logs Panel)** at the bottom of the dashboard queries the log stream directly and will show recent historical events immediately.
