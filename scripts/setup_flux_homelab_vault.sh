#!/bin/bash

# Check arguments
if [ -z "$1" ]; then
  echo "
Usage: $0 <environment>
Example: $0 staging
Example: $0 production
"
  exit 1
fi

# Set arguments
ENVIRONMENT="$1"

# Validate environment
case "$ENVIRONMENT" in
  staging|production)
    echo "Environment set to '$ENVIRONMENT'."
    ;;
  *)
    echo "
Invalid environment: '$ENVIRONMENT'. 
Allowed values are 'staging' or 'production'.
"
    exit 1
    ;;
esac

# Variables
# GITHUB_TOKEN=$(pass show github/tokens/classic/flux)
NAMESPACE="flux-system"
APP_NAME="homelab-vault"
GIT_URL="ssh://git@github.com/micha-aucoin/homelab-vault.git"
PRIVATE_KEY_FILE="$HOME/.ssh/fluxcd"
GIT_BRANCH="master"
EXPORT_DIR="clusters/$ENVIRONMENT"
OUTPUT_FILE="$EXPORT_DIR/$APP_NAME.yaml"
KUSTOMIZATION_PATH="./$ENVIRONMENT"

# Bootstrap
# echo "Bootstrapin..."
# flux bootstrap github \
#   --token-auth \
#   --owner=micha-aucoin \
#   --repository=homelab \
#   --branch=master \
#   --path=clusters/staging \
#   --personal

# Create the Git authentication secret
echo "Creating Git authentication secret..."
flux create secret git "$APP_NAME" \
  --namespace="$NAMESPACE" \
  --url="$GIT_URL" \
  --private-key-file="$PRIVATE_KEY_FILE" 

# Check if secret was created successfully
if kubectl -n "$NAMESPACE" get secret "$APP_NAME" >/dev/null 2>&1; then
  echo "Secret '$APP_NAME' created successfully in namespace '$NAMESPACE'."
else
  echo "Failed to create secret '$APP_NAME' in namespace '$NAMESPACE'."
  exit 1
fi

# Ensure the export directory exists
mkdir -p "$EXPORT_DIR"

# Remove existing output file if it exists
if [ -f "$OUTPUT_FILE" ]; then
  rm "$OUTPUT_FILE"
fi

# Export GitRepository to YAML file
echo "Exporting GitRepository to $OUTPUT_FILE..."
flux create source git "$APP_NAME" \
  --namespace="$NAMESPACE" \
  --url="$GIT_URL" \
  --branch="$GIT_BRANCH" \
  --interval=1m0s \
  --secret-ref="$APP_NAME" \
  --export > "$OUTPUT_FILE"

# Export Kustomization and append to the same YAML file
echo "Appending Kustomization to $OUTPUT_FILE..."
flux create kustomization "$APP_NAME" \
  --namespace="$NAMESPACE" \
  --source="GitRepository/$APP_NAME" \
  --path="$KUSTOMIZATION_PATH" \
  --prune=true \
  --interval=1h0m0s \
  --retry-interval=2m0s \
  --timeout=3m0s \
  --wait=true \
  --export >> "$OUTPUT_FILE"

echo "
All resources have been exported to $OUTPUT_FILE for the '$ENVIRONMENT' environment.
"
