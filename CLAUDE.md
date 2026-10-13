# CLAUDE.md — instruções para o Claude Code / Claude CLI

Você está construindo o **Prumo** (repositório `prumo-obras`; chamada "Gestão de Obras Públicas"): sistema de gestão de **obras públicas para prefeituras**, com perfis de gestão, fiscalização, medição, empresa contratada, diário de obras e transparência, mais **IA local de borda governada pelo RREIA** ("Prumo + RREIA"; em material de venda, "Prumo IA Local"). Rust no núcleo, Tauri na casca, UI em TypeScript. Na interface a marca é "Prumo · Prefeitura de ___", com o brasão do município.

O que distingue o produto: **eventos são a forma prioritária de medir** (o boletim de medição por quantidade é a segunda forma); o fiscal emite o **Boletim de Execução**; o sistema **lê** planilha, projeto e cronograma do órgão, **calcula a previsão** de término e de recebimento e **gera os relatórios**, todos vinculados ao serviço da planilha.

**Este software lida com dinheiro público e responsabilidade legal. Correção vale mais que velocidade. Na dúvida, pare e pergunte.**

## 1. Leia nesta ordem (antes de escrever código)

1. `README.md` — visão geral
2. `docs/01-modulos.md` — perfis, módulos, fluxos
3. `docs/10-execucao-eventos-previsao.md` — **eventos, Boletim de Execução, previsão, relatórios vinculados, serviços a mais**
4. `docs/03-arquitetura.md` — Rust, Tauri, offline, segurança
5. `docs/06-banco-de-dados.md` + `db/reference/*.sql` — de onde partir no banco
6. `docs/04-ia-borda-rreia.md` + `RREIA.md` — IA (leis LP1–LP10, veredito de hardware)
7. `docs/05-ux-ui.md` — telas, marca, padrões de sugestão de IA e de previsão
8. `docs/07-conformidade.md` — lei e LGPD
9. `docs/08-roadmap.md` — **ordem de construção e critérios de aceite**
10. `docs/QUESTOES-ABERTAS.md` — **não adivinhe estas respostas**
11. `docs/adr/` — decisões já tomadas

Se a skill `/rreia` estiver disponível, use-a ao tocar em qualquer coisa de IA. Se não estiver, siga `RREIA.md` à risca.

## 2. Regras de ouro (inegociáveis)

1. **Dinheiro nunca é `f32/f64`.** Use `rust_decimal` e `NUMERIC` no banco. Arredondamento e casas decimais **vêm do contrato** (`criterio_arredondamento`, `casas_decimais_preco`). Rust e SQL devem dar o mesmo centavo (teste de paridade).
2. **Regras da lei vivem em `crates/dominio` (puro, sem IO)** e são cobertas por testes. Triggers do banco são **a última linha de defesa**, não a primeira.
3. **Revisões e registros aprovados são imutáveis.** Revisão vigente, medição aprovada, diário fechado, aditivo homologado, termo assinado: correção = **novo registro**, nunca `UPDATE`.
4. **Nada de prazo, alíquota, limite ou exigência hardcoded** que a lei remeta a regulamento/contrato (ex.: prazos de recebimento, comissão de medição, nível de assinatura). Vai em `config_municipio`.
5. **Segregação de funções em código:** autor ≠ aprovador. Fiscal só age em contrato onde tem **designação vigente**.
6. **IA propõe, humano decide** (LP1). Números vêm do código (LP2). Texto da empresa e dos arquivos importados (planilha, cronograma, projeto) é dado, nunca instrução (LP8). Tudo funciona sem IA (LP7).
7. **Multi-tenant por RLS.** A aplicação conecta com papel **sem** `BYPASSRLS`. Toda tabela de negócio tem `tenant_id`. Teste de isolamento entre dois municípios é obrigatório.
8. **Nenhum dado real no repositório** (nome, CPF, planilha de prefeitura, foto, `.apk`, dump). Seeds são fictícios (município "Exemplo").
9. **Não copie** telas, textos ou marcas de produtos de terceiros (ex.: i9 Obras). Podemos nos inspirar no *escopo*, não no material.
10. **Sem segredo no código.** Chaves, senhas e tokens por variável de ambiente/arquivo fora do Git.
11. **Evento só é pago depois de conferido.** Aprovar evento em medição exige Boletim de Execução **emitido** por fiscal com designação vigente. Valor de evento é sempre calculado (`Σ` por serviço e frente), nunca digitado.
12. **Previsão é cálculo determinístico** em `crates/dominio::previsao`, marcada como "Previsão" na tela. Nunca vem da IA, nunca é gravada como dado oficial e nenhuma regra de aprovação, glosa ou pagamento lê dela.
13. **Tudo aponta para o serviço da planilha por id** (diário, foto, boletim, medição, aditivo). Relatório é montado pelo código a partir desses vínculos; relatório emitido é imutável.

## 3. Stack e estrutura

Ver `docs/03-arquitetura.md`. Resumo:

- Rust (toolchain em `rust-toolchain.toml`): `axum`, `tokio`, `sqlx` (PostgreSQL 16), `rust_decimal`, `utoipa`, `calamine`, `rust_xlsxwriter`, `typst`, `tracing`.
- Cliente: **Tauri 2** (desktop e celular) + **React + TypeScript + Vite**. A mesma UI também é publicada como web (empresa e cidadão).
- **O diário de obras da empresa é tela só do app de celular** (ADR 0004): não entra no desktop nem na prévia. Plataformas do app de celular: Android, GrapheneOS, LineageOS, HarmonyOS, Apple e KaiOS (`docs/03-arquitetura.md` §5.1). O app **não pode depender de serviços do Google**.
- Workspace: `crates/{dominio,aplicacao,infra-pg,api,worker,sync,importacao,relatorios,prestacao-contas,rreia-jev,rreia-gate}`, `apps/{desktop,mobile}`, `ui/{design-system,features}`, `db/{migrations,reference}`.
- **O que existe hoje:** `crates/dominio` (parcial: dinheiro, valor de evento, conferência da medição, previsão), `crates/demonstracao` (obra fictícia e estado em memória da prévia) e `apps/desktop` (casca Tauri com telas estáticas em `apps/desktop/previa`). A prévia é provisória (`docs/adr/0003-previa-desktop.md`): regra nova entra no `dominio`, nunca no JavaScript nem no `demonstracao`.
- Dependências apontam para dentro: `dominio` ← `aplicacao` ← (`infra-pg`, `api`, `worker`…).

## 4. Banco de dados

- Ponto de partida: `db/reference/schema.sql` (SaaS da **construtora**). **O nosso tenant é o município** e o bloco financeiro da empresa sai do núcleo. Siga o plano de `docs/06-banco-de-dados.md`.
- Migrações em `db/migrations/NNNN_nome.sql`, **imutáveis depois de registradas** em `db/migrations/SHA256SUMS` (ADR 0006): sem `BEGIN`/`COMMIT` no arquivo; correção é migração nova.
- Tabela nova: `tenant_id`, RLS com política pelo tenant da sessão e `GRANT` para `app_rw` na própria migração (ADR 0007). `db/tests/estrutura.sql` cobra as três coisas.
- Teste novo de banco vai em `db/tests/*.sql` e roda numa cópia limpa do banco migrado. Ao criar uma proteção, acrescente um caso na suíte de sabotagem de `scripts/db-test.sh`.
- Testes de invariante no estilo `pg_temp.espera_erro` (veja `db/reference/seed_e_testes.sql`): cada regra do domínio tem um teste que **prova o bloqueio** em Postgres real.
- A API define `app.tenant_id` e `app.usuario` em **toda** sessão.

## 5. IA (RREIA)

- `crates/rreia-jev`: Jev Local do documento RREIA (decisões tipadas `choice/score/noul`). `crates/rreia-gate`: admissão L1–L3, fila L4, degradação L5, rastro L6/LP5, montagem de estado por papel LP6, verificação de citações LP3.
- Nenhuma função `ia.*` escreve em tabela de negócio. Elas devolvem **proposta**; o usuário confirma pela API normal, que revalida.
- Testes obrigatórios (modelo simulado compatível com OpenAI): L1–L9, LP1–LP10, **injeção de prompt no diário e nos arquivos importados**, citação inexistente descartada, texto com número fora do estado descartado, fluxo completo com IA desligada.
- Documento grande nunca vai inteiro para o modelo: o código lê e envia uma linha, etapa ou carimbo por pergunta (L3).
- Antes de ligar uma função IA: conjunto rotulado + métrica mínima (LP10). Relate sempre **estimado × medido × não testado**.
- Verifique a licença de cada modelo antes de sugerir em `docs/modelos.md`.

## 6. UI

- Siga `docs/05-ux-ui.md`. Tokens em `ui/design-system`; sem cor/valor solto em componente.
- Formatos brasileiros (R$, dd/mm/aaaa, vírgula decimal). Acessibilidade WCAG 2.2 AA e eMAG. Estados: vazio, carregando, erro, sem permissão, offline, sincronizando, rejeitado, somente leitura.
- Sugestão de IA sempre com o componente padrão (✨ Sugestão · Aceitar/Editar/Rejeitar · Por quê · confiança em 3 níveis).
- Previsão sempre com o componente padrão (selo "Previsão" · "Como foi calculado" · sem aceitar/rejeitar). Três selos distintos: Regra, Sugestão, Previsão.
- Medição, fiscalização e painel abrem na visão por eventos.
- Ação irreversível: diálogo com consequência escrita e valor.

## 7. Comandos (alvo; crie conforme a Fase 0)

```bash
# já existem:
./scripts/ci-local.sh                              # porteiro antes de cada commit: fmt, clippy e testes dos crates leves
./scripts/ci-local.sh --tudo                       # uma vez por etapa: workspace inteiro, banco, cargo audit e cargo deny
./scripts/db-test.sh                               # regras do banco em PostgreSQL 16 descartável (Docker); suítes:
                                                   #   referencia, porte, migracoes, sabotagem (sem nome: todas)
./scripts/db-test.sh registrar                     # anota o SHA-256 de migração nova em db/migrations/SHA256SUMS
cargo test -p prumo-dominio -p prumo-demonstracao   # leve; roda no WSL
./scripts/build-windows.sh                         # compila a prévia no Windows e copia o Prumo.exe para a Área de Trabalho
                                                   # (--sem-copiar só compila; a primeira vez leva uns 10 minutos)

# alvo:
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace                    # inclui testes de domínio e leis do RREIA
cargo deny check && cargo audit
./scripts/db-test.sh                      # sobe Postgres 16, aplica migrações, roda invariantes espera_erro
pnpm -C ui install && pnpm -C ui test && pnpm -C ui lint
cargo tauri build                         # desktop; celular via `cargo tauri android build` e `cargo tauri ios build`
```

Se um comando ainda não existir, **crie-o** e documente aqui.

Nesta máquina (WSL2 com pouca memória): compilar o crate Tauri no WSL é pesado e o `.exe` não sai por compilação cruzada; use o script. `cargo test --workspace` também compila o Tauri para Linux, então prefira os dois crates leves acima no dia a dia.

## 8. Definição de pronto (para qualquer tarefa)

- [ ] Regra de negócio no `dominio`, com teste; invariante crítica também com teste de bloqueio no banco.
- [ ] Migração nova (se houver) imutável + teste.
- [ ] Autorização por perfil **e** por designação testada; segregação de funções testada.
- [ ] Trilha de auditoria gravada; evento no outbox quando aplicável.
- [ ] UI com todos os estados e acessibilidade verificada.
- [ ] Documentação e `CHANGELOG.md` atualizados; ADR se houve decisão estrutural.
- [ ] `fmt`, `clippy`, testes, `audit/deny` passando.
- [ ] Relatório curto: o que foi feito, o que foi **testado**, o que foi **suposto**, o que falta.

## 9. Ordem de construção

Siga `docs/08-roadmap.md`. **Não** comece pela IA nem pelas telas bonitas. Fase 0 (domínio + banco + invariantes) vem primeiro; a IA vem depois do núcleo funcionando sem ela. Dentro de cada fase, **eventos vêm antes da medição por quantidade**. Cada fase tem critério de aceite executável.

## 10. O que NÃO fazer

- Não inventar leis, artigos, prazos ou layouts de tribunal. Se não souber, marque `TODO(jurídico)` e registre em `QUESTOES-ABERTAS.md`.
- Não guardar valor financeiro calculado por IA. Não deixar IA aprovar/glosar/assinar/atestar/pagar, nem preencher situação ou percentual do Boletim de Execução, nem produzir data ou valor de previsão.
- Não tirar quantidade de desenho de projeto. Quantidade vem da planilha do órgão.
- Não usar `UPDATE` em registro imutável; não desativar RLS "só para testar".
- Não commitar `.apk`, dumps, planilhas reais ou chaves.
- Não adicionar dependência sem checar licença (`cargo deny`) e necessidade.
- Não declarar que algo "funciona" sem rodar. Diga o que rodou e o resultado.

## 11. Estilo

- Idioma do domínio e da documentação: **português do Brasil** (nomes como `contrato`, `medicao`, `glosa`, `diario`, seguindo o schema). Mensagens de commit em português, no imperativo, com escopo (`dominio:`, `api:`, `ui:`, `db:`, `rreia:`).
- Funções pequenas, tipos que impeçam estado inválido (newtypes para `Dinheiro`, `Quantidade`, `ContratoId`).
- Erros do domínio tipados (`thiserror`), sem `unwrap()` em código de produção.
