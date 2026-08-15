#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
AWS_ENDPOINT_URL=${AWS_ENDPOINT_URL:-http://localhost:4566}
AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-east-1}
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-test}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-test}
ECR_REPOSITORY=${ECR_REPOSITORY:-student-registration}
APP_CONTAINER=${APP_CONTAINER:-student-registration-app}
COMMIT_SHA=$(git -C "$ROOT_DIR" rev-parse HEAD)
BRANCH_NAME=$(git -C "$ROOT_DIR" branch --show-current)
FAILED_STAGE=bootstrap
IMAGE_URI=not-built
DEPLOY_TARGET=floci-local-docker

export AWS_ENDPOINT_URL AWS_DEFAULT_REGION AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
export COMMIT_SHA BRANCH_NAME IMAGE_URI DEPLOY_TARGET FAILED_STAGE
export PIPELINE_RUN_URL=${PIPELINE_RUN_URL:-local-run}
export SMTP_HOST=${SMTP_HOST:-localhost} SMTP_PORT=${SMTP_PORT:-1025}
export SMTP_SECURITY=${SMTP_SECURITY:-none}
export SMTP_FROM=${SMTP_FROM:-cicd@local.test} SMTP_TO=${SMTP_TO:-student@local.test}

notify_failure() {
  local exit_code=$?
  export PIPELINE_OUTCOME=failure FAILED_STAGE IMAGE_URI
  python3 "$ROOT_DIR/scripts/send_notification.py" || true
  exit "$exit_code"
}
trap notify_failure ERR

cd "$ROOT_DIR"

FAILED_STAGE=checkout
git diff --check

FAILED_STAGE=install
python3 -m pip install -r requirements.txt

FAILED_STAGE=test
docker compose -f compose.local.yml up -d mongodb mailpit floci
until docker inspect --format '{{.State.Health.Status}}' cicd-mongodb 2>/dev/null | grep -q healthy; do sleep 2; done
MONGO_URI=mongodb://localhost:27017/test_student_db SECRET_KEY=test-secret python3 -m pytest -q

FAILED_STAGE=build
for attempt in {1..30}; do curl -fsS "$AWS_ENDPOINT_URL/_localstack/health" >/dev/null && break; sleep 2; done
aws --endpoint-url "$AWS_ENDPOINT_URL" ecr describe-repositories --repository-names "$ECR_REPOSITORY" >/dev/null 2>&1 \
  || aws --endpoint-url "$AWS_ENDPOINT_URL" ecr create-repository --repository-name "$ECR_REPOSITORY" >/dev/null
IMAGE_URI=$(aws --endpoint-url "$AWS_ENDPOINT_URL" ecr describe-repositories \
  --repository-names "$ECR_REPOSITORY" --query 'repositories[0].repositoryUri' --output text):"$COMMIT_SHA"
export IMAGE_URI
docker build --tag "$IMAGE_URI" .

FAILED_STAGE=push
REGISTRY=${IMAGE_URI%%/*}
aws --endpoint-url "$AWS_ENDPOINT_URL" ecr get-login-password \
  | docker login --username AWS --password-stdin "$REGISTRY"
docker push "$IMAGE_URI"

FAILED_STAGE=deploy
docker pull "$IMAGE_URI"
docker stop "$APP_CONTAINER" >/dev/null 2>&1 || true
docker rm "$APP_CONTAINER" >/dev/null 2>&1 || true
docker run -d --name "$APP_CONTAINER" --restart unless-stopped \
  --network cicd-assign-local -p 5000:5000 \
  -e MONGO_URI=mongodb://mongodb:27017/student_registration \
  -e SECRET_KEY=local-only-secret "$IMAGE_URI" >/dev/null

FAILED_STAGE=verify
for attempt in {1..30}; do
  curl -fsS http://localhost:5000/health >/dev/null && break
  if [ "$attempt" -eq 30 ]; then docker logs "$APP_CONTAINER"; exit 1; fi
  sleep 2
done

FAILED_STAGE=notify
export PIPELINE_OUTCOME=success FAILED_STAGE IMAGE_URI
python3 "$ROOT_DIR/scripts/send_notification.py"
trap - ERR
printf 'Local pipeline succeeded. Image: %s\nMail: http://localhost:8025\nApp: http://localhost:5000\n' "$IMAGE_URI"
