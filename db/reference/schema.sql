-- =============================================================================
-- SaaS de Gestão de Obras Públicas — esquema relacional (PostgreSQL 16)
-- Núcleo: Planilha Orçamentária (EAP + revisões) · Medições · Aditivos · Financeiro
-- Também: Suprimentos (apropriação de custo), RDO, Importação (staging),
--         Auditoria, Outbox de eventos e isolamento multi-tenant por RLS.
--
-- Convenções
--   * Valores em R$  → NUMERIC(18,2)   (nunca float)
--   * Quantidades    → NUMERIC(18,4)
--   * Preço unitário → NUMERIC(18,4)   (casas efetivas definidas por contrato)
--   * tenant_id em toda tabela; o default vem da sessão (SET app.tenant_id)
--   * Regras de negócio vivem no domínio (camada de aplicação); os triggers
--     daqui são a última linha de defesa para as invariantes críticas.
-- =============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS ltree;       -- hierarquia da EAP
CREATE EXTENSION IF NOT EXISTS btree_gist;  -- exclusão de períodos sobrepostos

-- Tenant corrente da sessão (NULL se não definido → RLS não devolve nada)
CREATE FUNCTION app_tenant() RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('app.tenant_id', true), '')::uuid
$$;

-- -----------------------------------------------------------------------------
-- Tipos enumerados
-- -----------------------------------------------------------------------------
-- Regimes do art. 46 da Lei 14.133/2021
CREATE TYPE regime_execucao AS ENUM (
  'empreitada_preco_unitario', 'empreitada_preco_global', 'empreitada_integral',
  'contratacao_por_tarefa', 'contratacao_integrada', 'contratacao_semi_integrada');
CREATE TYPE criterio_arredondamento AS ENUM ('truncar', 'arredondar');
CREATE TYPE status_contrato   AS ENUM ('assinado', 'em_execucao', 'paralisado', 'concluido', 'rescindido');
CREATE TYPE status_revisao    AS ENUM ('rascunho', 'vigente', 'substituida');
CREATE TYPE origem_revisao    AS ENUM ('importacao', 'aditivo');
CREATE TYPE tipo_item         AS ENUM ('grupo', 'servico');
CREATE TYPE status_medicao    AS ENUM ('rascunho', 'enviada', 'aprovada', 'cancelada');
-- BM = boletim por quantidade (acompanhamento físico); PLE = eventos por frente de obra (Caixa)
CREATE TYPE forma_acompanhamento AS ENUM ('bm', 'ple');
-- a empresa executa a obra ou fiscaliza o contrato para o tomador
CREATE TYPE papel_empresa     AS ENUM ('contratada', 'fiscalizadora');
CREATE TYPE tipo_aditivo      AS ENUM ('prazo', 'valor', 'prazo_valor');
CREATE TYPE status_aditivo    AS ENUM ('rascunho', 'enviado', 'homologado', 'rejeitado');
-- restabelecimento = devolver quantidade suprimida antes, no mesmo item e preço
-- (TCU, Acórdão 66/2021-Plenário); o sistema reporta à parte do limite de acréscimos
CREATE TYPE operacao_aditivo  AS ENUM ('acrescimo', 'supressao', 'inclusao', 'restabelecimento');
CREATE TYPE tipo_titulo       AS ENUM ('pagar', 'receber');
CREATE TYPE status_titulo     AS ENUM ('previsto', 'aberto', 'quitado', 'cancelado');
CREATE TYPE tipo_retencao     AS ENUM ('INSS', 'ISS', 'IRRF', 'PIS_COFINS_CSLL', 'CAUCAO', 'OUTRA');
CREATE TYPE origem_apropriacao AS ENUM ('direta', 'pedido', 'rateio');
CREATE TYPE criterio_rateio   AS ENUM ('receita_medida', 'custo_direto', 'percentual_fixo');
CREATE TYPE status_importacao AS ENUM ('recebida', 'processando', 'aguardando_revisao', 'concluida', 'falhou', 'descartada');
CREATE TYPE classe_linha      AS ENUM ('grupo', 'servico', 'continuacao', 'rodape', 'ignorada');

-- -----------------------------------------------------------------------------
-- Identidade e tenancy
-- -----------------------------------------------------------------------------
CREATE TABLE tenant (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  razao_social  text NOT NULL,
  cnpj          char(14) NOT NULL UNIQUE,
  criado_em     timestamptz NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- Cadastros gerais
-- -----------------------------------------------------------------------------
CREATE TABLE orgao (                               -- cliente público
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id  uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  nome       text NOT NULL,
  cnpj       char(14) NOT NULL,
  esfera     text NOT NULL CHECK (esfera IN ('municipal', 'estadual', 'federal')),
  uf         char(2) NOT NULL,
  municipio  text,
  UNIQUE (tenant_id, cnpj)
);

CREATE TABLE fornecedor (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  razao_social  text NOT NULL,
  cnpj_cpf      varchar(14) NOT NULL,
  email         text,
  telefone      text,
  ativo         boolean NOT NULL DEFAULT true,
  UNIQUE (tenant_id, cnpj_cpf)
);

CREATE TABLE funcionario (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  nome         text NOT NULL,
  cpf_cifrado  bytea NOT NULL,                     -- LGPD: cifrado na aplicação (KMS)
  cpf_hash     char(64) NOT NULL,                  -- busca sem decifrar
  funcao       text NOT NULL,
  admissao     date,
  ativo        boolean NOT NULL DEFAULT true,
  UNIQUE (tenant_id, cpf_hash)
);

CREATE TABLE equipamento (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  descricao   text NOT NULL,
  patrimonio  text,
  proprio     boolean NOT NULL DEFAULT true,
  fornecedor_id uuid REFERENCES fornecedor        -- locador, quando não é próprio
);

CREATE TABLE obra (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id  uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  nome       text NOT NULL,
  municipio  text NOT NULL,
  uf         char(2) NOT NULL,
  status     text NOT NULL DEFAULT 'ativa' CHECK (status IN ('ativa', 'paralisada', 'concluida')),
  criado_em  timestamptz NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- CONVÊNIO / OPERAÇÃO DE REPASSE (Caixa, TransfereGov) — opcional
-- -----------------------------------------------------------------------------
CREATE TABLE convenio (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id            uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  tomador_orgao_id     uuid NOT NULL REFERENCES orgao,
  agente               text NOT NULL DEFAULT 'CAIXA',
  numero_operacao      text NOT NULL,          -- ex.: '1090814-10'
  numero_transferegov  text,                   -- ex.: '948519/2023'
  apelido              text NOT NULL,          -- apelido do empreendimento
  valor_repasse        numeric(18,2) NOT NULL CHECK (valor_repasse >= 0),
  valor_contrapartida  numeric(18,2) NOT NULL CHECK (valor_contrapartida >= 0),
  UNIQUE (tenant_id, agente, numero_operacao)
);

-- -----------------------------------------------------------------------------
-- CONTRATO
-- -----------------------------------------------------------------------------
CREATE TABLE contrato (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id                uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  obra_id                  uuid NOT NULL REFERENCES obra,
  orgao_id                 uuid NOT NULL REFERENCES orgao,
  numero                   text NOT NULL,          -- nº do contrato no órgão
  processo_licitatorio     text NOT NULL,          -- ex.: 'Concorrência Eletrônica nº 10/2026'
  objeto                   text NOT NULL,
  regime_execucao          regime_execucao NOT NULL,
  data_assinatura          date NOT NULL,
  data_base_orcamento      date NOT NULL,          -- marco do reajuste
  prazo_execucao_dias      integer NOT NULL CHECK (prazo_execucao_dias > 0),  -- prazo ORIGINAL
  vigencia_fim             date NOT NULL,                                     -- vigência ORIGINAL
  valor_inicial            numeric(18,2) NOT NULL CHECK (valor_inicial > 0),  -- valor da proposta
  valor_orcamento_base     numeric(18,2) NOT NULL CHECK (valor_orcamento_base > 0), -- orçamento do edital
  -- relação proposta/orçamento-base: fator do art. 127 para preçar itens novos
  fator_art127             numeric(12,8) GENERATED ALWAYS AS
                             (round(valor_inicial / valor_orcamento_base, 8)) STORED,
  bdi_percentual           numeric(7,4) NOT NULL CHECK (bdi_percentual >= 0),
  reforma                  boolean NOT NULL DEFAULT false,   -- limite de acréscimo 50% (art. 125)
  criterio_arredondamento  criterio_arredondamento NOT NULL DEFAULT 'arredondar',
  casas_decimais_preco     smallint NOT NULL DEFAULT 2 CHECK (casas_decimais_preco BETWEEN 2 AND 4),
  status                   status_contrato NOT NULL DEFAULT 'assinado',
  forma_acompanhamento     forma_acompanhamento NOT NULL DEFAULT 'bm',
  papel_empresa            papel_empresa NOT NULL DEFAULT 'contratada',
  data_inicio_obra         date,
  -- referência de custos do orçamento (ex.: SINAPI Curitiba 07/2024, não desonerado)
  localidade_referencia    text,
  desonerado               boolean NOT NULL DEFAULT false,
  -- contratos com repasse: parte financiada pelo repasse; o resto é contrapartida
  convenio_id              uuid REFERENCES convenio,
  valor_repasse            numeric(18,2) CHECK (valor_repasse >= 0),
  UNIQUE (tenant_id, orgao_id, numero),
  CHECK (valor_repasse IS NULL OR (convenio_id IS NOT NULL AND valor_repasse <= valor_inicial))
);

-- Retenções na fonte aplicadas a cada medição (alíquota e base por contrato)
CREATE TABLE contrato_retencao (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id        uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  contrato_id      uuid NOT NULL REFERENCES contrato ON DELETE CASCADE,
  tipo             tipo_retencao NOT NULL,
  aliquota         numeric(7,4) NOT NULL CHECK (aliquota >= 0),
  base_percentual  numeric(7,4) NOT NULL DEFAULT 100 CHECK (base_percentual BETWEEN 0 AND 100),
  UNIQUE (contrato_id, tipo)
);

-- -----------------------------------------------------------------------------
-- PLANILHA ORÇAMENTÁRIA: revisões imutáveis + item contratual com identidade estável
-- -----------------------------------------------------------------------------
CREATE TABLE revisao_orcamento (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  contrato_id    uuid NOT NULL REFERENCES contrato,
  numero         smallint NOT NULL CHECK (numero >= 0),   -- 0 = planilha contratual
  origem         origem_revisao NOT NULL,
  aditivo_id     uuid,                                     -- FK adicionada após 'aditivo'
  status         status_revisao NOT NULL DEFAULT 'rascunho',
  data_vigencia  date,
  valor_total    numeric(18,2),                            -- calculado ao tornar-se vigente
  criado_em      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (contrato_id, numero),
  UNIQUE (contrato_id, id),
  CHECK ((numero = 0 AND origem = 'importacao' AND aditivo_id IS NULL)
      OR (numero > 0 AND origem = 'aditivo' AND aditivo_id IS NOT NULL))
);
-- No máximo UMA revisão vigente por contrato
CREATE UNIQUE INDEX ux_revisao_vigente ON revisao_orcamento (contrato_id) WHERE status = 'vigente';

-- Identidade do item ao longo de todas as revisões (medições apontam para cá)
CREATE TABLE item_contratual (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  contrato_id  uuid NOT NULL REFERENCES contrato,
  criado_em    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (contrato_id, id)
);

-- O item como ele está em UMA revisão (nó da EAP: grupo ou serviço)
CREATE TABLE item_revisao (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id             uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  revisao_id            uuid NOT NULL REFERENCES revisao_orcamento ON DELETE CASCADE,
  item_contratual_id    uuid NOT NULL REFERENCES item_contratual,
  parent_id             uuid,
  ordem                 integer NOT NULL CHECK (ordem BETWEEN 1 AND 99999),
  path                  ltree NOT NULL,           -- calculado: posição na árvore
  codigo_eap            text NOT NULL,            -- como veio na planilha: '2.1.3'
  tipo                  tipo_item NOT NULL,
  descricao             text NOT NULL,
  unidade               text,
  quantidade            numeric(18,4),
  custo_unitario        numeric(18,4),            -- sem BDI (referência ou composição)
  bdi_percentual        numeric(7,4),             -- BDI do item (BDI 1, 2, 3 da Caixa); NULL = do contrato
  preco_unitario        numeric(18,4),            -- com BDI
  valor_total           numeric(18,2),            -- serviço: qtd × PU (regra do contrato)
  fonte                 text,                     -- SINAPI, SINAPI-I, SICRO, ORSE, CPOS, COMPOSIÇÃO...
  codigo_referencia     text,                     -- ex.: código SINAPI
  data_base_referencia  date,
  fonte_recurso         text NOT NULL DEFAULT 'RA' CHECK (fonte_recurso IN ('RA', 'RP', 'CP', 'OU')),
                                                  -- RA rateio repasse/contrapartida · RP repasse · CP contrapartida · OU outros
  agrupador_evento_id   uuid,                     -- PLE: agrupador de eventos (FK adiante)
  codigo_original       text,                     -- item como veio no arquivo, se foi renumerado
  linha_origem          integer,                  -- linha da planilha importada
  UNIQUE (revisao_id, id),
  UNIQUE (revisao_id, item_contratual_id),
  UNIQUE (revisao_id, codigo_eap),
  UNIQUE (revisao_id, path),
  FOREIGN KEY (revisao_id, parent_id) REFERENCES item_revisao (revisao_id, id),  -- pai na MESMA revisão
  CHECK (
    (tipo = 'grupo'   AND unidade IS NULL AND quantidade IS NULL AND preco_unitario IS NULL)
 OR (tipo = 'servico' AND unidade IS NOT NULL AND quantidade >= 0 AND preco_unitario >= 0))
);
CREATE INDEX ix_item_revisao_path ON item_revisao USING gist (path);
CREATE INDEX ix_item_revisao_item ON item_revisao (item_contratual_id);

-- -----------------------------------------------------------------------------
-- MEDIÇÕES
-- -----------------------------------------------------------------------------
CREATE TABLE medicao (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  contrato_id     uuid NOT NULL REFERENCES contrato,
  numero          integer NOT NULL CHECK (numero > 0),
  revisao_id      uuid NOT NULL,                  -- revisão vigente quando foi aberta
  periodo_inicio  date NOT NULL,
  periodo_fim     date NOT NULL,
  status          status_medicao NOT NULL DEFAULT 'rascunho',
  valor_bruto     numeric(18,2) NOT NULL DEFAULT 0,
  enviada_em      timestamptz,
  aprovada_em     timestamptz,
  aprovada_por    text,                           -- fiscal do contrato
  observacao      text,
  UNIQUE (contrato_id, numero),
  FOREIGN KEY (contrato_id, revisao_id) REFERENCES revisao_orcamento (contrato_id, id),
  CHECK (periodo_fim >= periodo_inicio),
  -- períodos de medições válidas não se sobrepõem
  EXCLUDE USING gist (contrato_id WITH =, daterange(periodo_inicio, periodo_fim, '[]') WITH &&)
    WHERE (status <> 'cancelada')
);
-- Só uma medição em aberto por contrato (rascunho ou enviada ao fiscal)
CREATE UNIQUE INDEX ux_medicao_aberta ON medicao (contrato_id) WHERE status IN ('rascunho', 'enviada');

CREATE TABLE medicao_item (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  medicao_id          uuid NOT NULL REFERENCES medicao ON DELETE CASCADE,
  item_contratual_id  uuid NOT NULL REFERENCES item_contratual,
  quantidade          numeric(18,4) NOT NULL,     -- pode ser negativa (estorno)
  valor               numeric(18,2) NOT NULL,     -- calculado: qtd × PU (BM) ou soma das frentes (PLE)
  origem              forma_acompanhamento NOT NULL DEFAULT 'bm',
  quantidade_aferida  numeric(18,4),              -- aferição do agente (Caixa), quando houver
  memoria_calculo     text,
  UNIQUE (medicao_id, item_contratual_id)
);
CREATE INDEX ix_medicao_item_item ON medicao_item (item_contratual_id);

-- Quadro de glosas do BM (quantidade não aceita pela fiscalização ou pelo agente)
CREATE TABLE medicao_glosa (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  medicao_id          uuid NOT NULL REFERENCES medicao ON DELETE CASCADE,
  item_contratual_id  uuid NOT NULL REFERENCES item_contratual,
  quantidade          numeric(18,4) NOT NULL CHECK (quantidade > 0),
  valor               numeric(18,2) NOT NULL CHECK (valor > 0),
  motivo              text NOT NULL
);

-- -----------------------------------------------------------------------------
-- MEDIÇÃO POR EVENTOS (PLE — Planilha de Levantamento de Eventos, Caixa)
-- Evento = agrupador × frente de obra. Vale a soma, serviço a serviço, de
-- round(quantidade na frente × PU); é medido inteiro quando concluído.
-- -----------------------------------------------------------------------------
CREATE TABLE frente_obra (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  contrato_id  uuid NOT NULL REFERENCES contrato,
  ordem        smallint NOT NULL CHECK (ordem > 0),
  nome         text NOT NULL,                    -- ex.: 'TELHADO - FRENTE 01'
  UNIQUE (contrato_id, ordem)
);

CREATE TABLE agrupador_evento (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  contrato_id  uuid NOT NULL REFERENCES contrato,
  numero       smallint NOT NULL CHECK (numero > 0),
  titulo       text NOT NULL,                    -- ex.: 'REFORMA DO TELHADO'
  UNIQUE (contrato_id, numero)
);
ALTER TABLE item_revisao ADD FOREIGN KEY (agrupador_evento_id) REFERENCES agrupador_evento;

-- Memória de cálculo por frente: quanto de cada serviço cai em cada frente
CREATE TABLE item_frente (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id        uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  item_revisao_id  uuid NOT NULL REFERENCES item_revisao ON DELETE CASCADE,
  frente_id        uuid NOT NULL REFERENCES frente_obra,
  quantidade       numeric(18,4) NOT NULL CHECK (quantidade > 0),
  UNIQUE (item_revisao_id, frente_id)
);

CREATE TABLE evento (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id         uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  revisao_id        uuid NOT NULL REFERENCES revisao_orcamento ON DELETE CASCADE,
  agrupador_id      uuid NOT NULL REFERENCES agrupador_evento,
  frente_id         uuid NOT NULL REFERENCES frente_obra,
  valor             numeric(18,2) NOT NULL,      -- calculado por fn_recalcular_eventos
  periodo_previsto  smallint CHECK (periodo_previsto > 0),   -- cronograma previsto (CRONOPLE)
  UNIQUE (revisao_id, agrupador_id, frente_id)
);

-- Eventos concluídos em cada medição (PLE)
CREATE TABLE medicao_evento (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  medicao_id  uuid NOT NULL REFERENCES medicao ON DELETE CASCADE,
  evento_id   uuid NOT NULL REFERENCES evento,
  UNIQUE (medicao_id, evento_id)
);

-- Cronograma físico-financeiro previsto: % de cada grupo da EAP por período
CREATE TABLE cronograma_parcela (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  revisao_id          uuid NOT NULL REFERENCES revisao_orcamento ON DELETE CASCADE,
  item_contratual_id  uuid NOT NULL REFERENCES item_contratual,
  periodo             smallint NOT NULL CHECK (periodo > 0),
  percentual          numeric(7,4) NOT NULL CHECK (percentual BETWEEN 0 AND 100),
  UNIQUE (revisao_id, item_contratual_id, periodo)
);

-- -----------------------------------------------------------------------------
-- REFERÊNCIAS DE CUSTO (SINAPI, SICRO, banco 'Referência' da Caixa, composições próprias)
-- tenant_id NULL = base pública, visível a todas as empresas; carregada pela plataforma
-- -----------------------------------------------------------------------------
CREATE TABLE base_referencia (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid REFERENCES tenant,
  origem          text NOT NULL,                 -- 'CAIXA_REFERENCIA', 'SINAPI', 'SICRO', 'PROPRIA'
  localidade      text NOT NULL,                 -- 'CURITIBA'
  data_base       date NOT NULL CHECK (extract(day FROM data_base) = 1),
  arquivo_sha256  char(64),
  importado_em    timestamptz NOT NULL DEFAULT now(),
  UNIQUE NULLS NOT DISTINCT (tenant_id, origem, localidade, data_base)
);

CREATE TABLE preco_referencia (
  tenant_id              uuid REFERENCES tenant,
  base_id                uuid NOT NULL REFERENCES base_referencia ON DELETE CASCADE,
  fonte                  text NOT NULL,          -- SINAPI, SINAPI-I, COMPOSIÇÃO...
  codigo                 text NOT NULL,
  descricao              text NOT NULL,
  unidade                text NOT NULL,
  custo_desonerado       numeric(18,4),
  custo_nao_desonerado   numeric(18,4),
  PRIMARY KEY (base_id, fonte, codigo)
);

-- -----------------------------------------------------------------------------
-- ADITIVOS
-- -----------------------------------------------------------------------------
CREATE TABLE aditivo (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id              uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  contrato_id            uuid NOT NULL REFERENCES contrato,
  numero                 smallint NOT NULL CHECK (numero > 0),
  tipo                   tipo_aditivo NOT NULL,
  status                 status_aditivo NOT NULL DEFAULT 'rascunho',
  fundamento_legal       text NOT NULL,           -- ex.: 'Art. 124, I, b, Lei 14.133/2021'
  justificativa          text NOT NULL,
  dias_prazo_execucao    integer NOT NULL DEFAULT 0,
  nova_vigencia_fim      date,
  revisao_base_id        uuid,                    -- revisão que o aditivo altera
  revisao_resultante_id  uuid,                    -- gerada na homologação
  data_assinatura        date,
  homologado_em          timestamptz,
  UNIQUE (contrato_id, numero),
  UNIQUE (contrato_id, id),
  FOREIGN KEY (contrato_id, revisao_base_id)       REFERENCES revisao_orcamento (contrato_id, id),
  FOREIGN KEY (contrato_id, revisao_resultante_id) REFERENCES revisao_orcamento (contrato_id, id),
  CHECK (tipo = 'valor' OR dias_prazo_execucao <> 0 OR nova_vigencia_fim IS NOT NULL),
  CHECK (tipo = 'prazo' OR revisao_base_id IS NOT NULL),
  CHECK (status <> 'homologado' OR data_assinatura IS NOT NULL)
);

ALTER TABLE revisao_orcamento
  ADD FOREIGN KEY (contrato_id, aditivo_id) REFERENCES aditivo (contrato_id, id);

CREATE TABLE aditivo_item (
  id                         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id                  uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  aditivo_id                 uuid NOT NULL REFERENCES aditivo ON DELETE CASCADE,
  item_contratual_id         uuid NOT NULL REFERENCES item_contratual,
  operacao                   operacao_aditivo NOT NULL,
  quantidade_delta           numeric(18,4) NOT NULL,
  preco_unitario             numeric(18,4) NOT NULL,   -- existente: PU da revisão base
  valor_delta                numeric(18,2) NOT NULL,   -- calculado
  -- somente para inclusão de item novo:
  parent_item_contratual_id  uuid REFERENCES item_contratual,
  codigo_eap                 text,
  descricao                  text,
  unidade                    text,
  fonte                      text,
  codigo_referencia          text,
  preco_referencia           numeric(18,4),            -- preço de referência na data do aditivo
  UNIQUE (aditivo_id, item_contratual_id),
  CHECK ((operacao = 'supressao' AND quantidade_delta < 0)
      OR (operacao <> 'supressao' AND quantidade_delta > 0)),
  CHECK (operacao <> 'inclusao' OR (parent_item_contratual_id IS NOT NULL AND codigo_eap IS NOT NULL
         AND descricao IS NOT NULL AND unidade IS NOT NULL AND preco_referencia IS NOT NULL))
);

-- -----------------------------------------------------------------------------
-- IMPORTAÇÃO DE PLANILHA (staging)
-- -----------------------------------------------------------------------------
CREATE TABLE importacao (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id            uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  contrato_id          uuid NOT NULL REFERENCES contrato,
  arquivo_s3_key       text NOT NULL,             -- original preservado (prova)
  arquivo_sha256       char(64) NOT NULL,
  nome_arquivo         text NOT NULL,
  aba                  text,
  linha_cabecalho      integer,
  mapeamento_colunas   jsonb,                     -- {"codigo":"A","descricao":"C",...}
  perfil_layout        text,                      -- layout reutilizável por órgão
  criterio_detectado   criterio_arredondamento,
  total_planilha       numeric(18,2),             -- total declarado no arquivo
  total_calculado      numeric(18,2),
  status               status_importacao NOT NULL DEFAULT 'recebida',
  revisao_id           uuid REFERENCES revisao_orcamento,  -- preenchida no commit
  criado_em            timestamptz NOT NULL DEFAULT now(),
  criado_por           text
);
-- mesmo arquivo não é importado duas vezes no mesmo contrato
CREATE UNIQUE INDEX ux_importacao_arquivo ON importacao (contrato_id, arquivo_sha256)
  WHERE status NOT IN ('descartada', 'falhou');

CREATE TABLE importacao_linha (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id          uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  importacao_id      uuid NOT NULL REFERENCES importacao ON DELETE CASCADE,
  linha              integer NOT NULL,            -- nº da linha no Excel
  bruto              jsonb NOT NULL,              -- células como vieram
  classe             classe_linha,
  codigo_eap         text,
  nivel              smallint,
  linha_pai          integer,
  descricao          text,
  unidade            text,
  quantidade         numeric(18,4),
  preco_unitario     numeric(18,4),
  valor_total        numeric(18,2),
  fonte              text,
  codigo_referencia  text,
  erros              jsonb NOT NULL DEFAULT '[]', -- bloqueiam o commit
  avisos             jsonb NOT NULL DEFAULT '[]', -- exigem ciência do usuário
  editada            boolean NOT NULL DEFAULT false,
  UNIQUE (importacao_id, linha)
);

-- -----------------------------------------------------------------------------
-- SUPRIMENTOS (cotação → pedido → apropriação)
-- -----------------------------------------------------------------------------
CREATE TABLE plano_contas (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id          uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  codigo             text NOT NULL,
  descricao          text NOT NULL,
  natureza           text NOT NULL CHECK (natureza IN ('receita', 'despesa')),
  parent_id          uuid REFERENCES plano_contas,
  aceita_lancamento  boolean NOT NULL DEFAULT true,
  UNIQUE (tenant_id, codigo)
);

CREATE TABLE cotacao (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  obra_id      uuid NOT NULL REFERENCES obra,
  numero       integer NOT NULL,
  data_limite  date,
  status       text NOT NULL DEFAULT 'aberta' CHECK (status IN ('aberta', 'em_analise', 'concluida', 'cancelada')),
  UNIQUE (tenant_id, numero)
);

CREATE TABLE cotacao_item (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  cotacao_id          uuid NOT NULL REFERENCES cotacao ON DELETE CASCADE,
  descricao           text NOT NULL,
  unidade             text NOT NULL,
  quantidade          numeric(18,4) NOT NULL CHECK (quantidade > 0),
  item_contratual_id  uuid REFERENCES item_contratual   -- serviço da EAP que vai consumir
);

CREATE TABLE cotacao_proposta (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  cotacao_item_id     uuid NOT NULL REFERENCES cotacao_item ON DELETE CASCADE,
  fornecedor_id       uuid NOT NULL REFERENCES fornecedor,
  preco_unitario      numeric(18,4) NOT NULL CHECK (preco_unitario >= 0),
  prazo_entrega_dias  integer,
  vencedora           boolean NOT NULL DEFAULT false,
  UNIQUE (cotacao_item_id, fornecedor_id)
);
CREATE UNIQUE INDEX ux_proposta_vencedora ON cotacao_proposta (cotacao_item_id) WHERE vencedora;

CREATE TABLE pedido_compra (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  obra_id        uuid NOT NULL REFERENCES obra,
  fornecedor_id  uuid NOT NULL REFERENCES fornecedor,
  cotacao_id     uuid REFERENCES cotacao,
  numero         integer NOT NULL,
  emissao        date NOT NULL,
  status         text NOT NULL DEFAULT 'emitido' CHECK (status IN ('emitido', 'aprovado', 'recebido', 'cancelado')),
  UNIQUE (tenant_id, numero)
);

CREATE TABLE pedido_compra_item (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  pedido_id           uuid NOT NULL REFERENCES pedido_compra ON DELETE CASCADE,
  cotacao_item_id     uuid REFERENCES cotacao_item,
  item_contratual_id  uuid REFERENCES item_contratual,  -- apropriação no orçamento
  plano_conta_id      uuid NOT NULL REFERENCES plano_contas,
  descricao           text NOT NULL,
  unidade             text NOT NULL,
  quantidade          numeric(18,4) NOT NULL CHECK (quantidade > 0),
  preco_unitario      numeric(18,4) NOT NULL CHECK (preco_unitario >= 0),
  valor               numeric(18,2) GENERATED ALWAYS AS (round(quantidade * preco_unitario, 2)) STORED
);

-- -----------------------------------------------------------------------------
-- FINANCEIRO
-- -----------------------------------------------------------------------------
CREATE TABLE conta_bancaria (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id  uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  descricao  text NOT NULL,
  banco      char(3) NOT NULL,          -- código COMPE
  ativa      boolean NOT NULL DEFAULT true
);

CREATE TABLE titulo (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id         uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  tipo              tipo_titulo NOT NULL,
  fornecedor_id     uuid REFERENCES fornecedor,
  orgao_id          uuid REFERENCES orgao,
  obra_id           uuid REFERENCES obra,            -- NULL = despesa administrativa
  medicao_id        uuid UNIQUE REFERENCES medicao,  -- conta a receber gerada pela medição
  pedido_compra_id  uuid REFERENCES pedido_compra,
  plano_conta_id    uuid NOT NULL REFERENCES plano_contas,
  documento         text,                            -- nº NF / NFS-e
  emissao           date NOT NULL,
  valor_bruto       numeric(18,2) NOT NULL CHECK (valor_bruto > 0),
  status            status_titulo NOT NULL DEFAULT 'aberto',
  CHECK ((tipo = 'receber' AND orgao_id IS NOT NULL AND fornecedor_id IS NULL)
      OR (tipo = 'pagar'   AND fornecedor_id IS NOT NULL AND medicao_id IS NULL))
);

CREATE TABLE titulo_retencao (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  titulo_id   uuid NOT NULL REFERENCES titulo ON DELETE CASCADE,
  tipo        tipo_retencao NOT NULL,
  base        numeric(18,2) NOT NULL,
  aliquota    numeric(7,4) NOT NULL,
  valor       numeric(18,2) NOT NULL,
  UNIQUE (titulo_id, tipo)
);

CREATE TABLE titulo_parcela (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  titulo_id   uuid NOT NULL REFERENCES titulo ON DELETE CASCADE,
  numero      smallint NOT NULL,
  vencimento  date NOT NULL,
  valor       numeric(18,2) NOT NULL CHECK (valor > 0),   -- líquido de retenções
  UNIQUE (titulo_id, numero)
);

CREATE TABLE baixa (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id          uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  parcela_id         uuid NOT NULL REFERENCES titulo_parcela,
  conta_bancaria_id  uuid NOT NULL REFERENCES conta_bancaria,
  data_pagamento     date NOT NULL,
  valor              numeric(18,2) NOT NULL CHECK (valor > 0),
  juros              numeric(18,2) NOT NULL DEFAULT 0,
  multa              numeric(18,2) NOT NULL DEFAULT 0,
  desconto           numeric(18,2) NOT NULL DEFAULT 0
);

CREATE TABLE rateio (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  competencia  date NOT NULL CHECK (extract(day FROM competencia) = 1),  -- 1º dia do mês
  criterio     criterio_rateio NOT NULL,
  status       text NOT NULL DEFAULT 'rascunho' CHECK (status IN ('rascunho', 'aplicado')),
  UNIQUE (tenant_id, competencia)
);

CREATE TABLE rateio_obra (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  rateio_id     uuid NOT NULL REFERENCES rateio ON DELETE CASCADE,
  obra_id       uuid NOT NULL REFERENCES obra,
  base_calculo  numeric(18,2) NOT NULL,
  percentual    numeric(9,6) NOT NULL CHECK (percentual BETWEEN 0 AND 100),
  UNIQUE (rateio_id, obra_id)
);

-- Para onde vai cada real: obra, item da EAP e conta contábil
CREATE TABLE apropriacao (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  titulo_id           uuid NOT NULL REFERENCES titulo ON DELETE CASCADE,
  obra_id             uuid REFERENCES obra,
  item_contratual_id  uuid REFERENCES item_contratual,
  plano_conta_id      uuid NOT NULL REFERENCES plano_contas,
  origem              origem_apropriacao NOT NULL,
  rateio_id           uuid REFERENCES rateio,
  valor               numeric(18,2) NOT NULL,
  CHECK (origem <> 'rateio' OR (rateio_id IS NOT NULL AND obra_id IS NOT NULL))
);
CREATE INDEX ix_apropriacao_obra ON apropriacao (obra_id, item_contratual_id);

-- -----------------------------------------------------------------------------
-- DIÁRIO DE OBRA (RDO)
-- -----------------------------------------------------------------------------
CREATE TABLE rdo (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id          uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  obra_id            uuid NOT NULL REFERENCES obra,
  data               date NOT NULL,
  clima_manha        text CHECK (clima_manha IN ('bom', 'nublado', 'chuva_fraca', 'chuva_forte')),
  clima_tarde        text CHECK (clima_tarde IN ('bom', 'nublado', 'chuva_fraca', 'chuva_forte')),
  praticavel         boolean NOT NULL DEFAULT true,
  responsavel        text NOT NULL,
  status             text NOT NULL DEFAULT 'rascunho' CHECK (status IN ('rascunho', 'fechado', 'assinado')),
  sincronizado_em    timestamptz,               -- preenchido no envio do app offline
  UNIQUE (obra_id, data)
);

CREATE TABLE rdo_efetivo (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  rdo_id         uuid NOT NULL REFERENCES rdo ON DELETE CASCADE,
  funcao         text NOT NULL,
  quantidade     integer NOT NULL CHECK (quantidade > 0),
  proprio        boolean NOT NULL DEFAULT true,
  fornecedor_id  uuid REFERENCES fornecedor     -- empreiteiro, quando terceirizado
);

CREATE TABLE rdo_equipamento (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id         uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  rdo_id            uuid NOT NULL REFERENCES rdo ON DELETE CASCADE,
  equipamento_id    uuid NOT NULL REFERENCES equipamento,
  horas_trabalhadas numeric(5,2) NOT NULL DEFAULT 0,
  horas_paradas     numeric(5,2) NOT NULL DEFAULT 0
);

CREATE TABLE rdo_ocorrencia (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id  uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  rdo_id     uuid NOT NULL REFERENCES rdo ON DELETE CASCADE,
  tipo       text NOT NULL,                     -- servico_executado, acidente, visita_fiscal...
  descricao  text NOT NULL,
  item_contratual_id uuid REFERENCES item_contratual
);

CREATE TABLE rdo_foto (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id  uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  rdo_id     uuid NOT NULL REFERENCES rdo ON DELETE CASCADE,
  s3_key     text NOT NULL,
  legenda    text,
  tirada_em  timestamptz NOT NULL,
  latitude   numeric(9,6),
  longitude  numeric(9,6)
);

-- -----------------------------------------------------------------------------
-- AUDITORIA e OUTBOX DE EVENTOS
-- -----------------------------------------------------------------------------
CREATE TABLE auditoria (
  id           bigserial PRIMARY KEY,
  tenant_id    uuid NOT NULL,
  tabela       text NOT NULL,
  registro_id  uuid NOT NULL,
  acao         char(1) NOT NULL CHECK (acao IN ('I', 'U', 'D')),
  antes        jsonb,
  depois       jsonb,
  usuario      text,
  em           timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_auditoria_registro ON auditoria (tabela, registro_id);

CREATE TABLE outbox (
  id            bigserial PRIMARY KEY,
  tenant_id     uuid NOT NULL DEFAULT app_tenant(),
  agregado      text NOT NULL,
  agregado_id   uuid NOT NULL,
  evento        text NOT NULL,                  -- 'MedicaoAprovada', 'AditivoHomologado'...
  payload       jsonb NOT NULL,
  criado_em     timestamptz NOT NULL DEFAULT now(),
  publicado_em  timestamptz
);
CREATE INDEX ix_outbox_pendente ON outbox (id) WHERE publicado_em IS NULL;

-- =============================================================================
-- FUNÇÕES E TRIGGERS — invariantes críticas
-- =============================================================================

-- Valor de um item segundo a regra do contrato
CREATE FUNCTION fn_valor_item(p_qtd numeric, p_pu numeric, p_criterio criterio_arredondamento)
RETURNS numeric LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_criterio WHEN 'truncar' THEN trunc(p_qtd * p_pu, 2)
                         ELSE round(p_qtd * p_pu, 2) END
$$;

-- Quantidade já medida de um item (medições não canceladas)
CREATE FUNCTION fn_qtd_medida(p_item uuid, p_ignorar_linha uuid DEFAULT NULL)
RETURNS numeric LANGUAGE sql STABLE AS $$
  SELECT coalesce(sum(mi.quantidade), 0)
    FROM medicao_item mi JOIN medicao m ON m.id = mi.medicao_id
   WHERE mi.item_contratual_id = p_item
     AND m.status <> 'cancelada'
     AND mi.id IS DISTINCT FROM p_ignorar_linha
$$;

-- item_revisao: só muda em rascunho; calcula path e valor; não deixa reduzir abaixo do medido
CREATE FUNCTION fn_item_revisao_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_rev    revisao_orcamento%ROWTYPE;
  v_ctr    contrato%ROWTYPE;
  v_pai    item_revisao%ROWTYPE;
  v_medido numeric;
BEGIN
  SELECT * INTO v_rev FROM revisao_orcamento WHERE id = coalesce(NEW.revisao_id, OLD.revisao_id);
  IF v_rev.status <> 'rascunho' THEN
    RAISE EXCEPTION 'Revisão % está "%": itens só podem mudar em rascunho', v_rev.numero, v_rev.status
      USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;

  IF NOT EXISTS (SELECT 1 FROM item_contratual
                  WHERE id = NEW.item_contratual_id AND contrato_id = v_rev.contrato_id) THEN
    RAISE EXCEPTION 'Item contratual não pertence ao contrato da revisão' USING ERRCODE = 'check_violation';
  END IF;

  IF NEW.parent_id IS NULL THEN
    NEW.path := lpad(NEW.ordem::text, 5, '0')::ltree;
  ELSE
    SELECT * INTO v_pai FROM item_revisao WHERE id = NEW.parent_id;
    IF v_pai.tipo <> 'grupo' THEN
      RAISE EXCEPTION 'Item % só pode ficar abaixo de um grupo', NEW.codigo_eap USING ERRCODE = 'check_violation';
    END IF;
    NEW.path := v_pai.path || lpad(NEW.ordem::text, 5, '0');
  END IF;

  IF NEW.tipo = 'servico' THEN
    SELECT * INTO v_ctr FROM contrato WHERE id = v_rev.contrato_id;
    IF NEW.preco_unitario <> round(NEW.preco_unitario, v_ctr.casas_decimais_preco) THEN
      RAISE EXCEPTION 'Preço unitário do item % tem mais de % casas decimais', NEW.codigo_eap, v_ctr.casas_decimais_preco
        USING ERRCODE = 'check_violation';
    END IF;
    NEW.valor_total := fn_valor_item(NEW.quantidade, NEW.preco_unitario, v_ctr.criterio_arredondamento);
    v_medido := fn_qtd_medida(NEW.item_contratual_id);
    IF NEW.quantidade < v_medido THEN
      RAISE EXCEPTION 'Item %: quantidade % é menor que a já medida (%)', NEW.codigo_eap, NEW.quantidade, v_medido
        USING ERRCODE = 'check_violation';
    END IF;
  ELSE
    NEW.valor_total := NULL;   -- grupos são somados na leitura (ltree)
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_item_revisao_guard BEFORE INSERT OR UPDATE OR DELETE ON item_revisao
  FOR EACH ROW EXECUTE FUNCTION fn_item_revisao_guard();

-- revisao_orcamento: revisão vigente/substituída é histórica; ao virar vigente calcula total
-- e, na Rev. 0, exige soma igual ao valor do contrato
CREATE FUNCTION fn_revisao_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_valor_contrato numeric;
  v_forma          forma_acompanhamento;
  v_cod            text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.status <> 'rascunho' THEN
      RAISE EXCEPTION 'Revisão % não pode ser excluída (status %)', OLD.numero, OLD.status USING ERRCODE = 'check_violation';
    END IF;
    RETURN OLD;
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'rascunho' THEN
      RAISE EXCEPTION 'Revisão nasce em rascunho' USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;
  IF OLD.status = 'substituida' THEN
    RAISE EXCEPTION 'Revisão % já foi substituída e é somente leitura', OLD.numero USING ERRCODE = 'check_violation';
  END IF;
  IF OLD.status = 'vigente' AND NEW.status NOT IN ('vigente', 'substituida') THEN
    RAISE EXCEPTION 'Revisão vigente só pode passar a substituída' USING ERRCODE = 'check_violation';
  END IF;
  IF OLD.status = 'rascunho' AND NEW.status = 'vigente' THEN
    SELECT forma_acompanhamento INTO v_forma FROM contrato WHERE id = NEW.contrato_id;
    IF v_forma = 'ple' THEN
      -- todo serviço precisa de agrupador e da quantidade inteira distribuída nas frentes
      SELECT ir.codigo_eap INTO v_cod
        FROM item_revisao ir
       WHERE ir.revisao_id = NEW.id AND ir.tipo = 'servico'
         AND (ir.agrupador_evento_id IS NULL
              OR ir.quantidade <> (SELECT coalesce(sum(f.quantidade), 0) FROM item_frente f
                                    WHERE f.item_revisao_id = ir.id))
       ORDER BY ir.path LIMIT 1;
      IF v_cod IS NOT NULL THEN
        RAISE EXCEPTION 'PLE: item % sem agrupador ou com quantidade não distribuída nas frentes', v_cod
          USING ERRCODE = 'check_violation';
      END IF;
      PERFORM fn_recalcular_eventos(NEW.id);
    END IF;
    SELECT coalesce(sum(valor_total), 0) INTO NEW.valor_total
      FROM item_revisao WHERE revisao_id = NEW.id AND tipo = 'servico';
    NEW.data_vigencia := coalesce(NEW.data_vigencia, current_date);
    IF NEW.numero = 0 THEN
      SELECT valor_inicial INTO v_valor_contrato FROM contrato WHERE id = NEW.contrato_id;
      IF NEW.valor_total <> v_valor_contrato THEN
        RAISE EXCEPTION 'Soma da planilha (%) difere do valor do contrato (%)', NEW.valor_total, v_valor_contrato
          USING ERRCODE = 'check_violation';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_revisao_guard BEFORE INSERT OR UPDATE OR DELETE ON revisao_orcamento
  FOR EACH ROW EXECUTE FUNCTION fn_revisao_guard();

-- medicao: nasce sobre a revisão vigente; aprovada é imutável; consolida valor ao enviar/aprovar
CREATE FUNCTION fn_medicao_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NOT EXISTS (SELECT 1 FROM revisao_orcamento WHERE id = NEW.revisao_id AND status = 'vigente') THEN
      RAISE EXCEPTION 'Medição deve ser aberta sobre a revisão vigente' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.status <> 'rascunho' THEN
      RAISE EXCEPTION 'Medição nasce em rascunho' USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;
  IF TG_OP = 'DELETE' THEN
    IF OLD.status <> 'rascunho' THEN
      RAISE EXCEPTION 'Medição nº % não pode ser excluída (status %)', OLD.numero, OLD.status USING ERRCODE = 'check_violation';
    END IF;
    RETURN OLD;
  END IF;
  IF OLD.status IN ('aprovada', 'cancelada') THEN
    RAISE EXCEPTION 'Medição nº % está "%" e é imutável; corrija na próxima medição', OLD.numero, OLD.status
      USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status IN ('enviada', 'aprovada') THEN
    SELECT coalesce(sum(valor), 0) INTO NEW.valor_bruto FROM medicao_item WHERE medicao_id = NEW.id;
    IF NEW.status = 'enviada' THEN NEW.enviada_em := coalesce(NEW.enviada_em, now()); END IF;
    IF NEW.status = 'aprovada' THEN NEW.aprovada_em := coalesce(NEW.aprovada_em, now()); END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_medicao_guard BEFORE INSERT OR UPDATE OR DELETE ON medicao
  FOR EACH ROW EXECUTE FUNCTION fn_medicao_guard();

-- medicao_item: só em rascunho; calcula valor; acumulado entre 0 e o contratado
CREATE FUNCTION fn_medicao_item_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_med    medicao%ROWTYPE;
  v_item   item_revisao%ROWTYPE;
  v_crit   criterio_arredondamento;
  v_forma  forma_acompanhamento;
  v_qtd_ev numeric;
  v_acum   numeric;
BEGIN
  SELECT * INTO v_med FROM medicao WHERE id = coalesce(NEW.medicao_id, OLD.medicao_id);
  IF v_med.status <> 'rascunho' THEN
    RAISE EXCEPTION 'Medição nº % está "%": itens não podem ser alterados', v_med.numero, v_med.status
      USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;

  SELECT * INTO v_item FROM item_revisao
   WHERE revisao_id = v_med.revisao_id AND item_contratual_id = NEW.item_contratual_id;
  IF NOT FOUND OR v_item.tipo <> 'servico' THEN
    RAISE EXCEPTION 'Item não é serviço da revisão da medição' USING ERRCODE = 'check_violation';
  END IF;

  SELECT criterio_arredondamento, forma_acompanhamento INTO v_crit, v_forma
    FROM contrato WHERE id = v_med.contrato_id;
  IF NEW.origem <> v_forma THEN
    RAISE EXCEPTION 'Contrato acompanhado por %: lançamento por % não é permitido', upper(v_forma::text), upper(NEW.origem::text)
      USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.origem = 'ple' THEN
    -- quantidade e valor vêm das frentes dos eventos concluídos nesta medição
    SELECT coalesce(sum(f.quantidade), 0),
           coalesce(sum(fn_valor_item(f.quantidade, v_item.preco_unitario, v_crit)), 0)
      INTO v_qtd_ev, NEW.valor
      FROM medicao_evento me
      JOIN evento e      ON e.id = me.evento_id
      JOIN item_frente f ON f.frente_id = e.frente_id AND f.item_revisao_id = v_item.id
     WHERE me.medicao_id = NEW.medicao_id AND e.agrupador_id = v_item.agrupador_evento_id;
    IF NEW.quantidade <> v_qtd_ev THEN
      RAISE EXCEPTION 'Item %: no PLE a quantidade é a soma das frentes concluídas (%)', v_item.codigo_eap, v_qtd_ev
        USING ERRCODE = 'check_violation';
    END IF;
  ELSE
    NEW.valor := fn_valor_item(NEW.quantidade, v_item.preco_unitario, v_crit);
  END IF;

  v_acum := fn_qtd_medida(NEW.item_contratual_id, NEW.id) + NEW.quantidade;
  IF v_acum > v_item.quantidade THEN
    RAISE EXCEPTION 'Item %: acumulado medido (%) ultrapassa o contratado (%)', v_item.codigo_eap, v_acum, v_item.quantidade
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_acum < 0 THEN
    RAISE EXCEPTION 'Item %: acumulado medido ficaria negativo (%)', v_item.codigo_eap, v_acum
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_medicao_item_guard BEFORE INSERT OR UPDATE OR DELETE ON medicao_item
  FOR EACH ROW EXECUTE FUNCTION fn_medicao_item_guard();

-- aditivo_item: só em rascunho; PU de item existente vem da revisão base;
-- supressão não pode ir abaixo do já medido; calcula valor_delta
CREATE FUNCTION fn_aditivo_item_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_ad    aditivo%ROWTYPE;
  v_ctr   contrato%ROWTYPE;
  v_base  item_revisao%ROWTYPE;
BEGIN
  SELECT * INTO v_ad FROM aditivo WHERE id = coalesce(NEW.aditivo_id, OLD.aditivo_id);
  IF v_ad.status <> 'rascunho' THEN
    RAISE EXCEPTION 'Aditivo nº % está "%": itens não podem ser alterados', v_ad.numero, v_ad.status
      USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  SELECT * INTO v_ctr FROM contrato WHERE id = v_ad.contrato_id;

  IF NEW.operacao = 'inclusao' THEN
    IF EXISTS (SELECT 1 FROM item_revisao WHERE revisao_id = v_ad.revisao_base_id
                                            AND item_contratual_id = NEW.item_contratual_id) THEN
      RAISE EXCEPTION 'Inclusão deve criar item novo' USING ERRCODE = 'check_violation';
    END IF;
  ELSE
    SELECT * INTO v_base FROM item_revisao
     WHERE revisao_id = v_ad.revisao_base_id AND item_contratual_id = NEW.item_contratual_id;
    IF NOT FOUND OR v_base.tipo <> 'servico' THEN
      RAISE EXCEPTION 'Item não é serviço da revisão base do aditivo' USING ERRCODE = 'check_violation';
    END IF;
    NEW.preco_unitario := v_base.preco_unitario;        -- mesmas condições contratuais
    IF v_base.quantidade + NEW.quantidade_delta < fn_qtd_medida(NEW.item_contratual_id) THEN
      RAISE EXCEPTION 'Item %: supressão deixa quantidade abaixo do já medido (%)',
        v_base.codigo_eap, fn_qtd_medida(NEW.item_contratual_id) USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  NEW.valor_delta := fn_valor_item(NEW.quantidade_delta, NEW.preco_unitario, v_ctr.criterio_arredondamento);
  RETURN NEW;
END $$;
CREATE TRIGGER trg_aditivo_item_guard BEFORE INSERT OR UPDATE OR DELETE ON aditivo_item
  FOR EACH ROW EXECUTE FUNCTION fn_aditivo_item_guard();

-- aditivo homologado é imutável
CREATE FUNCTION fn_aditivo_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.status IN ('homologado', 'rejeitado') THEN
    RAISE EXCEPTION 'Aditivo nº % está "%" e é imutável', OLD.numero, OLD.status USING ERRCODE = 'check_violation';
  END IF;
  RETURN coalesce(NEW, OLD);
END $$;
CREATE TRIGGER trg_aditivo_guard BEFORE UPDATE OR DELETE ON aditivo
  FOR EACH ROW EXECUTE FUNCTION fn_aditivo_guard();

-- PLE: valor de cada evento = Σ round(qtd na frente × PU) dos serviços do agrupador
CREATE FUNCTION fn_recalcular_eventos(p_revisao uuid) RETURNS void LANGUAGE sql AS $$
  INSERT INTO evento (tenant_id, revisao_id, agrupador_id, frente_id, valor)
  SELECT ir.tenant_id, ir.revisao_id, ir.agrupador_evento_id, f.frente_id,
         sum(fn_valor_item(f.quantidade, ir.preco_unitario, c.criterio_arredondamento))
    FROM item_revisao ir
    JOIN item_frente f       ON f.item_revisao_id = ir.id
    JOIN revisao_orcamento r ON r.id = ir.revisao_id
    JOIN contrato c          ON c.id = r.contrato_id
   WHERE ir.revisao_id = p_revisao AND ir.tipo = 'servico'
   GROUP BY ir.tenant_id, ir.revisao_id, ir.agrupador_evento_id, f.frente_id
  ON CONFLICT (revisao_id, agrupador_id, frente_id) DO UPDATE SET valor = EXCLUDED.valor;
$$;

-- item_frente só muda com a revisão em rascunho, e só em serviços
CREATE FUNCTION fn_item_frente_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_status status_revisao; v_tipo tipo_item;
BEGIN
  SELECT r.status, ir.tipo INTO v_status, v_tipo
    FROM item_revisao ir JOIN revisao_orcamento r ON r.id = ir.revisao_id
   WHERE ir.id = coalesce(NEW.item_revisao_id, OLD.item_revisao_id);
  IF v_status <> 'rascunho' THEN
    RAISE EXCEPTION 'Distribuição por frente só muda com a revisão em rascunho' USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP <> 'DELETE' AND v_tipo <> 'servico' THEN
    RAISE EXCEPTION 'Só serviços são distribuídos em frentes' USING ERRCODE = 'check_violation';
  END IF;
  RETURN coalesce(NEW, OLD);
END $$;
CREATE TRIGGER trg_item_frente_guard BEFORE INSERT OR UPDATE OR DELETE ON item_frente
  FOR EACH ROW EXECUTE FUNCTION fn_item_frente_guard();

-- evento: valor e composição só mudam em rascunho; o período previsto pode ser reprogramado
CREATE FUNCTION fn_evento_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_status status_revisao;
BEGIN
  SELECT status INTO v_status FROM revisao_orcamento WHERE id = coalesce(NEW.revisao_id, OLD.revisao_id);
  IF v_status <> 'rascunho' AND (TG_OP <> 'UPDATE'
       OR (NEW.valor, NEW.agrupador_id, NEW.frente_id) IS DISTINCT FROM (OLD.valor, OLD.agrupador_id, OLD.frente_id)) THEN
    RAISE EXCEPTION 'Eventos de revisão % só têm o período previsto alterável', v_status USING ERRCODE = 'check_violation';
  END IF;
  RETURN coalesce(NEW, OLD);
END $$;
CREATE TRIGGER trg_evento_guard BEFORE INSERT OR UPDATE OR DELETE ON evento
  FOR EACH ROW EXECUTE FUNCTION fn_evento_guard();

-- medicao_evento: só em medição em rascunho de contrato PLE; evento da revisão da medição;
-- o mesmo evento (agrupador × frente) não é medido duas vezes
CREATE FUNCTION fn_medicao_evento_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_med   medicao%ROWTYPE;
  v_ev    evento%ROWTYPE;
  v_forma forma_acompanhamento;
BEGIN
  SELECT * INTO v_med FROM medicao WHERE id = coalesce(NEW.medicao_id, OLD.medicao_id);
  IF v_med.status <> 'rascunho' THEN
    RAISE EXCEPTION 'Medição nº % está "%": eventos não podem ser alterados', v_med.numero, v_med.status
      USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  SELECT forma_acompanhamento INTO v_forma FROM contrato WHERE id = v_med.contrato_id;
  IF v_forma <> 'ple' THEN
    RAISE EXCEPTION 'Contrato acompanhado por BM não mede eventos' USING ERRCODE = 'check_violation';
  END IF;
  SELECT * INTO v_ev FROM evento WHERE id = NEW.evento_id;
  IF v_ev.revisao_id <> v_med.revisao_id THEN
    RAISE EXCEPTION 'Evento não pertence à revisão da medição' USING ERRCODE = 'check_violation';
  END IF;
  IF EXISTS (SELECT 1 FROM medicao_evento me
               JOIN evento e  ON e.id = me.evento_id
               JOIN medicao m ON m.id = me.medicao_id
              WHERE m.contrato_id = v_med.contrato_id AND m.status <> 'cancelada'
                AND e.agrupador_id = v_ev.agrupador_id AND e.frente_id = v_ev.frente_id
                AND me.id <> NEW.id) THEN
    RAISE EXCEPTION 'Evento já medido anteriormente' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_medicao_evento_guard BEFORE INSERT OR UPDATE OR DELETE ON medicao_evento
  FOR EACH ROW EXECUTE FUNCTION fn_medicao_evento_guard();

-- Ao marcar ou desmarcar eventos, regenera as linhas do boletim (origem PLE),
-- para que BM, saldo, financeiro e RRE usem um único caminho
CREATE FUNCTION fn_aplicar_eventos() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_medicao uuid := coalesce(NEW.medicao_id, OLD.medicao_id);
BEGIN
  DELETE FROM medicao_item WHERE medicao_id = v_medicao AND origem = 'ple';
  INSERT INTO medicao_item (tenant_id, medicao_id, item_contratual_id, quantidade, valor, origem)
  SELECT ir.tenant_id, v_medicao, ir.item_contratual_id, sum(f.quantidade), 0, 'ple'
    FROM medicao_evento me
    JOIN evento e        ON e.id = me.evento_id
    JOIN item_revisao ir ON ir.revisao_id = e.revisao_id AND ir.agrupador_evento_id = e.agrupador_id
                        AND ir.tipo = 'servico'
    JOIN item_frente f   ON f.item_revisao_id = ir.id AND f.frente_id = e.frente_id
   WHERE me.medicao_id = v_medicao
   GROUP BY ir.tenant_id, ir.item_contratual_id;
  RETURN NULL;
END $$;
CREATE TRIGGER trg_aplicar_eventos AFTER INSERT OR DELETE ON medicao_evento
  FOR EACH ROW EXECUTE FUNCTION fn_aplicar_eventos();

-- Auditoria genérica
CREATE FUNCTION fn_auditar() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auditoria (tenant_id, tabela, registro_id, acao, antes, depois, usuario)
  VALUES (coalesce(NEW.tenant_id, OLD.tenant_id), TG_TABLE_NAME, coalesce(NEW.id, OLD.id), left(TG_OP, 1),
          CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END,
          CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END,
          current_setting('app.usuario', true));
  RETURN NULL;
END $$;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['contrato', 'revisao_orcamento', 'medicao', 'medicao_item', 'medicao_evento',
                           'medicao_glosa', 'aditivo', 'aditivo_item', 'titulo', 'titulo_parcela', 'baixa',
                           'rateio'] LOOP
    EXECUTE format('CREATE TRIGGER trg_auditoria AFTER INSERT OR UPDATE OR DELETE ON %I
                    FOR EACH ROW EXECUTE FUNCTION fn_auditar()', t);
  END LOOP;
END $$;

-- =============================================================================
-- CONSULTAS DE DOMÍNIO
-- =============================================================================

-- Boletim de Medição: contratado | anterior | atual | acumulado | saldo, com subtotais por grupo
CREATE FUNCTION fn_boletim_medicao(p_medicao uuid)
RETURNS TABLE (
  codigo_eap text, descricao text, tipo tipo_item, nivel int, unidade text,
  qtd_contratada numeric, preco_unitario numeric, valor_contratado numeric,
  qtd_anterior numeric, qtd_atual numeric, qtd_acumulada numeric, qtd_saldo numeric,
  valor_anterior numeric, valor_atual numeric, valor_acumulado numeric, valor_saldo numeric,
  perc_acumulado numeric)
LANGUAGE sql STABLE AS $$
  WITH m AS (SELECT * FROM medicao WHERE id = p_medicao),
  hist AS (
    SELECT mi.item_contratual_id,
           sum(mi.quantidade) FILTER (WHERE md.numero < m.numero) AS qa,
           sum(mi.valor)      FILTER (WHERE md.numero < m.numero) AS va,
           sum(mi.quantidade) FILTER (WHERE md.id = m.id)         AS qt,
           sum(mi.valor)      FILTER (WHERE md.id = m.id)         AS vt
      FROM medicao_item mi
      JOIN medicao md ON md.id = mi.medicao_id
      JOIN m ON md.contrato_id = m.contrato_id
     WHERE md.status <> 'cancelada' AND md.numero <= m.numero
     GROUP BY mi.item_contratual_id),
  itens AS (SELECT ir.* FROM item_revisao ir JOIN m ON ir.revisao_id = m.revisao_id),
  folhas AS (
    SELECT i.path, i.valor_total,
           coalesce(h.qa, 0) qa, coalesce(h.va, 0) va, coalesce(h.qt, 0) qt, coalesce(h.vt, 0) vt
      FROM itens i LEFT JOIN hist h USING (item_contratual_id)
     WHERE i.tipo = 'servico')
  SELECT i.codigo_eap, i.descricao, i.tipo, nlevel(i.path), i.unidade,
         CASE WHEN i.tipo = 'servico' THEN i.quantidade END,
         CASE WHEN i.tipo = 'servico' THEN i.preco_unitario END,
         coalesce(sum(f.valor_total), 0),
         CASE WHEN i.tipo = 'servico' THEN sum(f.qa) END,
         CASE WHEN i.tipo = 'servico' THEN sum(f.qt) END,
         CASE WHEN i.tipo = 'servico' THEN sum(f.qa + f.qt) END,
         CASE WHEN i.tipo = 'servico' THEN i.quantidade - sum(f.qa + f.qt) END,
         coalesce(sum(f.va), 0), coalesce(sum(f.vt), 0), coalesce(sum(f.va + f.vt), 0),
         coalesce(sum(f.valor_total), 0) - coalesce(sum(f.va + f.vt), 0),
         round(100 * sum(f.va + f.vt) / nullif(sum(f.valor_total), 0), 2)
    FROM itens i
    LEFT JOIN folhas f ON f.path <@ i.path
   GROUP BY i.id, i.codigo_eap, i.descricao, i.tipo, i.path, i.unidade, i.quantidade, i.preco_unitario
   ORDER BY i.path
$$;

-- Limites do art. 125: acréscimos e supressões somados SEPARADAMENTE, sem compensação,
-- sobre o valor inicial (MVP: sem reajuste; "valor inicial atualizado" entra com o módulo de reajuste).
-- p_simular inclui um aditivo ainda em rascunho na conta.
CREATE FUNCTION fn_limites_aditivos(p_contrato uuid, p_simular uuid DEFAULT NULL)
RETURNS TABLE (
  valor_inicial numeric, acrescimos numeric, supressoes numeric, restabelecimentos numeric,
  perc_acrescimos numeric, perc_supressoes numeric, limite_acrescimo numeric, limite_supressao numeric,
  situacao text)
LANGUAGE sql STABLE AS $$
  WITH c AS (SELECT * FROM contrato WHERE id = p_contrato),
  s AS (
    SELECT coalesce(sum(ai.valor_delta) FILTER (WHERE ai.operacao IN ('acrescimo', 'inclusao')), 0)  AS acr,
           coalesce(-sum(ai.valor_delta) FILTER (WHERE ai.operacao = 'supressao'), 0)            AS sup,
           coalesce(sum(ai.valor_delta) FILTER (WHERE ai.operacao = 'restabelecimento'), 0)      AS rest
      FROM aditivo a JOIN aditivo_item ai ON ai.aditivo_id = a.id
     WHERE a.contrato_id = p_contrato AND (a.status = 'homologado' OR a.id = p_simular))
  SELECT c.valor_inicial, s.acr, s.sup, s.rest,
         round(100 * s.acr / c.valor_inicial, 2), round(100 * s.sup / c.valor_inicial, 2),
         CASE WHEN c.reforma THEN 50 ELSE 25 END, 25,
         CASE WHEN 100 * s.acr / c.valor_inicial > CASE WHEN c.reforma THEN 50 ELSE 25 END
                OR 100 * s.sup / c.valor_inicial > 25 THEN 'EXCEDE LIMITE LEGAL'
              WHEN 100 * s.acr / c.valor_inicial > 0.9 * CASE WHEN c.reforma THEN 50 ELSE 25 END
                OR 100 * s.sup / c.valor_inicial > 22.5 THEN 'ATENÇÃO: acima de 90% do limite'
              ELSE 'OK' END
    FROM c, s
$$;

-- Situação atual do contrato: valor, prazo e vigência após aditivos; executado e saldo
CREATE VIEW vw_contrato_situacao WITH (security_invoker = true) AS
SELECT c.id AS contrato_id, c.numero, c.processo_licitatorio,
       c.valor_inicial,
       rv.valor_total                                            AS valor_atual,
       rv.numero                                                 AS revisao_vigente,
       c.prazo_execucao_dias + coalesce(ad.dias, 0)              AS prazo_atual_dias,
       coalesce(ad.vigencia, c.vigencia_fim)                     AS vigencia_atual,
       coalesce(med.aprovado, 0)                                 AS medido_aprovado,
       rv.valor_total - coalesce(med.aprovado, 0)                AS saldo_contratual,
       round(100 * coalesce(med.aprovado, 0) / rv.valor_total, 2) AS perc_executado
  FROM contrato c
  JOIN revisao_orcamento rv ON rv.contrato_id = c.id AND rv.status = 'vigente'
  LEFT JOIN LATERAL (
    SELECT sum(a.dias_prazo_execucao) AS dias,
           (array_agg(a.nova_vigencia_fim ORDER BY a.numero DESC)
              FILTER (WHERE a.nova_vigencia_fim IS NOT NULL))[1] AS vigencia
      FROM aditivo a WHERE a.contrato_id = c.id AND a.status = 'homologado') ad ON true
  LEFT JOIN LATERAL (
    SELECT sum(m.valor_bruto) AS aprovado
      FROM medicao m WHERE m.contrato_id = c.id AND m.status = 'aprovada') med ON true;

-- RRE: cada medição dividida em repasse, contrapartida e outros (contratos com repasse).
-- Itens RA rateiam pela proporção da contrapartida no total RA do contrato.
CREATE VIEW vw_rre_medicao WITH (security_invoker = true) AS
WITH linhas AS (
  SELECT m.id AS medicao_id, m.contrato_id, m.numero, m.status, ir.fonte_recurso, mi.valor
    FROM medicao m
    JOIN medicao_item mi ON mi.medicao_id = m.id
    JOIN item_revisao ir ON ir.revisao_id = m.revisao_id AND ir.item_contratual_id = mi.item_contratual_id),
rateio AS (
  SELECT c.id AS contrato_id,
         (c.valor_inicial - c.valor_repasse
            - coalesce(sum(ir.valor_total) FILTER (WHERE ir.fonte_recurso IN ('CP', 'OU')), 0))
         / nullif(sum(ir.valor_total) FILTER (WHERE ir.fonte_recurso = 'RA'), 0) AS perc_cp_ra
    FROM contrato c
    JOIN revisao_orcamento r ON r.contrato_id = c.id AND r.numero = 0
    JOIN item_revisao ir     ON ir.revisao_id = r.id AND ir.tipo = 'servico'
   WHERE c.valor_repasse IS NOT NULL
   GROUP BY c.id, c.valor_inicial, c.valor_repasse),
soma AS (
  SELECT l.medicao_id, l.contrato_id, l.numero, l.status,
         sum(l.valor) AS investimento,
         round(coalesce(sum(l.valor) FILTER (WHERE l.fonte_recurso = 'RA'), 0) * r.perc_cp_ra, 2)
           + coalesce(sum(l.valor) FILTER (WHERE l.fonte_recurso = 'CP'), 0) AS contrapartida,
         coalesce(sum(l.valor) FILTER (WHERE l.fonte_recurso = 'OU'), 0) AS outros
    FROM linhas l JOIN rateio r USING (contrato_id)
   GROUP BY l.medicao_id, l.contrato_id, l.numero, l.status, r.perc_cp_ra)
SELECT medicao_id, contrato_id, numero, status, investimento,
       investimento - contrapartida - outros AS repasse, contrapartida, outros
  FROM soma;

-- Fluxo de caixa mensal: previsto (parcelas por vencimento) x realizado (baixas por pagamento)
CREATE VIEW vw_fluxo_caixa WITH (security_invoker = true) AS
WITH prev AS (
  SELECT date_trunc('month', p.vencimento)::date AS mes,
         sum(p.valor) FILTER (WHERE t.tipo = 'receber') AS entradas_previstas,
         sum(p.valor) FILTER (WHERE t.tipo = 'pagar')   AS saidas_previstas
    FROM titulo_parcela p JOIN titulo t ON t.id = p.titulo_id
   WHERE t.status <> 'cancelado'
   GROUP BY 1),
real AS (
  SELECT date_trunc('month', b.data_pagamento)::date AS mes,
         sum(b.valor + b.juros + b.multa - b.desconto) FILTER (WHERE t.tipo = 'receber') AS entradas_realizadas,
         sum(b.valor + b.juros + b.multa - b.desconto) FILTER (WHERE t.tipo = 'pagar')   AS saidas_realizadas
    FROM baixa b JOIN titulo_parcela p ON p.id = b.parcela_id JOIN titulo t ON t.id = p.titulo_id
   GROUP BY 1)
SELECT mes,
       coalesce(entradas_previstas, 0)  AS entradas_previstas,
       coalesce(saidas_previstas, 0)    AS saidas_previstas,
       coalesce(entradas_previstas, 0) - coalesce(saidas_previstas, 0) AS saldo_previsto,
       coalesce(entradas_realizadas, 0) AS entradas_realizadas,
       coalesce(saidas_realizadas, 0)   AS saidas_realizadas,
       coalesce(entradas_realizadas, 0) - coalesce(saidas_realizadas, 0) AS saldo_realizado
  FROM prev FULL JOIN real USING (mes)
 ORDER BY mes;

-- Custo apropriado x custo orçado (PU sem BDI) por item da EAP
CREATE VIEW vw_custo_item WITH (security_invoker = true) AS
SELECT c.id AS contrato_id, ir.codigo_eap, ir.descricao,
       round(ir.valor_total / (1 + coalesce(ir.bdi_percentual, c.bdi_percentual) / 100), 2) AS custo_orcado_sem_bdi,
       coalesce(sum(ap.valor), 0)                              AS custo_apropriado,
       round(100 * coalesce(sum(ap.valor), 0)
             / nullif(ir.valor_total / (1 + coalesce(ir.bdi_percentual, c.bdi_percentual) / 100), 0), 2) AS perc_consumido
  FROM contrato c
  JOIN revisao_orcamento rv ON rv.contrato_id = c.id AND rv.status = 'vigente'
  JOIN item_revisao ir ON ir.revisao_id = rv.id AND ir.tipo = 'servico'
  LEFT JOIN apropriacao ap ON ap.item_contratual_id = ir.item_contratual_id
 GROUP BY c.id, c.bdi_percentual, ir.bdi_percentual, ir.codigo_eap, ir.descricao, ir.valor_total, ir.path
 ORDER BY c.id, ir.path;

-- =============================================================================
-- ROW-LEVEL SECURITY: toda tabela com tenant_id só enxerga o tenant da sessão
-- (o dono das tabelas ignora RLS; a aplicação conecta com um papel sem BYPASSRLS)
-- =============================================================================
DO $$
DECLARE t text;
BEGIN
  FOR t IN SELECT table_name FROM information_schema.columns
            WHERE table_schema = 'public' AND column_name = 'tenant_id'
              AND table_name NOT IN ('base_referencia', 'preco_referencia')
              AND table_name IN (SELECT table_name FROM information_schema.tables
                                  WHERE table_schema = 'public' AND table_type = 'BASE TABLE') LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY isolamento_tenant ON %I USING (tenant_id = app_tenant())
                    WITH CHECK (tenant_id = app_tenant())', t);
  END LOOP;
  -- referências públicas (tenant_id NULL) são lidas por todos e gravadas só pela plataforma
  FOREACH t IN ARRAY ARRAY['base_referencia', 'preco_referencia'] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY leitura ON %I FOR SELECT USING (tenant_id IS NULL OR tenant_id = app_tenant())', t);
    EXECUTE format('CREATE POLICY escrita_propria ON %I FOR ALL USING (tenant_id = app_tenant())
                    WITH CHECK (tenant_id = app_tenant())', t);
  END LOOP;
END $$;

COMMIT;
