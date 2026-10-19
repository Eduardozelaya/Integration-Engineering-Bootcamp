# 002 — O build do BAR no CI público

**Situação:** decidida e implementada (19/10). Encerra o P5-2.

## Contexto
O P5-2 queria que o GitHub Actions gerasse o BAR (e a imagem do ACE) a cada push, como faz com o MQ.
Três restrições impedem isso no repositório público:
- gerar o BAR exige o ACE instalado (`ibmint`, P5-0);
- o ACE para desenvolvedores só é baixado com login (IBMid): o runner não o obtém sozinho;
- a licença de desenvolvedor não permite redistribuir o produto (repositório nem imagem públicos).

## Opções
| Opção | Custo / risco |
| --- | --- |
| A. runner próprio (o WSL com o ACE) | pipeline depende do notebook ligado; em repositório **público**, um pull request de terceiros executaria código na máquina (uso desaconselhado pelo GitHub) |
| B. imagem do ACE num registro privado, baixada pelo CI com token | licença de desenvolvedor num registro fica em zona cinzenta; um registro tornado público por engano seria violação |
| C. imagem oficial da IBM no registro dela | exige chave de acesso paga (entitlement) |
| D. o CI valida o código de integração sem o produto; BAR e imagem gerados localmente pelo script | sem custo e sem risco; o BAR não vira artefato do CI |

## Decisão
**D no lab.** O job `ace-validacao` roda `scripts/valida-ace.sh` a cada push: XML bem formado
(msgflow, policyxml, descritores, .project), cada `computeExpression` do flow com o seu
`CREATE ... MODULE` no ESQL, e cada override de `ace/docker/container.properties` apontando para um
node que existe. O BAR e a imagem continuam saindo de `scripts/build-ace-image.sh`, a partir do commit.

**B numa empresa com licença:** registro interno com a imagem base do ACE e runners internos; o
pipeline gera o BAR e a imagem dentro dela. É o desenho real; no lab, a licença não o permite.

## Consequências
- Calibrado em 19/10: no código real, tudo ok; numa cópia com três estragos (XML quebrado, módulo
  renomeado, override para node inexistente), exatamente três falhas e exit 1.
- A checagem 3 pega o tipo de erro do P5-1b: um override que o ibmint aceita e que não tem efeito.
- O que o CI **não** pega: erros que só o ACE detecta (ESQL inválido, propriedades de node). Esses
  continuam dependendo do build local e do teste final.
