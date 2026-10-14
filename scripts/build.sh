#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
image_tag="${1:-$(git rev-parse HEAD)}"
region="${AWS_REGION:-eu-central-1}"
prefix="${ECR_REPOSITORY_PREFIX:-hello-world}"
if [[ ! "$image_tag" =~ ^[0-9a-f]{40}$ ]]; then
  echo 'Use the full Git commit SHA as the image tag.' >&2
  exit 1
fi
account_id="$(aws sts get-caller-identity --query Account --output text)"
registry="$account_id.dkr.ecr.$region.amazonaws.com"
aws ecr get-login-password --region "$region" | docker login --username AWS --password-stdin "$registry"

for component in app nginx; do
  repository="$prefix/$component"
  if aws ecr describe-images --region "$region" --repository-name "$repository" \
      --image-ids "imageTag=$image_tag" >/dev/null 2>&1; then
    echo "Reusing immutable image $repository:$image_tag"
    continue
  fi
  context=.
  if [[ "$component" == nginx ]]; then context=nginx; fi
  docker build --platform linux/amd64 --tag "$registry/$repository:$image_tag" "$context"
  docker push "$registry/$repository:$image_tag"
done
