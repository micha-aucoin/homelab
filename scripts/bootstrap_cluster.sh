#!/bin/bash
################################################################
# bootstrap a github repository with flux
#
# Workflow:
# 1. switch cluster context for flux deployment.
#    this name will be used in clusters/ dir.
# 2. search thru password-store for a github token.
#    assuming you have the standard unix password manager.
# 3. search thru remote git urls.
#    flux will map the cluster to the repo.
################################################################


# Functions
################################################################
set_cluster_context() {
  CLUSTER_NAME=$(kubectl config get-contexts -o name | fzf --prompt="Select cluster context: ")
  [ -z "$CLUSTER_NAME" ] && echo "Context ." && return 1
  kubectl config use-context "$CLUSTER_NAME"
  echo "Context switched to $CLUSTER_NAME."
}

find_gh_token() {
    find ~/.password-store -type f \
    | sed 's|^'"$HOME"'/.password-store/||; s|\.gpg$||' \
    | grep -v '^.git\|^.gpg'
}

find_gh_repo_bg() {
    local temp_file=$(mktemp)

    find ~/ -name ".git" -type d -prune | grep -v ".local\|.password-store" | while read repo; do
        repo_dir=$(dirname "$repo")
        remote_url=$(git -C "$repo_dir" remote get-url origin 2>/dev/null)
        if [ -n "$remote_url" ]; then
            echo "$remote_url" | sed 's|.*/\(.*\)\.git$|\1|'
        fi
    done > $temp_file &

    local pid=$!

    echo "$temp_file $pid"
}


# Main
################################################################
main() {
    set_cluster_context

    PASS=$(find_gh_token | fzf --prompt="Set Github Token: ")
    if [ -z "$PASS" ]; then
        echo "nope!"
        exit 1
    fi

    returnd=$(find_gh_repo_bg)
    temp_file=$(echo $returnd | awk '{print $1}')
    pid=$(echo $returnd | awk '{print $2}')
    echo "$temp_file $pid"

    echo "Searching for Git Repositories..."
    ps -e -o %p, -o lstart -o ,%C, -o %mem -o ,%c | head -1
    while ps -p $pid > /dev/null; do
        ps -e -o %p, -o lstart -o ,%C, -o %mem -o ,%c | grep $pid
        sleep 1
    done

    GITHUB_REPO=$(fzf --prompt="Set Git Repository: " < $temp_file)
    rm -f $temp_file
    if [ -z "$GITHUB_REPO" ]; then
        echo "nope!"
        exit 1
    fi

    read -p "Set Github User Name: " GITHUB_USER
    if [ -z "$GITHUB_USER" ]; then
        echo "nope!"
        exit 1
    fi

    flux check --pre
    if [ $? -ne 0 ]; then
        echo "nope!"
        exit 1
    fi

    export  GITHUB_TOKEN=$(pass $PASS)
    flux bootstrap github \
        --owner=${GITHUB_USER} \
        --repository=${GITHUB_REPO} \
        --branch=master \
        --personal \
        --path=clusters/${CLUSTER_NAME}
}
main

