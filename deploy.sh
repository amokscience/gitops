#!/bin/bash

# Deploy CFB app to specified environment using Helm + Kustomize pipeline
# Usage: ./deploy.sh dev|qa|staging|prod [--apply]

set -e

ENV=${1:-}
APPLY=${2:-}

if [[ ! "$ENV" =~ ^(dev|qa|staging|prod)$ ]]; then
    echo "Usage: $0 {dev|qa|staging|prod} [--apply]"
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELM_CHART="$REPO_ROOT/cfb/helm"
DEFAULTS_FILE="$REPO_ROOT/helm-defaults/defaults.yaml"
VALUES_FILE="$REPO_ROOT/cfb/helm/values.yaml"
OVERLAY_PATH="$REPO_ROOT/cfb/overlays/$ENV"

echo -e "\033[36mDeploying CFB to $ENV environment...\033[0m"

# Step 1: Template Helm chart
echo -e "\033[33mStep 1: Rendering Helm chart...\033[0m"
HELM_OUTPUT=$(helm template cfb "$HELM_CHART" \
    -f "$DEFAULTS_FILE" \
    -f "$VALUES_FILE" 2>&1) || {
    echo -e "\033[31mError rendering Helm chart:\033[0m"
    echo "$HELM_OUTPUT"
    exit 1
}

# Step 2: Pipe through Kustomize
echo -e "\033[33mStep 2: Applying Kustomize overlays...\033[0m"

# Create temporary directory
TEMP_KUST_DIR=$(mktemp -d)
trap "rm -rf $TEMP_KUST_DIR" EXIT

# Save helm output to temp file
echo "$HELM_OUTPUT" > "$TEMP_KUST_DIR/helm-manifest.yaml"

# Copy overlay kustomization
cp "$OVERLAY_PATH/kustomization.yaml" "$TEMP_KUST_DIR/kustomization.yaml"

# Copy any patch files
cp "$OVERLAY_PATH"/*-patch.yaml "$TEMP_KUST_DIR/" 2>/dev/null || true

# Add helm-manifest.yaml as resource if not already present
if ! grep -q "resources:" "$TEMP_KUST_DIR/kustomization.yaml"; then
    {
        echo "resources:"
        echo "- helm-manifest.yaml"
        echo ""
        cat "$TEMP_KUST_DIR/kustomization.yaml"
    } > "$TEMP_KUST_DIR/kustomization.yaml.tmp"
    mv "$TEMP_KUST_DIR/kustomization.yaml.tmp" "$TEMP_KUST_DIR/kustomization.yaml"
fi

FINAL_MANIFEST=$(kustomize build "$TEMP_KUST_DIR" 2>&1) || {
    echo -e "\033[31mError applying Kustomize overlays:\033[0m"
    echo "$FINAL_MANIFEST"
    exit 1
}

# Step 3: Apply or display
if [[ "$APPLY" == "--apply" ]]; then
    echo -e "\033[33mStep 3: Applying to cluster...\033[0m"
    echo "$FINAL_MANIFEST" | kubectl apply -f -
    echo -e "\033[32mSuccessfully deployed to $ENV!\033[0m"
else
    echo -e "\033[33mStep 3: Generated manifests (use --apply flag to deploy):\033[0m"
    echo -e "\033[36m---\033[0m"
    echo "$FINAL_MANIFEST"
fi

