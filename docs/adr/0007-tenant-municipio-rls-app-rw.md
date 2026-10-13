# ADR 0007 · O tenant é o município: RLS em toda tabela e aplicação como `app_rw`

- **Estado:** aceito (decisão 1 do plano da Fase 0, aprovado em 13/10/2026), com pontos a fechar na migração `0002`
- **Data:** 13/10/2026
- **Decisor:** Gabriel Onezio Ferreira

## Contexto

No schema de referência o tenant é a construtora e o órgão público é cliente dela. No Prumo é o contrário: quem usa o sistema é a prefeitura. O mesmo banco pode guardar mais de um município (questão 1: instalação por prefeitura e serviço hospedado, os dois previstos), e um município não pode ver nem alterar dado de outro, mesmo que a aplicação tenha um defeito.

A referência já trazia o mecanismo: coluna `tenant_id` em toda tabela, a função `app_tenant()` que lê o tenant da sessão, e uma política de RLS por tabela. Faltava o papel com que a aplicação conecta, que a referência só criava dentro do arquivo de teste.

## Decisão

1. **O tenant é o município.** Toda tabela de negócio tem `tenant_id` e RLS ligada, com política que compara `tenant_id` com o tenant da sessão, na leitura e na gravação.
2. **A aplicação conecta como `app_rw`**, ou como um papel de login que é membro dele. O papel não é dono de nada, não é superusuário, não tem `BYPASSRLS` e não cria objeto no schema. Por isso a RLS vale para ele sempre.
3. **`app_rw` só grava em tabela protegida por RLS.** Três exceções para menos: a trilha de auditoria só cresce (lê e acrescenta, não altera nem apaga); o cadastro de municípios é só leitura; o registro de migrações não é acessível.
4. **Visão roda com a permissão de quem consulta** (`security_invoker`) e **nenhuma função roda com a permissão do dono** (`SECURITY DEFINER`). As duas coisas passariam por cima da RLS.
5. **Sessão sem município não enxerga nem grava nada.** Tenant inválido na sessão dá erro, não acesso.
6. A API define `app.tenant_id` e `app.usuario` em toda sessão (Fase 1).

## Como se prova

Em `scripts/db-test.sh migracoes`, sobre PostgreSQL 16 real:

- `db/tests/estrutura.sql` confere as regras 1 a 4 no catálogo, sem dado nenhum. Uma migração futura que crie tabela sem `tenant_id`, sem RLS, sem política ou sem acesso para a aplicação faz o teste falhar.
- `db/tests/isolamento.sql` cria dois municípios fictícios com os mesmos cadastros, tudo gravado como `app_rw`, e prova: cada um só enxerga o que é seu em todas as tabelas, nas visões e nas funções de consulta; não grava com o tenant do outro; alterar ou apagar o que é do outro não atinge linha nenhuma; sem tenant na sessão nada aparece; e a aplicação não consegue alterar a auditoria, esvaziar tabela, desligar RLS, desligar gatilho, trocar função de regra nem ler o registro de migrações.
- `scripts/db-test.sh sabotagem` retira uma proteção por vez (22 casos) e exige que esses dois arquivos acusem.

## O que ainda não está fechado

| Ponto | Situação | Onde fecha |
|---|---|---|
| A tabela ainda se chama `tenant` e tem campos de empresa (razão social, CNPJ) | Porte fiel na `0001` | `0002` |
| `tenant` não tem RLS: a aplicação lê o nome e o CNPJ de todos os municípios do banco | Só leitura por enquanto | `0002` |
| **Chave estrangeira confere só o id.** Uma linha do município A pode apontar para um registro do município B, se alguém souber o id dele | Conferido em 13/10/2026: A criou contrato seu apontando para obra de B. A continua sem ler nada de B, mas a linha existe e impede B de apagar a própria obra | Questão 35; proposta: chave composta com `tenant_id`, na `0002` |
| O dono das tabelas ignora a RLS | É o papel que aplica migração e faz suporte. Quem tem essa senha vê tudo | Fase 1 e distribuição: senha fora da aplicação, acesso registrado |
| A API ainda não existe | Nada define `app.tenant_id` fora dos testes | Fase 1 |

## Alternativas descartadas

| Alternativa | Por que não |
|---|---|
| Um banco por município, sem RLS | Resolve o isolamento na instalação por prefeitura, mas não no serviço hospedado. A RLS serve aos dois e não atrapalha o primeiro |
| Filtrar por município só na aplicação | Um `WHERE` esquecido vaza dado de outra prefeitura. No banco a regra vale mesmo com defeito na aplicação |
| Um schema por município | Migração e manutenção multiplicadas pelo número de municípios |
| Forçar RLS também para o dono (`FORCE ROW LEVEL SECURITY`) | As migrações e os gatilhos de chave estrangeira rodam como dono; exigiria definir tenant em toda migração. Pode ser revisto na Fase 1 |

## Consequências

- Toda tabela nova precisa de `tenant_id`, política e concessão. O teste de estrutura cobra as três.
- Tabela sem `tenant_id` só entra com o nome numa lista explícita em `db/tests/estrutura.sql`, com o motivo.
- Consulta que cruza municípios (painel de um consórcio, por exemplo) não existe e não pode ser feita pela aplicação. Se um dia for necessária, é decisão nova.
