-- =============================================================================
-- Prumo · migração 0006 · configuração do município, registro de IA, publicação e denúncia
--
-- 1. config_municipio: o que a lei remete ao município ou ao contrato. Nenhuma coluna tem
--    valor padrão. Regra que precisa de uma configuração ausente para, com erro; não assume.
-- 2. Quem atesta a medição passa a depender da configuração: comissão de medição, se o
--    município exigir; senão o gestor do contrato.
-- 3. ia_decisao: toda proposta de IA fica registrada, com modelo, versão e desfecho.
--    Quem decide é pessoa, e nenhuma tabela de negócio aponta para este registro.
-- 4. publicacao (PNCP, tribunal de contas, portal) e denuncia.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Configuração do município
-- -----------------------------------------------------------------------------
CREATE TABLE config_municipio (
  tenant_id                          uuid PRIMARY KEY REFERENCES tenant,
  -- medição
  comissao_medicao_exigida           boolean,
  -- aditivo
  parecer_aditivo_exigido            boolean,
  aditivo_atencao_pct                numeric(5,2) CHECK (aditivo_atencao_pct BETWEEN 0 AND 100),
  -- Boletim de Execução
  boletim_evidencias_para_concluido  smallint CHECK (boletim_evidencias_para_concluido >= 0),
  boletim_periodicidade_dias         smallint CHECK (boletim_periodicidade_dias > 0),
  -- prazos de processo: só para a previsão de recebimento, nunca para aprovar ou bloquear
  prazo_envio_medicao_dias           smallint CHECK (prazo_envio_medicao_dias >= 0),
  prazo_analise_fiscal_dias          smallint CHECK (prazo_analise_fiscal_dias >= 0),
  prazo_comissao_dias                smallint CHECK (prazo_comissao_dias >= 0),
  prazo_atesto_liquidacao_dias       smallint CHECK (prazo_atesto_liquidacao_dias >= 0),
  prazo_pagamento_dias               smallint CHECK (prazo_pagamento_dias >= 0),
  prazos_em_dias_uteis               boolean,
  fechamento_medicao                 text CHECK (fechamento_medicao IN ('ultimo_dia_do_mes')),
  -- limiares da previsão
  previsao_avanco_minimo_pct         smallint CHECK (previsao_avanco_minimo_pct BETWEEN 1 AND 99),
  previsao_eventos_minimos           smallint CHECK (previsao_eventos_minimos >= 1),
  previsao_fator_minimo              numeric(5,2) CHECK (previsao_fator_minimo > 0),
  previsao_fator_maximo              numeric(5,2),
  -- fiscalização
  prazo_resposta_notificacao_dias    smallint CHECK (prazo_resposta_notificacao_dias > 0),
  atualizado_em                      timestamptz NOT NULL DEFAULT now(),
  CHECK (previsao_fator_maximo >= previsao_fator_minimo)
);
ALTER TABLE config_municipio ENABLE ROW LEVEL SECURITY;
CREATE POLICY isolamento_tenant ON config_municipio USING (tenant_id = app_tenant()) WITH CHECK (tenant_id = app_tenant());
GRANT SELECT, INSERT, UPDATE ON config_municipio TO app_rw;

CREATE FUNCTION fn_config_municipio_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'A configuração do município não se apaga' USING ERRCODE = 'check_violation';
  END IF;
  NEW.atualizado_em := now();
  RETURN NEW;
END $$;
CREATE TRIGGER trg_config_municipio_guard BEFORE UPDATE OR DELETE ON config_municipio
  FOR EACH ROW EXECUTE FUNCTION fn_config_municipio_guard();

-- auditoria.registro_id é o id da linha; aqui a chave é o tenant.
CREATE FUNCTION fn_auditar_config() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auditoria (tenant_id, tabela, registro_id, acao, antes, depois, usuario)
  VALUES (NEW.tenant_id, TG_TABLE_NAME, NEW.tenant_id, left(TG_OP, 1),
          CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END, to_jsonb(NEW),
          current_setting('app.usuario', true));
  RETURN NULL;
END $$;
CREATE TRIGGER trg_auditoria AFTER INSERT OR UPDATE ON config_municipio
  FOR EACH ROW EXECUTE FUNCTION fn_auditar_config();

-- O município exige comissão de medição? Sem resposta configurada, é erro: o banco não chuta.
CREATE FUNCTION fn_comissao_medicao_exigida() RETURNS boolean LANGUAGE plpgsql STABLE AS $$
DECLARE v boolean;
BEGIN
  SELECT comissao_medicao_exigida INTO v FROM config_municipio WHERE tenant_id = app_tenant();
  IF v IS NULL THEN
    RAISE EXCEPTION 'Configuração do município ausente: se a comissão de medição é exigida' USING ERRCODE = 'check_violation';
  END IF;
  RETURN v;
END $$;

-- -----------------------------------------------------------------------------
-- 2. Etapa da medição: quem atesta vem da configuração; condições em função à parte
-- -----------------------------------------------------------------------------
-- O que cada ação exige da medição, além de quem pode. Fica separada do gatilho da etapa
-- porque a 0008 acrescenta aqui a conferência contra o Boletim de Execução.
CREATE FUNCTION fn_medicao_pronta_para(p_medicao uuid, p_acao acao_medicao) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_acao = 'aprovar_fiscal' AND EXISTS (SELECT 1 FROM medicao_glosa WHERE medicao_id = p_medicao) THEN
    RAISE EXCEPTION 'Medição com glosa por quantidade não é aprovada: devolva para a empresa corrigir a quantidade'
      USING ERRCODE = 'check_violation';
  END IF;
  IF p_acao = 'registrar_liquidacao' AND NOT EXISTS (
       SELECT 1 FROM execucao_financeira_ref WHERE medicao_id = p_medicao AND tipo = 'liquidacao') THEN
    RAISE EXCEPTION 'Sem a referência da liquidação desta medição não há o que registrar' USING ERRCODE = 'check_violation';
  END IF;
  IF p_acao = 'registrar_pagamento' AND NOT EXISTS (
       SELECT 1 FROM execucao_financeira_ref WHERE medicao_id = p_medicao AND tipo = 'pagamento') THEN
    RAISE EXCEPTION 'Sem a referência do pagamento desta medição não há o que registrar' USING ERRCODE = 'check_violation';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION fn_medicao_etapa() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_med      medicao%ROWTYPE;
  v_usuario  uuid := app_usuario();
  v_hoje     date := current_date;
  v_pode     boolean;
BEGIN
  IF v_usuario IS NULL THEN
    RAISE EXCEPTION 'A sessão não diz quem está agindo: a medição não muda de situação' USING ERRCODE = 'check_violation';
  END IF;
  SELECT * INTO v_med FROM medicao WHERE id = NEW.medicao_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Medição não encontrada' USING ERRCODE = 'check_violation';
  END IF;
  NEW.usuario_id := v_usuario;
  NEW.de := v_med.status;
  NEW.para := fn_transicao_medicao(v_med.status, NEW.acao);
  NEW.em := now();
  IF NEW.para IS NULL THEN
    RAISE EXCEPTION 'Medição nº % em "%" não aceita a ação "%"', v_med.numero, v_med.status, NEW.acao
      USING ERRCODE = 'check_violation';
  END IF;

  -- quem pode: a empresa declara, o fiscal confere, outra pessoa atesta
  v_pode := CASE
    WHEN NEW.acao IN ('enviar', 'cancelar') THEN fn_da_contratada(v_usuario, v_med.contrato_id, v_hoje)
    WHEN NEW.acao IN ('iniciar_analise', 'devolver', 'aprovar_fiscal') THEN fn_fiscal_do_contrato(v_usuario, v_med.contrato_id, v_hoje)
    WHEN NEW.acao = 'atestar' THEN
      fn_designado(v_usuario, v_med.contrato_id,
                   ARRAY[CASE WHEN fn_comissao_medicao_exigida() THEN 'comissao_medicao' ELSE 'gestor_contrato' END]::funcao_designacao[],
                   v_hoje)
    ELSE fn_designado(v_usuario, v_med.contrato_id, ARRAY['gestor_contrato']::funcao_designacao[], v_hoje)
  END;
  IF NOT v_pode THEN
    RAISE EXCEPTION 'Quem está na sessão não tem, neste contrato, a função que a ação "%" exige', NEW.acao
      USING ERRCODE = 'check_violation';
  END IF;

  IF NEW.acao = 'devolver' AND nullif(btrim(NEW.motivo), '') IS NULL THEN
    RAISE EXCEPTION 'Devolver a medição exige o motivo por escrito' USING ERRCODE = 'check_violation';
  END IF;

  -- segregação de funções: quem enviou não aprova nem atesta; quem aprovou não atesta
  IF NEW.acao IN ('aprovar_fiscal', 'atestar') AND v_usuario = fn_quem_fez_a_etapa(v_med.id, 'enviar') THEN
    RAISE EXCEPTION 'Quem enviou a medição não pode aprová-la nem atestá-la' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.acao = 'atestar' AND v_usuario = fn_quem_fez_a_etapa(v_med.id, 'aprovar_fiscal') THEN
    RAISE EXCEPTION 'Quem aprovou a medição como fiscal não pode atestá-la' USING ERRCODE = 'check_violation';
  END IF;

  PERFORM fn_medicao_pronta_para(v_med.id, NEW.acao);
  RETURN NEW;
END $$;

-- -----------------------------------------------------------------------------
-- 3. Registro das decisões de IA (leis L6 e LP5 do RREIA)
-- -----------------------------------------------------------------------------
-- A IA propõe; este registro guarda o que ela propôs e o que a pessoa fez com a proposta.
-- Não é dado de negócio: aceitar uma proposta é a pessoa gravar pela API normal, que revalida.
CREATE TABLE ia_decisao (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  funcao          text NOT NULL CHECK (funcao ~ '^IA-[0-9]{2}$'),   -- ponto de IA (docs/04)
  classe          text NOT NULL CHECK (classe IN ('choice', 'score', 'noul')),
  modelo          text NOT NULL,
  versao_modelo   text NOT NULL,
  versao_prompt   text NOT NULL,
  entrada_sha256  char(64) NOT NULL CHECK (entrada_sha256 ~ '^[0-9a-f]{64}$'),
  proposta        jsonb NOT NULL,
  confianca       text NOT NULL CHECK (confianca IN ('alta', 'media', 'baixa')),
  contrato_id     uuid REFERENCES contrato,
  pedida_por      uuid REFERENCES usuario,
  criada_em       timestamptz NOT NULL DEFAULT now(),
  -- o que aconteceu com a proposta
  desfecho        text CHECK (desfecho IN ('aceita', 'editada', 'rejeitada', 'descartada')),
  decidida_por    uuid REFERENCES usuario,
  decidida_em     timestamptz,
  CHECK ((desfecho IS NULL) = (decidida_em IS NULL)),
  -- "descartada" é do sistema (citação inexistente, número fora do estado); as outras, de gente
  CHECK (desfecho IS NULL OR (desfecho = 'descartada') = (decidida_por IS NULL))
);
CREATE INDEX ix_ia_decisao_funcao ON ia_decisao (funcao, criada_em);

CREATE FUNCTION fn_ia_decisao_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Registro de decisão de IA não se apaga' USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.desfecho IS NOT NULL THEN
      RAISE EXCEPTION 'A proposta de IA nasce sem desfecho: quem decide vem depois' USING ERRCODE = 'check_violation';
    END IF;
    NEW.pedida_por := app_usuario();
    NEW.criada_em := now();
    RETURN NEW;
  END IF;
  IF OLD.desfecho IS NOT NULL THEN
    RAISE EXCEPTION 'O desfecho da proposta de IA já foi registrado e não muda' USING ERRCODE = 'check_violation';
  END IF;
  IF (to_jsonb(NEW) - 'desfecho' - 'decidida_por' - 'decidida_em') IS DISTINCT FROM
     (to_jsonb(OLD) - 'desfecho' - 'decidida_por' - 'decidida_em') THEN
    RAISE EXCEPTION 'A proposta de IA registrada não se altera; só o desfecho é acrescentado' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.desfecho IS NULL THEN
    RAISE EXCEPTION 'Informe o desfecho da proposta' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.desfecho = 'descartada' THEN
    NEW.decidida_por := NULL;
  ELSE
    -- aceitar, editar ou rejeitar é decisão de pessoa: fica em nome de quem está na sessão
    IF app_usuario() IS NULL THEN
      RAISE EXCEPTION 'Proposta de IA só é aceita, editada ou rejeitada por uma pessoa identificada na sessão'
        USING ERRCODE = 'check_violation';
    END IF;
    NEW.decidida_por := app_usuario();
  END IF;
  NEW.decidida_em := now();
  RETURN NEW;
END $$;
CREATE TRIGGER trg_ia_decisao_guard BEFORE INSERT OR UPDATE OR DELETE ON ia_decisao
  FOR EACH ROW EXECUTE FUNCTION fn_ia_decisao_guard();

-- -----------------------------------------------------------------------------
-- 4. Publicação e denúncia
-- -----------------------------------------------------------------------------
CREATE TABLE publicacao (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  alvo            text NOT NULL CHECK (alvo IN ('pncp', 'tce', 'portal')),
  contrato_id     uuid REFERENCES contrato,
  documento       text NOT NULL,                 -- o que é publicado: 'contrato', 'aditivo', 'medicao'...
  payload         jsonb NOT NULL,
  status          text NOT NULL DEFAULT 'pendente' CHECK (status IN ('pendente', 'enviada', 'confirmada', 'falhou')),
  protocolo       text,
  erro            text,
  criada_por      uuid NOT NULL REFERENCES usuario,
  criada_em       timestamptz NOT NULL DEFAULT now(),
  atualizada_em   timestamptz NOT NULL DEFAULT now(),
  CHECK (status <> 'confirmada' OR nullif(btrim(protocolo), '') IS NOT NULL)
);

-- O que foi mandado publicar não muda; a situação anda, e publicação confirmada é final.
CREATE FUNCTION fn_publicacao_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Publicação não se apaga' USING ERRCODE = 'check_violation';
  END IF;
  IF (NEW.alvo, NEW.contrato_id, NEW.documento, NEW.payload, NEW.criada_por, NEW.criada_em, NEW.tenant_id)
       IS DISTINCT FROM (OLD.alvo, OLD.contrato_id, OLD.documento, OLD.payload, OLD.criada_por, OLD.criada_em, OLD.tenant_id) THEN
    RAISE EXCEPTION 'O conteúdo mandado publicar não se altera: publique de novo' USING ERRCODE = 'check_violation';
  END IF;
  IF OLD.status = 'confirmada' THEN
    RAISE EXCEPTION 'Publicação confirmada não muda' USING ERRCODE = 'check_violation';
  END IF;
  NEW.atualizada_em := now();
  RETURN NEW;
END $$;
CREATE TRIGGER trg_publicacao_quem BEFORE INSERT ON publicacao
  FOR EACH ROW EXECUTE FUNCTION fn_ato_de_quem_esta_na_sessao('criada_por', 'qualquer', 'mandar publicar');
CREATE TRIGGER trg_publicacao_guard BEFORE UPDATE OR DELETE ON publicacao
  FOR EACH ROW EXECUTE FUNCTION fn_publicacao_guard();

-- Denúncia do cidadão. Não guarda nome, documento nem contato de quem denuncia (LGPD).
CREATE TABLE denuncia (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  canal          text NOT NULL CHECK (canal IN ('portal', 'ouvidoria', 'outro')),
  texto          text NOT NULL CHECK (btrim(texto) <> ''),
  obra_id        uuid REFERENCES obra,
  status         text NOT NULL DEFAULT 'recebida'
                   CHECK (status IN ('recebida', 'em_analise', 'procedente', 'improcedente', 'arquivada')),
  ocorrencia_id  uuid REFERENCES ocorrencia,
  recebida_em    timestamptz NOT NULL DEFAULT now()
);
CREATE FUNCTION fn_denuncia_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Denúncia não se apaga' USING ERRCODE = 'check_violation';
  END IF;
  IF (NEW.canal, NEW.texto, NEW.obra_id, NEW.recebida_em, NEW.tenant_id)
       IS DISTINCT FROM (OLD.canal, OLD.texto, OLD.obra_id, OLD.recebida_em, OLD.tenant_id) THEN
    RAISE EXCEPTION 'O texto da denúncia não se altera' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_denuncia_guard BEFORE UPDATE OR DELETE ON denuncia
  FOR EACH ROW EXECUTE FUNCTION fn_denuncia_guard();

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['ia_decisao', 'publicacao', 'denuncia'] LOOP
    EXECUTE format('CREATE TRIGGER trg_auditoria AFTER INSERT OR UPDATE OR DELETE ON %I
                    FOR EACH ROW EXECUTE FUNCTION fn_auditar()', t);
  END LOOP;
END $$;

SELECT prumo_fechar_migracao();
REVOKE DELETE ON ia_decisao, publicacao, denuncia FROM app_rw;
