# Runbook — recriar o lab numa máquina nova

Objetivo: do zero ao teste final 9/9, usando só o repositório e downloads públicos.
O Toolkit NÃO é necessário: o BAR é gerado do git pelo `ibmint` (P5-0).

## 0. Pré-requisitos da máquina
- Windows com WSL2 e Debian. `.wslconfig` em `C:\Users\<voce>\.wslconfig`: `memory=4GB` com 8 GB de RAM;
  `memory=6GB` com 12 GB (o notebook secundário). Arquivo, não pasta (armadilha de 16/09).
- Docker Engine dentro do WSL (não o Docker Desktop), git, jq, shellcheck, curl.
- Chave SSH para o GitHub: `ssh-keygen -t ed25519` e a chave pública em github.com/settings/keys.

## 1. Repositório e segredos
```bash
git clone git@github.com:Eduardozelaya/Integration-Engineering-Bootcamp.git ~/integration-lab
cd ~/integration-lab && cp .env.example .env
```
- Preencher o `.env` com senhas **novas** (`openssl rand -hex 8`, uma para admin, outra para app).
  O `.env` nunca vai para o git; cada máquina tem as suas.

## 2. MQ (sem ACE): o primeiro marco
```bash
./scripts/up.sh          # termina com '2 MQSC commands read' (authorities.mqsc)
```
Conferir: `docker ps` com `qm1 (healthy)`.

## 3. ACE para Linux (sem Toolkit)
- Baixar **12.0.12.27-ACE-LINUX64-DEVELOPER.tar.gz** (2.495.915.610 bytes) em
  ibm.com/resources/mrs/assets?source=swg-wmbfd (IBMid; mesma versão do lab).
- Extrair em `~/ace`; `sudo ./ace make registry global accept license silently`;
  `sudo usermod -aG mqbrkrs "$USER"` e **`wsl --shutdown`** (o grupo só vale depois disso).
- Cliente MQ **9.4.0.26** (LTS, pelo nome, não "o mais recente"):
  public.dhe.ibm.com/ibmdl/export/pub/software/websphere/messaging/mqdev/redist/9.4.0.26-IBM-MQC-Redist-LinuxX64.tar.gz
  extraído em `~/mqclient`.

## 4. Imagem do ACE e o teste final no compose
```bash
./scripts/build-ace-image.sh                 # ~5-10 min; imagem de ~1,6 GB comprimida
docker compose --profile ace up -d ace
./scripts/teste-final.sh 1
```
Critério: **9/9 PASSOU, ~144 s** (o limite de 1 tps do modo developer).

## 5. Kubernetes
- `kubectl` e `kind` em `~/.local/bin`, conferidos por sha256 (ver P5-4a); `~/.local/bin` no PATH.
- Com 4 GB no WSL, parar o compose antes; com 6 GB, os dois cabem.
```bash
kind create cluster --config infra/kind/cluster.yaml && kubectl create namespace lab
# Secret (do .env) e ConfigMap (dos .mqsc): ver docs/evidencias/p5-4b-mq-no-cluster.txt
kubectl apply -f infra/k8s/mq.yaml
kind load docker-image integration-lab/ace:12.0.12.27-dev --name lab
kubectl apply -f infra/k8s/ace.yaml
```
Teste no cluster: `kubectl port-forward -n lab pod/mq-0 1414:1414 9443:9443 &` e
`MQ_EXEC="kubectl exec -i -n lab mq-0 --" ./scripts/teste-final.sh N`.

## Armadilhas já conhecidas
| Sintoma | Causa | Solução |
| --- | --- | --- |
| `BIP2164E Permission denied` em `/var/mqsi` | grupo `mqbrkrs` não ativo | `wsl --shutdown` |
| script para em silêncio ao carregar o ACE | `mqsiprofile` recusa repetição sob `set -e` | já tratado nos scripts |
| `BIP2684E` (MQ libraries not available) | falta o cliente MQ | passo 3 |
| `cp: cannot create hard link` | arquivos de dono root | já tratado (contextos nomeados do BuildKit) |
| `/tmp` vazio depois de reiniciar | o `/tmp` do WSL é temporário | o que importa vai para `docs/evidencias/` |
| colar comandos com o prompt | o `>` da linha apaga arquivos | colar só os comandos |

## Versões do lab original (17/10)
- WSL/Debian:  "Debian GNU/Linux 13 (trixie)"
- Docker:      29.8.1
- ACE:         ace-12.0.12.27
- cliente MQ:  9.4.0.26
- kubectl:     v1.37.1
- kind:        v0.33.0
- terraform:   Terraform v1.16.5
- imagem MQ:   sha256:2cb02e7991ac9fc44d10ba4e353abdc1402ec1667243b74a4574df5f274d7907
