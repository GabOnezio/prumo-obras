# ADR 0006 · Migrações em SQL puro, numeradas e com registro de SHA-256

- **Estado:** aceito (decisão 2 do plano da Fase 0, aprovado em 13/10/2026)
- **Data:** 13/10/2026
- **Decisor:** Gabriel Onezio Ferreira

## Contexto

O banco parte de `db/reference/schema.sql`, um arquivo único escrito para o SaaS de uma construtora. O Prumo vai mudar esse schema em nove passos na Fase 0 e continuar mudando depois. Como o banco guarda medição e pagamento de obra pública, é preciso saber, em qualquer instalação, exatamente qual schema está aplicado, e provar que ele é o que foi testado.

O `CLAUDE.md` já exigia migrações em `db/migrations/NNNN_nome.sql`, imutáveis depois de publicadas. Faltava dizer como isso é garantido.

## Decisão

1. **SQL puro, um arquivo por migração**, em `db/migrations/NNNN_nome.sql`, com numeração sem saltos. O arquivo não tem `BEGIN` nem `COMMIT`: quem aplica abre a transação, roda o arquivo e grava o registro na mesma transação.
2. **Registro no repositório:** `db/migrations/SHA256SUMS` guarda o SHA-256 de cada migração. Migração registrada não muda; o que estiver errado é corrigido por uma migração nova. `scripts/db-test.sh` falha se um arquivo registrado mudar, se faltar o registro de um arquivo ou se houver salto na numeração. `scripts/db-test.sh registrar` só acrescenta linhas, nunca reescreve.
3. **Registro no banco:** a tabela `migracao_aplicada` guarda versão, nome, SHA-256 e a hora de cada migração aplicada. Aplicar de novo não faz nada. Se o arquivo estiver diferente do que foi aplicado, a aplicação para.
4. **A `0001` é o porte fiel da referência**, sem o que é só da construtora (14 tabelas, 2 visões, 4 tipos) e com um único acréscimo: o papel da aplicação (ADR 0007). Nenhuma regra muda nela. Mudança de sentido entra da `0002` em diante, cada uma com teste.
5. **Cada migração concede à aplicação o acesso das tabelas que cria.** Não há concessão automática para tabelas futuras.
6. **Os testes rodam sobre todas as migrações**, cada arquivo de `db/tests` numa cópia limpa do banco migrado, em PostgreSQL 16 real.

## Como se prova

| O quê | Como |
|---|---|
| A `0001` é igual à referência | `scripts/db-test.sh porte` compara o catálogo das duas, fato a fato (colunas, restrições, índices, funções, gatilhos, visões, tipos, políticas): 687 fatos, nenhum diferente. Depois roda o seed do engenheiro sobre a `0001` e exige os mesmos 12 bloqueios e os mesmos 26 números |
| Migração registrada não muda | Alterar um arquivo registrado faz o teste falhar (conferido em 13/10/2026) |
| Aplicar duas vezes não estraga | A suíte aplica de novo e exige zero migrações aplicadas |
| Arquivo diferente do aplicado é recusado | A suíte troca o SHA-256 gravado no banco e exige a recusa |
| Os testes pegam erro de verdade | `scripts/db-test.sh sabotagem` retira uma proteção por vez e exige que o teste acuse |

O seed do engenheiro roda sobre a `0001` com dois cortes feitos por máquina, sem reescrever nada: sai o bloco financeiro, cujas tabelas não existem mais, e sai a linha que cria o papel `app_rw`, que a `0001` já cria.

## Alternativas descartadas

| Alternativa | Por que não |
|---|---|
| Usar já o migrador do `sqlx` | O acesso ao banco pela aplicação é da Fase 1. Os nomes de arquivo seguem o formato que ele aceita, para a troca ser possível |
| Ferramenta externa de migração | Mais uma dependência para instalar na prefeitura, para fazer o que um script de 30 linhas faz |
| Deixar a `0001` editável até a primeira instalação | Perderia a prova de que o porte é fiel, que é o que sustenta os testes do engenheiro |
| Concessão automática de acesso a tabelas novas | Uma tabela criada sem RLS já nasceria gravável pela aplicação |

## Consequências

- Corrigir uma migração custa uma migração nova, mesmo antes da primeira instalação.
- Toda mudança em `SHA256SUMS` aparece no diff; linha alterada ou removida ali é sinal de alerta em revisão.
- **Ainda não existe quem aplique as migrações numa instalação real.** Hoje só o script de teste aplica. O aplicador da instalação é da Fase 1 e tem que respeitar a tabela `migracao_aplicada`, ou trocar de registro de forma explícita.
- Os testes não são imutáveis: quando uma migração nova muda um comportamento, o teste antigo é atualizado no mesmo commit.
