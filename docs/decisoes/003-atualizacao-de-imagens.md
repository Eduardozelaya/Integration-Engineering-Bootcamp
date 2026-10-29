# 003 — Atualização das imagens de terceiros (fixar e atualizar de propósito)

**Situação:** decidida e implementada (26/10).

## Contexto
Desde 26/10 nenhuma imagem de terceiros do lab usa `latest`: o MQ e o WireMock estão fixados por digest.
Fixar protege de mudanças inesperadas, mas também **congela** as vulnerabilidades. A pergunta: como atualizar
de propósito, e como impedir que uma falha **nova** passe calada?

## Medições (26/10)
| Imagem | Base | Varredura do ECR | Trivy 0.76.1 | Com correção publicada |
| --- | --- | --- | --- | --- |
| WireMock 3.13.2 | Ubuntu 26.04 | 21 CRITICAL, 103 HIGH | 0 CRITICAL, 26 HIGH | todas |
| MQ 10.0.0.0 (dev) | Red Hat 10.2 | — | 7 CRITICAL, 84 HIGH | todas |

- **A nota depende da fonte:** o ECR se apoia na nota geral (NVD); o Trivy, na da distribuição. A mesma imagem
  teve 21 críticas num e 0 no outro. Uma regra de bloqueio precisa dizer qual scanner e qual fonte usa.
- **Achados não são problemas:** as 7 críticas do MQ são **uma** CVE (CVE-2026-8763) em 7 pacotes; as 21 do ECR,
  ~10 CVEs em 5 componentes.
- **Atualizar não resolve hoje:** o `latest` do WireMock ainda é a 3.13.2 (mesmo digest); o MQ depende da IBM.

## Opções
| Opção | Custo |
| --- | --- |
| esperar o fornecedor refazer a imagem | nenhum, mas o risco fica até lá |
| refazer a imagem (FROM ...@digest + atualizar os pacotes do sistema) | corrige, mas passa a ser uma imagem nossa para manter |
| aceitar o risco, documentado e com prazo | nenhum; exige revisão periódica |

## Decisão
1. **Dependabot** semanal (`.github/dependabot.yml`): compose, manifests do Kubernetes, Dockerfile do ACE e
   actions. Cada versão nova vira um pull request, validado pelo CI e aceito de propósito.
2. **Trivy no CI** (versão fixada por digest): reprova se uma imagem de terceiros do compose tiver uma crítica
   **com correção** que **não** esteja aceita. As altas são só relatadas.
3. **Aceitação com prazo** (`.trivyignore`): CVE-2026-8763 do MQ, até 31/12/2026. Contexto: laboratório, imagem
   de desenvolvedor, sem exposição externa nem dados reais. Ao vencer, o CI fica vermelho e obriga a revisar.
4. As 26 altas do WireMock ficam aceitas pelo mesmo contexto; imagem própria corrigida fica como alternativa.

## Calibração (26/10)
COM a lista: MQ exit 0, WireMock exit 0. SEM a lista: MQ exit 1. (Uma primeira calibração mediu o `$?` do `cut`
dentro do `echo`, e não o do Trivy: corrigida guardando o código logo após o comando.)

## Consequências
- Uma crítica nova (numa imagem atualizada ou num CVE recém-publicado) deixa o CI vermelho.
- O MQ é referenciado só pelo digest, sem tag: o Dependabot não consegue comparar versões dele. Próximo passo:
  usar `imagem:tag@digest`, como já é o caso do WireMock.
- O Trivy baixa o banco de vulnerabilidades a cada execução do CI: o job depende da disponibilidade dele.

## Primeiros PRs do Dependabot (26/10)
- **checkout v5 → v7** (PR #2): o CI rodou os 5 jobs com a v7 antes do merge. Coberto pelo CI.
- **Ubuntu 22.04 → 25.10 no Dockerfile do ACE** (PR #1): aceito **sem** teste local; o CI público não constrói
  a imagem do ACE (ADR 002), então o verde do PR não dizia nada sobre ela. Testado depois do merge: build ok,
  ACE inicia, teste final 14 = 9/9 (~144 s).
- **Mas 25.10 é uma versão intermediária** (suporte de ~9 meses), não LTS: o Dependabot escolhe a maior versão
  e não distingue. Próximo: `ubuntu:26.04` (LTS) fixada por digest, e o Dependabot ignorando as intermediárias.
- **Regra acrescentada:** PR do Dependabot que mexe no Dockerfile do ACE só é aceito depois de
  `build-ace-image.sh` + teste final local. Para o resto, o CI verde basta.

## Base do ACE: Ubuntu 26.04 LTS por digest (27/10)
- `FROM ubuntu:26.04@sha256:19fcd1bf...` (Ubuntu 26.04.1 LTS). O Dependabot passa a ignorar saltos de versao
  do Ubuntu (major e minor) no `ace/docker`: propoe so digests novos da 26.04 (as correcoes). Trocar de LTS e
  decisao humana, com build + teste final local.
- Prova: build ok, BIP1991I sem erro de biblioteca, `Ubuntu 26.04.1 LTS` dentro do container, teste final 16 = 9/9.
- Tropeco: um comentario na mesma linha do `FROM` quebrou o build ("FROM requires either one or three
  arguments"); o bloco nao parou, o compose religou o container antigo (25.10) e o teste passou sobre a base
  errada. Pego pela conferencia do `/etc/os-release`. A execucao 15 foi descartada. Desde entao, o teste so roda
  com travas: codigo do build pelo PIPESTATUS, `--force-recreate`, e o sistema do container conferido antes.

## As travas viraram script (28/10)
`scripts/testa-imagem-ace.sh <N>`: recusa um numero de execucao ja usado; le a base esperada do Dockerfile;
constroi a imagem sem pipe (o `set -e` ve a falha do build direto); recria o container; confere o
`/etc/os-release` antes do teste final. Calibrado: sem argumento, recibo 1 com a mensagem de uso; com o 16
(ja existe), "PARADO" e recibo 1. E o caminho para testar um PR do Dependabot no Dockerfile do ACE.
