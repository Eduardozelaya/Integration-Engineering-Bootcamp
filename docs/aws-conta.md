# Conta AWS do lab

Nenhum segredo aqui: sem senhas, sem chaves, sem o número da conta e sem e-mails.

| Item | Situação |
| --- | --- |
| criação | 19/10/2026, **plano gratuito**: US$ 100 em créditos, 183 dias (até 19/04/2027); fecha sozinha ao fim |
| identidade | **AWS Builder ID**, login pelo **Google**; ao entrar, assume o papel `AccountFullAccessRole` |
| permissões do papel | `AdministratorAccess`, sem políticas embutidas, sem permissions boundary |
| organização | a conta é **membro** de uma organização alheia: uma SCP pode negar ações mesmo com `AdministratorAccess` |
| MFA da AWS | app autenticador (TOTP), testado no login |
| e-mail de recuperação | configurado (diferente do de login) |
| chaves de acesso de longa duração | **nenhuma** |
| linha de comando | `aws login --remote` (AWS CLI 2.38.5): credenciais temporárias, renovadas sozinhas; `aws logout` ao fim |
| região de trabalho | `us-east-2` (Ohio) |
| estado do Terraform | bucket S3 `integration-lab-tfstate-…` (versionado, privado, cifrado, trava nativa); `infra/aws` e o próprio `bootstrap` migrados; nenhum estado local |
| alerta de gastos | **orçamento `lab-gasto-zero-sns` pelo Terraform (`infra/aws`)**, avisando por tópico SNS com e-mail confirmado; o do console ficou com o e-mail Inactive (SCP nos contatos de notificação) |
| proteção atual | custos só nos créditos; avisos do plano em 50%, 25% e 10% dos créditos |

## Lições
- **"Íntegro" não é funcionando:** o orçamento existia e não avisaria ninguém.
- **IAM × SCP:** o erro "no identity-based policy allows" é do IAM (resolvível no papel); "explicit deny in a
  service control policy" vem da organização (não resolvível de dentro da conta).
- O código de autorização do `aws login` vale uma vez: não se cola em lugar nenhum.

## Próximo
Alerta do orçamento por tópico SNS, criado pelo Terraform (contorna a SCP dos contatos de notificação).

Regras: o que importa vive no git; a conta é descartável. Não clicar em "Atualizar" o plano.
