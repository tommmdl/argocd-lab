# Lab ArgoCD + Kustomize

## 1. Publicar este diretorio como repositorio publico
cd argocd-lab
git init && git add . && git commit -m "lab argocd kustomize"
gh repo create argocd-lab --public --source=. --push
# sem gh: crie o repo no GitHub e faca git remote add origin + git push -u origin main

Depois troque TROQUE_PELA_URL_DO_SEU_REPO nos dois arquivos de apps/.

## 2. Cluster e ArgoCD
kind create cluster --name lab
kubectl create namespace argocd
kubectl apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
# server-side obrigatorio: o CRD applicationsets estoura o limite de 262144 bytes
# da annotation last-applied-configuration usada pelo apply client-side
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
kubectl port-forward -n argocd svc/argocd-server 8080:443

## 3. Criar as duas Applications
kubectl apply -f apps/app-dev.yaml
kubectl apply -f apps/app-prod.yaml
kubectl -n argocd get applications

## 4. Testar drift SEM self-heal (lab-dev)
kubectl -n lab-dev scale deploy/dev-web --replicas=5
kubectl -n argocd get application lab-dev -o jsonpath='{.status.sync.status}'; echo
# OutOfSync: o ArgoCD acusa mas nao corrige

## 5. Testar drift COM self-heal (lab-prod)
kubectl -n lab-prod scale deploy/prod-web --replicas=9
sleep 25
kubectl -n lab-prod get deploy prod-web
# volta para 3 sozinho

## 6. Testar mudanca via Git (o fluxo correto)
# edite overlays/prod/kustomization.yaml -> replicas 5
git commit -am "prod para 5 replicas" && git push
# o ArgoCD reconcilia sozinho em ate 3 minutos, ou force:
kubectl -n argocd patch application lab-prod --type merge -p '{"operation":{"sync":{}}}'

## 7. Ver o que o Kustomize gera, sem cluster
kubectl kustomize overlays/dev
kubectl kustomize overlays/prod
