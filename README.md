# argocd-lab

Laboratório mínimo de GitOps com ArgoCD e Kustomize, montado para observar na prática
o comportamento de reconciliação: o que acontece quando um recurso é alterado direto no
cluster, com e sem self-heal, e o que muda quando a alteração vem do Git.

## Estrutura

```
base/                  Deployment nginx e Service, com requests, limits e probes
overlays/dev/          namespace lab-dev, prefixo dev-, 1 réplica
overlays/prod/         namespace lab-prod, prefixo prod-, 3 réplicas, request de CPU maior
apps/app-dev.yaml      Application do ArgoCD, self-heal DESLIGADO
apps/app-prod.yaml     Application do ArgoCD, self-heal LIGADO
pratica/               manifestos de apoio: classes de QoS, pods em Pending, liveness ruim
COMANDOS.md            passo a passo completo
```

As duas Applications têm sync automatizado. A única diferença entre elas é o self-heal,
o que isola a variável e permite comparar os dois comportamentos lado a lado.

## O que o laboratório demonstra

**1. Drift sem self-heal.** Alterar réplicas na mão em `lab-dev` deixa a Application em
`OutOfSync`, e o ArgoCD não corrige. Ele acusa, mas não age.

**2. Drift com self-heal.** A mesma alteração em `lab-prod` é desfeita sozinha em
segundos. A reação é rápida porque o ArgoCD observa os recursos do cluster, sem depender
do ciclo de verificação do Git.

**3. Mudança pelo Git.** Commit e push alterando o overlay de prod é aplicado e mantido.

Mesmo comando, resultado oposto, conforme a origem da alteração e a configuração de
self-heal.

## Como rodar

Pré-requisitos: Docker, kind, kubectl.

```bash
kind create cluster --name lab
kubectl create namespace argocd
kubectl apply --server-side --force-conflicts -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
```

O `--server-side` é obrigatório: o CRD do ApplicationSet passa do limite de 262144 bytes
da annotation `last-applied-configuration` usada pelo apply client-side.

Senha inicial e interface:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
kubectl port-forward -n argocd svc/argocd-server 8080:443
```

Depois aplique as Applications e siga o `COMANDOS.md` para os experimentos de drift.

## Detalhes que só apareceram fazendo

**commonLabels do Kustomize.** Foi depreciado em favor de `labels` com
`includeSelectors: false`. O motivo é que o `commonLabels` injeta o label também no
selector do Deployment, e selector é imutável. Adicionar um label novo em algo que já
está em produção faz o apply falhar.

**Limit de CPU.** O Deployment define request de CPU e limit de memória, mas não limit de
CPU. Request garante escalonamento previsível, limit de memória protege o nó contra
vazamento, e limit de CPU causa throttling, que costuma piorar latência em serviço
sensível.

**Credential helper no WSL.** Sem `credsStore` definido, o Docker CLI no Linux procura um
binário `docker-credential-*` no PATH. O WSL concatena o PATH do Windows, e um helper do
Rancher Desktop encontrado por ali trava qualquer `docker pull`, inclusive o da imagem do
nó do kind.

## Limpeza

```bash
kind delete cluster --name lab
```
