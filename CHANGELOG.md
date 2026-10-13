# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/); versionamento [SemVer](https://semver.org/lang/pt-BR/).

## [Não lançado]

### Fase 0 · Fundação (em andamento, branch `fase-0-fundacao`)
- **Etapa 0, ferramentas:** toolchain fixada em Rust 1.99.0 (`rust-toolchain.toml`); `scripts/ci-local.sh` com os mesmos passos do CI, que é o porteiro enquanto o GitHub Actions não inicia na conta; `deny.toml` com a política provisória de licenças e origens. `cargo deny check` e `cargo audit` passam; o `.exe` compila no Windows com a toolchain fixada.
- **Etapa 1, verdade de referência:** `scripts/db-test.sh` sobe um PostgreSQL 16 descartável, roda o schema e o seed do engenheiro sem alteração e exige os 12 bloqueios e os 26 números de aceite (`db/tests/referencia/numeros.sql`).
- **Etapa 2, banco base:** `db/migrations/0001_base.sql`, porte do schema de referência sem o que é só da construtora (ficam 34 tabelas), mais o papel `app_rw`. O porte é provado em PostgreSQL 16: catálogo igual ao da referência em 687 fatos, os mesmos 12 bloqueios e os mesmos 26 números. Registro de migrações com SHA-256 no repositório (`SHA256SUMS`) e no banco (`migracao_aplicada`). Testes novos: `db/tests/estrutura.sql` (19 conferências no catálogo), `db/tests/isolamento.sql` (dois municípios fictícios, 15 bloqueios e 23 conferências) e a suíte de sabotagem (22 proteções retiradas, 22 percebidas). ADRs 0006 e 0007. Questão 35.
- **Etapa 3, eventos no banco:** seed fictício `db/seed/exemplo.sql` (município de Exemplo; contrato 045/2026 por eventos, com a mesma planilha da prévia, e contrato 052/2026 por quantidade, com critério de truncar). `db/tests/eventos.sql`: 33 valores conferidos à mão e 27 bloqueios dos gatilhos de eventos, 25 deles exigindo o motivo. `crates/paridade`: valor de item em 20.050 comparações contra o SQL, 121 eventos de contratos sorteados e os 6 eventos do seed iguais no banco, no Rust e na prévia (R$ 164.039,34). `valor_item` e `percentual` passam a fazer a conta em inteiros: resultado exato ou erro. A sabotagem cobre 28 proteções. ADR 0008. Questões 36 a 38 e a lista de achados em `docs/plano-fase-0.md` §10.

### Alterado
- **Nome do produto: Prumo** (antes "SGOP", nome de trabalho). Repositório e pasta `prumo-obras`; artefatos com prefixo `prumo-`; marca na tela "Prumo · Prefeitura de ___" com o brasão do município; IA como "Prumo + RREIA" e, em venda, "Prumo IA Local" (ADR 0001).
- **Eventos passam a ser a forma prioritária de medir**; o boletim de medição por quantidade é a segunda forma. Os cinco perfis de acompanhamento viram recortes dessas duas formas (ADR 0002).
- `RREIA.md` reescrito no formato da skill `/rreia`: dispositivo, política de modelo e custo, verificação L1–L3 com as contas, ações e permissões, leis com o teste de cada uma, o que não foi testado.
- Tabela de dimensionamento da IA corrigida: o modelo de 8B não cabe em 8 GB; em 16 GB só tem folga com máquina dedicada.
- Roadmap reordenado: eventos, Boletim de Execução, relatórios e previsão entram na Fase 2, antes da medição por quantidade.
- `CLAUDE.md`: três regras de ouro novas (evento só é pago depois de conferido; previsão determinística; tudo vinculado ao serviço da planilha).

### Adicionado
- **Diário da empresa só no app de celular** (ADR 0004): a tela saiu da prévia de desktop. Plataformas-alvo do app de celular registradas: Android, GrapheneOS, LineageOS, HarmonyOS, Apple e KaiOS, com o que cada uma exige (`docs/03-arquitetura.md` §5.1) e a proibição de depender de serviços do Google. Questões em aberto 25 a 29.
- **Prévia de desktop (Tauri 2)**: `apps/desktop`, com telas navegáveis sobre uma obra fictícia. Planilha e eventos, Boletim de Execução, medição por eventos e previsão usam regra de verdade; painel, medição por quantidade e console de IA são desenho estático. Não tem banco, login nem IA (ADR 0003).
- `crates/dominio`: dinheiro com arredondamento por contrato, valor de evento, conferência da medição contra o Boletim de Execução e previsão de término e de pagamento. 33 testes, entre eles o valor da escavação do seed de referência (2.929,52).
- `crates/demonstracao`: obra fictícia e estado em memória da prévia. 11 testes.
- `scripts/build-windows.sh`: compila a prévia com o Rust do Windows e copia o `Prumo.exe` para a Área de Trabalho.
- `docs/adr/0003-previa-desktop.md`.
- `docs/10-execucao-eventos-previsao.md`: leitura dos documentos do órgão (planilha, projeto, cronograma), duas formas de medir, Boletim de Execução da fiscalização, previsão de término e de recebimento, relatórios vinculados (planilha de medição, relatório fotográfico, planilha de aditivo), serviços a mais, 15 invariantes novas.
- Módulos P16 (Relatórios vinculados) e P17 (Previsão).
- Seis pontos de IA novos, IA-19 a IA-24, todos só de proposta. Total: 24.
- Modelo de dados proposto para eventos, boletim, previsão e relatórios; migrações 0007 a 0009 no plano.
- Padrão de componente "Previsão" e telas novas em `docs/05-ux-ui.md`.
- `docs/adr/0001-nome-e-marca.md` e `docs/adr/0002-eventos-como-forma-prioritaria.md`.
- Questões em aberto 15 a 24.
- Documentação inicial: módulos, arquitetura, IA de borda (RREIA – Módulo Prefeitura), UX/UI, banco, conformidade, roadmap, distribuição.
- Schema e seed de referência em `db/reference/` (a confirmar autoria e licença).
