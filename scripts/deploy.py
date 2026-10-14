"""Deploy the commit's images to K3s through AWS SSM and wait for rollout."""

import base64
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time


def aws(*arguments):
    command = ["aws", *arguments, "--region", "eu-central-1", "--output", "json", "--no-cli-pager"]
    result = subprocess.run(command, capture_output=True, text=True, timeout=60)
    if result.returncode:
        raise RuntimeError(result.stderr.strip())
    return json.loads(result.stdout)


def remote_script(manifest: str) -> str:
    encoded = base64.b64encode(manifest.encode()).decode()
    return f"""#!/usr/bin/env bash
set -euo pipefail
exec 9>/var/lock/hello-world-deploy.lock
flock -w 300 9
test -f /var/lib/hello-world-bootstrap.done
work_dir=$(mktemp -d /tmp/hello-world-deploy.XXXXXX)
trap 'rm -rf "$work_dir"' EXIT
printf '%s' '{encoded}' | base64 --decode > "$work_dir/app.yaml"
/usr/local/bin/k3s kubectl apply -f "$work_dir/app.yaml"
if ! /usr/local/bin/k3s kubectl -n hello-world rollout status deployment/hello-world --timeout=300s; then
  /usr/local/bin/k3s kubectl -n hello-world get pods -o wide
  /usr/local/bin/k3s kubectl -n hello-world describe pods
  /usr/local/bin/k3s kubectl -n hello-world rollout undo deployment/hello-world || true
  /usr/local/bin/k3s kubectl -n hello-world rollout status deployment/hello-world --timeout=180s || true
  exit 1
fi
curl --fail --silent --show-error --retry 10 --retry-all-errors --retry-delay 3 \
  --connect-timeout 3 --max-time 5 http://127.0.0.1/healthz
"""


def main() -> int:
    if len(sys.argv) != 2 or not re.fullmatch(r"[0-9a-f]{40}", sys.argv[1]):
        print("Usage: python3 scripts/deploy.py FULL_COMMIT_SHA", file=sys.stderr)
        return 2
    instance_id = os.environ.get("INSTANCE_ID", "")
    prefix = os.environ.get("ECR_REPOSITORY_PREFIX", "hello-world")
    if not re.fullmatch(r"i-[0-9a-f]{8,17}", instance_id):
        print("Set INSTANCE_ID to the Terraform instance_id output.", file=sys.stderr)
        return 2
    if not re.fullmatch(r"[a-z0-9][a-z0-9/_-]*", prefix):
        print("Invalid ECR_REPOSITORY_PREFIX.", file=sys.stderr)
        return 2
    try:
        account_id = aws("sts", "get-caller-identity")["Account"]
        registry = f"{account_id}.dkr.ecr.eu-central-1.amazonaws.com/{prefix}"
        manifest = (Path(__file__).resolve().parent.parent / "k8s/app.yaml").read_text()
        manifest = manifest.replace("${APP_IMAGE}", f"{registry}/app:{sys.argv[1]}")
        manifest = manifest.replace("${NGINX_IMAGE}", f"{registry}/nginx:{sys.argv[1]}")
        result = aws(
            "ssm", "send-command", "--instance-ids", instance_id,
            "--document-name", "AWS-RunShellScript", "--timeout-seconds", "900",
            "--comment", f"Deploy {sys.argv[1]}",
            "--parameters", json.dumps({"commands": ["bash <<'DEPLOY'\n" + remote_script(manifest) + "\nDEPLOY"], "executionTimeout": ["900"]}),
        )
        command_id = result["Command"]["CommandId"]
        print(f"SSM command: {command_id}", flush=True)
        deadline = time.monotonic() + 1000
        while time.monotonic() < deadline:
            time.sleep(5)
            try:
                invocation = aws("ssm", "get-command-invocation", "--command-id", command_id, "--instance-id", instance_id)
            except RuntimeError as error:
                if "InvocationDoesNotExist" in str(error):
                    continue
                raise
            status = invocation["Status"]
            if status in {"Pending", "InProgress", "Delayed"}:
                continue
            print(invocation.get("StandardOutputContent", ""))
            print(invocation.get("StandardErrorContent", ""), file=sys.stderr)
            if status != "Success":
                raise RuntimeError(f"SSM deployment finished with status {status}")
            print(f"Deployed {sys.argv[1]}")
            return 0
        raise RuntimeError(f"Timed out waiting for SSM command {command_id}; inspect it in AWS Console.")
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        print(f"Deployment failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
