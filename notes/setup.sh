#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
bash notes/k.sh -n notes-lab get secret notes-db >/dev/null
bash notes/k.sh create namespace argocd --dry-run=client -o yaml | bash notes/k.sh apply -f -
bash notes/k.sh apply --server-side -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.5/manifests/install.yaml
for resource in deployment/argocd-server deployment/argocd-repo-server statefulset/argocd-application-controller; do
  bash notes/k.sh -n argocd rollout status "$resource" --timeout=300s
done
bash notes/k.sh apply -f notes/project.yaml -f notes/application.yaml
