# Prumo — Gestão de Obras Públicas

> Status: **pré-alfa / projeto**. Ainda não use em produção. Hoje o repositório tem documentação, o schema de referência, os primeiros módulos do domínio em Rust e uma **prévia de desktop** com dados fictícios. Não há banco, login nem IA rodando.
> O Prumo acompanha uma obra pública do contrato ao recebimento, com visões diferentes para **gestão**, **fiscalização**, **empresa contratada** e **cidadão**, e com **IA local de borda** governada pelo [RREIA](RREIA.md) (na linguagem de venda: **Prumo IA Local**).
> Na tela de cada cidade aparece "Prumo · Prefeitura de ___", com o brasão do município.

[![CI](https://img.shields.io/badge/CI-a%20configurar-lightgrey)](.github/workflows/ci.yml)
[![Licença](https://img.shields.io/badge/licen%C3%A7a-a%20definir-lightgrey)](docs/QUESTOES-ABERTAS.md)
[![Rust](https://img.shields.io/badge/n%C3%BAcleo-Rust-orange)](docs/03-arquitetura.md)
[![Tauri](https://img.shields.io/badge/cliente-Tauri%202-blue)](docs/03-arquitetura.md)

## O que é

Uma obra pública tem vários atores e uma só verdade:

| Quem | Faz | No sistema |
|---|---|---|
| **Órgão** | Fornece | Planilha orçamentária, projeto e cronograma, que o sistema **lê e confere** |
| **Empresa contratada** | Executa e declara | Diário de obras, medição, pleitos, notificações |
| **Fiscalização** | Confere e atesta | **Boletim de Execução**, validação do diário, análise e glosa da medição, ocorrências, vistorias, recebimento |
| **Gestão / Planejamento** | Decide e presta contas | Contratos, planilha e revisões, eventos, aditivos (limites da Lei 14.133), previsão, painéis, PNCP/TCE |
| **Cidadão** | Acompanha | Mapa e ficha pública da obra, ouvidoria |

Pilares:

1. **Regras da lei como código testado** (revisões imutáveis, medição, aditivos com limite do art. 125 e fator do art. 127, recebimento e garantia de 5 anos).
2. **Eventos em primeiro lugar.** Duas formas de medir: por **eventos** (prioritária) e por **boletim de medição** por quantidade. O evento só é pago depois que o fiscal o confere no Boletim de Execução.
3. **Tudo vinculado à planilha do órgão.** Diário, foto, boletim, medição e aditivo apontam para o serviço da planilha; por isso o sistema gera sozinho a planilha de medição, o relatório fotográfico e a planilha de aditivo.
4. **Previsão calculada, não adivinhada.** Término de cada evento e data de recebimento saem de um cálculo determinístico sobre o cronograma e o ritmo verificado.
5. **Rastro completo**: quem fez o quê, quando, com antes/depois.
6. **Funciona no campo**: app offline para diário, boletim, fotos georreferenciadas e vistoria.
7. **IA local de borda, sem decidir por você**: sugere, cita a fonte, e um humano confirma. Funciona com a IA desligada.

## Módulos

Prefeitura: cadastros · obras e contratos · planilha, projeto, cronograma e eventos · aditivos e serviços a mais · fiscalização e Boletim de Execução · medição e atesto · diário (visão fiscal) · recebimento · execução financeira (referências) · painéis · mapa e transparência · prestação de contas · documentos e assinaturas · ouvidoria · administração e console de IA · relatórios vinculados · previsão.
Empresa: meus contratos · diário · medição · gestão da execução · documentos · pleitos · notificações.
Detalhes e fluxos: [`docs/01-modulos.md`](docs/01-modulos.md) e [`docs/10-execucao-eventos-previsao.md`](docs/10-execucao-eventos-previsao.md).

## Arquitetura em um olhar

```
Navegador (empresa, cidadão) ─┐
Tauri Desktop (fiscal, gestor)├─► API Rust (axum) ─► domínio (regras, eventos, previsão) ─► PostgreSQL 16 (RLS, auditoria, outbox)
App de celular (campo offline)┘        │                                                    └► arquivos (S3/MinIO ou disco)
                                       ├─► leitura de planilha, cronograma e projeto ─► relatórios (PDF, xlsx)
                                       └─► rreia-gate ─► Jev Local ─► llama.cpp / mistral.rs (modelo local)
```
Mais em [`docs/03-arquitetura.md`](docs/03-arquitetura.md).

O **diário de obras da empresa é tela só do app de celular**: não existe no desktop. O app de celular tem como alvo Android, GrapheneOS, LineageOS, HarmonyOS, Apple (iPhone e iPad) e KaiOS, e não depende de serviços do Google. Ele ainda não existe; o que cada plataforma exige está em [`docs/03-arquitetura.md`](docs/03-arquitetura.md) §5.1.

## IA de borda (Prumo + RREIA, Módulo Prefeitura)

24 pontos de IA mapeados por módulo, tela e botão (ditar diário, sugerir item da planilha, classificar linhas da planilha e do cronograma, sugerir agrupador de evento, indícios de conclusão de evento, divergências da medição, minutar glosa, explicar a previsão, "pergunte aos dados", entre outros), com **dez leis específicas** (a IA propõe, o humano decide; números só do código; citação obrigatória; dado não sai da prefeitura; tudo funciona sem IA…).

Verificação de hardware feita pelas fórmulas do RREIA, **sem medição**: o modelo de referência (8B em Q4) cabe em servidor de 16 GB **dedicado**, com velocidade no limite; não cabe com folga se a máquina também hospedar o banco; não cabe em 8 GB. Contas em [`RREIA.md`](RREIA.md) §3.
Veja [`docs/04-ia-borda-rreia.md`](docs/04-ia-borda-rreia.md) e [`RREIA.md`](RREIA.md).

## Documentação

| Doc | Assunto |
|---|---|
| [01 Módulos](docs/01-modulos.md) | Perfis, módulos, fluxos |
| [02 Glossário](docs/02-glossario.md) | Termos do ofício |
| [03 Arquitetura](docs/03-arquitetura.md) | Rust, Tauri, offline, segurança, implantação |
| [04 IA de borda](docs/04-ia-borda-rreia.md) | Onde a IA entra e como é governada |
| [05 UX/UI](docs/05-ux-ui.md) | Telas, navegação, marca, padrões de sugestão e de previsão |
| [06 Banco de dados](docs/06-banco-de-dados.md) | Como adaptar o schema de referência |
| [07 Conformidade](docs/07-conformidade.md) | Lei 14.133, LGPD, PNCP/TCE, acessibilidade |
| [08 Roadmap](docs/08-roadmap.md) | Fases e critérios de aceite |
| [09 Distribuição](docs/09-distribuicao.md) | Releases assinadas, SBOM, implantação |
| [10 Eventos, boletins, previsão](docs/10-execucao-eventos-previsao.md) | Documentos do órgão, duas formas de medir, Boletim de Execução, previsão, relatórios vinculados, serviços a mais |
| [Decisões (ADR)](docs/adr/) | Nome e marca; eventos como forma prioritária; prévia de desktop; diário só no celular |
| [Questões em aberto](docs/QUESTOES-ABERTAS.md) | O que ainda precisa ser decidido |

## Como desenvolver (com o Claude Code)

1. Leia [`CLAUDE.md`](CLAUDE.md) — ele define as regras de ouro e a ordem de construção.
2. A **Fase 0** do [roadmap](docs/08-roadmap.md) (domínio, banco e testes de invariante) está concluída; o que foi e o que não foi testado está em [`docs/relatorio-fase-0.md`](docs/relatorio-fase-0.md). A próxima é a Fase 1.
3. Cada tarefa termina com a *definição de pronto* do `CLAUDE.md`.

O que já roda:

```bash
./scripts/ci-local.sh                              # porteiro antes de cada commit: fmt, clippy e testes
./scripts/ci-local.sh --tudo                       # workspace inteiro, banco, cargo audit e cargo deny
./scripts/db-test.sh                               # o banco em PostgreSQL 16 descartável (precisa de Docker):
                                                   # porte, migrações, paridade Rust × SQL e sabotagem
./scripts/build-windows.sh                         # gera o Prumo.exe da prévia e copia para a Área de Trabalho (WSL + Rust no Windows)
```

Ainda não existe (Fase 1 em diante):

```bash
pnpm -C ui test
cargo tauri dev
```

## Prévia de desktop

`apps/desktop` é uma casca Tauri 2 que abre as telas do Prumo com uma obra fictícia. Serve para ver como está ficando; **não é o sistema**: não tem banco, usuário, assinatura nem trilha, e nada é gravado. O que nela é de verdade são as regras de `crates/dominio`: valor de evento, conferência da medição contra o Boletim de Execução e previsão de término e de pagamento. As telas marcadas "desenho" mostram números fixos. Decisão e limites em [`docs/adr/0003-previa-desktop.md`](docs/adr/0003-previa-desktop.md).

## Segurança e privacidade

Política de vulnerabilidades em [`SECURITY.md`](SECURITY.md). Tratamento de dados pessoais, RIPD e retenção em [`docs/07-conformidade.md`](docs/07-conformidade.md).

## Distribuição

Releases com binários **assinados**, `SHA256SUMS`, **SBOM** e atestado de proveniência. Procedimento em [`docs/09-distribuicao.md`](docs/09-distribuicao.md).

## Licença

**A definir** (ver [questões em aberto](docs/QUESTOES-ABERTAS.md)). Enquanto isso, todos os direitos reservados.

## Créditos

- Conceito **RREIA** (Recursos Responsáveis para IA de Borda): Gabriel Onezio Ferreira.
- Domínio de engenharia civil e schema de referência (`db/reference/`): engenheiro civil colaborador — **confirmar autoria e licença antes de publicar**.
