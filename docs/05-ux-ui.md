# 05 · UX e UI Design

> Princípio: **cada perfil abre numa tela que responde "o que eu preciso fazer agora?"**, não numa lista de tabelas. O sistema é institucional e sóbrio: quem usa é servidor público, engenheiro e apontador de obra, muitas vezes ao sol, com luva, com sinal ruim.

## 1. Princípios

1. **Tela por papel, não por tabela.** Fiscal vê fila de trabalho; gestor vê situação; empresa vê pendências.
2. **Dado oficial ≠ sugestão de IA ≠ previsão.** Sempre visualmente distintos (ver §5). São três selos: **Regra** (verificação determinística), **Sugestão** (proposta da IA local) e **Previsão** (estimativa calculada pelo código).
3. **Eventos primeiro.** Medição, fiscalização e painel abrem na visão por eventos; a visão por serviço da planilha fica a um clique.
4. **Campo primeiro no mobile:** alvos de toque ≥ 48 px, texto ≥ 16 px, contraste alto, poucas telas, uma ação principal por tela.
5. **Offline é estado normal**, não erro. Mostrar "salvo no aparelho" e "aguardando envio" com clareza.
6. **Planilha é cidadã de primeira classe.** EAP em árvore, colunas travadas, teclado (setas, Enter, Tab), virtualização para milhares de linhas, soma conferida na tela.
7. **Nada irreversível sem confirmação com consequência escrita** ("Você está atestando a Medição nº 3 no valor de R$ …. Esta ação não pode ser desfeita.").
8. **Linguagem do ofício:** "evento", "frente", "boletim de execução", "BM", "glosa", "atesto", "RDO", "aditivo", "apostila", "termo de recebimento". Sem jargão de software.
9. **Acessibilidade:** WCAG 2.2 AA e eMAG (governo). Foco visível, leitor de tela, nunca só cor para significar estado (sempre ícone + texto), navegação por teclado completa.
10. **Formato brasileiro:** R$ 1.234,56 · 12/10/2026 · vírgula decimal · unidades (m², m³, kg) · fuso do município.
11. **Rápido em máquina fraca:** carga inicial leve, tabelas virtualizadas, sem animação gratuita.
12. **Todo número de relatório é clicável** até o registro que o gerou (diário, foto, linha do boletim, item da planilha).

## 2. Linguagem visual

| Elemento | Direção |
|---|---|
| Tom | Institucional, claro, confiável. Fundo claro, tema escuro opcional (campo noturno) |
| Cor | Uma cor de marca sóbria (o i9 usa azul `#1e3faf` na barra do app, referência de gosto, não obrigação) + paleta semântica: **verde** ok/atestado, **âmbar** atenção/pendente, **vermelho** glosa/atraso/bloqueio, **azul-cinza** informativo. Cada estado tem ícone próprio |
| Tipografia | Sans-serif legível (ex.: Inter ou Source Sans 3), números **tabulares** em tabelas e valores |
| Densidade | Desktop: densa (tabelas). Mobile: espaçosa. Alternância "confortável / compacta" |
| Ícones | Conjunto único (ex.: Lucide), mesmo traço |
| Marca | No cabeçalho: **"Prumo · Prefeitura de ___"**, com o **brasão do município** à esquerda. O brasão e o nome da cidade são configuração do município; "Prumo" é fixo. Tema (cor principal) configurável por município. Tela de entrada e instalador: "Prumo — Gestão de Obras Públicas" |
| Nome da IA | Para o usuário final, só o selo "Sugestão" e o título "Sugestão da IA local". No console do Admin: "Console de IA (RREIA)". Em material de venda: "Prumo IA Local" |

Definir **tokens** (cor, espaço, raio, sombra, tipografia) em `ui/design-system/tokens` e nunca usar valor solto em componente.

## 3. Estrutura de navegação

### Desktop (gestão e fiscalização)

```
┌───────────────────────────────────────────────────────────────────────────────┐
│ [Brasão] Prumo · Prefeitura de ____  🔍 Buscar obra/contrato   🔔 3  ⚙  👤 Maria │
├────────────┬──────────────────────────────────────────────────────────────────┤
│ ◉ Início   │  Contrato 045/2026 · Ampliação da Escola Municipal · por eventos │
│ ▤ Obras    │  [Resumo] [Eventos] [Planilha] [Cronograma] [Projeto] [Diário]   │
│ ▣ Boletins │  [Boletins de execução] [Medições] [Previsão] [Aditivos]         │
│ ✎ Medições │  [Relatórios] [Documentos] [Recebimento] [Histórico]             │
│ ☰ Diário   │ ─────────────────────────────────────────────────────────────── │
│ ⚠ Ocorrên. │  conteúdo da aba                                                 │
│ ± Aditivos │                                                                  │
│ ◷ Previsão │                                                                  │
│ ▦ Painéis  │                                                                  │
│ ⚙ Admin    │                                                                  │
└────────────┴──────────────────────────────────────────────────────────────────┘
```
O menu lateral **muda conforme o perfil** (Fiscal não vê Admin; Planejamento não vê Atesto).

### Celular / campo (empresa e fiscal)

**O diário de obras da empresa só existe no app de celular** (ADR 0004); não há tela dele no desktop. Barra inferior com 4 itens. Empresa: **Hoje · Diário · Medição · Mais**. Fiscal: **Hoje · Boletim · Diário · Mais**. Botão central de ação (câmera/áudio) sempre acessível; ao fotografar, a tela pede **frente e serviço** (a lista do dia já vem sugerida).

### Web da empresa

Mesma estrutura do desktop, reduzida a: Meus contratos (com previsão de recebimento) · Medições · Notificações · Pleitos · Documentos. O diário não é lançado aqui; se a empresa vai poder **consultar** os diários fechados pelo navegador está em aberto (questão 25).

### Portal público

Mapa em tela cheia + lista + filtro por secretaria/bairro/status. Ficha da obra com fotos, valor, prazo, % executado.

## 4. Telas-chave

### 4.1 Início do Fiscal ("Minha fila")

```
┌ Minha fila ───────────────────────────────────────────────────────────────┐
│ 🔴 Medição nº 3 · Escola Municipal · enviada há 2 dias · prazo de análise 3 dias │
│ 🟠 Boletim de Execução nº 7 · Escola Municipal · vence sexta · 2 eventos a conferir │
│ 🟠 Diário 10/10 aguardando validação (3 dias)                              │
│ 🟠 Notificação 07/2026 · resposta vence amanhã                             │
│ ⚪ Vistoria agendada · Pavimentação Rua das Flores · quinta                │
├ Minhas obras ─────────────────────────────────────────────────────────────┤
│ Escola Municipal ▓▓▓▓▓▓▓░░░ 68% (cronograma 72%)  ⚠ 1 alerta             │
└───────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Análise de medição (a tela mais importante da fiscalização)

A tela tem duas variantes, conforme a forma de medir do contrato. **Por eventos é a principal**; os exemplos usam dados fictícios.

**Por eventos:**

```
┌ Medição nº 3 · por eventos · 01/12–31/12/2026 · Valor bruto R$ 42.656,34 ── [Devolver] [Aprovar] ┐
│ Evento                        Previsto   Valor       Boletim de Execução     Evidência    Alerta  │
│ Estrutura: pilares × Térreo   nov/2026   26.014,74   ✓ concluído em 11/12    📷 6  RDO 9  ✓       │
│ Alvenaria × Térreo            dez/2026   16.641,60   ◐ em andamento, 70 %    📷 4  RDO 5  ⚠       │
├ Painel do evento selecionado ─────────────────────────────────────────────────────────────────────┤
│ Serviços do evento (da planilha): Alvenaria de vedação 160,00 m² · Chapisco 320,00 m²             │
│ ⚠ Regra: o Boletim de Execução nº 7 marca este evento como "em andamento".                        │
│   Evento só é aprovado quando o boletim o marca concluído.                                        │
│ Glosa do evento: [ motivo estruturado ▾ ] [✨ Redigir motivo]      Valor glosado: R$ 16.641,60     │
│ [Ver por serviço da planilha]   [Abrir Boletim nº 7]   [Fotos do evento]                          │
└───────────────────────────────────────────────────────────────────────────────────────────────────┘
```
O fiscal não digita valor: glosar um evento tira o evento inteiro, e o valor glosado é o valor do evento. O botão **Aprovar** fica bloqueado enquanto houver evento sem boletim que o marque concluído e sem glosa.

**Por quantidade (BM):**

```
┌ Medição nº 3 · 01/12–31/12/2026 · Valor bruto R$ 41.231,07 ───── [Devolver] [Aprovar] ┐
│ Item        Descrição               Contr.  Ant.   Atual   Saldo   Evidência  Alerta     │
│ 2.1.2      Concreto fck 25         22,20   10,00  12,20   0,00    📷 3  RDO 4  ✓        │
│ 2.3        Dreno c/ brita nº 2     40,00   0,00   40,00   0,00    📷 1  RDO 0  ⚠ ✨      │
│ 3.1        Alvenaria bloco cer.    320,00  0,00   100,00  220,00  📷 5  RDO 8  ✓        │
├ Painel lateral do item selecionado ──────────────────────────────────────────────────────┤
│ Fotos georreferenciadas · RDO relacionados · Quantidade informada x vista nas fotos       │
│ ✨ Sugestão: "Quantidade 40 m declarada em 1 dia; RDO de 03/12 cita 12 m." [Por quê ▾]   │
│    [Aceitar como alerta] [Ignorar]        Confiança: Média — revise                       │
│ Glosa: [ quantidade __ ] [ motivo estruturado ▾ ] [✨ Redigir motivo] ← IA-07            │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```
Cálculos de saldo, limites e totais são **sempre** do servidor/domínio. A coluna Alerta combina **regras** (selo ⚠) e **sugestões de IA** (selo ✨), com legenda diferente.

### 4.3 Diário de obras no celular (empresa)

Tela exclusiva do app de celular. Tem que caber nas plataformas de `03-arquitetura.md` §5.1; no KaiOS, se houver, será outra tela, para teclado e tela pequena.

```
┌ Diário · 12/10 · Escola Municipal ────────────┐
│ ☀ Manhã [Bom ▾]   🌧 Tarde [Chuva fraca ▾]   │
│ Praticável?  (●) Sim  ( ) Não                 │
│ ──────────────────────────────────────────── │
│ Efetivo: Pedreiro 4 · Servente 6 · [+]        │
│ Equipamentos: Betoneira 1 · [+]               │
│ Serviços executados:                          │
│  • Alvenaria 2º pav. – 32 m²   [item 3.1 ✨]  │
│  [+ adicionar]    [🎙 Ditar diário]  ← IA-01  │
│ Fotos: [📷 Tirar foto]  (3)  [🏷 legendas ✨]  │
│ ──────────────────────────────────────────── │
│ 💾 Salvo no aparelho · 3 itens aguardando envio│
│            [ Fechar o dia e assinar ]         │
└───────────────────────────────────────────────┘
```
Ditar → mostra a transcrição **ao lado** dos campos preenchidos, com cada campo marcado ✨ até o apontador tocar. "Fechar o dia" exige que nenhum campo ✨ esteja pendente de revisão.

### 4.4 Painel do Gestor

Cartões: obras em execução, atrasadas, paralisadas, medições pendentes, valor medido × pago, aditivos próximos do limite, **desembolso previsto no mês** (selo Previsão). Na lista de obras, três colunas separadas: **físico verificado × previsto** (dado oficial, vem do Boletim de Execução), **desvio previsto** em dias (selo Previsão, vem do cálculo) e **risco de atraso** (selo Sugestão, IA-16). Curva S por obra. Mapa. Caixa **"Pergunte aos dados"** (IA-15) que mostra *qual consulta pré-aprovada foi usada* e permite clicar para ver a tabela de origem.

### 4.5 Planilha orçamentária / EAP

Árvore expansível, colunas fixas (código, descrição, un., qtd, preço unitário, total), edição só em rascunho de revisão, comparação **Rev. N × Rev. N+1** lado a lado (acréscimo/supressão/item novo coloridos com ícone), totais por grupo, conferência de total com o edital. Importador em 3 passos: **Arquivo → Mapear colunas → Revisar linhas** (fila das de baixa confiança, IA-12).

### 4.6 Console de IA (Admin)

Lista de funções IA-01…24 com interruptor, limiar de confiança, métrica de qualidade (aceitação, rejeição, respostas válidas), fila atual por classe, modelo carregado, uso de memória, temperatura, aviso L5 ativo. Botão **"Desligar toda a IA"**. Funções de alto risco (IA-06, IA-07, IA-22) aparecem "Desligada: falta parecer jurídico" até a liberação.

### 4.7 Documentos do órgão (Planejamento)

```
┌ Documentos do órgão · Contrato 045/2026 ──────────────────────────────────────────────────────────┐
│ ▤ Planilha orçamentária   planilha.xlsx     ✓ Rev. 0 publicada · soma = valor do contrato          │
│ ◷ Cronograma              cronograma.xlsx   ◐ 2 linhas a revisar ✨ · somas conferidas             │
│ 📐 Projeto                 24 pranchas PDF   ◐ 3 pranchas sem vínculo com a EAP ✨                  │
│ 🧩 Eventos                 eventograma não enviado → [Montar eventos]  8 agrupadores · 3 frentes    │
│ [Enviar arquivo]      Cada arquivo fica guardado com hash.                                         │
└───────────────────────────────────────────────────────────────────────────────────────────────────┘
```
Todos seguem o importador em passos: **Arquivo → Mapear → Revisar → Conferir → Publicar**. A fila de revisão mostra só o que a heurística não resolveu (IA-12, IA-19, IA-20, IA-21). O botão Publicar só habilita com as somas conferidas pelo código. Na montagem de eventos, a sugestão de agrupador é confirmada **linha a linha**, sem "aceitar tudo".

### 4.8 Boletim de Execução (Fiscal, desktop e campo)

```
┌ Boletim de Execução nº 7 · 01/12–15/12 · Escola Municipal ────────── [Salvar] [Emitir e assinar] ┐
│ Evento                        Previsto       Situação           Avanço    Evidência               │
│ Estrutura: pilares × Térreo   até 30/11      (●) Concluído       100 %    📷 6 · vistoria 11/12   │
│ Alvenaria × Térreo            01/12–18/12    (●) Em andamento   [ 70 ] %  📷 4                    │
│ Cobertura × Térreo            05/01–29/01    (●) Não iniciado      —       —                      │
├ Evento selecionado: Alvenaria × Térreo ───────────────────────────────────────────────────────────┤
│ [📷 Fotografar]   frente: Térreo · serviço: Alvenaria de vedação                                  │
│ ✨ Sugestão · indícios de conclusão · Confiança: Média, revise                                    │
│    "Os diários de 02/12 a 11/12 somam 112 m² de 160 m²."  [Por quê ▾]                             │
│    A sugestão não preenche a situação nem o percentual.                                           │
│ [+ Apontar serviço a mais]   [+ Ocorrência]                                                       │
└───────────────────────────────────────────────────────────────────────────────────────────────────┘
```
No celular, uma linha por cartão, com a situação em quatro botões grandes. "Emitir e assinar" abre o diálogo de ação irreversível: "Você está emitindo o Boletim de Execução nº 7. Ele libera a análise de 1 evento no valor de R$ 26.014,74 e não pode ser alterado; correções exigem boletim retificador."

### 4.9 Previsão (Gestor, Fiscal; a empresa vê só o recebimento)

```
┌ Previsão · Contrato 045/2026 ──── calculada em 15/12 sobre o Boletim nº 7 e o cronograma v1 ──────┐
│ Término contratual 30/04/2027 · ◷ Término previsto 13/05/2027 · ◷ Desvio +9 dias úteis            │
│                                                                          [Como foi calculado ▾]   │
│ Evento                        Linha de base   Situação / tendência       ◷ Pagamento    Valor     │
│ Estrutura: pilares × Térreo   até 30/11       concluído em 11/12         19/02/2027   26.014,74   │
│ Alvenaria × Térreo            01/12–18/12     ◷ até 22/12 (+2 dias)      19/02/2027   16.641,60   │
│ Cobertura × Térreo            05/01–29/01     ◷ 05/01–02/02 (+2 dias)    19/04/2027   38.920,00   │
├ Desembolso previsto por mês ──────────────────────────────────────────────────────────────────────┤
│ ◷ fev/2027  R$ 42.656,34      ◷ abr/2027  R$ 38.920,00      ◷ mai/2027  R$ 37.895,20              │
│ ◷ Previsão: estimativa calculada pelo sistema. Não altera prazo, medição nem pagamento.           │
└───────────────────────────────────────────────────────────────────────────────────────────────────┘
```
"Como foi calculado" lista as entradas: versão do cronograma, número do boletim, ritmo verificado de cada evento, fator de ritmo da obra e os prazos de processo configurados, com a origem de cada prazo (contrato ou configuração do município). Os números do exemplo são os que o cálculo devolve para a obra fictícia da prévia de desktop (`crates/demonstracao`), e mudam se o boletim mudar.

### 4.10 Relatórios vinculados

```
┌ Relatórios · Contrato 045/2026 ───────────────────────────────────────────────────────────────────┐
│ Planilha de medição nº 3      PDF · XLSX   emitida 05/01 · 2 eventos · [Ver fontes]                │
│ Relatório fotográfico nº 3    PDF          18 fotos em 2 eventos · ⚠ 2 fotos sem vínculo           │
│ Boletim de Execução nº 7      PDF          emitido 15/12 por Maria Souza                           │
│ Caderno de medição nº 3       PDF          gerado na aprovação                                     │
│ Planilha de aditivo nº 1      PDF · XLSX   rascunho · 2 serviços a mais                            │
│ Relatório de previsão         PDF · XLSX   ◷ cálculo de 15/12                                      │
└───────────────────────────────────────────────────────────────────────────────────────────────────┘
```
"Ver fontes" abre a lista dos registros que compõem o relatório. No relatório fotográfico, cada foto mostra legenda, data e hora, coordenada com precisão, autor e os primeiros caracteres do hash; foto sem vínculo confirmado fica de fora e aparece na fila.

### 4.11 Serviços a mais

Lista de apontamentos por contrato: origem (diário, vistoria, boletim, pleito), frente, descrição, quantidade estimada, tipo (acréscimo ou serviço novo), situação. Ao aceitar, o painel lateral mostra a **simulação dos limites do art. 125 calculada em código** e o botão "Incluir no rascunho do aditivo". Aviso fixo: "Serviço a mais só é medido depois do aditivo homologado."

## 5. Padrão de componente: "Sugestão de IA"

| Elemento | Regra |
|---|---|
| Marca | Ícone ✨ e rótulo "Sugestão" em chip com cor própria (nunca verde/vermelho de status) |
| Conteúdo | Aparece **sem preencher** o campo oficial até o usuário aceitar (exceto ditado, em que fica marcado "a revisar") |
| Ações | **Aceitar · Editar · Rejeitar** (teclado: Enter / E / Esc) |
| Por quê | Expansível; lista fontes clicáveis (RDO #, foto #, cláusula) |
| Confiança | 3 níveis em texto: **Alta**, **Média**, **Revise**. Nunca "87%" |
| Auditoria | Cada ação grava `desfecho` (LP5) e marca o campo `assistido_por_ia` |
| Ausência | IA desligada/indisponível: o botão fica oculto ou cinza com explicação curta; nada quebra |
| Carregando | Esqueleto + "Gerando sugestão…" com botão Cancelar; tempo máximo por classe |
| Erro | "Não foi possível gerar. Siga manualmente." Sem erro técnico para o usuário |

### 5.1 Padrão de componente: "Previsão"

| Elemento | Regra |
|---|---|
| Marca | Ícone de relógio e rótulo "Previsão", com contorno tracejado e cor própria (nem cor de status, nem a da Sugestão) |
| Conteúdo | Data, prazo ou valor estimado. Nunca ocupa o lugar do campo oficial; aparece ao lado dele |
| Como foi calculado | Expansível; lista as entradas e as fontes. Se a IA estiver ligada, a explicação em texto (IA-23) aparece dentro, marcada como Sugestão |
| Ações | Nenhuma de aceitar ou rejeitar: previsão não vira dado oficial |
| Sem dados | Sem cronograma publicado ou sem boletim emitido: "Sem dados para prever". Nunca um chute |
| Desatualizada | Mostra a data do cálculo e o boletim usado; se houver boletim mais novo, oferece recalcular |

## 6. Estados que toda tela precisa desenhar

Vazio · Carregando · Erro · Sem permissão · Offline · Sincronizando · Conflito/rejeitado pelo servidor · Somente leitura (registro imutável) · Aguardando outra pessoa · Prazo vencido.

## 7. Textos que precisam de revisão jurídica antes de ir ao ar

Termos de aceite de medição, texto de emissão do Boletim de Execução, termos de recebimento, mensagem de notificação, aviso de uso de IA, aviso de que a previsão é estimativa, política de privacidade, texto de assinatura, avisos públicos da ficha da obra. O sistema usa **modelos de texto versionados**, editáveis pela prefeitura, com campos preenchidos pelo código.

## 8. Entregável de design para o Claude Code

Antes de codificar telas: gerar `ui/design-system` com tokens, os componentes base (botão, campo numérico BR, tabela virtualizada, árvore EAP, quadro de eventos por frente, seletor de situação do evento, chip de status, chip de sugestão, chip de previsão, diálogo de confirmação irreversível, galeria de fotos com mapa, linha do tempo de aprovação, linha do tempo de eventos (linha de base × tendência), banner de sincronização…) e uma página de catálogo (Storybook ou equivalente) revisada com um fiscal e um apontador reais.

As telas de referência estão no canvas de design "Prumo · Telas e pontos de IA" (fora do repositório). Parte delas já pode ser aberta na **prévia de desktop** (`apps/desktop`, ver `adr/0003-previa-desktop.md`): planilha e eventos, Boletim de Execução, medição por eventos e previsão com regra de verdade; painel, medição por quantidade e console de IA como desenho estático. O diário da empresa não está na prévia, porque é tela só de celular.
