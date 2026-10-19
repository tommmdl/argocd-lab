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

## Acompanhar as requisições

O [tracing-lab](https://github.com/tommmdl/tracing-lab) adiciona uma imagem instrumentada com OpenTelemetry. A opção fica em `workloads/notes-traced`; os manifestos básicos continuam em `workloads/notes`. Construa e carregue a imagem primeiro e use o script `scripts/argocd.sh` daquele projeto para escolher a opção. Reaplicar `notes/application.yaml` volta à aplicação básica.

Os digests das imagens agora incluem a primeira rodada de correções na API e no PostgreSQL. O banco continua na versão 17 e no Bookworm; mudam o auxiliar gosu e suas dependências Go. A API atualiza Flask/liblzma e remove da execução as ferramentas de instalação do pip. Veja os [relatórios completos de antes e depois](https://github.com/tommmdl/security-lab/blob/main/docs/remediation.md). Os achados restantes continuam bloqueando o gate de segurança separado.

Validação das correções: 23 testes do Compose, restauração controlada de três notas da imagem original do PostgreSQL para a recompilada e 19 testes locais de tracing. A aplicação do Argo CD está Synced/Healthy e mantém o mesmo PVC. As evidências completas e as pendências estão no link acima.

A [análise dos críticos do PostgreSQL](https://github.com/tommmdl/security-lab/blob/main/docs/postgresql-critical.md) remove o SQLite sem uso e limita a conta da aplicação. Volumes existentes exigem execução explícita do `lab-db-harden` depois da troca de imagem; os hooks não se repetem. Neste lab Kubernetes, use `bash scripts/harden-db.sh` no checkout do kubernetes-lab depois de salvar backups dos dados/objetos globais/HBA. A manutenção passa a usar `psql -U notes_admin -d notes` pelo socket Unix do container do banco. Dois achados críticos continuam visíveis e bloqueando.

Depois da análise dos críticos do PostgreSQL, a API usa uma conta SQL comum e a imagem do banco fica sem SQLite. A aplicação está saudável; passaram 24 testes de Kubernetes e 19 de tracing no CI. A [análise completa](https://github.com/tommmdl/security-lab/blob/main/docs/postgresql-critical.md) mantém os dois críticos restantes e seus limites visíveis.
