# Student Registration CI/CD Assignment

This repository contains the Flask/MongoDB application and one GitHub Actions pipeline required by the assignment. The production path tests the app, builds an immutable Docker image tagged with the full Git commit SHA, pushes it to Amazon ECR, replaces the running EC2 container, verifies `/health`, and sends a customized result email.

## What was added

- `Dockerfile` and `.dockerignore`
- MongoDB-aware `GET /health` readiness endpoint plus success/failure tests
- `.github/workflows/ci-cd.yml` (the only pipeline definition)
- customized SMTP notification script
- Floci-based local AWS rehearsal with MongoDB and Mailpit

## Local prerequisites

- Python 3
- Docker Desktop running
- AWS CLI v2
- Git

## Run the complete local rehearsal (no AWS account)

Floci provides a local ECR-compatible registry and local AWS APIs. The script performs the same gates locally: install, test, commit-SHA image build, push to Floci ECR, replace the app container, poll `/health`, and send an email to Mailpit.

```bash
chmod +x scripts/local_pipeline.sh
./scripts/local_pipeline.sh
```

After success:

- Application: <http://localhost:5000>
- Health gate: <http://localhost:5000/health>


Stop the local infrastructure when finished:

```bash
docker rm -f student-registration-app 2>/dev/null || true
docker compose -f compose.local.yml down
```

Important: Floci is excellent for development evidence, but it is not Amazon AWS. The rubric explicitly grades a successful push to Amazon ECR and deployment to Amazon EC2, so a real AWS account is required before final submission.

## Real AWS prerequisites

Create these manually before enabling the production workflow:

1. An ECR repository named `student-registration` (or set repository variable `ECR_REPOSITORY`).
2. An Amazon Linux 2023 or Ubuntu EC2 instance with Docker and AWS CLI installed.
3. An EC2 instance profile with `AmazonEC2ContainerRegistryReadOnly`, or a least-privilege equivalent for this repository.
4. A security group that allows TCP 5000 only from intended reviewers/users. Allow TCP 22 only from the deployment source needed for SSH; do not leave it open globally without justification.
5. A root-owned EC2 environment file at `/opt/student-registration/app.env`:

   ```text
   MONGO_URI=<runtime MongoDB URI>
   SECRET_KEY=<random application secret>
   ```

   Protect it with `chmod 600`. The workflow never transmits or commits the MongoDB URI.

6. An IAM user or role for GitHub Actions with only ECR push and identity permissions. For a student account using keys, the minimum API actions are `sts:GetCallerIdentity`, `ecr:GetAuthorizationToken`, and repository-scoped ECR upload actions.

## GitHub configuration

Create these in **Settings → Secrets and variables → Actions**.

Repository secrets:

| Secret | Purpose |
|---|---|
| `AWS_ACCESS_KEY_ID` | AWS identity used to push to ECR |
| `AWS_SECRET_ACCESS_KEY` | AWS credential; never commit it |
| `EC2_HOST` | EC2 public DNS/IP |
| `EC2_SSH_PRIVATE_KEY` | Private key for SSH deployment |
| `SMTP_HOST`, `SMTP_PORT` | SMTP server endpoint |
| `SMTP_USERNAME`, `SMTP_PASSWORD` | SMTP login |
| `SMTP_FROM`, `SMTP_TO` | Notification sender and recipient |

Repository variables:

| Variable | Default | Purpose |
|---|---|---|
| `AWS_REGION` | `us-east-1` | AWS region |
| `ECR_REPOSITORY` | `student-registration` | Existing ECR repository |
| `EC2_USER` | `ec2-user` | SSH user; use `ubuntu` for Ubuntu AMIs |
| `SMTP_SECURITY` | `starttls` | Use `starttls`, `ssl`, or `none` |

Use a GitHub personal access token, not a GitHub account password, when Git asks for a password over HTTPS. Enter it only at the prompt or credential manager; do not place it in `.env`, workflow YAML, shell history, or commits.

## Pipeline order and failure behavior

The workflow triggers on every push to `main` and executes in the required order:

1. Checkout
2. Install dependencies
3. Run pytest (a failure stops build and deployment)
4. Build image tagged with `${GITHUB_SHA}`
5. Authenticate and push to ECR
6. SSH to EC2, pull the new image, stop/remove the old container, and run the replacement with `--restart unless-stopped`
7. Poll `/health` on the EC2 host; failure makes the deployment fail
8. Send an outcome-specific email with commit, branch, image, target, failed stage (on failure), and pipeline URL

SSH was chosen because it is the simplest method stated in the assignment. In production, SSM is preferable because it avoids an inbound SSH rule.

## Manual deployment if GitHub Actions is unavailable

```bash
export AWS_REGION=us-east-1
export ACCOUNT_ID=<aws-account-id>
export ECR_REPOSITORY=student-registration
export COMMIT_SHA=$(git rev-parse HEAD)
export IMAGE_URI="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY:$COMMIT_SHA"

docker build -t "$IMAGE_URI" .
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "${IMAGE_URI%%/*}"
docker push "$IMAGE_URI"

ssh -i <private-key.pem> <ec2-user>@<ec2-host>
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin <account>.dkr.ecr.us-east-1.amazonaws.com
docker pull <full-image-uri-with-sha>
docker stop student-registration-app 2>/dev/null || true
docker rm student-registration-app 2>/dev/null || true
docker run -d --name student-registration-app --restart unless-stopped \
  --env-file /opt/student-registration/app.env -p 5000:5000 <full-image-uri-with-sha>
curl --fail http://localhost:5000/health
```

## Required submission evidence

- Repository link
- Screenshot/recording of one fully green run ending in real EC2 deployment
- Screenshot of the customized success email
- One intentionally broken test run showing build/deploy stopped, plus its customized failure email naming the failed stage
- A text, Word, or PDF file containing the repository link for Vlearn

Do not leave the intentionally failing test committed on `main`; capture the evidence, then revert it and confirm the green run again.
