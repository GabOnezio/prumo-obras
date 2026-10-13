# ADR 0002 · Eventos como forma prioritária, Boletim de Execução e previsão determinística

- **Estado:** aceito, com pontos a validar (questões 15 a 24)
- **Data:** 12/10/2026
- **Decisor:** Gabriel Onezio Ferreira

## Contexto

O pedido do autor para o produto: duas formas de medir (eventos e boletins de medição), **priorizando eventos**; boletim de execução na fiscalização; previsão de execução e de recebimentos a partir do término de cada execução; relatórios gerados pelo sistema, todos vinculados à planilha orçamentária; planilha, projeto e cronograma fornecidos pelo órgão e lidos pelo sistema; relatório fotográfico, planilha de medição e aditivos de serviços a mais elaborados pelo sistema.

A documentação anterior tratava a medição por quantidade como caso comum e os eventos como um perfil entre cinco. O schema de referência já modela eventos (agrupador × frente), mas sem testes neste repositório.

## Decisão

1. **Duas formas de medir por contrato: `eventos` (prioritária) e `bm`.** Eventos são construídos e homologados primeiro, são a forma sugerida no cadastro conforme o regime e são a visão de abertura das telas. Os antigos perfis `global`, `ple` e `pavimentacao_linear` viram recortes de `eventos`; `servico_continuo` vira recorte de `bm`.
2. **Boletim de Execução é documento da fiscalização** e condição para aprovar evento na medição. A empresa declara; o fiscal confere e emite. Emitido é imutável.
3. **Previsão é cálculo determinístico** em `crates/dominio::previsao`, nunca resposta de modelo de IA. Prazos de processo vêm só de configuração. A previsão não entra em nenhuma regra de aprovação, glosa ou pagamento.
4. **Tudo se vincula ao serviço da planilha**, por id. Relatórios são montados pelo código a partir dos vínculos; relatório emitido é imutável e rastreável.
5. **Serviço a mais vira apontamento e depois item de aditivo.** Não é medido antes do aditivo homologado. Evento medido não muda; acréscimo vira evento novo.
6. **A IA entra em seis pontos novos (IA-19 a IA-24), todos só de proposta.** Nenhum deles produz quantidade, valor, data, situação ou percentual.

## Alternativas descartadas

| Alternativa | Por que não |
|---|---|
| Manter BM como padrão e eventos como perfil | Contraria a prioridade pedida e a forma de medir dos regimes de preço global |
| Evento concluído só pela declaração da empresa (como na referência) | A fiscalização precisa conferir antes de pagar; sem o boletim não há ato do fiscal para auditar |
| Previsão feita por modelo de IA | Viola a lei LP2 (número vem do código); não é reproduzível nem auditável |
| Tirar quantidade do projeto com IA | Erro vira dinheiro público; quantidade vem da planilha do órgão |
| Valor padrão para os prazos de processo | A lei remete a contrato e regulamento; regra de ouro 4 |

## Consequências

- Migrações 0007 a 0009 e ajuste do trigger de evento já medido (`06-banco-de-dados.md` §4, item 9).
- Seed fictício e testes de eventos entram na Fase 0; 15 invariantes novas (`10-execucao-eventos-previsao.md` §9).
- O fiscal ganha um ato a mais por período. O boletim precisa ser rápido no app de campo, senão trava o pagamento.
- A leitura de projeto fica limitada ao texto do carimbo de PDF na primeira versão.
- O método de previsão é inicial e precisa ser validado com dados de obra real (questão 21); o erro da previsão é medido a cada ciclo.
- Dois artigos da Lei 14.133 usados como justificativa estão marcados `TODO(jurídico)` (questão 23).
