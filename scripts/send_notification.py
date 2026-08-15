#!/usr/bin/env python3
"""Send the assignment's customized success or failure email."""

import os
import smtplib
import ssl
import sys
from email.message import EmailMessage


def required(name):
    value = os.getenv(name)
    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def main():
    outcome = required("PIPELINE_OUTCOME").lower()
    success = outcome == "success"
    marker = "SUCCESS" if success else "FAILURE"
    commit = required("COMMIT_SHA")
    branch = required("BRANCH_NAME")
    image = os.getenv("IMAGE_URI", "not-built")
    target = os.getenv("DEPLOY_TARGET", "not-reached")
    run_url = os.getenv("PIPELINE_RUN_URL", "local-run")
    failed_stage = os.getenv("FAILED_STAGE", "none")

    message = EmailMessage()
    message["Subject"] = f"[{marker}] CI/CD {branch} {commit[:8]}"
    message["From"] = required("SMTP_FROM")
    message["To"] = required("SMTP_TO")
    lines = [
        f"Pipeline outcome: {marker}",
        f"Commit SHA: {commit}",
        f"Branch: {branch}",
        f"Docker image: {image}",
        f"Deployment target: {target}",
        f"Pipeline run: {run_url}",
    ]
    if not success:
        lines.insert(1, f"Failed stage: {failed_stage}")
    message.set_content("\n".join(lines) + "\n")

    host = required("SMTP_HOST")
    port = int(os.getenv("SMTP_PORT", "587"))
    username = os.getenv("SMTP_USERNAME", "")
    password = os.getenv("SMTP_PASSWORD", "")
    security = os.getenv("SMTP_SECURITY", "starttls").lower()

    if security == "ssl":
        server = smtplib.SMTP_SSL(host, port, context=ssl.create_default_context())
    else:
        server = smtplib.SMTP(host, port)
    with server:
        if security == "starttls":
            server.starttls(context=ssl.create_default_context())
        if username:
            server.login(username, password)
        server.send_message(message)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"Notification error: {exc}", file=sys.stderr)
        raise
