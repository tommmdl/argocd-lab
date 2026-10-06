# Lab ArgoCD + Kustomize

Versão em inglês: [COMMANDS.md](COMMANDS.md)

## 1. Obter o repositório

Para os experimentos de leitura, clone este repositório. Para mudanças via Git (passo 6), use seu próprio fork e atualize as três referências repoURL antes de criar as Applications.

```bash
git clone https://github.com/tommmdl/argocd-lab.git
cd argocd-lab
```

Como alternativa, comece com um fork:

```bash
gh repo fork tommmdl/argocd-lab --clone
cd argocd-lab
sed -i 's#github.com/tommmdl/argocd-lab#github.com/YOUR_USER/argocd-lab#' apps/app-dev.yaml apps/app-prod.yaml appsets/lab.yaml
git commit -am "point apps to the fork"
git push
```

Troque YOUR_USER pelo seu usuário do GitHub. No macOS, use `sed -i ''` em vez de `sed -i`.

## 2. Instalar ferramentas e criar o lab

Pré-requisitos: Docker em execução, Bash, curl, tar, Python 3 e make (Linux, macOS ou WSL). As ferramentas são instaladas dentro do repositório. O setup cria o cluster e instala o ArgoCD; não cria as Applications. Os scripts sempre usam o contexto `kind-lab`. Use esse contexto explicitamente nos comandos abaixo.

```bash
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -r scripts/requirements.txt
make tools
export PATH="$PWD/.tools/bin:$PATH"
make validate
make setup
kubectl config use-context kind-lab
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
kubectl port-forward -n argocd svc/argocd-server 8080:443
```

## 3. Criar Applications e aguardar o primeiro sync

Execute em outro terminal com o mesmo PATH e contexto. Esperado: ambas as Applications Synced e Healthy, fase do sync Succeeded quando uma operação foi necessária, dev com 1 réplica e prod com 3. Uma Application nova OutOfSync pode fazer um sync automático mesmo com self-heal desligado: aguarde antes de testar drift. Workloads já iguais ao Git podem ficar Synced/Healthy sem histórico de operação.

```bash
kubectl apply -f apps/
make wait-sync
make status
```

## 4. Testar drift SEM self-heal

Esperado: lab-dev fica OutOfSync e mantém 5 réplicas. A detecção é assíncrona; aguarde o status em vez de consultá-lo imediatamente.

```bash
kubectl -n lab-dev scale deployment/dev-web --replicas=5
kubectl -n argocd wait application/lab-dev \
  --for=jsonpath='{.status.sync.status}'=OutOfSync --timeout=120s
kubectl -n lab-dev get deployment dev-web
```

## 5. Testar drift COM self-heal

Esperado: prod volta à quantidade de réplicas no Git (inicialmente 3). Se já a alterou no passo 6, use o novo valor no comando de espera.

```bash
kubectl -n lab-prod scale deployment/prod-web --replicas=9
kubectl -n lab-prod wait deployment/prod-web \
  --for=jsonpath='{.spec.replicas}'=3 --timeout=120s
kubectl -n lab-prod get deployment prod-web
```

## 6. Alterar via Git

No seu fork, altere o patch de réplicas em overlays/prod/kustomization.yaml de 3 para 5, valide, faça commit e push. Esperado: o ArgoCD aplica 5 réplicas e as mantém. Solicite um refresh para não aguardar o polling do Git; o sync automático faz a entrega.

```bash
make validate
git add overlays/prod/kustomization.yaml
git commit -m "prod to 5 replicas"
git push
kubectl -n argocd annotate application lab-prod argocd.argoproj.io/refresh=hard --overwrite
kubectl -n lab-prod wait deployment/prod-web \
  --for=jsonpath='{.spec.replicas}'=5 --timeout=300s
make wait-sync
```

## 7. Renderizar e validar sem cluster

A validação renderiza os dois overlays e confere workloads, manifests de prática, Applications e ApplicationSet. Os schemas do ArgoCD são extraídos dos CRDs da versão fixada. Schemas ausentes e campos desconhecidos falham a validação; os problemas de comportamento nos exemplos de prática continuam intencionais. Schemas não verificam o comportamento dos controllers nem a disponibilidade de recursos.

```bash
kubectl kustomize overlays/dev
kubectl kustomize overlays/prod
make validate
```

## 8. Usar ApplicationSet (opcional)

Use Applications ou ApplicationSet, um por vez. Restaure dev para 1 réplica antes da troca. As Applications manuais não têm finalizer de exclusão, então seus workloads permanecem. Aguarde as Applications geradas ficarem Synced/Healthy. Se os workloads preservados já correspondem ao Git, não há novo sync. Antes de testar drift, faça um sync explícito nas duas Applications para registrar a revisão atual; sem isso, o primeiro drift pode disparar um sync automático inicial mesmo com self-heal desligado. preserveResourcesOnDeletion mantém workloads ao excluir este ApplicationSet.

```bash
kubectl -n lab-dev scale deployment/dev-web --replicas=1
make wait-sync
kubectl -n argocd delete application lab-dev lab-prod
kubectl apply -f appsets/lab.yaml
make wait-sync
for app in lab-dev lab-prod; do
  kubectl -n argocd patch application "$app" --type merge -p '{"operation":{"sync":{}}}'
  kubectl -n argocd wait "application/$app" \
    --for=jsonpath='{.status.operationState.phase}'=Succeeded --timeout=300s
done
make wait-sync
make status
```

Para voltar às Applications manuais:

```bash
kubectl -n argocd delete applicationset lab
kubectl apply -f apps/
make wait-sync
```

## 9. Inspecionar sync waves e hooks

Um sync completo executa PreSync migrate → Service (wave 0) → Deployment (wave 1) → PostSync smoke-test. O smoke test chama o Service. Solicite um sync completo e aguarde uma nova operação começar e terminar antes de consultar seus resultados. O self-heal do drift de réplicas não reexecuta esses hooks; compare as datas de criação dos Jobs antes e depois de repetir o passo 5.

```bash
previous=$(kubectl -n argocd get application lab-dev -o jsonpath='{.status.operationState.startedAt}')
kubectl -n argocd patch application lab-dev --type merge -p '{"operation":{"sync":{}}}'
for attempt in {1..60}; do
  current=$(kubectl -n argocd get application lab-dev -o jsonpath='{.status.operationState.startedAt}')
  if [ "$current" != "$previous" ]; then break; fi
  sleep 2
done
[ "$current" != "$previous" ] || { echo "Sync did not start"; exit 1; }
bash scripts/wait-sync.sh lab-dev
kubectl -n argocd get application lab-dev \
  -o jsonpath='{range .status.operationState.syncResult.resources[*]}{.syncPhase}{"\t"}{.kind}{"\t"}{.name}{"\n"}{end}'
kubectl -n lab-dev get jobs
kubectl -n lab-dev logs job/dev-migrate
kubectl -n lab-dev logs job/dev-smoke-test
```

## Diagnóstico

Se uma espera expirar, confira status, eventos e logs dos hooks:

```bash
make status
kubectl -n argocd get application lab-dev -o yaml
kubectl -n lab-dev get events --sort-by=.metadata.creationTimestamp
kubectl -n lab-dev logs job/dev-migrate
kubectl -n lab-dev logs job/dev-smoke-test
```

O setup reutiliza um cluster chamado lab se já existir; ele não atualiza os nodes existentes. Para reproduzir a versão fixada, use um cluster novo. Sem make, execute o comando `bash scripts/*.sh` correspondente no Makefile.

## Limpeza

Isso exclui o cluster do lab e seus workloads.

```bash
.tools/bin/kind delete cluster --name lab
```
