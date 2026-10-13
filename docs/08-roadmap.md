# 08 · Roadmap e ordem de construção

Princípio: **primeiro o que não pode errar (regras, banco, auditoria), depois a conveniência (IA, painéis).** Dentro de cada fase, **eventos vêm antes da medição por quantidade**. Cada fase termina com **critérios de aceite executáveis** (teste automatizado ou roteiro de homologação assinado pelo fiscal-piloto).

## Fase 0 — Fundação (sem tela bonita)

> Já existe, feito para a prévia de desktop (ADR 0003): o workspace, e em `crates/dominio` o dinheiro com arredondamento por contrato, o valor de evento, a conferência da medição contra o Boletim de Execução e a previsão de término e de pagamento, com 33 testes. Falta todo o resto desta fase: migrações, paridade com o SQL, limites de aditivo, máquinas de estado, RLS, CI.
>
> **Andamento em 13/10/2026** (branch `fase-0-fundacao`, plano em `plano-fase-0.md`): toolchain fixada e verificação local; `scripts/db-test.sh` em PostgreSQL 16 real; migração `0001` com o porte provado contra a referência; registro de migrações; papel `app_rw` e teste de isolamento entre dois municípios. As caixas abaixo só são marcadas quando o item inteiro estiver pronto.

- [ ] Workspace Rust, `rust-toolchain.toml`, `Cargo.lock`, CI verde (fmt, clippy `-D warnings`, test, audit, deny).
- [ ] `db/migrations/0001..0009` a partir do schema de referência (ver `06-banco-de-dados.md`) + suíte de invariantes `espera_erro` rodando em Postgres real.
- [ ] `dominio`: dinheiro/arredondamento por contrato, **valor de evento**, limites art. 125, fator art. 127, estados de medição, diário, aditivo e **Boletim de Execução**. **Testes de paridade Rust × SQL** (mesmo centavo), incluindo `fn_recalcular_eventos`.
- [ ] `dominio::previsao`: cálculo puro de término e de recebimento, com teste de propriedade (mesma entrada, mesma saída) e teste de que os prazos vêm da configuração.
- [ ] **Seed fictício com um contrato por eventos e um por quantidade.** O seed de referência não exercita frentes, agrupadores nem eventos; o teste que cobria isso usava dados reais e não está no repositório.
- [ ] RLS e papel `app_rw` sem `BYPASSRLS`; teste de isolamento entre dois municípios.
- [ ] `docs/adr/` com as decisões seguintes (tenant = município, UI em TS, Postgres). Já registradas: nome e marca (0001), eventos como forma prioritária (0002).
- **Aceite:** reproduzir em Rust os números do seed do engenheiro (escavação 2.929,52; aditivo; boletim nº 3), os valores dos eventos do seed fictício, e passar todos os testes de bloqueio, inclusive as 15 invariantes de `10-execucao-eventos-previsao.md` §9.

## Fase 1 — Núcleo contratual e documentos do órgão

- [ ] P01 cadastros, P02 obra/contrato/OS com a **forma de medir**, designação por portaria.
- [ ] P03 leitura da **planilha** (arquivo → staging → revisão → Rev. 0) com conferência de total.
- [ ] P03 leitura do **cronograma** (linha de base) e do **eventograma**; montagem manual de frentes, agrupadores e eventos quando o órgão não manda.
- [ ] P03 cadastro de **pranchas do projeto** com texto do carimbo extraído por código e vínculo manual com a EAP.
- [ ] Autenticação, perfis, designação, segregação de funções.
- **Aceite:** ler a planilha e o cronograma reais de uma obra-piloto, bater o total com o edital centavo a centavo, e publicar os eventos com a soma dos eventos igual ao valor da revisão.

## Fase 2 — Execução por eventos (o coração)

Ordem interna: primeiro tudo por eventos, depois a medição por quantidade.

- [ ] E02/P07 diário com serviço por frente e fluxo completo; fotos pela câmera do app com frente e serviço; PDF do RDO.
- [ ] **P05 Boletim de Execução** (desktop e campo, offline), com emissão, assinatura e retificador.
- [ ] **E03/P06 medição por eventos**: declaração, conferência contra o boletim, glosa do evento, devolução, aprovação.
- [ ] **P16 relatórios**: planilha de medição (PDF e `.xlsx`), relatório fotográfico, Boletim de Execução, Caderno de Medição.
- [ ] **P17 previsão**: término por evento, término da obra, desembolso previsto e previsão de recebimento.
- [ ] E03/P06 medição **por quantidade (BM)**, reaproveitando análise, glosa e relatórios.
- [ ] App de celular para **Android**, offline, sem serviços do Google, + `sync` (comandos idempotentes, mídia em partes). O mesmo APK é testado em GrapheneOS, LineageOS e HarmonyOS até a 4.
- [ ] O mesmo app para **Apple (iPhone e iPad)**, depois do Android homologado. Depende de máquina macOS e conta de desenvolvedor (questão 27).
- **Aceite:** fiscal e apontador reais completam um ciclo mensal de uma obra-piloto por eventos **sem planilha paralela**: boletim emitido, medição aprovada, planilha de medição e relatório fotográfico gerados pelo sistema e conferidos à mão pelo fiscal. A previsão do mês seguinte é comparada com o que aconteceu, e o erro em dias é registrado.

## Fase 3 — Fiscalização, serviços a mais, aditivos, recebimento

- [ ] P05 ocorrências, notificações, vistorias e **apontamento de serviço a mais**.
- [ ] P04 aditivos com rascunho montado a partir dos serviços a mais, simulação de limites, **planilha de aditivo**; evento novo na Rev. N+1; reprogramação do cronograma.
- [ ] P08 recebimento e garantia de 5 anos.
- [ ] Assinatura (provedor plugável) e trilha de aprovação.
- **Aceite:** aditivo com um acréscimo e um serviço novo precificado pelo fator art. 127, Rev. 1 gerada com evento complementar, planilha de aditivo emitida; termo de recebimento emitido.

## Fase 4 — Transparência e prestação de contas

- [ ] P11 mapa e ficha pública (percentual **verificado**); P14 ouvidoria; P12 adaptador PNCP, adaptador do tribunal do estado-alvo, relatórios de repasse (PLE, CRONOPLE, RRE como exportação).
- [ ] Auditoria de acessibilidade do portal.
- **Aceite:** pacote mensal aceito no ambiente de homologação do tribunal; publicação no PNCP de ambiente de teste.

## Fase 5 — IA de borda (Prumo IA Local, RREIA)

Ordem em `docs/04-ia-borda-rreia.md` §7. Só liga cada função após métrica mínima em conjunto rotulado (LP10).
- [ ] Responder as perguntas de `RREIA.md` §1 e rodar a sonda de hardware no servidor-alvo; decidir máquina dedicada ou compartilhada.
- [ ] `rreia-jev` + `rreia-gate` integrados; testes das leis L1–L9 e LP1–LP10 com modelo simulado.
- [ ] IA-12, IA-19, IA-21 e IA-09 → IA-02, IA-01, IA-03 → IA-20, IA-23, IA-24 → IA-06, IA-07, IA-22 (com parecer jurídico) → painel IA.
- **Aceite:** relatório "estimado / medido / não testado", com tok/s, pico de memória e taxa de respostas válidas do hardware real.

## Fase 6 — Endurecimento e implantação

- [ ] Teste de intrusão, teste de carga (n fiscais × m empresas), teste de restauração de backup, plano de continuidade.
- [ ] Manual de implantação on-prem, roteiro de homologação para a prefeitura, treinamento por perfil.
- [ ] Primeira release assinada com SBOM e atestado de proveniência (ver `09-distribuicao.md`).

## Fora do escopo inicial (consciente)

Contabilidade pública completa, almoxarifado municipal, protocolo geral, folha de pagamento. O sistema **referencia** empenho/liquidação/pagamento; não os substitui. BIM/IFC fica para depois da Fase 4. KaiOS e HarmonyOS NEXT estão na lista de plataformas do autor, mas não rodam o APK e ainda não têm plano (questões 26 e 28). Também ficam de fora, por decisão: levantar quantidade a partir de desenho, OCR de prancha escaneada, leitura de planilha ou cronograma que só existam em PDF, leitura de DWG.

## Riscos principais

| Risco | Mitigação |
|---|---|
| Layout do tribunal de contas muda ou difere do esperado | Adaptador isolado; homologar cedo (Fase 1) |
| Regra municipal (prazos, comissão, assinatura) varia | Tudo em `config_municipio`; nada hardcoded |
| IA errar em algo que afeta pagamento | LP1, LP2, LP10; funções de alto risco só após parecer jurídico |
| Campo sem sinal | Offline-first desde a Fase 2 |
| Plataformas da lista que não rodam o APK (KaiOS, HarmonyOS NEXT) viram dois clientes a mais para manter | Decidir o escopo de cada uma antes de começar (questões 26 e 28); o servidor valida tudo, então um cliente reduzido não enfraquece as regras |
| App dependente do Google deixa de funcionar em GrapheneOS, LineageOS e HarmonyOS | Proibido depender do Google Play Services (`03-arquitetura.md` §5); testar o APK nesses sistemas na Fase 2 |
| Dependência de uma pessoa (autor do RREIA, engenheiro) | ADRs, testes, documentação; repositório com mais de um mantenedor |
| Falha de hardware da prefeitura | Backup 3-2-1, restauração testada, modo sem IA |
| Órgão entrega planilha, cronograma ou projeto em formato que o sistema não lê | Confirmar formatos antes do piloto (questão 15); digitação assistida como saída; arquivo original sempre guardado com hash |
| Estrutura de eventos mal montada vira marco de pagamento errado | Valor calculado em código; soma dos eventos = valor da revisão; confirmação linha a linha; publicação é ato do planejador, com diálogo de ação irreversível |
| Previsão lida como promessa de pagamento | Selo "Previsão" em toda data e valor; aviso revisado pelo jurídico; não publicada ao cidadão sem decisão do gestor; erro da previsão medido a cada ciclo |
| Fiscal sem tempo para emitir o Boletim de Execução trava o pagamento | Boletim no app de campo, offline, em poucos toques; alerta de prazo na fila do fiscal; periodicidade configurável |
| Servidor de 16 GB compartilhado com o banco deixa a IA sem folga de memória | Decidir dedicado × compartilhado antes de comprar (`RREIA.md` §3); modelo de 3B ou 32 GB como saída |
