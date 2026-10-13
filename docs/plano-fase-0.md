# Plano da Fase 0 · Fundação

> **Aprovado em 13/10/2026**, com estas respostas às perguntas do §7:
> começar sem o commit de login e reaplicá-lo quando chegar; fechar a fase com 13 invariantes provadas, levando metade da 13 para a Fase 2 e a 15 para a Fase 5; verificação local como porteiro enquanto o GitHub Actions não iniciar.
> Escrito sobre o commit `9513d0b` do `main`. O andamento de cada etapa fica no `CHANGELOG.md`.

## 1. Ponto de partida

O que conferi antes de planejar:

| Item | Resultado |
|---|---|
| `cargo test -p prumo-dominio -p prumo-demonstracao` | Passa: 33 e 11 testes |
| `cargo test -p prumo-identidade` | **Não roda: o crate não existe neste repositório** |
| Commit de login (`4b1444f`: `prumo-identidade`, ADR 0005, `ROTEIRO-DE-TESTE.md`, tabela "Situação em 13/10/2026" do roadmap) | **Não está aqui.** Não há branch, PR nem arquivo de patch; a colagem veio cortada. Ver pergunta 1 |
| Falha da prévia no Windows relatada por você | Nenhuma |
| `rust-toolchain.toml`, `deny.toml`, `scripts/db-test.sh`, `db/migrations/` | Não existem; são desta fase |
| Schema de referência | 48 tabelas, 17 funções, 12 testes `espera_erro`. **Nenhum teste cobre frentes, agrupadores ou eventos** |
| Schema e seed de referência rodados sem alteração, em PostgreSQL 16.15 descartável | Passam: 48 tabelas criadas, os 12 bloqueios provados, nenhum erro. Os números do §4 saíram do SQL |

O que a máquina oferece para a fase:

- **Postgres:** Docker funciona sem `sudo` e a imagem `postgres:16-alpine` já está baixada, com `ltree` e `btree_gist`. Não há `psql` instalado; o script usa o do contêiner.
- **Contêineres seus em execução:** `pgvector/pgvector:pg16` e `caddy`. Não toco neles; o teste sobe um contêiner próprio, com outro nome e outra porta, e o remove no fim.
- **Rust:** 1.98.1 no WSL e 1.99.0 no Windows. As versões diferem, então fixar a toolchain é necessário.
- **Ferramentas:** `cargo-audit` instalado; `cargo-deny` não.
- **Memória:** 5,9 GB no WSL, cerca de 2,7 GB livres. Compilar o crate do Tauri no WSL é possível, mas lento; os crates leves rodam a cada commit e o workspace inteiro uma vez por etapa.
- **GitHub Actions:** não inicia em repositório privado desta conta (`startup_failure`, também em outros cinco repositórios seus). O CI no GitHub não pode ser conferido hoje.

## 2. O que a fase entrega

- Toolchain fixada e uma verificação local única (`scripts/ci-local.sh`) com os mesmos passos do CI.
- Banco: migrações `0001` a `0009`, `scripts/db-test.sh` rodando as invariantes em Postgres 16 real, RLS com papel `app_rw` sem `BYPASSRLS`, teste de isolamento entre dois municípios.
- Seed fictício com um contrato por eventos e um por quantidade.
- Domínio: aditivos (limites do art. 125, fator do art. 127), boletim de medição por quantidade, máquinas de estado de medição, diário, aditivo e Boletim de Execução.
- Teste de paridade Rust × SQL, ao centavo.

**Fora desta fase:** API, acesso ao banco pela aplicação (`sqlx`, `infra-pg`), identidade em Postgres, trilha de auditoria da aplicação, telas, IA, troca dos dados fictícios da prévia. São das fases 1 e 2.

## 3. Etapas, na ordem

Cada etapa termina com tudo verde e um commit por tarefa, na branch `fase-0-fundacao`. Mensagens no formato `feat(db): …`, juntando o tipo que você pediu ao escopo que o `CLAUDE.md` exige.

| # | Etapa | Entrega | Como se prova | Tamanho |
|---|---|---|---|---|
| 0 | Ferramentas | `rust-toolchain.toml`, `scripts/ci-local.sh`, `deny.toml`, `cargo audit` | `ci-local.sh` passa; o `.exe` compila no Windows com a toolchain fixada | Pequeno |
| 1 | Verdade de referência | `scripts/db-test.sh` rodando o schema e o seed do engenheiro, sem alterar | Os 12 bloqueios aparecem e os números do §4 saem do SQL. Já conferido à mão uma vez; a etapa torna isso repetível | Pequeno |
| 2 | Banco base | `0001_base.sql`, registro de migrações com hash, RLS, `app_rw`, isolamento | Os 12 testes de bloqueio da referência passam sobre a `0001`; dois municípios não se enxergam | Médio |
| 3 | Eventos no banco | Seed fictício; testes de bloqueio para todos os gatilhos de eventos; crate de paridade | Valor dos 6 eventos igual no SQL, no Rust e na prévia (total 164.039,34) | Médio |
| 4 | Domínio | Aditivos, Rev. N+1, boletim por quantidade, máquinas de estado | Números do §4 reproduzidos em Rust; paridade com `fn_limites_aditivos` e `fn_boletim_medicao` | Médio a grande |
| 5 | Prefeitura no banco | `0002` a `0006`: pessoas e designação, fiscalização, fluxo da medição, fluxo do diário, publicação, registro de IA, configuração do município | Um teste de bloqueio por regra nova | Grande |
| 6 | Eventos, boletim e previsão no banco | `0007` a `0009`: documentos do órgão, cronograma com versões, Boletim de Execução, foto, serviço a mais, previsão, relatório emitido | Invariantes do §5 | Grande |
| 7 | Fechamento | CI com `--workspace`, ADRs, changelog, roadmap, questões, relatório do que foi e não foi testado | `ci-local.sh --tudo` passa do zero | Pequeno |

As etapas 5 e 6 são cerca de dois terços do trabalho: oito migrações e perto de 35 tabelas novas. A ordem deixa o repositório consistente ao fim de qualquer etapa.

### Detalhe das etapas

**0. Ferramentas**
- Fixar Rust `1.99.0` com `rustfmt` e `clippy`. O WSL baixa essa versão na primeira compilação.
- `scripts/ci-local.sh`: `fmt`, `clippy -D warnings` e `test` nos crates leves. Com `--tudo`: workspace inteiro, `db-test.sh`, `cargo audit` e `cargo deny`.
- `deny.toml` com a lista de licenças que já aparecem na árvore de dependências. O que ficar de fora é listado para você decidir (pergunta 5).

**1. Verdade de referência**
- `scripts/db-test.sh` sobe o contêiner descartável, aplica `db/reference/schema.sql`, roda `seed_e_testes.sql` e falha se algum `espera_erro` deixar passar ou se um número do §4 divergir.
- Serve para provar, a cada execução, que os números de aceite vêm do SQL do engenheiro e não só da minha conta. A primeira conferência manual, em 13/10/2026, já bateu (§4).

**2. Banco base**
- `0001_base.sql` é o schema de referência sem os blocos da construtora: suprimentos (6 tabelas), financeiro (8 tabelas) e as visões de fluxo de caixa e de custo. Ficam 34 tabelas.
- A `0001` não muda regra nenhuma. Assim os 12 testes de bloqueio do engenheiro rodam sobre ela sem adaptação e provam que o porte está fiel; só a parte financeira do cenário dele fica de fora, porque essas tabelas saem. Mudanças de sentido (tenant vira município, novos estados) entram nas migrações seguintes, cada uma com teste.
- Registro de migrações com nome e SHA-256. `db-test.sh` falha se uma migração já registrada mudar.
- Teste estrutural: toda tabela com `tenant_id` tem RLS ligada e política; `app_rw` não é dono, não é superusuário e não tem `BYPASSRLS`; sem `app.tenant_id` na sessão nada aparece.

**3. Eventos no banco**
- `db/seed/exemplo.sql`: município de Exemplo, contrato por eventos com os mesmos dados de `crates/demonstracao` e um contrato por quantidade com dados fictícios próprios.
- Testes de bloqueio que hoje não existem: serviço sem agrupador ou com quantidade não distribuída nas frentes; frente alterada com revisão vigente; valor de evento alterado fora do rascunho; evento medido duas vezes; evento em contrato por quantidade; quantidade diferente da soma das frentes.
- Crate `prumo-paridade`, só de teste: compara SQL e Rust com o banco de pé. Os testes ficam marcados `#[ignore]` e quem os roda é o `db-test.sh`, para o `cargo test` sem banco não fingir que conferiu.
- Primeiras paridades: `fn_valor_item` (grade fixa e 10 mil pares pseudoaleatórios com semente fixa, incluindo meio centavo e quantidade negativa, nos dois critérios) e `fn_recalcular_eventos`.

**4. Domínio** (tudo puro, sem IO)
- Aditivos: fator do art. 127 com 8 casas, preço de item novo, soma de acréscimos e de supressões sem compensação, restabelecimento à parte, situação (dentro, atenção, excede). O limiar de atenção é parâmetro; os percentuais legais levam `TODO(jurídico)` nos pontos da pergunta 8.
- Aplicar aditivo à planilha: Rev. N+1 a partir da Rev. N e dos itens do aditivo.
- Boletim de medição por quantidade: contratado, anterior, atual, acumulado, saldo, subtotal por grupo.
- Máquinas de estado: tabela de transições permitidas, com teste de cada transição permitida e de cada proibida, e autor diferente de aprovador como condição da transição.
- Paridade com `fn_limites_aditivos`, `fn_boletim_medicao` e a coluna `fator_art127`.

**5 e 6. Migrações `0002` a `0009`**
- Seguem `docs/06-banco-de-dados.md` §3, §3.1 e §5. Cada migração traz seu arquivo de testes de bloqueio.
- Pontos já mapeados: evento glosado tem que poder voltar (ajuste do gatilho de evento já medido); `forma_acompanhamento` vira `('eventos', 'bm')`; aprovação de evento exige linha de boletim emitido; nada de aprovação, glosa ou pagamento lê as tabelas de previsão.

**7. Fechamento**
- `ci.yml` volta a `--workspace`, com as bibliotecas do WebKitGTK instaladas no runner e o `db-test.sh` ligado.
- ADRs das decisões do §6, numerados a partir de 0006 (o 0005 é do commit de login).
- Perguntas novas em `QUESTOES-ABERTAS.md` a partir da 34 (30 a 33 são do commit de login).

## 4. Números de aceite

Calculados à mão a partir das entradas de `db/reference/seed_e_testes.sql` (contrato 045/2026, critério `truncar`) e **confirmados em 13/10/2026 contra o SQL de referência**, rodado em PostgreSQL 16.15: todos iguais, ao centavo. A exceção é a última linha, dos eventos fictícios, que ainda não existe em SQL (etapa 3). A etapa 4 reproduz todos em Rust.

| Número | Valor |
|---|---|
| Escavação, 42,50 × 68,93 | 2.929,52 (já tem teste em Rust) |
| Soma da Rev. 0 = valor do contrato | 58.551,28 |
| Fator do art. 127, 58.551,28 ÷ 64.300,00 | 0,91059533 |
| Preço do item novo (dreno), 52,00 × fator | 47,35 |
| Aditivo 1: acréscimo, supressão, inclusão | 3.141,60 · 1.486,00 · 1.894,00 |
| Aditivo 1: acréscimos e supressões sobre o valor inicial | 8,60% e 2,54%, dentro do limite |
| Rev. 1 | 62.100,88 |
| Aditivo 2 simulado: acréscimos | 26,87%, excede o limite |
| Medições 1 e 2 | 6.990,90 e 11.836,90 |
| Boletim nº 3: concreto, dreno, alvenaria, chapisco | 9.581,88 · 1.894,00 · 8.915,00 · 2.229,00 |
| Boletim nº 3: total | 22.619,88 |
| Depois da medição 3: medido, saldo, executado | 41.447,68 · 20.653,20 · 66,74% |
| Eventos do seed fictício: pilares, alvenaria, total da planilha | 26.014,74 · 16.641,60 · 164.039,34 |

## 5. As 15 invariantes de `docs/10` §9

Como fecharam. "Banco" quer dizer teste de bloqueio em PostgreSQL 16 real, no arquivo indicado de `db/tests/`.

| # | Invariante | Onde está provada |
|---|---|---|
| 1 | Evento só é aprovado com boletim emitido por fiscal designado | Banco: `boletim.sql`. Domínio: `conferir_medicao` e a máquina da medição |
| 2 | Boletim emitido é imutável | Banco: `boletim.sql` (nem o dono das tabelas altera). Domínio: máquina do boletim |
| 3 | Valor do evento, paridade Rust × SQL | `crates/paridade`: 121 eventos de contratos sorteados e os 6 do seed |
| 4 | Soma nas frentes = quantidade contratada | Banco: `eventos.sql` |
| 5 | Evento medido não muda | Banco: `eventos.sql` |
| 6 | Evento glosado pode voltar | Banco: `boletim.sql` |
| 7 | Forma de medir não muda | Banco: `contrato_travas.sql`. Ficou mais restrita: trava quando a planilha fica vigente (questão 41) |
| 8 | Linha de base imutável | Banco: `cronograma.sql` |
| 9 | Somas do cronograma | Banco: `cronograma.sql` (todos os eventos, ou 100% de cada grupo) |
| 10 | Previsão determinística e fora das tabelas oficiais | Domínio (já testado). Banco: `estrutura.sql` e `aditivo_e_extras.sql` |
| 11 | Prazos vêm da configuração | Domínio (já testado). Banco: `config_e_ia.sql` (nenhuma coluna com padrão; trocar a configuração troca o resultado) |
| 12 | Relatório fotográfico só com foto da câmera, hash e vínculo confirmado | Banco: `boletim.sql` (foto) e `aditivo_e_extras.sql` (relatório) |
| 13 | Relatório emitido imutável e reproduzível | **Metade:** imutável no banco (`aditivo_e_extras.sql`). "Mesmos números na reemissão" depende do gerador de relatórios, que é da Fase 2 |
| 14 | Serviço a mais só entra em aditivo com o item do aditivo | Banco: `aditivo_e_extras.sql` |
| 15 | Texto com instruções não altera resultado | **Não nesta fase:** depende da IA, que é da Fase 5 |

Fechada com 13 provadas, a 13 pela metade e a 15 levada para a Fase 5, como combinado na aprovação.

## 6. Decisões que proponho

Viram ADR se você aprovar.

1. **Tenant é o município**, com RLS em toda tabela de negócio e a aplicação conectando como `app_rw`.
2. **Migrações em SQL puro**, numeradas, com hash registrado e imutáveis depois de aplicadas. A `0001` é porte fiel da referência.
3. **Paridade conferida com o banco de pé**, em crate separado; o `dominio` continua sem IO.
4. **Verificação local como porteiro** enquanto o GitHub Actions não iniciar (pergunta 2).
5. **Toolchain 1.99.0** fixada para WSL, Windows e CI.

## 7. Perguntas

**Decide por onde começo**

1. **Commit de login.** Ele não está no repositório, e o seu prompt o pressupõe. A Fase 0 não depende dele, mas os dois mexem em `Cargo.toml`, `ci.yml`, `CHANGELOG.md` e no roadmap. Prefiro recebê-lo antes (por branch no GitHub ou arquivo `.patch` completo) e abrir a branch da fase em cima dele. Se preferir, começo agora e reaplico depois.

**Não bloqueiam; sigo com a resposta provisória**

2. **GitHub Actions.** Aceita a verificação local como porteiro por enquanto? Para o CI rodar no GitHub é preciso resolver a cobrança ou cota do Actions da conta.
3. **Schema do engenheiro (questão 6).** As migrações derivam dele. Sigo com o repositório privado e a origem citada no cabeçalho de cada arquivo. Continua valendo: nada disso é publicado antes de a autoria e a licença serem confirmadas.
4. **Docker.** Vou subir e remover um contêiner `prumo-db-test` a partir da imagem que já está na máquina. Diga se não quiser.
5. **`cargo-deny` e política de licenças (questão 7).** Instalo o binário pronto em `~/.cargo/bin`. A lista de licenças aceitas fica provisória até a licença do repositório ser definida.
6. **Toolchain 1.99.0.** O WSL vai baixar essa versão.
7. **Aceite das invariantes 13 e 15**, como no §5.
8. **Art. 125, `TODO(jurídico)`.** O SQL de referência calcula sobre o valor inicial sem reajuste, aplica 50% só aos acréscimos de reforma e limita supressão a 25%. Reproduzo isso e marco os três pontos para conferência no texto da lei.
9. **Comissão de medição (questão 4).** A máquina de estado da medição terá a etapa de comissão ligada por configuração, desligada por padrão.

## 8. Riscos

| Risco | O que faço |
|---|---|
| Porte da `0001` mudar comportamento sem ninguém notar | Os testes do engenheiro rodam sobre a referência e sobre a `0001`; os números do §4 têm que sair iguais |
| Tabelas novas sem RLS | Teste estrutural falha se alguma tabela com `tenant_id` ficar sem política |
| Paridade que "passa" sem banco | Testes de paridade só rodam pelo `db-test.sh`, com o banco de pé |
| Memória do WSL | Crates leves a cada commit; workspace inteiro e Tauri uma vez por etapa, com dois processos |
| Fase grande demais para uma entrega | Ordem que deixa o repositório consistente ao fim de cada etapa; relato o estado no changelog a cada uma |
| Licença do schema negada depois | Origem citada em cada migração derivada, para saber o que reescrever |

## 9. Observações sobre o prompt

- A primeira versão citava a LP9 para "nenhum dado sai da prefeitura". A versão reenviada já traz LP4 para isso e LP9 para "sem identificar pessoas", como no `RREIA.md`.
- "Paraná e Santa Catarina primeiro" responde em parte a questão 2 (tribunal de contas). Registro isso na abertura da fase; o efeito prático é só na Fase 4.

## 10. Achados durante a execução

O que apareceu ao rodar o schema de referência de verdade. Tudo conferido em PostgreSQL 16, em 13/10/2026. Nada disto foi corrigido na `0001`, que é porte fiel; a coluna da direita diz onde fecha.

| # | Achado | Efeito | Onde fecha |
|---|---|---|---|
| 1 | **Chave estrangeira não passa pela RLS.** O município A gravou um contrato seu apontando para uma obra do município B | A não lê nada de B, mas a linha existe e impede B de apagar a própria obra | **Fechado na `0002`:** o tenant entra em toda chave entre tabelas com tenant; `isolamento.sql` e `estrutura.sql` provam |
| 2 | **Evento criado à mão sobrevive.** Com a planilha em rascunho dá para gravar um evento com valor digitado. Se o par agrupador × frente tiver serviço, o banco recalcula ao publicar. Se não tiver, o evento fica com o valor digitado | No teste: planilha de R$ 100,00 e eventos somando R$ 5.100,00. Marcado numa medição, o evento fantasma entra com R$ 0,00, então não gera pagamento, mas aparece na lista com valor inventado | **Fechado na `0007`:** evento não se cria, altera nem apaga à mão; `eventos.sql` prova |
| 3 | **Frente e agrupador podem ser renomeados** com a planilha vigente e evento já medido | Muda o sentido de documento emitido | **Fechado na `0007`**, com a resposta provisória da questão 37; `contrato_travas.sql` prova |
| 4 | **A forma de medir do contrato pode ser trocada** com medição em andamento | Era a invariante 7 de `docs/10` §9, já prevista | **Fechado na `0007`**; `contrato_travas.sql` prova |
| 5 | **Valor inicial, orçamento-base, critério de arredondamento, casas do preço e marca de reforma do contrato podem ser alterados** com a planilha vigente | Muda a base dos limites do art. 125, o fator do art. 127 e o centavo das próximas medições | **Fechado na `0007`**, com a resposta provisória da questão 38; `contrato_travas.sql` prova |
| 6 | **A soma dos eventos pode diferir do valor da planilha** por centavos, quando um serviço é repartido em frentes | Em 8 de 12 contratos sorteados. Não é defeito do porte: é como a referência calcula | Decisão sua (questão 36) |
| 7 | **Vários bloqueios têm mais de uma camada.** Tirar o gatilho da medição por eventos não mudava o resultado de nenhum teste, porque o gatilho das linhas de serviço barra as mesmas operações por outro motivo | O teste passava sem provar o gatilho que dizia provar | Fechado na etapa 3: os testes de eventos exigem o motivo, e a sabotagem cobre os cinco gatilhos |
| 8 | **O tipo decimal do Rust arredonda calado** quando o produto não cabe em 28 dígitos | Só com valores fora de qualquer contrato, mas daria centavo diferente do banco sem aviso | Fechado na etapa 3: conta em inteiros, resultado exato ou erro (ADR 0008) |
| 9 | **"Restabelecimento" não é conferido no banco.** O gatilho do aditivo aceita restabelecer quantidade de um item que nunca foi suprimido, e `fn_limites_aditivos` deixa restabelecimento fora da conta de acréscimos | Um acréscimo lançado como restabelecimento escaparia do limite de 25% | **Fechado:** no domínio na etapa 4 e no banco na `0009`; `aditivo_e_extras.sql` prova |
| 10 | **A revisão seguinte pode não valer "valor anterior + valor do aditivo"**, por arredondamento | Em 3 de 12 contratos sorteados. O limite do art. 125 usa a soma dos aditivos; o valor atual do contrato usa a revisão | Decisão sua (questão 36) |
| 11 | **No banco de referência qualquer um muda o estado da medição** e "aprovada por" é texto livre | Sem segregação de funções no banco | **Fechado:** domínio na etapa 4 (ADR 0009); banco na `0002` (designação) e na `0004` (etapas e trilha); `medicao_fluxo.sql` prova |
| 12 | **Diário sem trava.** Na referência o diário fechado, o efetivo, as ocorrências e as fotos podiam ser alterados a qualquer momento | "Dia fechado nunca é sobrescrito" era só intenção | **Fechado na `0005`**; `diario.sql` prova |
| 13 | **Aditivo mudava de situação sem regra**, inclusive direto de rascunho para homologado, e acima do limite legal | O limite do art. 125 era só um aviso | **Fechado na `0009`**; `aditivo_e_extras.sql` prova. O bloqueio não tem exceção (questão 40) |
| 14 | **Um teste que nunca falha não prova nada.** Três vezes a sabotagem mostrou teste que passava sem provar o que dizia: gatilho com segunda camada por trás, divisão sem caso de meio exato, restrição coberta por gatilho | Falsa segurança | Fechado: testes com o motivo exigido, casos de meio exato na paridade, e 111 sabotagens que os testes têm que perceber |

