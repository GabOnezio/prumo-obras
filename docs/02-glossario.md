# 02 · Glossário do ofício

| Termo | Significado no sistema |
|---|---|
| **Prumo** | Nome do produto. Chamada: "Gestão de Obras Públicas". Na tela: "Prumo · Prefeitura de ___", com o brasão do município |
| **Prumo IA Local** | Nome de venda da IA local do Prumo. Na documentação técnica: "Prumo + RREIA" |
| **Órgão / Unidade gestora** | Secretaria ou ente contratante. É quem **fornece** planilha orçamentária, projeto e cronograma |
| **Contratada** | Empresa que executa a obra |
| **Gestor do contrato** | Servidor responsável pela gestão administrativa do contrato |
| **Fiscal (técnico / administrativo)** | Servidor designado por portaria para acompanhar a execução (art. 117) |
| **Preposto** | Representante da contratada junto à fiscalização |
| **Responsável técnico (RT)** | Profissional com ART/RRT pela obra |
| **EAP** | Estrutura Analítica do Projeto: planilha em árvore (grupos e serviços) |
| **Planilha orçamentária** | Lista de serviços com unidade, quantidade e preço unitário |
| **Revisão (Rev. 0, 1…)** | Versão imutável da planilha; cada aditivo homologado gera uma nova |
| **Item contratual** | Serviço que mantém identidade ao longo das revisões |
| **BDI** | Benefícios e Despesas Indiretas, percentual sobre o custo |
| **SINAPI / SICRO / ORSE** | Bases oficiais de preços e composições |
| **Data-base** | Mês de referência dos preços (marco do reajuste) |
| **Projeto / Prancha** | Desenhos fornecidos pelo órgão. Cada prancha (folha) é cadastrada com número, título, disciplina e revisão, e ligada à EAP e às frentes |
| **Cronograma físico-financeiro** | Programação das etapas ou eventos no tempo, em percentual ou valor por período. Fornecido pelo órgão |
| **Linha de base / Reprogramação** | Primeira versão do cronograma, imutável / nova versão, com motivo e autor |
| **Previsão** | Estimativa **calculada pelo código** (não pela IA) de quando cada evento e a obra terminam, a partir do ritmo verificado nos Boletins de Execução |
| **Desembolso previsto / Previsão de recebimento** | Data e valor em que cada evento deve virar pagamento: término previsto + prazos de processo configurados. A prefeitura vê como desembolso; a empresa, como recebimento |
| **Forma de medir** | Como o contrato é medido: por **eventos** (forma prioritária) ou por **quantidade** (BM). Escolhida por contrato |
| **Frente de obra** | Parte física da obra onde o serviço acontece (Térreo, Bloco B, Trecho 1) |
| **Agrupador de eventos** | Conjunto de serviços da planilha que fazem sentido juntos (Estrutura: pilares, Alvenaria, Cobertura) |
| **Evento** | Agrupador × frente. Vale a soma, serviço a serviço, da quantidade na frente × preço unitário. É medido **inteiro quando concluído** |
| **Eventograma** | Planilha que distribui os serviços em agrupadores e frentes e programa os eventos no tempo. No modelo da Caixa: PLE e CRONOPLE |
| **Marco físico** | Evento cadastrado em contrato medido por quantidade, sem efeito financeiro, só para acompanhar e prever |
| **BM — Boletim de Medição** | Documento que apura o executado no período, por quantidade. Segunda forma de medir |
| **PLE / CRONOPLE** | Layouts da Caixa para a medição por eventos e para o cronograma de eventos. No Prumo são formatos de **exportação** da forma `eventos` |
| **RRE** | Relatório de Resumo de Evento: repasse × contrapartida |
| **Medição** | Apuração do que foi executado no período, base do pagamento. Declarada pela empresa, conferida pela fiscalização |
| **Planilha de medição** | Relatório gerado pelo sistema com o previsto, o medido no período, o acumulado e o saldo, por evento e por serviço |
| **Boletim de Execução** | Documento **da fiscalização**: situação e avanço físico de cada evento, conferidos no local, com evidência. Emitido é imutável. Sem ele o evento não é pago |
| **Relatório fotográfico** | Relatório gerado pelo sistema com as fotos da câmera do app, agrupadas por evento, frente e serviço, com data, coordenada e hash |
| **Glosa** | Parte da medição não aceita pela fiscalização, com motivo |
| **Atesto / Atestação** | Declaração formal de que o serviço foi executado, libera a liquidação |
| **Caderno de Medição** | Pacote da medição: capa, planilhas, memória de cálculo, fotos, documentos |
| **RDO — Relatório/Diário de Obras** | Registro diário de clima, efetivo, equipamentos, serviços e ocorrências |
| **Ocorrência** | Fato relevante registrado pela fiscalização (ou pela empresa) |
| **Notificação** | Comunicação formal da fiscalização com prazo de resposta |
| **Aditivo** | Alteração do contrato (prazo, valor, itens) com termo próprio |
| **Apostila** | Registro de ajuste que não exige aditivo (ex.: reajuste previsto) |
| **Acréscimo / Supressão** | Aumento/redução de quantidades dentro dos limites legais (art. 125) |
| **Serviço a mais** | O que aparece na obra e não cabe na planilha vigente: quantidade além da contratada ou serviço que não estava previsto. Vira apontamento, depois item de aditivo. Não é medido antes do aditivo homologado |
| **Restabelecimento** | Devolução de quantidade antes suprimida, no mesmo item e preço (TCU, Acórdão 66/2021-Plenário, conforme o schema de referência) |
| **Fator do art. 127** | Proposta ÷ orçamento-base, aplicado ao preço de referência de item novo |
| **Reequilíbrio / reajuste** | Recomposição econômico-financeira / correção por índice |
| **Recebimento provisório / definitivo** | Termos de aceitação da obra (art. 140). Não confundir com recebimento financeiro (pagamento) |
| **Garantia da obra** | Responsabilidade do contratado por solidez e segurança, mínimo de 5 anos (art. 140 §6º) |
| **Empenho / Liquidação / Pagamento** | Fases da despesa pública; o sistema as **referencia** |
| **PNCP** | Portal Nacional de Contratações Públicas |
| **TCE** | Tribunal de Contas do Estado |
| **Obrasgov.br** | Plataforma federal de obras com recursos da União |
| **LAI** | Lei de Acesso à Informação (12.527/2011) |
| **LGPD / RIPD** | Lei Geral de Proteção de Dados / Relatório de Impacto |
| **RREIA** | Recursos Responsáveis para IA de Borda (arquitetura do autor) |
| **Jev Local** | Servidor Rust de decisões tipadas (`choice`, `score`, `noul`) sobre o modelo local |
| **L1–L9 / LP1–LP10** | Leis do RREIA / leis específicas do módulo Prefeitura |
| **Regra · Sugestão · Previsão** | Os três selos da tela para o que não é dado oficial: verificação determinística; proposta da IA local, a confirmar; estimativa calculada pelo código |
| **Tenant** | Município (isolamento de dados por RLS) |
