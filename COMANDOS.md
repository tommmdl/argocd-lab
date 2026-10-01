# Lab ArgoCD + Kustomize

## 1. Obter o repositorio
Os passos 1 a 5 funcionam apontando para github.com/tommmdl/argocd-lab em modo
leitura: o repoURL dos apps/ ja aponta para ele e o ArgoCD so precisa clonar.
git clone https://github.com/tommmdl/argocd-lab.git
cd argocd-lab

O passo 6 (mudanca via Git) exige push, entao precisa de fork proprio, com o
repoURL dos apps/ apontando para ele:
gh repo fork tommmdl/argocd-lab --clone
cd argocd-lab
sed -i 's#github.com/tommmdl/argocd-lab#github.com/SEU_USUARIO/argocd-lab#' apps/app-dev.yaml apps/app-prod.yaml appsets/lab.yaml
git commit -am "aponta apps para o fork" && git push
# se as Applications ja foram criadas, reaplique: kubectl apply -f apps/

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

## 8. Mesmo lab com ApplicationSet (opcional)
# appsets/lab.yaml gera lab-dev e lab-prod a partir de um template;
# substitui as duas Applications de apps/, use um ou outro
kubectl -n argocd delete application lab-dev lab-prod
# as Applications de apps/ nao tem finalizer, entao os workloads ficam
kubectl apply -f appsets/lab.yaml
kubectl -n argocd get applicationset lab
kubectl -n argocd get applications
# espere Succeeded antes de repetir os passos 4 e 5: Application nova faz um
# auto-sync inicial mesmo sem self-heal, e isso desfaria o drift do lab-dev
kubectl -n argocd get application lab-dev -o jsonpath='{.status.operationState.phase}'; echo
# para voltar (preserveResourcesOnDeletion mantem os workloads):
kubectl -n argocd delete applicationset lab
kubectl apply -f apps/
