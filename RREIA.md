# RREIA.md — registro da IA do Prumo (Módulo Prefeitura)

Registro exigido pela skill `/rreia`, preenchido na ordem dos passos dela: onde roda, política de modelo e custo, verificação de compatibilidade, e o modelo de **ações, solicitantes, permissões, leis e atividades**. O agente de programação mantém este arquivo atualizado e **escreve um teste para cada lei**. Onde cada função aparece na tela: `docs/04-ia-borda-rreia.md`.

Nomes: **Prumo + RREIA** na documentação técnica; **Prumo IA Local** na linguagem de venda. O RREIA (Recursos Responsáveis para IA de Borda) é a arquitetura por trás.

> Estado em 12/10/2026: projeto. **Nenhum código de IA existe ainda neste repositório e nenhum número abaixo foi medido.** A máquina de desenvolvimento não foi sondada, porque o sistema não roda nela.

## 1. Onde o sistema roda (passo 1)

A IA de texto roda em **um servidor na prefeitura**, não em cada PC. O aparelho de campo roda só voz curta e classificação leve de imagem, para funcionar offline. A máquina-alvo ainda não existe (questão 9), então os campos abaixo são o **piso adotado**, não um levantamento.

| Campo | Valor | Origem |
|---|---|---|
| Tipo e modelo | A definir. Piso: PC ou servidor sem GPU | Suposição (questão 9) |
| Sistema operacional | A definir. O alvo de distribuição é Linux x86_64 | `docs/09-distribuicao.md` |
| Memória | 16 GB de RAM | Suposição (questão 9) |
| Tipo e banda de memória | DDR4-3200 em dois canais, 51,2 GB/s | **Estimativa teórica**, não medida |
| GPU ou acelerador | Nenhum | Suposição |
| Nível RREIA | R1 | Tabela de níveis da skill |
| Precisa funcionar offline | Sim. Servidor sem depender de internet; campo offline | `docs/03-arquitetura.md` |
| Dedicado ou compartilhado | **A definir.** Muda o veredito (ver §3) | Questão 9 |
| Usuários e latência | Piloto com 1 a 3 fiscais; uma geração por vez, em fila. Tempo aceitável por classe: a definir | `docs/04-ia-borda-rreia.md` §3 |

Perguntas da entrevista que ainda faltam (não adivinhar): marca e modelo da máquina; tipo e velocidade da memória; se a IA divide a máquina com o PostgreSQL e a API; sistema operacional e versão; limite de energia ou calor do local; quantos usuários ao mesmo tempo no pico; tempo de resposta aceitável para o fiscal em campo.

## 2. Política de modelo e custo (passo 2)

| Campo | Valor |
|---|---|
| Rota | **Só local, gratuito** (L8) |
| Modelo local de referência | Llama 3.1 8B em Q4_K_M, usado aqui só para dimensionar. A escolha final depende da licença e da métrica de cada função (LP10) |
| Origem dos pesos e licença | A registrar em `docs/modelos.md` antes de qualquer uso. A licença do Llama é própria; conferir o uso comercial no repositório do modelo |
| Fallback remoto | **Nenhum.** Modelo pago desligado. Só o gestor habilita, por escrito, com teto (L9) e declarando se dados podem sair |
| Teto mensal | R$ 0,00. No teto: recusa clara e fluxo manual (LP7) |
| Dados podem sair do dispositivo | **Não** (LP4) |
| Runtime | Servidor compatível com a API da OpenAI (`llama-server` ou `mistral.rs`), no servidor da prefeitura |
| Decisões tipadas | Jev Local (`crates/rreia-jev`): `choice`, `score`, `noul` |
| Texto livre | Via `crates/rreia-gate`, com citação obrigatória (LP3) e conferência de números (LP2) |
| Parâmetros iniciais, a calibrar | `f = 0,75`; `η = 0,5`; mínimo de 5 tok/s; até 3 tentativas |
| Onde ficam os limites | Um arquivo só (`config/rreia.toml`) para fração de memória, velocidade mínima, contexto, fila, tempos e orçamento. Limiares por função em `config_municipio` |

## 3. Verificação de compatibilidade (passo 3)

Contas feitas com a função `admit` da sonda da skill (`scripts/probe_hardware.py`), passando os valores à mão. **Nada foi medido.** Reserva de 2 GB = só sistema operacional; reserva de 6 GB = estimativa para a mesma máquina hospedar PostgreSQL, API e arquivos.

| Cenário | L1: sobra para o contexto | L3: contexto máximo | L2: piso de velocidade | Veredito |
|---|---|---|---|---|
| **A.** 16 GB DDR4, **dedicado**, 8B Q4 | 0,75 × 16 − 4,9 − 2 = **5,1 GB** | 38.909 tokens | 0,5 × 51,2 ÷ 4,9 = **5,22 tok/s** | Aceito. Folga de velocidade de 4 % sobre o mínimo |
| **B.** 16 GB DDR4, **compartilhado** com banco e API, 8B Q4 | 12 − 4,9 − 6 = **1,1 GB** | 8.392 tokens | 5,22 tok/s | Aceito **sem folga**: com contexto de 8.192, o pico é 11,97 GB de 12 GB |
| **C.** 16 GB DDR4, compartilhado, 3B Q4 | 12 − 2,0 − 6 = 4,0 GB | 34.877 tokens | 12,8 tok/s | Aceito, com folga. Qualidade menor, a medir por função |
| **D.** 32 GB DDR4, compartilhado, 8B Q4 | 24 − 4,9 − 6 = 13,1 GB | 99.945 tokens | 5,22 tok/s | Aceito, com folga de memória |
| **E.** Jetson Orin Nano 8 GB, 8B Q4 | 6 − 4,9 − 2 = **−0,9 GB** | não cabe | não se aplica | **Recusado pela L1** |
| **F.** Jetson Orin Nano 8 GB, 3B Q4 | 6 − 2,0 − 2 = 2,0 GB | 17.438 tokens | 25,5 tok/s | Aceito |

No cenário A com contexto de operação de 8.192 tokens: 4,9 (pesos) + 2 (reserva) + 1,07 (cache) = **7,97 GB de 12 GB permitidos**.

O que isso decide no projeto:

1. **O piso de 16 GB só tem folga se a máquina da IA for dedicada.** Se ela também hospedar o banco e a API, as opções são: máquina separada para a IA, 32 GB, ou modelo de 3B. Cada uma tem custo: hardware, ou qualidade a medir.
2. **Jetson Orin Nano de 8 GB não carrega o modelo de 8B** com estes parâmetros. A tabela de dimensionamento de `docs/04` foi corrigida para 3B nesse nível.
3. **A velocidade no DDR4 está no limite** (5,22 contra 5 tok/s). Qualquer medição real abaixo disso recusa o modelo pela L2; medir antes de prometer prazo de resposta.
4. **Documento grande nunca vai inteiro para o modelo.** Planilha, cronograma e projeto são lidos pelo código e fatiados (linha a linha, prancha a prancha). Entrada acima do contexto é recusada, nunca cortada em silêncio (L3).
5. **Lote fora do expediente.** As leituras de documento (IA-12, IA-19, IA-20, IA-21) são classe P3. Estimativa grosseira: resposta tipada de 40 tokens a 5,22 tok/s leva cerca de 8 s de geração por linha, fora o tempo de leitura do prompt, que não foi estimado. Por isso a heurística em código vem primeiro e a IA só recebe as linhas duvidosas.
6. **Outros modelos entram na mesma conta de memória.** Embeddings (busca), voz (IA-01) e visão (IA-03) **não foram dimensionados**. Antes de ligar qualquer um, refazer a L1 somando tudo o que fica carregado ao mesmo tempo, ou carregar um modelo por vez no lote noturno.

Números que são estimativa: banda de memória (teórica), tamanho dos pesos (aproximado; conferir no cartão do modelo), reserva de 6 GB (palpite a medir na máquina real), todas as velocidades. Medido no hardware real: **ainda não**.

## 4. Ações, solicitantes e permissões (passo 4)

### 4.1 Ações de IA (todas só propõem)

Nenhuma ação `ia.*` escreve em tabela de negócio. Ela devolve **proposta**; a pessoa confirma pela API normal, que revalida tudo.

| Ação | Ponto | Reversibilidade | Quem pode pedir | Classe máx. | Confirmação humana |
|---|---|---|---|---|---|
| `ia.ditar_diario` | IA-01 | leitura | Apontador, responsável técnico | P0 | Apontador revisa e fecha o dia |
| `ia.sugerir_item` | IA-02 | leitura | Apontador, responsável técnico | P0 | Apontador escolhe entre 3 |
| `ia.legendar_e_vincular_foto` | IA-03 | leitura | Autor da foto | P1 | Autor confirma legenda, frente e serviço |
| `ia.pre_checar_medicao` | IA-04 | leitura | Contratada | P1 | Empresa decide enviar |
| `ia.rascunhar_pleito` | IA-05 | leitura | Responsável técnico | P2 | Responsável técnico assina |
| `ia.divergencias_medicao` | IA-06 | leitura, **alto risco** | Fiscal, comissão | P1 | Fiscal aprova ou glosa |
| `ia.minutar_glosa` | IA-07 | leitura, **alto risco** | Fiscal | P1 | Fiscal edita e confirma |
| `ia.resumir_diario` | IA-08 | leitura | Fiscal | P1 | Fiscal valida |
| `ia.classificar_ocorrencia` | IA-09 | leitura | Fiscal | P1 | Fiscal confirma |
| `ia.minutar_notificacao` | IA-10 | leitura | Fiscal | P2 | Fiscal assina |
| `ia.listar_pendencias_recebimento` | IA-11 | leitura | Fiscal, comissão | P2 | Comissão decide |
| `ia.classificar_linha_planilha` | IA-12 | leitura | Planejamento, serviço `lote` | P3 | Planejador revisa a fila; total conferido em código |
| `ia.buscar_composicao` | IA-13 | leitura | Planejamento | P1 | Planejador escolhe |
| `ia.minutar_parecer_aditivo` | IA-14 | leitura | Planejamento | P2 | Parecer humano obrigatório |
| `ia.perguntar_aos_dados` | IA-15 | leitura | Gestor, planejamento | P2 | Só consultas pré-aprovadas |
| `ia.risco_atraso` | IA-16 | leitura | Serviço `lote` | P3 | Gestor lê; não dispara nada |
| `ia.explicar_obra_publica` | IA-17 | leitura | Serviço `lote` | P3 | Regra em código: só campos públicos |
| `ia.triar_denuncia` | IA-18 | leitura | Serviço `ouvidoria` | P2 | Ouvidor ou fiscal confirma |
| `ia.classificar_cronograma` | IA-19 | leitura | Planejamento, serviço `lote` | P3 | Planejador revisa; somas conferidas em código |
| `ia.ler_carimbo_prancha` | IA-20 | leitura | Planejamento, serviço `lote` | P3 | Planejador confirma; nenhuma quantidade é extraída |
| `ia.sugerir_agrupador_evento` | IA-21 | leitura | Planejamento, serviço `lote` | P3 | Planejador confirma linha a linha; valor do evento em código |
| `ia.indicios_conclusao_evento` | IA-22 | leitura, **alto risco** | Fiscal | P1 | Fiscal marca a situação no Boletim de Execução |
| `ia.explicar_previsao` | IA-23 | leitura | Gestor, fiscal | P2 | Só leitura; datas e valores vêm do cálculo |
| `ia.detectar_servico_fora_planilha` | IA-24 | leitura | Fiscal, serviço `api` | P1 | Fiscal ou planejador abre o apontamento |

### 4.2 Ações de negócio (sem IA)

| Ação | Reversibilidade | Quem pode pedir | Confirmação |
|---|---|---|---|
| `planilha.publicar_revisao` | **irreversível** (revisão vigente é imutável) | Planejamento | Diálogo com valor total; soma = valor do contrato |
| `cronograma.publicar_linha_de_base` | **irreversível** | Planejamento | Somas conferidas em código |
| `cronograma.reprogramar` | nova versão; a anterior fica | Planejamento | Motivo e autor obrigatórios |
| `eventos.publicar` | **irreversível** junto com a revisão | Planejamento | Todo serviço com agrupador e quantidade inteira nas frentes |
| `diario.fechar` | reversível por retificação | Autor (empresa) | Nenhum campo de sugestão pendente |
| `boletim_execucao.emitir` | **irreversível** (correção por retificador) | Fiscal com designação vigente | Assinatura do fiscal |
| `medicao.aprovar` / `medicao.glosar` / `medicao.atestar` | **irreversível** | Fiscal, comissão; autor ≠ aprovador | Diálogo com valor; evento exige boletim emitido |
| `servico_extra.aceitar` / `recusar` | reversível até entrar em aditivo | Fiscal | Motivo obrigatório |
| `aditivo.homologar` | **irreversível** | Gestor | Limites em código; parecer anexado |
| `recebimento.definitivo` | **irreversível** | Servidor ou comissão designada | Termo assinado |
| `relatorio.emitir` | **irreversível** (arquivo com hash) | Quem emite o ato correspondente | Lista de registros de origem gravada |
| `previsao.calcular` | leitura (não grava dado oficial) | Qualquer perfil do contrato, serviço `lote` | Nenhuma; resultado marcado "Previsão" |

### 4.3 Solicitantes

| Solicitante | Usa |
|---|---|
| Pessoa: apontador, responsável técnico (contratada) | IA-01 a IA-05 |
| Pessoa: fiscal, comissão | IA-06 a IA-11, IA-22, IA-23, IA-24 |
| Pessoa: planejador, gestor | IA-12 a IA-16, IA-19, IA-20, IA-21, IA-23 |
| Pessoa: cidadão (anônimo) | IA-17, só leitura de texto pré-gerado |
| Serviço `api` | Chamadas interativas em nome do usuário |
| Serviço `lote` | IA-12, IA-19, IA-20, IA-21 em massa; IA-16 noturno; IA-17 pré-geração |
| Serviço `ouvidoria` | IA-18 |

### 4.4 Permissões (chave → classe máxima)

| Chave | Classe máx. | Uso |
|---|---|---|
| `api-campo` | P0 | Comandos de campo (ditar, sugerir item) |
| `api-interativa` | P1 | Fiscal, empresa, planejamento |
| `api-analise` | P2 | Análises sob demanda |
| `servico-lote` | P3 | Leitura de documentos, indexação, noturno, pré-geração |
| `servico-ouvidoria` | P2 | Triagem de denúncia |

A classe efetiva é a **menor** entre a pedida e a da chave (L4). Quem pede mais do que pode é atendido na classe permitida, não recusado.

## 5. Leis (valem sempre; vivem no código)

Estado de todas: **a criar**. Nenhum teste existe ainda. O `rreia-jev` virá do código que acompanha a skill (20 testes com modelo simulado, segundo a skill; **não executados nesta sessão**).

| Lei | Regra | Onde vai morar | Teste que prova |
|---|---|---|---|
| L1 Memória | Pesos + cache + reserva abaixo de `f` da memória física | `rreia-jev` (admissão) | Modelo que não cabe é recusado na partida |
| L2 Banda | `η × banda ÷ GB lidos por token` ≥ mínimo da tarefa | `rreia-jev` | Modelo lento é recusado |
| L3 Contexto | Contexto limitado ao que a memória comporta | `rreia-jev`, `rreia-gate` | Entrada acima do limite devolve erro; documento grande é fatiado, nunca truncado |
| L4 Prioridade | Fila P0 a P3; classe efetiva = mínimo(pedida, chave) | `rreia-jev` | P0 passa na frente de P3; chave P3 não obtém P0 |
| L5 Degradação | Reduz antes de recusar; chega a "zero IA", nunca a "sistema parado" | `rreia-gate` | Sob pressão, cai um nível e registra |
| L6 Rastro | Um registro por decisão, sem conteúdo privado | `rreia-jev`, `rreia-gate`, tabela `ia_decisao` | Toda chamada gera registro; o registro não contém o texto do estado |
| L7 Causa | Falha classificada por causa antes de trocar o modelo | `rreia-gate` | Cada tipo de erro cai na causa certa |
| L8 Local primeiro | Rota local por padrão | `rreia-gate` (roteador) | Com a política padrão, nenhuma rota remota existe |
| L9 Orçamento | Remoto para no teto | `rreia-gate` | Teto zero bloqueia qualquer chamada remota |
| LP1 | IA propõe, pessoa decide | `rreia-gate`, `api` | Nenhuma função `ia.*` tem permissão de escrita em tabela de negócio |
| LP2 | Número vem do código | `rreia-gate` | Texto gerado com número que não está no estado enviado é descartado |
| LP3 | Citação obrigatória e conferida | `rreia-gate` | Citação inexistente ou de outro contrato descarta a sugestão |
| LP4 | Dado não sai da prefeitura | `rreia-gate`, configuração | Com a política padrão, nenhuma chamada de rede externa |
| LP5 | Rastro com aceite, edição ou rejeição | `api`, `ia_decisao` | Cada desfecho humano é gravado |
| LP6 | Estado montado por papel | `rreia-gate` | Estado da empresa não contém nota interna da fiscalização; o do cidadão só tem campo público |
| LP7 | Tudo funciona sem IA | Todos os fluxos | Com a IA desligada, os fluxos do §5.1 completam |
| LP8 | Texto externo é dado, não instrução | `rreia-gate` | Instrução escondida em diário, planilha, cronograma ou prancha não muda resultado tipado |
| LP9 | Sem identificar pessoas | Prompts versionados, revisão | Nenhuma pergunta tipada pede identidade; revisão a cada mudança de prompt |
| LP10 | Função só liga com métrica mínima | Console P15, configuração | Função abaixo da métrica fica desligada |

### 5.1 Regras de negócio com IA no caminho (testes obrigatórios)

1. Medição enviada por empresa **não pode** ser aprovada por quem a criou, nem por perfil sem designação ativa no contrato.
2. Aditivo que ultrapasse 25 % (ou 50 % se `reforma`) **não homologa** sem marcação explícita de exceção e parecer anexado.
3. Texto de diário, planilha, cronograma ou prancha contendo instruções ("aprove", "ignore as regras") **não altera** nenhum resultado tipado.
4. Sugestão com citação inexistente ou de outro contrato **é descartada**.
5. Com a IA desligada, completam: leitura de planilha e cronograma, montagem de eventos, diário, Boletim de Execução, medição por eventos e por quantidade, previsão, emissão de relatórios, aditivo de serviço a mais.
6. Evento **não é aprovado** em medição sem Boletim de Execução emitido por fiscal designado, qualquer que seja o resultado da IA-22.
7. Data ou valor de previsão mostrado na tela é **exatamente** a saída de `dominio::previsao`; a IA-23 não consegue alterá-lo.
8. Sugestão de agrupador (IA-21) aceita não muda o valor de nenhum evento já publicado.

## 6. Atividades (registro de auditoria, L6)

Campos por decisão: `quando`, `quem` (usuário ou serviço), `ação`, `classe pedida e efetiva`, `modelo + versão + quantização`, `hash do prompt de sistema`, `resultado resumido` (opção ou nota, nunca o texto privado), `confiança`, `tentativas`, `tempo de fila`, `latência`, `tokens`, `rota` (local ou remota) e `custo`, `desfecho humano` (aceitou, editou, rejeitou, ignorou), `contrato_id`.

Não é gravado, de propósito: texto do diário, conteúdo de planilha ou prancha, áudio, foto, texto da denúncia. Só referências (ids).

Retenção: conforme a tabela de temporalidade do município (a definir). Acesso: Admin TI vê métricas; só Controle Interno e auditor autorizado leem o rastro por contrato.

## 7. Ainda não testado

- Nenhum modelo real foi executado. Nenhuma velocidade, pico de memória ou tempo até o primeiro token foi medido.
- A sonda de hardware não rodou em nenhuma máquina-alvo.
- Os 20 testes do `rreia-jev` não foram executados nesta sessão.
- Nenhuma função IA-01 a IA-24 tem conjunto rotulado nem métrica.
- Modelos de voz, visão e embeddings não foram escolhidos nem dimensionados.
- Calibração da confiança (a probabilidade é escrita pelo modelo, não lida dos logits) não foi verificada.
- O método de previsão não usa IA, mas também não foi implementado nem validado com dados de obra.

## 8. Checklist do agente

- [ ] Responder as perguntas do §1 e rodar a sonda no servidor-alvo; veredito L1 a L3 registrado em `docs/modelos.md`.
- [ ] Decidir dedicado × compartilhado e refazer a tabela do §3 com a reserva medida.
- [ ] Testes das leis L1 a L9 e LP1 a LP10 passam com modelo simulado.
- [ ] Taxa de respostas válidas e calibração medidas em conjunto rotulado antes de ligar cada função (LP10).
- [ ] Parecer jurídico antes de ligar IA-06, IA-07 e IA-22 (afetam pagamento).
- [ ] Relatório do que foi **estimado**, **medido** e **não testado**.
