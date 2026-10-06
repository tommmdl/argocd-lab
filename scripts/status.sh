#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
lab_kubectl -n argocd get applications
for env in dev prod; do
  lab_kubectl -n "lab-$env" get deployments,pods,jobs
done
