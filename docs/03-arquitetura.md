# 03 · Arquitetura (Rust + Tauri)

## 1. Decisão em uma frase

**Rust onde precisa ser certo** (regras da lei, banco, sincronização, IA); **HTML/TypeScript onde o usuário toca** (telas); **Tauri** para entregar a mesma interface como app de desktop e de celular; **navegador** para quem não pode instalar nada (empresa e cidadão). O diário de obras da empresa é a exceção: é tela só do app de celular (ADR 0004).

## 2. Por que não é "só um app Tauri"

Uma prefeitura tem vários atores, muitos usuários ao mesmo tempo e exigência de auditoria. Isso pede **uma fonte única da verdade no servidor**. O Tauri é a *casca* dos clientes, não o banco de dados.

```
                      ┌──────────────── Servidor da prefeitura (ou nuvem gov) ────────────────┐
 Navegador (empresa,  │  api (axum) ─► aplicacao ─► dominio (regras da Lei 14.133, puro)      │
 cidadão, auditor) ───┼─►   │                │                                                │
                      │     ├─► infra-pg ─► PostgreSQL 16 (RLS, triggers de defesa, outbox)   │
 Tauri Desktop ───────┼─►   ├─► armazenamento de arquivos (S3-compatível/MinIO ou disco)      │
 (fiscal, gestor)     │     ├─► worker (outbox → PNCP, TCE, e-mail, PDFs)                     │
                      │     └─► rreia-gate ─► rreia-jev ─► llama-server / mistral.rs          │
 App de celular ──────┼─►                                                                     │
 (campo, offline)     └────────────────────────────────────────────────────────────────────────┘
        └─ SQLite local + fila de comandos (crates/sync)
```

## 3. Stack

| Camada | Escolha | Motivo |
|---|---|---|
| Linguagem do núcleo | **Rust** (edição 2021+, toolchain fixado em `rust-toolchain.toml`) | Binário único, tipos fortes para dinheiro/estado, sem coletor de lixo |
| Servidor HTTP | `axum` + `tokio` + `tower` | Padrão do ecossistema |
| Banco | **PostgreSQL 16** via `sqlx` (consultas verificadas em compilação) | `ltree` para EAP, `btree_gist` para períodos, RLS, já usados no schema de referência |
| Dinheiro | `rust_decimal` (e `NUMERIC` no banco). **Proibido `f32/f64` para valor** | Exatidão |
| Contratos de API | `utoipa` (OpenAPI) → tipos TS gerados | Evita divergência cliente/servidor |
| Cliente web/desktop/celular | **Tauri 2** + UI em TypeScript | Mesma UI em 3 formas de entrega. Plataformas do celular em §5.1 |
| UI | React + TypeScript + Vite; componentes próprios em `ui/design-system` | Ecossistema grande; trocar por Svelte/Solid é viável, ver Questões em aberto |
| Planilhas | `calamine` (ler `.xlsx`, `.xls`, `.ods`), `rust_xlsxwriter` (gerar) | Leitura da planilha, do cronograma e do eventograma do órgão; geração da planilha de medição e da planilha de aditivo |
| PDF (gerar) | `typst` (biblioteca Rust) para Boletim de Execução, planilha de medição, relatório fotográfico, Caderno de Medição, RDO, termos | Layout fiel, sem navegador embutido |
| Projeto (ler) | Extração da camada de texto do PDF das pranchas, em Rust. Biblioteca **a escolher**, com licença conferida no `cargo deny` | Só texto do carimbo e das legendas. Sem OCR e sem leitura de DWG/IFC na primeira versão (ver `10-execucao-eventos-previsao.md` §2) |
| Busca | `pgvector` + modelo de embeddings pequeno local | IA-13 |
| IA | `rreia-jev` (Jev Local), `llama.cpp`/`mistral.rs` como runtime | Ver `04-ia-borda-rreia.md` |
| Observabilidade | `tracing` + OpenTelemetry opcional; métricas Prometheus em `/metrics` | Auditoria técnica |
| Autenticação | Contas locais + TOTP; OIDC opcional (gov.br, LDAP da prefeitura) | Cada prefeitura tem sua realidade |

## 4. Estrutura do repositório (alvo)

```
crates/
  dominio/              # PURO (sem IO). Tipos, invariantes, cálculos: limites art.125, fator art.127,
                        # arredondamento por contrato, valor de evento, máquinas de estado de
                        # medição/diário/aditivo/boletim de execução, e `previsao` (término e recebimento).
  aplicacao/            # Casos de uso + portas (traits). Ex.: HomologarAditivo, AprovarMedicao,
                        # EmitirBoletimExecucao, PublicarCronograma, CalcularPrevisao.
  infra-pg/             # Repositórios sqlx, outbox, RLS por sessão (SET app.tenant_id).
  api/                  # axum, autenticação, autorização por perfil e por designação, OpenAPI.
  worker/               # Consome outbox: PNCP, TCE, PDFs, e-mails, notificações.
  sync/                 # Protocolo offline (cliente e servidor): comandos idempotentes, mídia em partes.
  importacao/           # Documentos do órgão → staging → revisão → publicação:
                        # planilha (Rev. 0), cronograma (linha de base), eventograma, pranchas do projeto.
  relatorios/           # Typst e xlsx: Boletim de Execução, planilha de medição, relatório fotográfico,
                        # Caderno de Medição, planilha de aditivo, relatório de previsão, RDO, termos.
  prestacao-contas/     # Adaptadores: pncp, tce-<uf>, obrasgov, caixa-bm-ple-rre.
  rreia-jev/            # Jev Local (código do documento RREIA, 20 testes).
  rreia-gate/           # Leis LP1–LP10, montagem de estado por papel, citações, rastro, cliente do Jev.
  demonstracao/         # PROVISÓRIO: obra fictícia e estado em memória da prévia de desktop (ADR 0003).
apps/
  desktop/              # Tauri 2 (Windows/Linux). Hoje é a prévia: casca em `src-tauri/`, telas estáticas
                        # em `previa/` e dados fictícios (ADR 0003). Sai quando a interface em `ui/` existir.
  mobile/               # Tauri 2: Android (o mesmo APK serve a GrapheneOS, LineageOS e HarmonyOS até a 4) e iOS.
                        # É só aqui que existe o diário da empresa (ADR 0004). Ainda não existe.
ui/
  design-system/        # Tokens, componentes, padrões de IA (ver 05-ux-ui.md)
  features/             # Uma pasta por módulo (p05-boletim-execucao, p06-medicao, p17-previsao, e02-diario…)
db/
  migrations/           # Versionadas e imutáveis depois de publicadas
  reference/            # Schema e seed do engenheiro (ponto de partida; ver 06-banco-de-dados.md)
docs/  .github/  RREIA.md  CLAUDE.md  README.md
```

**Regra de dependência:** `dominio` não depende de ninguém. `aplicacao` depende de `dominio`. Infra, API e UI dependem para dentro, nunca o contrário. O mesmo `dominio` é compilado no servidor **e** (opcionalmente, via WASM ou no backend do Tauri) no cliente para validar antes de enviar.

## 5. Offline no campo

Campo é onde o sinal falha. Princípios:

1. **Escrever é sempre local primeiro** (SQLite no aparelho). Cada alteração vira um **comando** com `id` gerado no cliente (UUID v7) e `idempotency_key`.
2. **Fila de comandos** enviada em ordem por agregado. O servidor responde `aceito` ou `rejeitado(motivo)`; rejeitado volta para o usuário corrigir, nunca some em silêncio.
3. **Conflito:** diário é de um autor por dia (sem conflito); Boletim de Execução é de um fiscal por número (sem conflito) e só é emitido com o aparelho sincronizado; medição só é editável em `rascunho`; planilha, eventos, cronograma e saldo são **somente leitura** no cliente (servidor manda). Nada de "última escrita vence" em dados financeiros.
4. **Mídia** sobe em partes retomáveis com SHA-256. Foto de evidência só vale se vier da **câmera do app**, guardando hora do aparelho, offset do relógio contra o servidor, GPS e precisão. EXIF sozinho não é prova. Ao fotografar, a pessoa escolhe a **frente e o serviço**; é esse vínculo que monta o relatório fotográfico.
5. **Banner de sincronização** sempre visível: "3 itens aguardando envio". Nunca perder dado por falta de rede.
6. **Sem serviços do Google.** O app não pode depender do Google Play Services: nada de notificação por FCM, SDK de mapas do Google, localização "fundida" do Google nem verificação de integridade da Play. Localização vem da API do próprio sistema; aviso de novidade vem da sincronização; mapa, se houver, é de fonte aberta. Três das plataformas-alvo não trazem esses serviços.

### 5.1 Plataformas do app de campo

Decisão em `adr/0004-diario-so-no-celular.md`. **Nenhuma tem código nem foi testada em aparelho.** A coluna "o que exige" é o que se sabe de cada sistema, a conferir quando o trabalho começar.

| Plataforma | Como o app chega | O que exige | Estado |
|---|---|---|---|
| **Android** | APK e AAB, pelo Tauri 2 | É a base | Planejado (Fase 2) |
| **GrapheneOS** | O mesmo APK | Sem Google Play Services por padrão. Instalação por APK, fora da loja do Google | Planejado junto com o Android; testar em aparelho |
| **LineageOS** | O mesmo APK | Sem aplicativos do Google por padrão. Instalação por APK | Planejado junto com o Android; testar em aparelho |
| **HarmonyOS até a 4** | O mesmo APK | Roda apps Android, sem serviços do Google | A testar |
| **HarmonyOS NEXT (5 em diante)** | Não roda APK | App próprio da plataforma, hospedando a mesma interface web. `TODO(técnico)`: conferir se o Tauri já compila para ela | Sem plano (questão 26) |
| **Apple (iPhone e iPad)** | App iOS, pelo Tauri 2 | Build em macOS com Xcode; conta de desenvolvedor; distribuição pela App Store ou TestFlight, com revisão da Apple | Planejado depois do Android (questão 27) |
| **KaiOS** | Não roda APK nem Tauri | Celular de teclas: app web, tela pequena, navegação por teclado, pouca memória e motor de navegador antigo. Exige um cliente web reduzido, feito à parte | Sem plano (questão 28) |

A regra da foto de evidência (item 4) vale em toda plataforma. Onde o sistema não der câmera, hora e GPS com precisão ao app, aquela plataforma não gera evidência.

## 6. Segurança

- **Multi-tenant por RLS** (`tenant_id` + `app.tenant_id` por sessão). A aplicação conecta com papel **sem** `BYPASSRLS`. Aqui o *tenant é o município*; empresas são usuários externos limitados por `contrato_id`.
- **Autorização em duas camadas:** perfil (o que o papel pode) e **designação** (esta pessoa é fiscal *deste* contrato, em vigor na data, por esta portaria).
- **Segregação de funções** no domínio: autor ≠ aprovador.
- **Imutabilidade:** diário fechado, Boletim de Execução emitido, medição aprovada, aditivo homologado, revisão vigente, linha de base do cronograma e relatório emitido não se alteram; correção é novo registro. Triggers de defesa já existem no schema de referência para parte deles; os demais entram nas migrações novas.
- **Previsão não é dado oficial:** o cálculo fica em tabela própria, marcado com método e versão do algoritmo, e nenhuma regra de negócio lê dele para aprovar, glosar ou pagar.
- **Trilha completa** (`auditoria`, antes/depois em JSONB) + **outbox** para eventos.
- Senhas com `argon2`; sessões curtas; TOTP; bloqueio por tentativa; segredos fora do repositório.
- Cabeçalhos de segurança, CSP restrita no Tauri (sem `eval`, sem acesso irrestrito ao sistema de arquivos), updater do Tauri com **assinatura**.
- Backups cifrados, teste de restauração periódico, ver `09-distribuicao.md`.

## 7. Implantação (duas formas)

| Forma | Quando | Notas |
|---|---|---|
| **No servidor da prefeitura (on-prem)** | Exige dado local, IA local de borda é argumento de venda | `docker compose` ou pacotes `.deb`/serviço systemd; Postgres e arquivos no mesmo local; é o caminho do RREIA |
| **Nuvem governamental / provedor contratado** | Prefeitura sem TI | Um banco por município ou RLS por tenant; IA local exige hardware próprio ou fica desligada |

O código é o mesmo; a diferença é configuração. **Definir antes de codar** (ver `QUESTOES-ABERTAS.md`).

## 8. Decisões que ficam por escrito (ADR)

Cada decisão estrutural vira um arquivo curto em `docs/adr/NNNN-titulo.md` (contexto, decisão, consequências). Mudar uma regra da Lei no `dominio` exige ADR e teste novo.
