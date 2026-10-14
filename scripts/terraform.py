"""Run Terraform with credentials resolved by AWS CLI, without saving keys."""

import json
import os
import subprocess
import sys


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: python3 scripts/terraform.py [-chdir=DIR] COMMAND [OPTIONS]", file=sys.stderr)
        return 2

    profile = os.environ.get("AWS_PROFILE", "terraform")
    try:
        result = subprocess.run(
            ["aws", "configure", "export-credentials", "--profile", profile, "--format", "process"],
            check=True,
            capture_output=True,
            text=True,
            timeout=60,
        )
        credentials = json.loads(result.stdout)
        environment = os.environ.copy()
        environment["AWS_ACCESS_KEY_ID"] = credentials["AccessKeyId"]
        environment["AWS_SECRET_ACCESS_KEY"] = credentials["SecretAccessKey"]
        if credentials.get("SessionToken"):
            environment["AWS_SESSION_TOKEN"] = credentials["SessionToken"]
        else:
            environment.pop("AWS_SESSION_TOKEN", None)
        # Ensure SDKs use these credentials, rather than rereading a login profile
        # that older Terraform/backend SDK versions might not support.
        environment.pop("AWS_PROFILE", None)
        environment.pop("AWS_DEFAULT_PROFILE", None)
        os.execvpe("terraform", ["terraform", *sys.argv[1:]], environment)
    except subprocess.CalledProcessError:
        print(
            f"Cannot resolve AWS profile {profile!r}. Run: aws login --profile {profile} --region eu-central-1",
            file=sys.stderr,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired, ValueError, KeyError):
        print("Cannot start Terraform: check AWS CLI, Terraform and your AWS login session.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
