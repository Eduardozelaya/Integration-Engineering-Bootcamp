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
./scripts/teste-final.sh 12   # um número LIVRE: o script sobrescreve execucao-N
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
kubectl create configmap ace-sonda -n lab --from-file=pronto.sh=infra/k8s/sonda/pronto.sh   # sonda honesta (ADR 001)
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

## Teste real: notebook secundário (18/10)
Recriado do zero até o MQ saudável, sem nenhum arquivo copiado do lab original.
- **Sem `.wslconfig`**, o WSL já usa metade da RAM: 6,6 GiB num notebook de ~13 GB. O arquivo é dispensável aqui.
- **Docker Desktop (24.0.7) com a WSL integration ligada** no lugar do Engine: nada instalado no sistema,
  desfaz-se com um interruptor. Compose v2.23.3 e buildx v0.12.0 bastam (depends_on por saúde, contextos nomeados).
- `jq` e `shellcheck` não vinham instalados: `sudo apt-get install -y jq shellcheck`.
- Máquina emprestada: tudo numa pasta só (`~/provisorio`), com um `env.sh` carregado em cada terminal
  (chave SSH própria via `GIT_SSH_COMMAND`, `KUBECONFIG`, `ACE_DIR`, `MQC_DIR`) e uma lista de limpeza.
  A chave SSH vai no repositório (`git config core.sshCommand`), não só no `env.sh`: uma aba sem o `source` não a usa (push recusado em 18/10). O autor do git é configurado só no repositório, copiado do último commit (`git log -1 --format=%ae`).
- Marco 1: volume NOVO, `up.sh` com `authorities.mqsc`, 9 filas, BOTHRESH(3)/BOQNAME e permissões do app
  idênticas às do CI. Download das imagens: ~4 min.
- **Marco 2 (18/10): teste final 9/9 (~146 s) no notebook secundário**, com a imagem do ACE construída nele
  (Docker Desktop 24.0.7, buildx 0.12). Reprodutibilidade provada: só o repositório, um `.env` novo e
  downloads públicos. Evidência: `docs/evidencias/teste-final/maquina-nova-1.txt`.
- **Atenção ao número da execução:** o `teste-final.sh N` grava em `execucao-N*` e **sobrescreve** a
  evidência histórica de mesmo número. Numa máquina nova, usar um número livre (o próximo era o 12).
- **Kubernetes no notebook secundário: o cluster não sobe (18/10).** O `kind create` baixou o nó
  (kindest/node v1.37.0), mas a API nunca abriu. Causa, pelo log do kubelet (`kind create --retain` +
  `journalctl -u kubelet`): `failCgroupV1: true` — "kubelet is configured to not run on a host using
  cgroup v1". A máquina usa **cgroup v1** (`/sys/fs/cgroup` em `tmpfs`; Docker Desktop 24.0.7 com
  `Cgroup Version: 1`; kernel do WSL 5.15.133). **Pré-requisito do passo 5: cgroup v2.** Conferir antes:
  `stat -fc %T /sys/fs/cgroup/` deve dar `cgroup2fs`. Contorno temporário a testar: `failCgroupV1: false`
  num arquivo de cluster separado (só a config do kubelet muda; o v1 está em fim de vida).
- **Marco 3 (19/10): teste final 9/9 (~144 s) no kind do notebook secundário, com cgroup v1.** Contorno:
  `infra/kind/cluster-cgroupv1.yaml` (`kubeadmConfigPatches` com `failCgroupV1: false`); cluster em 39 s,
  `failCgroupV1: false` conferido em `/var/lib/kubelet/config.yaml`; MQ e ACE sem reinícios depois da carga.
  Evidência: `docs/evidencias/teste-final/maquina-nova-2-k8s.txt`.
- **`/tmp` do Debian 13 é `tmpfs` (RAM, 3,4 GB aqui):** o `kind load` do ACE (~3,6 GB) estourou com
  `no space left on device`. Solução: `export TMPDIR=$LAB/tmp` (no disco). O `kind load` levou 12 min
  com o Docker Desktop.
- **Intervalo entre "Available" e a leitura da fila:** nesta máquina, o ACE ficou `Available` (sonda de
  porta) alguns segundos antes de abrir a APP.IN (`IPPROCS(0)` logo depois, `(1)` 15 s depois): o caso
  da ADR 001, medido.
