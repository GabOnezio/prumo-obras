# 07 · Conformidade, segurança e LGPD

> Não é aconselhamento jurídico. Este documento lista **o que o sistema precisa suportar**; cada item deve ser validado pela assessoria jurídica e pelo controle interno do município antes de produção. Onde a lei remete a "regulamento", o sistema **recebe o valor por configuração**.

## 1. Lei 14.133/2021 (licitações e contratos) — o que vira regra no sistema

| Tema | Fonte | Como o sistema trata |
|---|---|---|
| Fiscalização por fiscais designados | art. 117 *caput* | Entidade `designacao` com portaria, vigência e substituto; fiscal só age no contrato onde está designado e em vigor |
| Registro de ocorrências e providências | art. 117 §1º | Módulo Fiscalização (ocorrência, notificação, plano de ação) |
| Comunicar o que excede a competência do fiscal | art. 117 §2º | Fluxo de escalonamento para gestor/superior com prazo |
| Apoio do jurídico e controle interno | art. 117 §3º | Perfil de leitura + parecer anexado ao aditivo |
| Terceiros que assistem o fiscal | art. 117 §4º | Perfil "assistente" **sem** poder de atesto; termo de confidencialidade anexado |
| Alteração unilateral: acréscimos/supressões | art. 125 · `TODO(jurídico)` questão 40 | **25%** do valor inicial atualizado; **50%** para reforma de edifício/equipamento (`contrato.reforma`); cálculo em código |
| Preço de item novo | art. 127 · `TODO(jurídico)` questão 40 | Fator = proposta ÷ orçamento-base (`fator_art127`) |
| Recebimento provisório e definitivo (obras) | art. 140, I | Termos detalhados; provisório pelo fiscal, definitivo por servidor/comissão designada |
| **Prazos de recebimento** | art. 140 §3º | **Configuração por município/contrato** (a lei não fixa dias) |
| Responsabilidade pela solidez e segurança | art. 140 §6º · `TODO(jurídico)` | Garantia da obra **≥ 5 anos** com contagem e alertas; edital pode prever mais |
| Regimes de execução | art. 46 | Enum `regime_execucao` |
| Medição e pagamento por etapas do cronograma nos regimes de preço global, integral, tarefa, integrada e semi-integrada | art. 46 §9º · `TODO(jurídico)` | Forma de medir **`eventos`** sugerida para esses regimes; aviso quando a forma escolhida contraria o regime; a escolha é humana e fica registrada (ver `10-execucao-eventos-previsao.md` §3) |
| Formalização do aditivo como condição para executar o acréscimo | art. 132 · `TODO(jurídico)` | Apontamento de serviço a mais guarda data, justificativa e data da formalização; nada é medido antes do aditivo homologado. O sistema não embute prazo |
| Prazos de envio, análise, atesto, liquidação e pagamento da medição | Contrato, edital e regulamento municipal | **Configuração por município/contrato.** Usados só para calcular a previsão de recebimento, nunca para aprovar ou bloquear |
| BIM | art. 19 §3º | Módulo opcional de integração IFC, fase tardia |

**Conferir** no texto oficial antes de produção: numeração dos artigos citados, atualizações posteriores à data deste documento (12/10/2026) e regulamento municipal. As duas linhas marcadas `TODO(jurídico)` foram **citadas de memória, sem consulta ao texto oficial**; não transformar em regra de código antes da conferência (questão 23).

**Previsão não é ato administrativo.** As datas e valores previstos pelo sistema são estimativas calculadas; não criam direito para a contratada nem obrigação para o município. O texto do aviso que acompanha a previsão precisa de revisão jurídica (`05-ux-ui.md` §7).

## 2. Publicação e controle externo

| Alvo | O que se espera do sistema | Observação |
|---|---|---|
| **PNCP** | Publicar/atualizar contratos, aditivos e termos | Adaptador `prestacao-contas/pncp`; fila com reenvio e protocolo guardado |
| **Tribunal de Contas do estado** | Layout mensal/anual de acompanhamento | **Um adaptador por tribunal.** Qual estado define o layout (ex.: SIM-AM no Paraná; outros estados têm sistemas próprios). Ver `QUESTOES-ABERTAS.md` |
| **Obrasgov.br / Caixa (repasse)** | Dados de obras com recursos federais; relatórios de medição por eventos | O schema de referência já modela BM/PLE/RRE |
| **Portal de transparência / LAI (Lei 12.527/2011)** | Publicação ativa de obras, valores e andamento | Módulo P11 + dados abertos (CSV/JSON) |

## 3. LGPD (Lei 13.709/2018)

| Item | Aplicação neste sistema |
|---|---|
| Bases legais | Execução de política pública / obrigação legal (art. 7º, II e III) para servidores e empresas; confirmar com o encarregado |
| Dados pessoais tratados | Servidores (nome, matrícula, cargo), responsáveis técnicos (CPF, conselho), operários citados no efetivo, **fotos de obra com pessoas**, geolocalização de equipes, denunciantes |
| Minimização | Efetivo no diário por **função e quantidade**, não por nome, salvo exigência contratual; CPF armazenado cifrado/hashed quando possível |
| Relatório fotográfico | Fotos de obra podem mostrar operários. O relatório interno (medição, Boletim de Execução) segue a base legal do contrato; o que vai ao portal público passa por revisão humana e não deve permitir identificar pessoas. Sem reconhecimento facial (LP9) |
| Projeto e documentos do órgão | Pranchas e memoriais podem trazer nome, registro profissional e assinatura de responsáveis técnicos; acesso restrito aos perfis do contrato |
| Encarregado (DPO) | Cadastrar contato no portal e no rodapé |
| Registro das operações | Art. 37: `auditoria` + `ia_decisao` |
| RIPD | Art. 38: modelo em `docs/modelos/ripd-obras.md` (criar), cobrindo foto/geolocalização e IA |
| Decisões automatizadas | Art. 20: IA nunca decide; revisão humana sempre; explicar critérios (aba "Por quê") |
| Denunciante | Anonimato opcional; separar identidade do conteúdo |
| Retenção | Tabela de temporalidade do município; contratos e diários costumam exigir guarda longa |
| Direitos do titular | Canal e fluxo para acesso, correção, eliminação onde cabível |
| Incidentes | Plano de resposta e comunicação (ver `SECURITY.md`) |

## 4. Assinatura eletrônica

Lei 14.063/2020 define níveis (simples, avançada, qualificada); ICP-Brasil e MP 2.200-2/2001 cobrem a qualificada. O sistema tem uma **interface de provedor de assinatura** (`trait AssinadorDocumento`) com implementações plugáveis: assinatura por login+TOTP com carimbo e hash (simples/avançada, conforme regra do município), gov.br, certificado A1/A3. **Qual nível é exigido em cada documento é decisão jurídica do município** e fica em `config_municipio`.

## 5. Diário de obras e responsabilidade técnica

- O diário de obras eletrônico deve suprir o "livro de ordem" onde a regra profissional/contratual exigir (conferir a norma do conselho profissional vigente e o edital).
- ART/RRT do responsável técnico é requisito cadastral do contrato; sistema alerta vencimento e ausência.

## 6. Segurança da informação (mínimos de produção)

- Criptografia em trânsito (TLS 1.2+) e em repouso (disco/volume e backups).
- Autenticação forte para fiscal, gestor e admin (TOTP obrigatório).
- Princípio do menor privilégio e segregação de funções.
- Log imutável de ações sensíveis; retenção definida.
- Gestão de vulnerabilidades: `cargo audit`/`cargo deny` em CI; dependências travadas; atualização com changelog.
- Backups 3-2-1, **teste de restauração** registrado.
- Testes de intrusão antes da primeira prefeitura em produção.
- Plano de continuidade: prefeitura continua medindo e fiscalizando em papel/planilha enquanto o sistema estiver fora (procedimento documentado).

## 7. Acessibilidade

WCAG 2.2 AA, eMAG, leitor de tela, navegação por teclado, alto contraste, tamanho de fonte ajustável, legendas em fotos relevantes. Auditoria de acessibilidade antes do portal público.

## 8. Propriedade intelectual e licenças

- Confirmar autoria/licença do schema de referência e de qualquer código do APK do engenheiro antes de publicar.
- **Marca "Prumo":** antes de divulgar, fazer busca de marca no INPI (classes de software e de serviços de engenharia) e checar o domínio (questão 12).
- Registrar a licença de **cada modelo de IA** em `docs/modelos.md`. Licenças diferem (a do Llama é própria; outras são Apache 2.0 conforme as fontes do RREIA) e algumas restringem uso comercial.
- RREIA: autoria de Gabriel Onezio Ferreira; manter `CITATION.cff` e referência ao DOI quando existir.
