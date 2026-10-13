# 10 · Execução por eventos, boletins, previsão e relatórios vinculados

> Este documento acrescenta ao núcleo do Prumo:
> 1. a leitura dos três documentos que **o órgão fornece**: planilha orçamentária, projeto e cronograma;
> 2. as **duas formas de medir**, com **eventos como forma prioritária** e o boletim de medição por quantidade como segunda forma;
> 3. o **Boletim de Execução**, documento da fiscalização;
> 4. a **previsão** de execução (prazos) e de recebimentos, a partir do término de cada evento;
> 5. os **relatórios gerados pelo sistema, todos vinculados à planilha**: planilha de medição, relatório fotográfico, boletim de execução, planilha de aditivo;
> 6. os **serviços a mais**, que viram aditivo.
>
> Estado: projeto. Nada aqui foi implementado nem testado. Onde o texto diz "método inicial", "a confirmar" ou `TODO(jurídico)`, há uma linha em [`QUESTOES-ABERTAS.md`](QUESTOES-ABERTAS.md) (itens 15 a 24). Decisão registrada em [`adr/0002-eventos-como-forma-prioritaria.md`](adr/0002-eventos-como-forma-prioritaria.md).

## 1. Ideia central: tudo aponta para a planilha

O serviço da planilha orçamentária (`item_contratual`) é a âncora. Diário, foto, boletim, medição, aditivo e relatório guardam o **id** do serviço, da frente ou do evento a que se referem. Por isso o sistema consegue montar qualquer relatório sozinho: ele só percorre os vínculos.

```
ÓRGÃO fornece ─► planilha orçamentária ─► serviço (item contratual)      ◄─ âncora de tudo
                 projeto (pranchas)    ─► prancha ↔ grupo da EAP / frente
                 cronograma            ─► início e término previstos de cada evento

serviço ─► quantidade por frente de obra ─► EVENTO (agrupador × frente)
                                              ▲           ▲            ▲
   EMPRESA  diário: serviço executado + foto ─┘           │            │
   FISCAL   Boletim de Execução: conferiu no local ───────┘            │
   EMPRESA  medição: evento concluído (ou quantidade) ─────────────────┘
                                              │
   SISTEMA  previsão de término e de recebimento, planilha de medição, relatório
            fotográfico, caderno de medição, planilha de aditivo
```

Exemplo que atravessa o documento (dados **fictícios**, município de Exemplo, Contrato 045/2026, Ampliação da Escola Municipal):

| Evento (agrupador × frente) | Serviços da planilha que o compõem | Qtd. na frente | Preço unit. | Valor |
|---|---|---:|---:|---:|
| **Estrutura: pilares × Térreo** | Fôrma de pilar (m²) | 96,00 | 62,30 | 5.980,80 |
| | Armadura CA-50 (kg) | 1.150,00 | 9,84 | 11.316,00 |
| | Concreto fck 25 MPa (m³) | 11,10 | 785,40 | 8.717,94 |
| | **Valor do evento** | | | **26.014,74** |
| **Alvenaria × Térreo** | Alvenaria de vedação, bloco cerâmico (m²) | 160,00 | 89,15 | 14.264,00 |
| | Chapisco em alvenaria (m²) | 320,00 | 7,43 | 2.377,60 |
| | **Valor do evento** | | | **16.641,60** |

O valor do evento é sempre `Σ arredonda(quantidade na frente × preço unitário)`, serviço a serviço, com o critério de arredondamento do contrato. Quem calcula é o código (`crates/dominio`), nunca uma pessoa digitando e nunca a IA.

## 2. O que o órgão fornece e o sistema lê

Os três documentos chegam do órgão (perfil Planejamento faz o envio). Cada um passa pelo mesmo caminho do importador que já existe para a planilha: **Arquivo → Mapear → Revisar → Conferir → Publicar**. O arquivo original fica guardado com hash (`documento_orgao`).

| Documento | Formato na primeira versão | O que o **código** lê e confere | Onde a IA só **sugere** | Quem confirma | O que nasce |
|---|---|---|---|---|---|
| **Planilha orçamentária** | `.xlsx`, `.xls`, `.ods` | Linhas, hierarquia da EAP, unidade, quantidade, preço. **Soma tem que bater com o valor do contrato, centavo a centavo** | IA-12: classe da linha quando a heurística falha | Planejamento | Revisão 0 (imutável depois de vigente) |
| **Cronograma físico-financeiro** | `.xlsx` (etapas × períodos, em % ou R$) | Períodos, percentuais ou valores. Cada etapa soma 100 %; total geral = valor da revisão; número de períodos cabe no prazo | IA-19: quais linhas são etapas, quais colunas são períodos, a que grupo ou agrupador a etapa corresponde | Planejamento | Cronograma versão 1 = **linha de base** |
| **Projeto** | `.pdf` de pranchas; `.dwg`, `.dxf`, `.ifc` ficam guardados como arquivo | Texto do carimbo e das legendas (camada de texto do PDF), número de páginas, hash | IA-20: campos do carimbo (número, título, disciplina, revisão) e a que grupo da EAP ou frente a prancha se refere | Planejamento | Cadastro de pranchas ligado à EAP e às frentes |
| **Eventograma** (quando o órgão manda) | `.xlsx` (modelo PLE/CRONOPLE ou próprio) | Agrupadores, frentes, quantidade de cada serviço por frente. Quantidade inteira de cada serviço distribuída nas frentes | IA-21: agrupador de cada serviço, só quando o arquivo não traz | Planejamento | Eventos da Revisão 0, com valor calculado |

Limites honestos da leitura de projeto:

- **O sistema não tira quantidade de desenho.** Quantidade vem da planilha do órgão. Levantar quantitativo a partir de PDF ou DWG com IA erraria em dinheiro público (lei LP2).
- Prancha escaneada (PDF só de imagem) entra como arquivo; os campos do carimbo são digitados. OCR é evolução posterior.
- Leitura estruturada de IFC (BIM) é fase tardia, por leitura determinística do arquivo, não por IA (ver `07-conformidade.md`, art. 19 §3º).
- Planilha ou cronograma que só existem em PDF não são lidos na primeira versão; o planejador digita ou pede o arquivo editável ao órgão.

Texto que vem dentro desses arquivos é **dado**, nunca instrução (lei LP8). Uma célula com "ignore as regras" não muda nenhum resultado, e há teste para isso.

## 3. Duas formas de medir, com eventos em primeiro lugar

| | **Eventos** (forma prioritária) | **Boletim de medição por quantidade (BM)** |
|---|---|---|
| O que se mede | O evento inteiro, quando concluído | A quantidade executada de cada serviço no período |
| Unidade de pagamento | Valor do evento (calculado no §1) | Quantidade × preço unitário |
| Pergunta do fiscal | "Este evento está concluído?" | "Esta quantidade foi executada?" |
| Glosa | O evento sai da medição, com motivo, e pode voltar em outra | Parte da quantidade, por item, com motivo |
| Planilha de medição | Quadro de eventos + boletim por item **derivado** | Boletim por item + memória de cálculo |
| Quando se usa | Regimes de preço global, integral, tarefa, integrada e semi-integrada; contratos com repasse medidos por eventos | Empreitada por preço unitário; serviço contínuo por demanda |

Por que eventos vêm primeiro:

1. **A lei pede.** O art. 46, §9º da Lei 14.133 manda que os regimes de preço global, empreitada integral, tarefa, contratação integrada e semi-integrada meçam e paguem por **etapas do cronograma físico-financeiro**, e veda remunerar por quantidade unitária nesses regimes. `TODO(jurídico)`: citado de memória; conferir no texto oficial antes de virar regra no código (`07-conformidade.md` §1, questão 23).
2. **É mais simples de fiscalizar e de prever.** Um evento tem data de início, data de término e valor fechado. Isso é o que alimenta a previsão do §6.
3. **O schema de referência já resolve a parte difícil.** Evento = agrupador × frente; ao marcar um evento, as linhas do boletim por item são geradas pelo banco, para que saldo, limites de aditivo e prestação de contas usem **um único caminho**.

O que "prioridade" significa no produto:

- Eventos é a forma construída e homologada primeiro (ver `08-roadmap.md`, Fase 2).
- Ao cadastrar o contrato, o sistema **sugere** a forma pelo regime de execução (regra configurável) e avisa quando a escolha contraria o regime. Quem escolhe é o planejador, e a escolha fica registrada.
- As telas de medição, fiscalização e painel abrem na visão por eventos. A visão por serviço da planilha fica a um clique.
- Em contrato medido por quantidade (BM), o planejador **pode** cadastrar eventos como **marcos físicos**, sem efeito financeiro, para usar o Boletim de Execução e a previsão do mesmo jeito.

Regras comuns às duas formas (já provadas no schema de referência): período de medição não se sobrepõe; uma medição aberta por contrato; nada acima do saldo da revisão vigente; medição aprovada é imutável; a medição fica presa à revisão vigente quando foi aberta.

As variações de acompanhamento que antes eram perfis separados passam a ser recortes destas duas formas:

| Caso | Forma | Como fica |
|---|---|---|
| Preço global por etapas | Eventos | Etapa do cronograma = agrupador; a obra inteira pode ser uma frente só |
| Repasse medido por eventos (modelo Caixa) | Eventos | Mesmos dados, exportados nos layouts PLE, CRONOPLE e RRE |
| Pavimentação e obra linear | Eventos | Frente = trecho georreferenciado (estaca inicial e final) |
| Preço unitário comum | BM | Quantidade por serviço |
| Serviço contínuo (tapa-buraco, roçada) | BM | Ordens de serviço por demanda e produção por período |

## 4. Como os eventos são montados

1. **Frentes de obra:** partes físicas da obra (Térreo, 1º pavimento, Bloco B, Trecho 1).
2. **Agrupadores:** conjuntos de serviços que fazem sentido juntos (Fundações, Estrutura: pilares, Alvenaria, Cobertura).
3. **Distribuição:** quanto de cada serviço da planilha cai em cada frente. A soma nas frentes tem que ser igual à quantidade contratada do serviço.
4. **Evento = agrupador × frente.** O valor sai do cálculo do §1.
5. **Cronograma:** cada evento recebe início e término previstos (linha de base).

Se o órgão manda o eventograma, o sistema lê (§2). Se não manda, o planejador monta na tela, com a IA-21 sugerindo o agrupador de cada serviço. Em qualquer caso a revisão só vira vigente se todo serviço tiver agrupador e quantidade inteira distribuída (regra que já existe no schema de referência).

Depois de vigente, composição e valor dos eventos não mudam. O que pode mudar é a **programação** (datas), por reprogramação registrada (§6.4).

## 5. Boletim de Execução (documento da fiscalização)

**O que é.** O registro do fiscal sobre o que está de fato executado, evento por evento, com evidência. A empresa **declara** (diário e medição); o fiscal **confere** e emite o Boletim de Execução. É ele que autoriza o evento a ser pago e é ele que alimenta a previsão.

| Campo | Regra |
|---|---|
| Quem emite | Fiscal com designação vigente no contrato. No app de campo (offline) ou no desktop |
| Periodicidade | Configuração do município ou do contrato (semanal, quinzenal, mensal, por vistoria). Nunca fixa no código |
| Uma linha por | Evento (forma eventos ou BM com marcos). Em BM sem eventos: grupo da EAP |
| Situação | `nao_iniciado` · `em_andamento` · `concluido` · `concluido_com_pendencia` · `paralisado` |
| Avanço físico | Percentual informado **pelo fiscal** quando `em_andamento`. A IA não preenche este número |
| Evidência | Fotos tiradas pelo fiscal no app, vistoria, diários do período. Para marcar `concluido`, a exigência mínima de evidência é configurável |
| Estados | `rascunho → emitido` (assinado, **imutável**). Correção = **boletim retificador**, que cita o anterior |

```
EMPRESA  diário (serviços + fotos) ─► declara evento concluído na medição
FISCAL   vistoria no local ─► Boletim de Execução: rascunho ─► emitido (assinado)
                                        │
           ┌────────────────────────────┼─────────────────────────────┐
           ▼                            ▼                             ▼
   análise da medição            previsão (§6)                painel e ficha pública
   (evento só é aprovado     (avanço verificado é a      (% executado mostrado é o
   se o boletim o marca        entrada do cálculo)         verificado, não o declarado)
   como concluído)
```

Regras:

1. **Evento só é aprovado na medição se houver Boletim de Execução emitido que o marque `concluido`**, com data de verificação dentro do período ou anterior. Sem isso, o evento é glosado ou a medição é devolvida.
2. `concluido_com_pendencia` **não** libera pagamento por padrão (o evento é medido inteiro quando concluído). Se o município quiser regra diferente, é configuração com parecer (questão 19).
3. O boletim nunca altera o que a empresa lançou. Divergência vira glosa, ocorrência ou notificação.
4. A IA-22 pode mostrar **indícios** ("o diário não cita o concreto dos pilares do Térreo") e apontar as fontes. Quem marca a situação é o fiscal. Função de **alto risco**: afeta pagamento.
5. O Boletim de Execução emitido gera o PDF correspondente (§7) e um evento no outbox.

## 6. Previsão: execução e recebimentos

**Princípio.** Previsão é **cálculo determinístico** em `crates/dominio::previsao`: mesma entrada, mesma saída, com teste. Não é resposta de modelo de IA (lei LP2). Na tela ela aparece sempre marcada como **Previsão**, diferente do dado oficial e diferente da sugestão de IA, com o botão **"Como foi calculado"**.

### 6.1 Entradas

| Entrada | De onde vem |
|---|---|
| Início e término previstos de cada evento | Cronograma vigente (linha de base ou reprogramação) |
| Situação e avanço verificado de cada evento | Último Boletim de Execução **emitido** |
| Dias trabalháveis passados | Calendário da obra menos os dias que o diário **validado** marcou como impraticáveis |
| Dias trabalháveis futuros | Calendário da obra (feriados e dias sem expediente cadastrados) |
| Ordem entre eventos | Predecessoras do cronograma; se o arquivo não traz, a ordem dos períodos |
| Prazos de processo | `config_municipio` e contrato (§6.3) |

### 6.2 Término previsto de cada evento (método inicial, a validar com o engenheiro)

| Situação do evento | Cálculo |
|---|---|
| Concluído | Data real = data de verificação no Boletim de Execução |
| Em andamento, com avanço `a` verificado | `ritmo = a ÷ dias trabalháveis desde o início real`; `dias restantes = (1 − a) ÷ ritmo`; término = hoje + dias restantes |
| Em andamento, com avanço abaixo do mínimo configurado | Duração prevista × fator de ritmo da obra, contada do início real |
| Não iniciado | Início = o maior entre o início previsto e o término previsto das predecessoras; duração = duração prevista × fator de ritmo da obra |

`fator de ritmo da obra = Σ duração real ÷ Σ duração prevista` dos eventos já concluídos, limitado a uma faixa configurável. Com poucos eventos concluídos (mínimo configurável), o fator é 1 e a tela diz que **ainda não há ritmo medido**.

**Término previsto da obra** = o maior término previsto entre os eventos. **Desvio** = término previsto menos o término contratual vigente (prazo original mais aditivos de prazo).

Exemplo: "Estrutura: pilares × Térreo" começou há 10 dias trabalháveis e o boletim verificou 40 %. Ritmo = 4 % ao dia. Faltam 60 %, logo 15 dias trabalháveis. A linha de base previa 20 dias no total; a tendência dá 25.

### 6.3 Recebimento financeiro: quando o evento X vira pagamento

A partir do término previsto do evento X, o sistema soma os prazos do processo. **Todos os prazos são configuração** (contrato ou `config_municipio`), inclusive se contam em dias úteis ou corridos.

```
término previsto do evento X
   ─► fechamento do período de medição que alcança essa data
   ─► + prazo de envio da medição pela empresa
   ─► + prazo de análise da fiscalização (e da comissão, se o município exigir)
   ─► + prazo de atesto e liquidação
   ─► + prazo de pagamento do contrato
   = data prevista de pagamento do evento X
```

| Saída | Como é calculada |
|---|---|
| Valor bruto previsto | Valor do evento (planilha) |
| Retenções previstas | Alíquotas e bases de `contrato_retencao` |
| Valor líquido previsto | Bruto menos retenções |
| Repasse × contrapartida | Mesma regra do RRE, para contrato com convênio |
| Data "pelo prazo do contrato" | Soma dos prazos configurados |
| Data "pelo histórico do município" | Mediana dos dias observados em cada etapa nas medições já pagas. Só aparece com amostra mínima configurável |

Duas leituras do mesmo cálculo:

- **Prefeitura (gestão e finanças): cronograma de desembolso previsto**, mês a mês, por contrato e por fonte de recurso.
- **Empresa: previsão de recebimento**, por evento.

Exemplo: o evento do §6.2 tem término previsto em 14/11. O período de medição fecha em 30/11. Com prazos fictícios de 5, 10, 5 e 30 dias, o pagamento previsto cai em 19/01. Valor bruto 26.014,74; com retenção fictícia de 11 %, retenção de 2.861,62 e líquido de 23.153,12.

### 6.4 Recebimento da obra e reprogramação

- **Recebimento da obra (termos):** término previsto do último evento → comunicação de conclusão → termo provisório → termo definitivo → início da garantia. Os prazos entre as etapas são os mesmos campos de configuração que o módulo P08 já usa (o art. 140 não fixa dias).
- **Reprogramação:** a linha de base é **imutável**. Mudar datas cria nova versão do cronograma, com motivo, autor e, quando houver, o aditivo de prazo correspondente. A previsão sempre informa contra qual versão compara.

### 6.5 O que a previsão não faz

- Não altera cronograma, prazo contratual, medição nem pagamento.
- Não dispara notificação à empresa sozinha. Ela aparece para o fiscal e o gestor, que decidem.
- Não é publicada na ficha do cidadão sem decisão do gestor (questão 22).
- A IA-23 só **explica** o resultado em linguagem simples; se o texto gerado trouxer número que não está no cálculo, o texto é descartado. A IA-16 (risco de atraso) é uma nota separada e não mexe nas datas.

## 7. Relatórios gerados pelo sistema, todos vinculados

Todos saem do banco pelo código (`crates/relatorios`: Typst para PDF, `rust_xlsxwriter` para planilha). Nenhum número de relatório vem da IA.

| Relatório | Quem emite | Conteúdo | De onde vem cada parte |
|---|---|---|---|
| **Boletim de Execução** | Fiscal | Situação e avanço por evento, evidências, pendências | Linhas do boletim, fotos do fiscal, vistorias |
| **Planilha de medição** (PDF e `.xlsx`) | Empresa envia; fiscal aprova | Eventos: previsto, concluído no período, acumulado, saldo. Por serviço: contratado, anterior, atual, acumulado, saldo. Memória de cálculo | `medicao_evento`, `medicao_item`, revisão vigente |
| **Relatório fotográfico** | Empresa (da medição) e fiscal (do boletim) | Fotos agrupadas por evento, frente e serviço, com legenda, data e hora, coordenada e precisão, autor e hash | Fotos da câmera do app com vínculo confirmado por pessoa |
| **Caderno de medição** | Sistema, na aprovação | Capa, planilha de medição, memória, relatório fotográfico, Boletim de Execução, glosas, documentos | Os anteriores, mais a trilha de aprovação |
| **Diário de obras (RDO)** | Empresa | Clima, efetivo, equipamentos, serviços por frente, fotos | Diário fechado e validação do fiscal |
| **Relatório de previsão** | Gestor ou fiscal | Linha de base × tendência por evento; desembolso previsto por mês | Fotografia do cálculo (`previsao_calculo`) |
| **Planilha de aditivo** (PDF e `.xlsx`) | Planejamento | Acréscimos, supressões, itens novos, limites do art. 125, fator do art. 127, comparação Rev. N × Rev. N+1 | Serviços a mais aceitos, itens do aditivo, simulação em código |
| **RRE** (contratos com repasse) | Sistema | Repasse × contrapartida por medição | Visão já existente no schema de referência |

Regras de todo relatório:

1. **Rastreável:** o rodapé traz número, versão do modelo, hash e a lista dos registros de origem. Na tela, cada número é clicável até a linha que o gerou.
2. **Imutável depois de emitido:** o arquivo emitido é guardado com hash (`relatorio_emitido`). Correção é nova emissão, que cita a anterior.
3. **Reproduzível:** gerar de novo com os mesmos registros dá os mesmos números.
4. **Foto só entra com vínculo confirmado.** No app, quem fotografa escolhe a frente e o serviço na hora (o diário do dia já sugere a lista). Foto sem vínculo fica na fila; a IA-03 sugere, a pessoa confirma.
5. **Texto fixo é modelo versionado**, editável pela prefeitura, com campos preenchidos pelo código (ver `05-ux-ui.md` §7).

## 8. Serviços a mais → aditivo

"Serviço a mais" é o que aparece na obra e não cabe na planilha vigente:

| Tipo | Exemplo | Como entra no aditivo |
|---|---|---|
| **Acréscimo** em serviço existente | A alvenaria do Térreo precisou de 20 m² além do contratado | `acrescimo`, pelo preço unitário do contrato |
| **Serviço novo** | Dreno que não estava na planilha | `inclusao`, com preço de referência × fator do art. 127 |

```
diário, vistoria, Boletim de Execução ou pleito
   ─► apontamento de serviço a mais (frente, descrição, quantidade estimada por uma pessoa, evidências)
   ─► análise técnica do fiscal ─► aceito | recusado (com motivo)
   ─► sistema monta o rascunho do aditivo: itens, simulação dos limites do art. 125,
      preço de item novo pelo art. 127, planilha de aditivo, minuta técnica (IA-14, com citações)
   ─► parecer jurídico e controle interno ─► gestor homologa ─► Rev. N+1 ─► publicação
```

Regras:

1. **Nada de serviço a mais é medido antes do aditivo homologado.** A regra do saldo já garante isso no banco.
2. O sistema **calcula e mostra** limites e preços; quem decide é gente (lei LP1).
3. A lei condiciona a execução do acréscimo à formalização do aditivo, com exceção justificada e prazo para formalizar (art. 132 da Lei 14.133). `TODO(jurídico)`: citado de memória; conferir (questão 23). O sistema **não** embute esse prazo: registra a data do apontamento, a justificativa e a data da formalização, para que o controle interno veja o intervalo.
4. **Evento já medido não muda de valor.** Acréscimo em frente cujo evento já foi medido entra como **evento novo** (complementar) na Rev. N+1 (questão 20).
5. A IA-24 só **avisa** que uma linha do diário parece não ter serviço correspondente na planilha. Abrir o apontamento é decisão do fiscal ou do planejador.

## 9. Invariantes novas (cada uma com teste que prova o bloqueio)

1. Evento não é aprovado em medição sem linha de Boletim de Execução **emitido**, por fiscal com designação vigente, marcando `concluido`.
2. Boletim de Execução emitido é imutável; só boletim retificador o corrige.
3. Valor do evento = soma arredondada por serviço; **paridade Rust × SQL**, mesmo centavo.
4. Soma das quantidades nas frentes = quantidade contratada do serviço (já existe; manter).
5. Evento medido não muda de valor nem de composição; acréscimo vira evento novo.
6. Evento glosado não conta como medido e pode voltar em medição futura.
7. A forma de medir do contrato não muda depois da primeira medição enviada.
8. Linha de base do cronograma é imutável; reprogramação é nova versão com motivo e autor.
9. Cronograma: cada etapa soma 100 %; total = valor da revisão.
10. Previsão é determinística: mesma entrada, mesma saída. Não escreve em tabela oficial. Toda data prevista guarda o método e o id do cálculo.
11. Prazos de processo vêm da configuração: o teste troca a configuração e o resultado muda (prova que não há constante no código).
12. Relatório fotográfico só inclui foto da câmera do app, com hash e vínculo confirmado por pessoa.
13. Relatório emitido é imutável; reemissão com os mesmos registros dá os mesmos números.
14. Apontamento de serviço a mais só passa a `incluido_em_aditivo` com o item do aditivo correspondente.
15. Texto de planilha, cronograma, prancha ou diário contendo instruções não altera nenhum resultado (teste de injeção).

## 10. Quem faz o quê

| Tarefa | Código | IA (só sugere) | Pessoa (decide) |
|---|---|---|---|
| Ler planilha, cronograma e carimbo de prancha | Lê, soma, confere | Classifica linha duvidosa (IA-12, IA-19, IA-20) | Planejador publica |
| Montar eventos | Calcula o valor | Sugere agrupador (IA-21) | Planejador confirma |
| Dizer que o evento está concluído | Exige o boletim | Mostra indícios (IA-22) | **Fiscal** |
| Prever término e recebimento | **Calcula tudo** | Explica em texto (IA-23) | Gestor e fiscal leem |
| Montar relatório fotográfico | Monta a partir dos vínculos | Sugere legenda e vínculo (IA-03) | Autor confirma |
| Aditivo de serviço a mais | Limites e preços | Avisa serviço fora da planilha (IA-24); minuta (IA-14) | Fiscal, jurídico, gestor |
| Aprovar, glosar, atestar, homologar, pagar | Valida regras | **Nunca** | Só pessoa com perfil e designação |

Detalhe de cada ponto de IA em [`04-ia-borda-rreia.md`](04-ia-borda-rreia.md); tabelas novas em [`06-banco-de-dados.md`](06-banco-de-dados.md) §3; telas em [`05-ux-ui.md`](05-ux-ui.md) §4.
