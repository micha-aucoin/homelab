#!/bin/bash
################################################################
# The goal of the script is to be a workflow for creating / configuring
# Flux resources that point to a remote git repository for a Git-based 
# deployment in a Kubernetes cluster.
#
# Workflow:
# 1. create kind cluster
#    `kind create cluster -n kind`
#
# 2. clone git repository
#    `git clone git@github.com:fluxcd/flux2-kustomize-helm-example.git ~/.config/flux-example`
#
# 3. The script takes a single argument that points to the cluster
#    where you want the yaml-file/flux-resource to be created.
#    it will check if ~/.config/homelab/clusters/<arg> exists.
#
# 3. The script creates a Git authentication secret for
#    connecting to the specified Git repository.

# 4. It generates Flux GitRepository and Kustomization resources,
#    exporting them as a single YAML file in the specified
#    export directory. This YAML file can then be applied
#    to set up or update the environment.
#
# The output directory structure is designed as follows:
#
# homelab
# ├── apps
# │
# ├── clusters
# │   ├── production
# │   │   ├── apps.yaml
# │   │   ├── flux-system
# │   │   ├── homelab-vault.yaml <- this script will create a yaml file that
# │   │   │                         Points to a Git repository, I have it set
# │   │   │                         up for my homlab-vault repo.
# │   │   └── infrastructure.yaml
# │   │
# │   └── staging
# │     ├── apps.yaml
# │     ├── flux-system
# │     ├── homelab-vault.yaml
# │     └── infrastructure.yaml
# │
# └── infrastructure
#     ├── configs
#     └── controllers
#
# Notes:
# - Ensure Flux is installed and accessible in your Kubernetes environment.
# - SSH access must be configured for the Git repository to use the specified private key.
# - The script will prompt you to confirm the export directory before proceeding.
#
################################################################


# Config
################################################################
# The Kubernetes namespace where Flux resources will be created
NAMESPACE="flux-system"
################################################################
# The name of the application and resources in Flux
APP_NAME="homelab-vault"
################################################################
# The URL for the Git repository used as a source
GIT_URL="ssh://git@github.com/micha-aucoin/homelab-vault.git"
################################################################
# Path to the private SSH key for authenticating with the Git repository
PRIVATE_KEY_FILE="$HOME/.ssh/grub"
################################################################
# base path to the kustomization file for flux
BASE_PATH="./sealed-secrets"
################################################################
# Git branch to be used for syncing with Flux
GIT_BRANCH="master"
################################################################
# Interval for Flux to check for source updates
INTERVAL="1m0s"
################################################################
# Retry interval if an error occurs when syncing the Kustomization
RETRY_INTERVAL="2m0s"
################################################################
# Timeout for the Kustomization process
TIMEOUT="3m0s"
################################################################


# Functions
################################################################
find_cluster_paths_bg() {
    temp_file=$(mktemp)

    find ~/ -path '*/clusters/*' -type d \
    | grep -v '.local' \
    | sed 's|/clusters/\(.*\)/.*|/clusters/\1|' \
    | sort -u \
    > $temp_file &

    pid=$!

    echo "$temp_file $pid"
}

# Create Git authentication secret
create_git_secret() {
    echo "Creating Git authentication secret..."
    flux create secret git "$APP_NAME" \
        --namespace="$NAMESPACE" \
        --url="$GIT_URL" \
        --private-key-file="$PRIVATE_KEY_FILE" 

    if kubectl -n "$NAMESPACE" get secret "$APP_NAME" >/dev/null 2>&1; then
        echo "Secret '$APP_NAME' created successfully in namespace '$NAMESPACE'."
    else
        echo "Failed to create secret '$APP_NAME' in namespace '$NAMESPACE'."
        exit 1
    fi
}

# Export GitRepository to YAML file
export_git_repository() {
    echo "Exporting GitRepository to $CLUSTER_PATH/$APP_NAME..."
    flux create source git "$APP_NAME" \
        --namespace="$NAMESPACE" \
        --url="$GIT_URL" \
        --branch="$GIT_BRANCH" \
        --interval="$INTERVAL" \
        --secret-ref="$APP_NAME" \
        --export > "$CLUSTER_PATH/$APP_NAME.yaml"
}

# Export Kustomization and append to YAML file
export_kustomization() {
    echo "Appending Kustomization to $CLUSTER_PATH/$APP_NAME.."
    flux create kustomization "$APP_NAME" \
        --namespace="$NAMESPACE" \
        --source="GitRepository/$APP_NAME" \
        --path="$BASE_PATH/$(basename $CLUSTER_PATH)" \
        --prune=true \
        --interval=1h0m0s \
        --retry-interval="$RETRY_INTERVAL" \
        --timeout="$TIMEOUT" \
        --wait=true \
        --export >> "$CLUSTER_PATH/$APP_NAME.yaml"
}


# Main
################################################################
main() {
    RETURN=$(find_cluster_paths_bg)
    TEMP_FILE=$(echo $RETURN | awk '{print $1}')
    PID1=$(echo $RETURN | awk '{print $2}')

    create_git_secret &
    PID2=$!

    # wait $PID1 $PID2
    ps -e -o %p, -o lstart -o ,%C, -o %mem -o ,%c | head -1
    while ps -p $PID1 $PID2; do
        ps -e -o %p, -o lstart -o ,%C, -o %mem -o ,%c | grep $PID1
        ps -e -o %p, -o lstart -o ,%C, -o %mem -o ,%c | grep $PID2
        sleep 1
    done

    CLUSTER_PATH=$(fzf --prompt="Set Git Repository: " < $TEMP_FILE)
    rm -f $TEMP_FILE
    if [ -z "$CLUSTER_PATH" ]; then
        echo "nope!"
        exit 1
    fi

    # Remove existing output file if it exists
    [ -f "$CLUSTER_PATH/$APP_NAME.yaml" ] && rm "$CLUSTER_PATH/$APP_NAME.yaml"

    export_git_repository
    export_kustomization

    echo "All resources have been exported to $CLUSTER_PATH/$APP_NAME.yaml"
}
main

