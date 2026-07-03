# NOTES.md — Orders API Fix-it Assessment



---

## 1. Application (`app/app.py`)

### Problem: Bound to 127.0.0.1
- **Fix:** Changed `host="127.0.0.1"` to `host="0.0.0.0"`.
- **Why:** Inside a container, 127.0.0.1 only accepts local traffic. The app becomes unreachable.

### Problem: `debug=True` in production
- **Fix:** Set `debug=False`.
- **Why:** Flask debug mode exposes interactive stack traces — severe security risk.

### Problem: Hardcoded `SECRET_KEY`
- **Fix:** `os.environ["SECRET_KEY"]` with no fallback.
- **Why:** Any fallback default is still a hardcoded secret. Failing fast forces explicit configuration.

### Problem: No logging
- **Fix:** Added basic `logging` configuration.
- **Why:** Without logs, debugging production issues is impossible.

---

## 2. Dependencies (`app/requirements.txt`)

### Problem: Unpinned version
- **Fix:** Pinned `flask==3.0.3`, added `gunicorn==23.0.0` and `psycopg2-binary==2.9.9`.
- **Why:** Unpinned dependencies cause non-reproducible builds. Gunicorn is a production WSGI server.

---

## 3. Container (`Dockerfile`)

### Problem: `FROM python:latest`
- **Fix:** Changed to `python:3.11-slim`.
- **Why:** `latest` is non-reproducible and ~1GB+. `3.11-slim` is ~120MB.

### Problem: `COPY . .`
- **Fix:** Split into `COPY requirements.txt` first, then `COPY app.py`, added `.dockerignore`.
- **Why:** Blind `COPY . .` pulls in secrets, `.git`, Terraform state. Also destroys Docker cache.

### Problem: Unnecessary packages (`build-essential gcc curl vim`)
- **Fix:** Removed all `apt-get install`.
- **Why:** These are compile-time/debug tools, not runtime. Each is a CVE vector.

### Problem: No `--no-cache-dir`
- **Fix:** Added `pip install --no-cache-dir`.
- **Why:** Pip cache bloats the image by ~50-100MB.

### Problem: Runs as root
- **Fix:** Created `appuser` and added `USER appuser`.
- **Why:** Container escape with root = host compromise.

### Problem: `CMD ["python", "app/app.py"]` — Flask dev server
- **Fix:** Replaced with `gunicorn`.
- **Why:** Flask dev server is single-threaded, not for production.

### Problem: Missing `PYTHONDONTWRITEBYTECODE` and `PYTHONUNBUFFERED`
- **Fix:** Added both.
- **Why:** Prevents `.pyc` bloat and ensures immediate log flushing.

---

## 4. Local Orchestration (`docker-compose.yml`)

### Problem: Wrong port mapping (`5000:8080`)
- **Fix:** Changed to `5000:5000`.
- **Why:** App listens on 5000, not 8080.

### Problem: `postgres:latest`
- **Fix:** Pinned to `postgres:16-alpine`.
- **Why:** `latest` is a moving target.

### Problem: No database persistence
- **Fix:** Added named volume `postgres_data`.
- **Why:** Without a volume, DB is wiped on restart.

### Problem: Hardcoded DB password
- **Fix:** Used `${POSTGRES_PASSWORD}` env var from `.env`.
- **Why:** Plaintext passwords in source control are a critical vulnerability.

### Problem: `depends_on` doesn't wait for DB readiness
- **Fix:** Added `condition: service_healthy` and health checks.
- **Why:** API crashes if PostgreSQL isn't ready.

### Problem: No resource limits
- **Fix:** Added `deploy.resources.limits`.
- **Why:** Prevents runaway containers from consuming all host resources.

### Problem: No restart policy
- **Fix:** Added `restart: unless-stopped`.
- **Why:** Auto-recovery after crash.

---

## 5. CI Pipeline (`.github/workflows/ci.yml`)

### Problem: Missing `actions/checkout`
- **Fix:** Added `uses: actions/checkout@v4`.
- **Why:** Without checkout, CI has no source code.

### Problem: `pytest || true` ignores failures
- **Fix:** Changed to `pytest || exit 1`.
- **Why:** Swallowing test failures defeats CI.

### Problem: Hardcoded registry credentials
- **Fix:** Replaced with `${{ secrets.DOCKERHUB_USERNAME }}` and `${{ secrets.DOCKERHUB_PASSWORD }}`.
- **Why:** Exposing credentials in source control is a critical breach.

### Problem: No branch filtering
- **Fix:** Restricted to `fix` branch only.
- **Why:** Only run CI on our working branch.

### Problem: No image tagging strategy
- **Fix:** Tagged with `${{ github.sha }}` only (no `latest`).
- **Why:** `latest` is non-reproducible. SHA tags enable rollbacks.

### Problem: Push to DockerHub missing
- **Fix:** Added DockerHub login and push steps.
- **Why:** Assessment requires building and pushing container images.

### Problem: Username hardcoded in CI
- **Fix:** Used `${{ secrets.DOCKERHUB_USERNAME }}` in `IMAGE_NAME`.
- **Why:** Keeps registry identity configurable and out of source code.

---
## 6. AWS Infrastructure (`infra/main.tf`)

I kept the Terraform intentionally simple using AWS default VPC,
focusing on critical security and cost fixes for a 2-3 hour assessment.

### Problem: Fake / invalid AMI
- **Fix:** Replaced with `data.aws_ami` lookup for Amazon Linux 2023.
- **Why:** Fake AMI ID would cause `terraform apply` to fail.

### Problem: Oversized EC2 (`m5.4xlarge`)
- **Fix:** Downgraded to `t3.micro`.
- **Why:** `m5.4xlarge` costs ~$0.77/hr for a tiny API. `t3.micro` is ~$0.01/hr.

### Problem: Oversized disk (500 GB)
- **Fix:** Reduced to 20 GB `gp3`.
- **Why:** 500 GB is unnecessary. `gp3` offers better IOPS/$.

### Problem: Unencrypted root volume
- **Fix:** Added `encrypted = true`.
- **Why:** Encryption at rest is a security baseline.

### Problem: SSH open to 0.0.0.0/0
- **Fix:** Restricted to internal VPC CIDR (`10.0.0.0/8`).
- **Why:** Open SSH is one of the most common attack vectors.

### Problem: Oversized RDS (`db.m5.2xlarge`, multi-AZ)
- **Fix:** Downgraded to `db.t3.micro`, disabled multi-AZ.
- **Why:** A small DB doesn't need 8 vCPUs. Multi-AZ doubles cost.

### Problem: Hardcoded RDS password
- **Fix:** Used `random_password` resource.
- **Why:** Hardcoded passwords in Terraform state are a vulnerability.

### Problem: RDS not encrypted, no backups
- **Fix:** Added `storage_encrypted = true` and `backup_retention_period = 7`.
- **Why:** Encryption and backups are security baselines.

### Problem: RDS publicly accessible
- **Fix:** Set `publicly_accessible = false`.
- **Why:** A database should never be reachable from the internet.

### What I simplified (and why):
- **No custom VPC, ALB, subnets** — Used AWS default VPC to keep config manageable.
  In production, I would absolutely add a custom VPC with public/private subnets,
  ALB, and IAM roles for proper isolation and security.
## How to validate

```bash
# Docker
$ docker-compose up --build
$ curl http://localhost:5000/healthz

# Terraform
$ cd infra
$ terraform init
$ terraform validate
$ terraform plan