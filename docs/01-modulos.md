# 01 · Módulos, perfis e fluxos

> Como funciona o Prumo: **um contrato público, vários atores, cada um com uma visão diferente da mesma verdade**. O órgão *fornece* planilha, projeto e cronograma; a empresa executa e *declara*; a fiscalização *confere e atesta*; a gestão *decide e presta contas*; o cidadão *acompanha*.

## 1. Perfis (quem usa)

| Perfil | Quem é | Onde usa | Pode | Não pode |
|---|---|---|---|---|
| **Gestor** | Prefeito, secretário, diretor de obras | Desktop, painel mobile | Ver portfólio, previsão de prazo e de desembolso, autorizar aditivos, paralisar/retomar | Editar diário ou medição |
| **Planejamento** | Engenheiro orçamentista | Desktop | Enviar planilha, projeto e cronograma do órgão, montar frentes e eventos, criar revisões, reprogramar cronograma, aditivos (rascunho) | Atestar medição |
| **Fiscal** | Servidor designado por portaria (art. 117) | Desktop + app de campo | Validar diário, **emitir Boletim de Execução**, analisar/glosar medição, abrir ocorrência, apontar serviço a mais, notificar, vistoriar | Alterar o que a empresa lançou (só devolver ou glosar) |
| **Comissão** | Comissão de recebimento / de medição | Desktop | Recebimento definitivo, atesto colegiado | — |
| **Controle interno / Jurídico** | CI, procuradoria | Desktop | Parecer em aditivo, leitura de tudo do contrato | Alterar dados |
| **Contratada** | Preposto, responsável técnico, apontador | App de celular (diário) + web (navegador) | Lançar diário (só no celular), montar e enviar medição, responder notificação, pleitear aditivo, ver previsão de recebimento | Ver notas internas da fiscalização |
| **Cidadão** | Público | Web público | Mapa, andamento, denúncia/ouvidoria | Qualquer escrita além da denúncia |
| **Auditor externo** | TCE, CGM | Web (somente leitura, com prazo) | Ler contrato, trilha, exportações | Escrever |
| **Admin TI** | Informática da prefeitura | Console | Usuários, perfis, backup, console de IA | Alterar dado de negócio |

Regras transversais: um usuário pode ter mais de um perfil, **mas a mesma pessoa não pode ser autora e aprovadora do mesmo ato** (segregação de funções, verificada em código).

## 2. Mapa de módulos

### Lado prefeitura (gestão, fiscalização)

| ID | Módulo | Para que serve |
|---|---|---|
| **P01** | Cadastros-base | Secretarias, empresas, servidores, fiscais, portarias de designação, comissões, bases de preço (SINAPI, SICRO, ORSE), convênios |
| **P02** | Obras e Contratos | Obra, contrato, processo licitatório, ordem de serviço, vigência, garantia contratual, ART/RRT, CNO, seguros, **forma de medir** (eventos ou quantidade) |
| **P03** | Planilha, Projeto, Cronograma e Eventos | **Leitura dos documentos que o órgão fornece**: planilha orçamentária (EAP em árvore, **revisões** Rev. 0, 1, 2…), cronograma físico-financeiro (linha de base e reprogramações), projeto (pranchas ligadas à EAP). Montagem de **frentes e eventos**. Curva S |
| **P04** | Aditivos e Apostilas | Prazo, valor, item novo, **serviços a mais**; **limites do art. 125** (25%; 50% reforma) e **fator do art. 127**, calculados em código |
| **P05** | Fiscalização | **Boletim de Execução**, ocorrências, notificações, vistorias com checklist, apontamento de serviço a mais, planos de ação, prazos de resposta, paralisação |
| **P06** | Medição e Atesto | Recebe a medição da empresa **por eventos (forma prioritária) ou por quantidade**, confere, glosa, aprova em etapas, gera o Caderno de Medição |
| **P07** | Diário de Obras (visão fiscal) | Valida, devolve ou registra instruções; nunca edita o texto da empresa |
| **P08** | Recebimento | Termo provisório, termo definitivo, pendências, **garantia de 5 anos** (art. 140 §6º) com alertas |
| **P09** | Contrato × Execução financeira | Empenho, liquidação e pagamento **referenciados** (integra com a contabilidade, não a substitui); retenções; reajuste e reequilíbrio |
| **P10** | Painéis e Indicadores | Curva S, atrasos, % físico **verificado** × financeiro, medições pendentes, obras paradas, desvio previsto de prazo |
| **P11** | Mapa e Transparência | Mapa georreferenciado público, ficha da obra, fotos, valores, situação |
| **P12** | Prestação de Contas | Adaptadores por tribunal (TCE), PNCP, Obrasgov, relatórios de repasse (modelo Caixa BM/PLE/RRE do schema de referência) |
| **P13** | Documentos e Assinaturas | Repositório com hash, versionamento, assinatura eletrônica (provedor plugável) |
| **P14** | Ouvidoria | Denúncia do cidadão vira ocorrência pré-triada para o fiscal |
| **P15** | Administração e Console de IA | Usuários, perfis, auditoria, política do RREIA (modelos, orçamentos, desligar IA) |
| **P16** | Relatórios vinculados | Central de emissão: planilha de medição, **relatório fotográfico**, Boletim de Execução, caderno de medição, planilha de aditivo, relatório de previsão. Cada número leva ao registro de origem |
| **P17** | Previsão | Término previsto de cada evento e da obra; **cronograma de desembolso previsto**; previsão de recebimento da obra (termos). Cálculo determinístico, sempre marcado "Previsão" |

### Lado empresa (contratada)

| ID | Módulo | Para que serve |
|---|---|---|
| **E01** | Meus contratos | Ordens de serviço, saldo, prazos, pendências, **previsão de recebimento por evento** |
| **E02** | Diário de Obras (visão empresa) | **Só no app de celular** (ADR 0004). Clima, efetivo, equipamentos, serviços executados **por frente e por serviço da planilha**, ocorrências, fotos georreferenciadas, áudio; **funciona offline** |
| **E03** | Medição (visão empresa) | Marca eventos concluídos (ou informa quantidades por item), anexa evidências, envia; vê glosas e responde. Planilha de medição e relatório fotográfico saem prontos |
| **E04** | Gestão da execução | Cronograma da empresa, solicitações de compra, insumos, equipe (versão leve) |
| **E05** | Documentos | ART/RRT, seguros, certidões, garantia, caderno técnico |
| **E06** | Pleitos | Pedido de aditivo (inclusive por serviço a mais), prorrogação, reequilíbrio, reprogramação do cronograma, com justificativa e anexos |
| **E07** | Notificações | Recebe e responde notificações da fiscalização dentro do prazo |

### Campo (app de celular)

Diário da empresa, fotos (com escolha de frente e serviço na hora), áudio, vistoria do fiscal, Boletim de Execução e ocorrência. Tudo offline-first (ver `03-arquitetura.md` §5).

**O diário da empresa só existe aqui.** Ele não tem tela no desktop; lá o fiscal só valida o diário que a empresa fechou (P07). Plataformas do app: Android, GrapheneOS, LineageOS, HarmonyOS, Apple (iPhone e iPad) e KaiOS, com o que cada uma exige em `03-arquitetura.md` §5.1.

## 3. Fluxos principais

Detalhes de eventos, boletins, previsão e relatórios em [`10-execucao-eventos-previsao.md`](10-execucao-eventos-previsao.md).

### 3.1 Contrato → execução

```
Licitação (fora do sistema) ─► P02 cadastra contrato e a forma de medir
   ─► ÓRGÃO fornece planilha, projeto e cronograma ─► P03 lê, confere e publica:
        planilha  ─► Rev. 0 (soma = valor do contrato)
        cronograma ─► linha de base
        projeto   ─► pranchas ligadas à EAP e às frentes
        frentes + agrupadores ─► eventos, com valor calculado
   ─► portaria designa fiscal (P01) ─► ordem de serviço (P02) ─► obra "em_execucao"
```

### 3.2 Diário de obras (RDO)

```
EMPRESA E02: rascunho ─► fechado (responsável assina) ─┐
                                                        ▼
FISCAL P07:                          em_validacao ─► validado | devolvido (com motivo)
                                                        │ devolvido volta p/ empresa, que
                                                        ▼ **retifica por novo registro**
                                                   (dia fechado nunca é sobrescrito)
```
Regras: um RDO por obra por dia; cada serviço executado aponta a **frente** e o **serviço da planilha**; fiscal adiciona **instruções** como entradas separadas e imutáveis; foto de evidência só entra pela câmera do app (guarda hora, GPS, precisão, hash, frente e serviço).

### 3.3 Boletim de Execução (fiscalização)

```
FISCAL P05: vistoria no local ─► rascunho (situação e avanço por evento, com evidência)
   ─► emitido (assinado, imutável) ─► alimenta: análise da medição · previsão · painel
   correção = boletim retificador
```
O que a empresa declara só vira "verificado" depois do boletim. **Evento sem boletim que o marque concluído não é aprovado na medição.**

### 3.4 Medição (duas formas; eventos primeiro)

```
E03 rascunho ─► enviada ─► P06 em_analise
     │                         │
     │  EVENTOS: marca os eventos concluídos        confere contra o Boletim de Execução;
     │  QUANTIDADE: informa a quantidade por item   glosa o evento inteiro ou parte da quantidade
     │                         │
     │             devolvida (empresa corrige)  ou  aprovada_fiscal
     │                                                 │
     │                     [comissão de medição, se o município exigir]
     ▼                                                 ▼
planilha de medição + relatório fotográfico        atestada ─► liquidação (P09) ─► paga
```
Invariantes (já provadas no schema de referência): período não sobrepõe outra medição; só uma medição aberta por contrato; não mede acima do saldo da revisão vigente; medição aprovada é imutável; medição usa a revisão vigente quando aberta; o mesmo evento não é medido duas vezes. Na forma por eventos, as linhas por serviço são **geradas** a partir dos eventos, para que saldo e limites usem um único caminho.

### 3.5 Previsão

```
cronograma vigente + último Boletim de Execução emitido + calendário da obra
   ─► P17 calcula: término previsto de cada evento e da obra (desvio em dias)
   ─► + prazos de processo configurados ─► data e valor previstos de pagamento de cada evento
   ─► gestão vê o desembolso por mês; empresa vê o recebimento por evento
```
Cálculo determinístico em código. Não altera cronograma, prazo, medição nem pagamento.

### 3.6 Aditivo (inclusive serviços a mais)

```
diário, vistoria ou Boletim de Execução ─► apontamento de serviço a mais ─► análise do fiscal
E06 pleito ──────────────────────────────────────────────┘
   ─► P04 rascunho do aditivo montado pelo sistema + simulação de limites (art. 125)
   ─► parecer jurídico/CI ─► autorização do gestor ─► termo aditivo assinado
   ─► Rev. N+1 vigente (eventos novos, se houver) ─► publicação PNCP
```
Itens novos são precificados pelo **fator do art. 127** (proposta ÷ orçamento-base). O sistema **calcula e mostra**; quem decide é gente. Serviço a mais **não é medido** antes do aditivo homologado.

### 3.7 Recebimento

```
conclusão comunicada ─► P08 termo provisório (fiscal) ─► pendências ─► termo definitivo (servidor/comissão)
   ─► contagem da garantia (mín. 5 anos, art. 140 §6º) com alertas
```
**Atenção:** o art. 140 **não fixa prazos em dias** para os recebimentos; eles vêm de regulamento municipal ou do contrato. Portanto os prazos são **configuração por município/contrato**, nunca constante no código.

## 4. Duas formas de medir

O pedido original fala em "obras públicas com acompanhamentos diferentes". No Prumo isso são **duas formas**, escolhidas por contrato (`forma_acompanhamento`), com **eventos como forma prioritária**:

| Forma | Quando | Como mede |
|---|---|---|
| **`eventos`** (prioritária) | Preço global, empreitada integral, tarefa, contratação integrada e semi-integrada; repasse medido por eventos | Evento (agrupador × frente) medido **inteiro quando concluído** e verificado no Boletim de Execução |
| **`bm`** | Empreitada por preço unitário; serviço contínuo por demanda | Quantidade por serviço da planilha, com memória de cálculo |

Os casos que antes eram perfis separados viram recortes das duas formas:

| Caso | Forma | Recorte |
|---|---|---|
| Preço global por etapas | `eventos` | Etapa do cronograma = agrupador |
| Repasse por eventos (modelo Caixa) | `eventos` | Exportação nos layouts PLE, CRONOPLE e RRE |
| Pavimentação e obra linear | `eventos` | Frente = trecho georreferenciado (estacas, km) |
| Serviço contínuo (manutenção, roçada, tapa-buraco) | `bm` | Ordens de serviço por demanda e produção por período |

Em contrato `bm`, eventos podem ser cadastrados como **marcos físicos**, sem efeito financeiro, para usar o Boletim de Execução e a previsão. Um recorte novo é um *adaptador de medição* na camada de aplicação, sem tocar nas invariantes comuns.
