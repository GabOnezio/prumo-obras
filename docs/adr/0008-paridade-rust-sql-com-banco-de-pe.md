# ADR 0008 · Paridade Rust × SQL conferida com o banco de pé; conta de dinheiro em inteiros

- **Estado:** aceito (decisão 3 do plano da Fase 0, aprovado em 13/10/2026)
- **Data:** 13/10/2026
- **Decisor:** Gabriel Onezio Ferreira

## Contexto

A mesma conta existe em dois lugares. O Rust calcula o que a tela mostra e o que os relatórios imprimem; o banco recalcula nos gatilhos, como última defesa. Se os dois derem centavos diferentes, o banco recusa o que a aplicação gravou, ou, pior, um relatório mostra um valor e o banco guarda outro.

A regra já existia ("Rust e SQL devem dar o mesmo centavo"). Faltava o teste, e faltava decidir onde ele mora, porque `crates/dominio` não pode falar com banco.

## Decisão

1. **A paridade é conferida contra o banco de verdade**, não contra uma cópia da fórmula. O teste manda as entradas ao PostgreSQL, lê o resultado do SQL e compara com o do Rust.
2. **Os testes ficam num crate separado, `crates/paridade`**, que não tem código de produção. O `dominio` continua puro.
3. **Todos os testes de paridade são `#[ignore]`.** Só rodam em `scripts/db-test.sh paridade`, que sobe o banco com as migrações e o seed e informa o endereço em `PRUMO_PARIDADE_URL`. `cargo test` sem banco mostra os testes como ignorados, e não como aprovados. O script exige um número mínimo de testes rodados, para um filtro errado não passar por sucesso.
4. **Os números vão e voltam do banco como texto.** Nada passa por ponto flutuante nem depende de conversão binária de `NUMERIC`.
5. **O teste conecta como a aplicação:** papel `app_rw`, com o município na sessão.
6. **A conta de valor de item no Rust é feita em inteiros.** `valor_item` e `percentual` multiplicam os inteiros dos dois números e arredondam em inteiro. O resultado é o exato, igual ao do `NUMERIC` do PostgreSQL, ou é erro (`Estouro`). Nunca um valor aproximado.

### Por que a decisão 6

O tipo decimal do Rust guarda 28 dígitos. Quando o produto exato de quantidade por preço passa disso, a multiplicação dele descarta as últimas casas sem avisar. O PostgreSQL não descarta. Com as colunas do banco (`NUMERIC(18,4)` × `NUMERIC(18,4)`) o produto exato pode ter até 36 dígitos. Em contrato real isso não acontece, mas a regra do projeto é que número errado não passa em silêncio: com a conta em inteiros, o que não cabe vira erro.

## O que está conferido hoje

| Paridade | Como |
|---|---|
| `valor_item` × `fn_valor_item` | 25 casos escolhidos à mão e 10.000 pares sorteados com semente fixa, nos dois critérios: 20.050 comparações. 2.149 pares caem em meio centavo exato; um em cada dez sorteados tem quantidade negativa |
| `Evento::valor` × `fn_recalcular_eventos` | 12 contratos sorteados, 10 serviços repartidos em até 4 frentes, 2 e 4 casas no preço, dois critérios: 121 eventos. Confere também o valor da planilha e o valor bruto de uma medição com todos os eventos |
| Seed fictício × prévia de desktop | Os 6 eventos e os 16 serviços do contrato 045/2026, campo a campo, e o total de R$ 164.039,34 no banco, no Rust e na prévia |
| Aditivo e boletim de medição, num contrato do começo ao fim | 12 contratos sorteados: Rev. 0, medição 1, aditivo 1 (acréscimo, supressão, item novo), limites simulados, homologação com a Rev. 1 calculada em Rust e aceita pelo banco, medição 2, aditivo 2 simulado com restabelecimento. Iguais: 324 linhas de `fn_boletim_medicao`, 60 itens de aditivo, `fn_limites_aditivos` nas três situações, o total de cada revisão |
| `fator_art127` × a coluna do banco | 10.013 pares, com casos de meio exato na nona casa |
| Percentual executado e preço de item novo | 10.002 percentuais e 10.000 preços; 2.000 e 3.000 deles em meio exato |

Para saber se os testes pegam erro, as contas em Rust foram estragadas de propósito duas vezes. Com o meio centavo deixando de subir, a paridade falhou no primeiro caso da grade, `42,50 × 68,93`. Com o meio exato da divisão arredondando para o lado errado, os testes de aditivo e boletim **não** falharam: os dados sorteados não caem em meio exato. Foram acrescentados casos construídos para cair, e aí a paridade falhou em dois testes.

## O que a paridade mostrou

**O valor da revisão seguinte pode não ser "valor anterior + valor do aditivo".** Pelo mesmo motivo: o aditivo arredonda o valor da quantidade acrescida, e a revisão seguinte arredonda a quantidade total. Em 3 dos 12 contratos sorteados a Rev. 1 ficou diferente de "valor inicial + acréscimos − supressões" por centavos. Os limites do art. 125 usam a soma dos valores dos aditivos; o valor atual do contrato usa a revisão. Entra na questão 36.

**A soma dos eventos pode não bater com o valor da planilha.** O evento arredonda cada serviço em cada frente; a planilha arredonda o serviço inteiro. Um serviço de 3,00 m² a R$ 0,33 vale R$ 0,99 na planilha; repartido em duas frentes de 1,50 m², vale R$ 0,50 em cada evento, R$ 1,00 no total. Em 8 dos 12 contratos sorteados a soma dos eventos ficou diferente da planilha por centavos. É assim no schema de referência, e o Rust reproduz. O que fazer com a diferença é a questão 36.

## Alternativas descartadas

| Alternativa | Por que não |
|---|---|
| Teste em Rust que repete a fórmula do SQL | Conferiria o Rust contra o Rust |
| Pôr o teste dentro do `dominio` | Traria driver de banco para o crate que tem que ser puro |
| Rust gerar um arquivo SQL com os valores esperados, sem driver | Evitaria a dependência, mas não leria dado do banco para dentro dos tipos do domínio, que é o que a aplicação vai fazer |
| Ligar o suporte a PostgreSQL do tipo decimal | Mudaria as dependências do `dominio` por causa de um teste. Texto resolve |
| Arredondar quando o produto não cabe | É o comportamento que a decisão 6 proíbe |

## Consequências

- Uma dependência nova, só de teste: o driver `postgres`. Não entra no executável. As licenças passam em `cargo deny`.
- A paridade não roda sem Docker ou sem um PostgreSQL informado. No CI entra pelo `db-test.sh`.
- Regra nova de cálculo no `dominio` que também exista no SQL ganha um teste aqui.
