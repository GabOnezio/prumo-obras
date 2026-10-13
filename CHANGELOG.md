# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/); versionamento [SemVer](https://semver.org/lang/pt-BR/).

## [Não lançado]

### Fase 0 · Fundação (concluída em 13/10/2026 na branch `fase-0-fundacao`; relatório em `docs/relatorio-fase-0.md`)
- **Etapa 0, ferramentas:** toolchain fixada em Rust 1.99.0 (`rust-toolchain.toml`); `scripts/ci-local.sh` com os mesmos passos do CI, que é o porteiro enquanto o GitHub Actions não inicia na conta; `deny.toml` com a política provisória de licenças e origens. `cargo deny check` e `cargo audit` passam; o `.exe` compila no Windows com a toolchain fixada.
- **Etapa 1, verdade de referência:** `scripts/db-test.sh` sobe um PostgreSQL 16 descartável, roda o schema e o seed do engenheiro sem alteração e exige os 12 bloqueios e os 26 números de aceite (`db/tests/referencia/numeros.sql`).
- **Etapa 2, banco base:** `db/migrations/0001_base.sql`, porte do schema de referência sem o que é só da construtora (ficam 34 tabelas), mais o papel `app_rw`. O porte é provado em PostgreSQL 16: catálogo igual ao da referência em 687 fatos, os mesmos 12 bloqueios e os mesmos 26 números. Registro de migrações com SHA-256 no repositório (`SHA256SUMS`) e no banco (`migracao_aplicada`). Testes novos: `db/tests/estrutura.sql` (19 conferências no catálogo), `db/tests/isolamento.sql` (dois municípios fictícios, 15 bloqueios e 23 conferências) e a suíte de sabotagem (22 proteções retiradas, 22 percebidas). ADRs 0006 e 0007. Questão 35.
- **Etapa 3, eventos no banco:** seed fictício `db/seed/exemplo.sql` (município de Exemplo; contrato 045/2026 por eventos, com a mesma planilha da prévia, e contrato 052/2026 por quantidade, com critério de truncar). `db/tests/eventos.sql`: 33 valores conferidos à mão e 27 bloqueios dos gatilhos de eventos, 25 deles exigindo o motivo. `crates/paridade`: valor de item em 20.050 comparações contra o SQL, 121 eventos de contratos sorteados e os 6 eventos do seed iguais no banco, no Rust e na prévia (R$ 164.039,34). `valor_item` e `percentual` passam a fazer a conta em inteiros: resultado exato ou erro. A sabotagem cobre 28 proteções. ADR 0008. Questões 36 a 38 e a lista de achados em `docs/plano-fase-0.md` §10.
- **Etapa 4, domínio:** `crates/dominio` ganha a planilha orçamentária, o aditivo (fator do art. 127, preço de item novo, revisão seguinte, limites do art. 125), o boletim de medição por quantidade e as máquinas de estado de medição, diário, aditivo e Boletim de Execução, com segregação de funções. 112 testes. Os números do cenário do engenheiro saem iguais em Rust: fator 0,91059533, dreno a 47,35, Rev. 1 de 62.100,88, 8,60% e 2,54%, aditivo 2 em 26,87%, boletim nº 3 com 22.619,88, medido 41.447,68, saldo 20.653,20 e 66,74%. Paridade com o banco: 6 testes, com `fn_limites_aditivos`, `fn_boletim_medicao` e `fator_art127`. Regra nova que a referência não tem: restabelecimento só devolve o que foi suprimido. Cinco pontos do art. 125 e 127 marcados `TODO(jurídico)`. ADR 0009. Questões 39 e 40.
- **Etapa 5, prefeitura no banco** (migrações `0002` a `0006`):
  - `0002`: o tenant é o município, com RLS própria; usuários, servidores, portaria, designação por contrato, função e período; empresa e pessoas da empresa; quem age vem da sessão. O tenant entra em toda chave estrangeira entre tabelas com tenant, o que fecha a questão 35.
  - `0003`: ordem de serviço, ocorrência, notificação, vistoria, recebimento provisório e definitivo, garantia da obra. Todo ato em nome de quem está na sessão e com designação vigente.
  - `0004`: estados novos da medição. A situação só muda por etapa registrada (`medicao_etapa`), com transição, função no contrato e segregação de funções conferidas pelo banco. Liquidação e pagamento só com a referência da contabilidade. `ple` passa a se chamar `eventos`.
  - `0005`: diário por contrato, com etapas; dia fechado não é sobrescrito; devolvido é retificado por registro novo; instrução do fiscal imutável.
  - `0006`: `config_municipio` sem nenhum valor padrão; quem atesta a medição sai da configuração; `ia_decisao` (a proposta não muda, o desfecho é de pessoa, nada de negócio aponta para lá); publicação e denúncia.
- **Etapa 6, eventos, boletim e previsão no banco** (migrações `0007` a `0009`):
  - `0007`: documentos do órgão guardados pelo hash; pranchas; cronograma com versões, linha de base imutável e reprogramação com motivo e autor. Travas novas: os números da licitação e a forma de medir não mudam com a planilha vigente; frente e agrupador de evento vigente não são renomeados; evento nunca é criado à mão.
  - `0008`: Boletim de Execução (emitido é imutável; correção é boletim retificador); a aprovação da medição confere o boletim; glosa do evento inteiro, que pode voltar em medição seguinte; `foto` única, só da câmera do app, com hash e vínculo confirmado por pessoa; `rdo_servico`.
  - `0009`: pleito e serviço a mais, até o item do aditivo; transições do aditivo, com segregação, limite legal e parecer; restabelecimento só do que foi suprimido; previsão guardada fora dos dados oficiais; relatório emitido imutável.
- **Etapa 7, fechamento:** `ci.yml` com o workspace inteiro, o banco e a auditoria de dependências (não executado: o Actions não inicia na conta); ADR 0010; questões 41 a 43; `docs/relatorio-fase-0.md` com o que foi e o que não foi testado.
- **`scripts/build-windows.sh` corrigido:** se o Windows não respondesse ao WSL, o script lia o log da compilação anterior e copiava um executável antigo dizendo "Pronto". Agora apaga o log antes de compilar e para com erro. O `Prumo.exe` da Área de Trabalho foi recompilado com esta branch e conferido pela porta de depuração.
- **Números da fase:** 9 migrações e 74 tabelas; 12 arquivos de teste de banco com 347 bloqueios e 196 conferências em PostgreSQL 16 real; porte da `0001` igual à referência em 687 fatos do catálogo; 9 testes de paridade Rust × SQL; 111 sabotagens, todas percebidas pelos testes; 112 testes no domínio.

### Marca e ícones (branch `marca-e-icones`)
- **Marca gráfica do Prumo** em `marca/`: o vetor e os arquivos do pacote fornecido pelo autor, com as regras de uso.
- **`scripts/gerar-icones.sh`** gera do vetor os ícones do programa de desktop, do Android, da Apple, do cliente web e do Linux.
- **O `Prumo.exe` tem o ícone novo**, a marca sobre um azulejo branco: a versão transparente do pacote some na barra de tarefas escura.
- **Prévia:** a marca aparece no cabeçalho, junto do nome "Prumo", e na tela "Sobre". O brasão do município continua com o lugar dele, junto do nome da cidade.
- Os ícones de celular estão prontos em `marca/android` e `marca/apple`, mas não estão ligados a nada: `apps/mobile` ainda não existe.

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
