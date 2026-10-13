# 04 · IA local de borda com o RREIA — Módulo Prefeitura

Este documento diz **onde** a IA entra no Prumo (módulo, tela, botão), **como** ela é governada pelo RREIA e **o que ela nunca faz**. A teoria (leis L1–L9, níveis R0–R3, Jev Local) está no documento do RREIA (`RREIA — Arquitetura de Recursos Responsáveis para IA de Borda`, v0.2). Aqui está a aplicação ao setor público.

Nomes: **Prumo + RREIA** nesta documentação; **Prumo IA Local** na linguagem de venda e no material para a prefeitura. O RREIA é a arquitetura por trás; o usuário final vê só o rótulo "Sugestão".

> Estado: projeto. Nenhuma velocidade abaixo foi medida neste sistema; usar a Seção 9 do RREIA para medir antes de prometer desempenho a uma prefeitura. O veredito de compatibilidade (L1–L3) com as contas está em `RREIA.md` §3.

## 1. Princípios do módulo Prefeitura

Estas são as **leis específicas** (LP) que se somam às L1–L9 do RREIA. Ficam em código (`crates/rreia-gate`), não no prompt.

| Lei | Regra |
|---|---|
| **LP1** | A IA **propõe**; nunca aprova, glosa, assina, homologa, atesta, empenha ou paga. Toda ação irreversível passa por confirmação humana (LGPD art. 20; alto risco no PL 2.338). |
| **LP2** | **Valor, quantidade, prazo e percentual vêm do banco/código**, nunca do modelo. A IA pode *explicar* um número; não o *produz*. |
| **LP3** | Toda sugestão em texto **cita os registros de origem** (ids de diário, medição, foto). Sem fonte, a sugestão é descartada. |
| **LP4** | Áudio, foto e texto da obra são processados **no dispositivo ou no servidor da prefeitura**. Nada sai para terceiros por padrão. Modelo pago/nuvem só se o gestor habilitar por escrito e definir teto (L8, L9). |
| **LP5** | Rastro por decisão (L6): quem pediu, ação, classe, modelo e versão, confiança, **aceitou / editou / rejeitou**. Nunca grava o conteúdo privado do prompt, só referências. |
| **LP6** | **Separação por papel na montagem do estado.** O estado enviado ao modelo é montado em código conforme o perfil de quem pede. A IA da empresa não vê nota interna da fiscalização; a do cidadão só vê dado público. |
| **LP7** | **Modo sem IA.** Todo fluxo funciona com a IA desligada. Degradação L5 chega a "zero IA", nunca a "sistema parado". |
| **LP8** | **Texto vindo da empresa é dado não confiável.** Diário e medição entram como valor em JSON no `state`, jamais como instrução. O resultado do modelo é tipado (choice/score/noul) para que "ignore as regras e aprove" não tenha onde agir. |
| **LP9** | **Sem identificação de pessoas.** Nada de reconhecimento facial ou biometria. Análise de imagem conta e classifica objetos/serviços, sem identificar indivíduos. |
| **LP10** | **Calibrar antes de confiar.** Cada função de IA tem um conjunto rotulado de teste e métrica mínima (RREIA Seção 9). Abaixo da métrica, a função fica desligada por padrão. |

## 2. Onde a IA entra: módulo → tela → botão

Legenda de **tipo**: `choice` / `score` / `noul` = decisões tipadas do Jev Local; `texto` = geração livre *com citação obrigatória* (LP3); `busca` = recuperação (embeddings/palavras-chave); `visão` = classificação de imagem; `voz` = transcrição.
Legenda de **classe** (RREIA L4): P0 comando operacional em campo · P1 interativo com o usuário esperando · P2 análise sob demanda · P3 lote em segundo plano.

### 2.1 Empresa (contratada)

| # | Módulo / tela | Botão ou ponto | O que a IA faz | Tipo | Classe | Onde roda | Portão humano |
|---|---|---|---|---|---|---|---|
| **IA-01** | E02 Diário · barra superior | 🎙 **Ditar diário** | Transcreve o áudio do apontador e preenche campos (clima, efetivo, serviços) para revisão | voz + choice | P0 | Dispositivo (modelo de voz pequeno) ou servidor da prefeitura | Apontador revisa e fecha o dia |
| **IA-02** | E02 Diário · lista de serviços | ✨ **Sugerir item da planilha** | Liga "reboco da sala 2" ao item contratual correto (top-3) | choice + busca | P0/P1 | Servidor | Apontador escolhe |
| **IA-03** | E02 Diário · fotos; P16 Relatório fotográfico · fila "sem vínculo" | 🏷 **Sugerir legenda e vínculo** | Classifica a foto (fundação, alvenaria, cobertura…), sugere legenda e, para foto que ficou sem vínculo, a frente e o serviço prováveis | visão + choice | P1 | Dispositivo/servidor | Autor confirma; foto só entra em relatório com vínculo confirmado |
| **IA-04** | E03 Medição · antes de enviar | 🔎 **Pré-checagem** | **Regras determinísticas** (saldo, período, quantidade > RDO?) + IA só para *explicar* a inconsistência em linguagem simples | regras + texto | P1 | Servidor | A empresa decide enviar |
| **IA-05** | E06 Pleitos | ✍ **Rascunhar justificativa** | Monta minuta a partir de ocorrências, chuvas e RDO do período, com citações | texto | P2 | Servidor | Responsável técnico revisa e assina |

### 2.2 Fiscalização

| # | Módulo / tela | Botão ou ponto | O que a IA faz | Tipo | Classe | Onde roda | Portão humano |
|---|---|---|---|---|---|---|---|
| **IA-06** | P06 Análise de medição · coluna "alertas" | ⚠ **Divergências** | Cruza medição × diário × fotos × cronograma × Boletim de Execução e **ordena por risco** (`score`); cada alerta aponta as linhas. Em medição por eventos, o alvo é o evento declarado concluído | score + regras | P1 | Servidor | Fiscal aprova ou glosa |
| **IA-07** | P06 · item com glosa | ✍ **Redigir motivo da glosa** | Minuta o motivo com citação (nº do RDO, foto, cláusula) | texto | P1 | Servidor | Fiscal edita e confirma |
| **IA-08** | P07 Diário · validação | ✅ **Resumo do dia** | Resume o RDO e destaca o que mudou desde o dia anterior | texto | P1 | Servidor | Fiscal valida |
| **IA-09** | P05 Ocorrências · nova | 🗂 **Classificar** | Categoria (`choice`) e urgência (`score`) a partir do texto/foto | choice + score | P1 | Servidor | Fiscal confirma |
| **IA-10** | P05 Notificação · editor | ✍ **Minutar notificação** | Rascunho com prazo de resposta do **contrato** (campo do banco) e fundamento já cadastrado | texto | P2 | Servidor | Fiscal assina |
| **IA-11** | P08 Recebimento | 📋 **Lista de pendências** | Sugere checklist a partir de ocorrências abertas e glosas | texto + busca | P2 | Servidor | Comissão decide |

### 2.3 Gestão e planejamento

| # | Módulo / tela | Botão ou ponto | O que a IA faz | Tipo | Classe | Onde roda | Portão humano |
|---|---|---|---|---|---|---|---|
| **IA-12** | P03 Importação de planilha · revisão | 🧹 **Classificar linhas** | Quando a heurística falha, classifica linha (`grupo` / `servico` / `continuacao` / `rodape`, enum já existente) com confiança; **baixa confiança vai para fila de revisão** | choice | P3 (lote) | Servidor | Planejador revisa a fila; total conferido por código |
| **IA-13** | P03 Orçamento · busca de composição | 🔍 **Achar código SINAPI/SICRO** | Busca semântica por descrição | busca (embeddings) | P1 | Servidor | Planejador escolhe |
| **IA-14** | P04 Aditivo · parecer técnico | ✍ **Rascunhar minuta técnica** | Texto a partir da simulação de limites **calculada em código** (art. 125/127) e dos apontamentos de serviço a mais aceitos, com citação de cada um | texto | P2 | Servidor | Parecer humano obrigatório |
| **IA-15** | P10 Painel · caixa "Pergunte" | 💬 **Pergunte aos dados** | Escolhe **uma consulta pré-aprovada** (`choice` entre modelos de consulta) e preenche parâmetros; **não gera SQL livre** | choice | P2 | Servidor | Resultado vem do banco |
| **IA-16** | P10 Painel · "Obras em risco" | 📉 **Risco de atraso** | Pontua cada obra a partir do desvio **já calculado** pela previsão (P17), chuva, glosas e ocorrências. É uma nota; não altera nenhuma data prevista | score | P3 (noturno) | Servidor | Gestor lê; não dispara ação sozinho |

### 2.4 Cidadão e ouvidoria

| # | Módulo / tela | Botão ou ponto | O que a IA faz | Tipo | Classe | Onde roda | Portão humano |
|---|---|---|---|---|---|---|---|
| **IA-17** | P11 Ficha pública da obra | 🗣 **Explicar em linguagem simples** | Resume andamento com **dados públicos já publicados** | texto | P3 (pré-gerado, em cache) | Servidor | Texto passa por regra: só campos públicos |
| **IA-18** | P14 Ouvidoria | 🗂 **Triar denúncia** | Aponta obra provável e categoria; gera ocorrência *pré-preenchida* | choice | P2 | Servidor | Ouvidor/fiscal confirma |

### 2.5 Documentos do órgão, eventos, previsão e serviços a mais

Contexto e regras em `10-execucao-eventos-previsao.md`.

| # | Módulo / tela | Botão ou ponto | O que a IA faz | Tipo | Classe | Onde roda | Portão humano |
|---|---|---|---|---|---|---|---|
| **IA-19** | P03 Leitura do cronograma · revisão | 🧹 **Classificar linhas e colunas** | Quando a heurística falha, diz quais linhas são etapas, quais colunas são períodos e a que grupo da EAP ou agrupador a etapa corresponde | choice | P3 (lote) | Servidor | Planejador revisa; somas (100 % por etapa, total = valor da revisão) conferidas por código |
| **IA-20** | P03 Projeto · pranchas | 📐 **Ler carimbo e sugerir vínculo** | A partir do texto que o **código** extraiu do PDF, preenche número, título, disciplina e revisão da prancha, e sugere o grupo da EAP ou a frente a que ela se refere | choice + busca | P3 (lote) | Servidor | Planejador confirma. **Nenhuma quantidade é extraída do desenho** |
| **IA-21** | P03 Eventos · montagem | 🧩 **Sugerir agrupador** | Quando o órgão não manda o eventograma, sugere em qual agrupador (entre os que o planejador criou) cada serviço entra | choice | P3 (lote) | Servidor | Planejador confirma linha a linha, sem aceite em lote; valor do evento calculado em código |
| **IA-22** | P05 Boletim de Execução · linha do evento | 🔎 **Indícios de conclusão** | Cruza diário, fotos e vistoria dos serviços do evento e devolve uma nota de evidência, com o que falta ("o diário não cita o concreto dos pilares do Térreo") | score + regras | P1 | Servidor | **Fiscal marca a situação.** O resultado nunca preenche situação nem percentual |
| **IA-23** | P17 Previsão · "Como foi calculado" | 💬 **Explicar a previsão** | Explica em linguagem simples por que a data mudou, citando eventos, boletins e diários. Datas e valores são **entrada**, não saída | texto | P2 | Servidor | Só leitura. Texto com número que não está no cálculo é descartado (LP2) |
| **IA-24** | P07 Diário · validação; P05 Boletim de Execução | ➕ **Serviço fora da planilha?** | Avisa que uma linha do diário parece não ter serviço correspondente na planilha vigente (`noul`) e se parece acréscimo de serviço existente ou serviço novo (`choice`) | noul + choice | P1 | Servidor | Fiscal ou planejador decide abrir o apontamento de serviço a mais |

Observações de recurso (RREIA L1–L3) para estas funções:

- **Documento inteiro nunca vai para o modelo.** O código lê o arquivo e envia uma linha, uma etapa ou um carimbo por pergunta. Isso mantém a entrada muito abaixo do limite de contexto e torna a resposta tipada.
- IA-19, IA-20 e IA-21 rodam em **lote, fora do expediente**, e só para o que a heurística não resolveu.
- IA-20 trabalha sobre **texto** extraído por código. Não exige modelo de visão. Prancha escaneada fica para digitação.

### 2.6 O que **não** terá IA (de propósito)

- Cálculo de medição, valor de evento, glosa em valor, limites do art. 125, fator do art. 127, retenções, reajuste, curva S: **somente código determinístico testado**.
- **Previsão de término, de desembolso e de recebimento:** cálculo em `crates/dominio::previsao`. A IA explica, não calcula.
- **Situação e percentual do Boletim de Execução:** só o fiscal informa.
- Levantamento de quantidade a partir de projeto.
- Montagem dos relatórios (planilha de medição, relatório fotográfico, caderno, planilha de aditivo): só código, a partir dos vínculos.
- Atesto, aprovação, assinatura, homologação, liquidação, pagamento.
- Julgamento de licitação ou de habilitação de empresa.
- Qualquer coisa que classifique pessoas (servidores, operários) por desempenho.

## 3. Onde cada IA roda: três lugares

```
┌──────────────────────────── Prefeitura (servidor de borda) ───────────────────────────┐
│  api (Rust) ──► rreia-gate ──► rreia-jev (Jev Local) ──► llama-server / mistral.rs    │
│                    │  L1–L3 admissão · L4 fila P0–P3 · L5 degradação · L6 rastro      │
│                    └──► busca (pgvector + embeddings pequenos)                        │
└───────────────────────────────────────────────────────────────────────────────────────┘
      ▲  HTTPS                                   ▲  HTTPS
┌─────┴─────────────┐                    ┌───────┴──────────────┐
│ Desktop (Tauri)   │                    │ Campo (Tauri Android)│
│ fiscal / gestor   │                    │ voz e visão leves no │
│ só chama o servidor│                   │ aparelho; resto no   │
└───────────────────┘                    │ servidor quando online│
                                         └──────────────────────┘
```

Decisão importante: **o computador da prefeitura é um servidor, não cada PC.** Rodar modelo em cada desktop multiplica hardware e dificulta auditoria. No aparelho de campo roda só o que precisa funcionar **offline**: transcrição de voz curta e classificação leve de imagem; o resto aguarda sincronizar.

### Dimensionamento (RREIA Seção 3, adaptado)

| Cenário | Nível RREIA | Hardware de referência | Modelo de texto | Observação |
|---|---|---|---|---|
| Piloto, 1 a 3 fiscais | **R1** | PC 16 GB, sem GPU, **dedicado à IA** | 4B–8B Q4 | 8B Q4: piso de 5,22 tok/s calculado (DDR4), **não medido**. Serve IA-08, IA-09, IA-12, IA-19 a IA-21 em lote |
| Piloto na mesma máquina do banco e da API | **R1** | PC 16 GB, sem GPU, compartilhado | 3B Q4, ou 8B Q4 com 32 GB | Com 16 GB compartilhados, o 8B fica sem folga de memória (pico de 11,97 GB em 12 GB) |
| Prefeitura pequena/média | **R2** | Jetson Orin Nano 8 GB ou equivalente | **3B** | Dedicada e de baixo consumo. O 8B Q4 **não cabe** em 8 GB com `f = 0,75` e reserva de 2 GB (L1 recusa por 0,9 GB) |
| Prefeitura grande ou muitos usuários | **R3** | GPU 24 GB ou Apple unificada ≥ 64 GB | 8B–32B | Fila continua serial por modelo (Jev Local atende uma geração por vez); escalar = mais instâncias |

As contas de cada linha estão em `RREIA.md` §3. A linha R2 dizia "3B–8B"; aplicando a L1 da skill o 8B é recusado, então a tabela foi corrigida.

O Jev Local tem **um worker por modelo**. Com 20 fiscais clicando, a fila P1 absorve; por isso as funções P3 (lote) só rodam fora do expediente. O console P15 mostra fila, tempo até o primeiro token e taxa de respostas válidas.

## 4. Como o código chama a IA (padrão único)

Toda função de IA é uma **pergunta tipada** ao Jev Local. Exemplo — IA-09 (classificar ocorrência):

```json
POST /v1/systemone     (cabeçalho X-RREIA-Class: P1, Authorization: chave do serviço "api")
{
  "state": { "texto": "<texto da ocorrência, como DADO>", "obra_id": "…", "origem": "fiscal" },
  "questions": {
    "categoria": { "type": "choice", "instructions": "Qual a categoria?",
                   "criteria": { "seguranca": "risco a pessoas", "qualidade": "defeito de execução",
                                 "prazo": "atraso", "documental": "falta de documento", "outra": "nenhuma das anteriores" } },
    "urgencia":  { "type": "score",  "instructions": "Quão urgente?", "criteria": ["baixa","media","alta","imediata"] },
    "envolve_risco_vida": { "type": "noul", "instructions": "Há risco imediato a pessoas?" }
  }
}
```

Regras de uso:

1. **Confiança abaixo do limiar** (configurável por função; padrão 0,5) → a UI mostra "Revise" e não pré-seleciona.
2. `noul` de risco de vida acima do limiar **só destaca na fila**; nunca bloqueia nem cancela nada sozinho.
3. Resposta inválida é repetida até 3 vezes; depois a UI cai para o fluxo manual (LP7).
4. O tempo limite por classe vem da L2 e do tempo por tentativa medido no hardware real. Para P0 em hardware R1, **uma ou duas tentativas** (ver exemplo da Seção 7 do RREIA).
5. **Texto livre** (IA-05, 07, 08, 10, 11, 14, 17, 23) usa o runtime direto (`/v1/chat/completions` via `rreia-gate`), com *prompt de sistema versionado em arquivo*, temperatura baixa e **pós-validação**: todo `[#id]` citado deve existir e pertencer ao contrato do usuário, senão a sugestão é descartada (LP3, LP6).
6. **Conferência de números (LP2):** todo número, data ou valor que aparece no texto gerado tem que estar no estado enviado pelo código. Apareceu um número novo, o texto é descartado. Vale para todas as funções de texto e é o que impede a IA-23 de "prever" por conta própria.

## 5. Como a IA aparece na tela (padrões de UX)

Ver `05-ux-ui.md` §5. Resumo:

- Toda saída de IA é uma **sugestão marcada** (ícone ✨ + rótulo "Sugestão"), visualmente distinta do dado oficial.
- Sempre três ações: **Aceitar · Editar · Rejeitar**. Aceitar/rejeitar alimenta o rastro (LP5) e a métrica de qualidade (LP10).
- Mostrar **"Por quê"** (fontes clicáveis) e a confiança em três níveis (Alta / Média / Revise), não em porcentagem.
- Estado "IA indisponível / desligada" é normal e discreto; o botão some ou fica cinza com tooltip, e o fluxo manual continua igual.
- O texto aceito vira dado do usuário (autoria humana); o campo guarda `assistido_por_ia = true` para auditoria.

## 6. Ética e conformidade (checklist do RREIA aplicado)

- [ ] Classificar cada função IA-xx por risco, pela finalidade (tabela §2). Funções que *afetam o pagamento da empresa* (IA-06, IA-07, IA-22) são tratadas como **alto risco**: supervisão humana, documentação, teste, explicação.
- [ ] Informar na interface que há IA envolvida (rótulo "Sugestão").
- [ ] RIPD (relatório de impacto) preparado: há foto de obra com pessoas, localização de equipes e dados de servidores e empresas. Modelo em `docs/07-conformidade.md`.
- [ ] Registro de toda decisão (L6, LGPD art. 37) sem guardar conteúdo privado.
- [ ] Licença de cada modelo conferida e registrada em `docs/modelos.md` antes de uso comercial (Llama tem licença própria; Qwen e Mistral citados como Apache 2.0 na fonte do RREIA; confirmar no repositório de cada um).
- [ ] Medir viés e calibração **no conjunto real de dados**, com amostra rotulada por engenheiros.
- [ ] Revisão jurídica antes de qualquer uso que influencie pagamento.

## 7. Plano de entrega da IA (depois do núcleo sem IA)

1. `rreia-gate` + `rreia-jev` integrados, com **modelo simulado** nos testes (como no RREIA).
2. IA-12, IA-19 e IA-21 (leitura de planilha, cronograma e montagem de eventos) e IA-09 (ocorrências): baixo risco, alto valor, bom conjunto de teste. São as que destravam a medição por eventos.
3. IA-02, IA-01 e IA-03 (diário e fotos): ganho grande para o apontador, mas exige teste real com aparelho de campo.
4. IA-20 (pranchas), IA-23 (explicar previsão) e IA-24 (serviço fora da planilha).
5. IA-06, IA-07 e IA-22: só após conjunto rotulado e aprovação do jurídico.
6. Painel IA no console P15: métricas da Seção 9 do RREIA, botão "desligar IA" por função.
