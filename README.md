# Argo CD na prática

[English](README.en.md) · Português

A aplicação de notas já rodava no Kubernetes. Agora o Git passa a guardar o estado que o Argo CD deve manter: duas réplicas da API, PostgreSQL e as configurações do ambiente.

O exercício é simples: mudar a quantidade de réplicas diretamente no cluster e observar o que acontece. Com `selfHeal` desligado, o Argo percebe a diferença e deixa a mudança lá. Ligado, ele volta ao que está no Git.

## Rodar o laboratório

Deixe este repositório e o [kubernetes-lab](https://github.com/tommmdl/kubernetes-lab) lado a lado. No Kubernetes lab, execute `bash scripts/prepare.sh` e `bash scripts/lab.sh up`. É esse projeto que prepara o cluster `devops-notes`, o namespace e a senha local do banco.

Aqui, execute:

```bash
bash notes/setup.sh
python3 notes/verify.py
bash notes/k.sh -n argocd get application notes
```

O script usa o kubeconfig privado do projeto vizinho. Para outro caminho, defina `KUBERNETES_LAB_DIR`. A aplicação continua em http://localhost:8005.

Para abrir o painel, mantenha este comando rodando em outro terminal:

```bash
bash notes/k.sh -n argocd port-forward --address 127.0.0.1 svc/argocd-server 8006:443
```

Acesse https://localhost:8006, com usuário `admin`. O certificado é local e autoassinado. Consulte a senha apenas no seu terminal:

```bash
bash notes/k.sh -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

## O que observar

O teste espera a primeira sincronização terminar antes de provocar drift. Ele mantém três réplicas durante 30 segundos com self-heal desligado, liga a correção e espera voltar a duas. Depois repete o drift com a correção ligada e confere se o volume e uma nota criada pelo próprio teste sobreviveram. Ao final, remove essa nota e deixa self-heal ligado.

O resultado executado fica em [evidence/notes-self-heal.json](evidence/notes-self-heal.json). Esse registro corresponde ao commit indicado no próprio arquivo; ele não substitui uma nova execução no seu ambiente.

## Como as peças se encaixam

`notes/application.yaml` aponta para `workloads/notes` neste repositório. O AppProject permite somente este repositório, o namespace `notes-lab` e os tipos usados pela aplicação. O banco e sua configuração entram primeiro; um Job de sincronização prepara a tabela na wave 1; a API entra na wave 2. A senha permanece fora do Git, criada pelo Kubernetes lab.

Os manifestos partem do kubernetes-lab no commit `af603c1`, mantendo imagens por digest, nomes, seletores e volume. O Job faz `CREATE TABLE IF NOT EXISTS`; não é um sistema de migrações versionadas. O volume existente é adotado sem recriar o banco. `prune` fica desligado: remover um arquivo do Git não apaga automaticamente o recurso.

Depois da adoção, altere a aplicação por este repositório. Executar novamente os scripts de deploy ou de escala do Kubernetes lab pode disputar o estado com o Argo CD. Kubernetes repõe Pods apagados; Argo CD corrige diferenças entre os manifestos no Git e os recursos no cluster. São mecanismos diferentes.

Para pausar o gerenciamento sem apagar a aplicação:

```bash
bash notes/k.sh -n argocd delete application notes
```

Essa Application não tem finalizer de exclusão em cascata. Para remover todo o ambiente, use `bash scripts/lab.sh down` no Kubernetes lab: isso também apaga os dados do banco. Parar o port-forward apenas fecha o acesso ao painel.

## Os primeiros exercícios continuam aqui

A cópia encontrada no E: deu origem a este trabalho. O GitHub já tinha avanços que ela ainda não tinha recebido; a integração parte dessa versão mais recente, preservando o histórico. Os exemplos de Nginx continuam em `base`, `overlays`, `apps` e `appsets`, com seus [guias originais](docs/nginx-lab.md), [comandos em português](COMANDOS.md) e [em inglês](COMMANDS.md).

Os scripts `scripts/` e a pipeline existente continuam voltados ao Nginx, em um cluster separado chamado `lab`, com Argo CD v3.5.3. A integração de notas usa `notes/`, o cluster `devops-notes` e Argo CD v3.5.5. Os testes de notas registrados foram executados localmente; a pipeline valida os manifestos de notas, mas não executa esse teste de self-heal.

É um ambiente de estudo local, sem autenticação na aplicação de notas nem estrutura de produção. A instalação padrão do Argo CD tem permissões amplas no cluster; o AppProject restringe esta Application, não a instalação inteira. A configuração e os testes foram feitos com ajuda do assistente.

Referências: [instalação](https://argo-cd.readthedocs.io/en/stable/getting_started/) e [sincronização automática e self-heal](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/).
