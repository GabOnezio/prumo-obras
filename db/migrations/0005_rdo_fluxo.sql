-- =============================================================================
-- Prumo · migração 0005 · fluxo do diário de obras (RDO)
--
--   rascunho → fechado → em_validacao → validado | devolvido (com motivo)
--
-- 1. O diário passa a pertencer a um contrato (a designação do fiscal é por contrato).
-- 2. Como na medição, a situação só muda por etapa registrada (rdo_etapa), em nome de quem
--    está na sessão: a empresa fecha, o fiscal valida ou devolve, e quem fechou não valida.
-- 3. Dia fechado não é sobrescrito: o conteúdo só muda em rascunho. Diário devolvido não
--    volta; a empresa retifica com um registro novo, que aponta para o devolvido.
-- 4. Instrução do fiscal é entrada separada e imutável (rdo_instrucao).
--
-- Do esboço de docs/06 §3: "rdo_validacao" é a trilha rdo_etapa; "rdo_retificacao" é a
-- coluna rdo.retifica_id. O estado "assinado" da referência some: fechar já é assinar.
-- As transições são as de crates/dominio::fluxo::diario.
-- =============================================================================

ALTER TABLE rdo ADD COLUMN contrato_id uuid NOT NULL REFERENCES contrato;
ALTER TABLE rdo ADD COLUMN retifica_id uuid UNIQUE REFERENCES rdo;

CREATE TYPE status_rdo AS ENUM ('rascunho', 'fechado', 'em_validacao', 'validado', 'devolvido');
ALTER TABLE rdo DROP CONSTRAINT rdo_status_check;
ALTER TABLE rdo ALTER COLUMN status DROP DEFAULT;
ALTER TABLE rdo ALTER COLUMN status TYPE status_rdo
  USING (CASE status WHEN 'assinado' THEN 'fechado' ELSE status END)::status_rdo;
ALTER TABLE rdo ALTER COLUMN status SET DEFAULT 'rascunho';

-- Um diário por contrato e por dia; o devolvido sai da conta para dar lugar ao retificador.
ALTER TABLE rdo DROP CONSTRAINT rdo_obra_id_data_key;
CREATE UNIQUE INDEX ux_rdo_dia ON rdo (contrato_id, data) WHERE status <> 'devolvido';

CREATE TYPE acao_rdo AS ENUM ('fechar', 'iniciar_validacao', 'validar', 'devolver');

CREATE FUNCTION fn_transicao_rdo(p_de status_rdo, p_acao acao_rdo) RETURNS status_rdo
LANGUAGE sql IMMUTABLE AS $$
  SELECT (CASE
    WHEN p_acao = 'fechar'            AND p_de = 'rascunho'     THEN 'fechado'
    WHEN p_acao = 'iniciar_validacao' AND p_de = 'fechado'      THEN 'em_validacao'
    WHEN p_acao = 'validar'           AND p_de = 'em_validacao' THEN 'validado'
    WHEN p_acao = 'devolver'          AND p_de = 'em_validacao' THEN 'devolvido'
  END)::status_rdo
$$;

CREATE TABLE rdo_etapa (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  rdo_id      uuid NOT NULL REFERENCES rdo,
  acao        acao_rdo NOT NULL,
  de          status_rdo NOT NULL,               -- preenchidos pelo banco
  para        status_rdo NOT NULL,
  usuario_id  uuid NOT NULL REFERENCES usuario,  -- quem está na sessão
  motivo      text,
  em          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_rdo_etapa_rdo ON rdo_etapa (rdo_id, em);

CREATE FUNCTION fn_rdo_etapa() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_rdo      rdo%ROWTYPE;
  v_usuario  uuid := app_usuario();
  v_pode     boolean;
BEGIN
  IF v_usuario IS NULL THEN
    RAISE EXCEPTION 'A sessão não diz quem está agindo: o diário não muda de situação' USING ERRCODE = 'check_violation';
  END IF;
  SELECT * INTO v_rdo FROM rdo WHERE id = NEW.rdo_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Diário não encontrado' USING ERRCODE = 'check_violation';
  END IF;
  NEW.usuario_id := v_usuario;
  NEW.de := v_rdo.status;
  NEW.para := fn_transicao_rdo(v_rdo.status, NEW.acao);
  NEW.em := now();
  IF NEW.para IS NULL THEN
    RAISE EXCEPTION 'Diário de % em "%" não aceita a ação "%"', v_rdo.data, v_rdo.status, NEW.acao USING ERRCODE = 'check_violation';
  END IF;
  v_pode := CASE WHEN NEW.acao = 'fechar' THEN fn_da_contratada(v_usuario, v_rdo.contrato_id, current_date)
                 ELSE fn_fiscal_do_contrato(v_usuario, v_rdo.contrato_id, current_date) END;
  IF NOT v_pode THEN
    RAISE EXCEPTION 'Quem está na sessão não tem, neste contrato, a função que a ação "%" exige', NEW.acao
      USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.acao = 'devolver' AND nullif(btrim(NEW.motivo), '') IS NULL THEN
    RAISE EXCEPTION 'Devolver o diário exige o motivo por escrito' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.acao = 'validar' AND v_usuario = (SELECT usuario_id FROM rdo_etapa WHERE rdo_id = v_rdo.id AND acao = 'fechar') THEN
    RAISE EXCEPTION 'Quem fechou o diário não pode validá-lo' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

CREATE FUNCTION fn_rdo_etapa_aplicar() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  UPDATE rdo SET status = NEW.para WHERE id = NEW.rdo_id;
  RETURN NULL;
END $$;

CREATE TRIGGER trg_rdo_etapa BEFORE INSERT ON rdo_etapa
  FOR EACH ROW EXECUTE FUNCTION fn_rdo_etapa();
CREATE TRIGGER trg_rdo_etapa_aplicar AFTER INSERT ON rdo_etapa
  FOR EACH ROW EXECUTE FUNCTION fn_rdo_etapa_aplicar();
CREATE TRIGGER trg_rdo_etapa_imutavel BEFORE UPDATE OR DELETE ON rdo_etapa
  FOR EACH ROW EXECUTE FUNCTION fn_imutavel('Etapa do diário');

-- rdo: nasce em rascunho; a situação só muda pela etapa; o conteúdo só muda em rascunho
CREATE FUNCTION fn_rdo_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_anterior rdo%ROWTYPE;
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.status <> 'rascunho' THEN
      RAISE EXCEPTION 'Diário de % está "%" e não se apaga', OLD.data, OLD.status USING ERRCODE = 'check_violation';
    END IF;
    RETURN OLD;
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'rascunho' THEN
      RAISE EXCEPTION 'Diário nasce em rascunho' USING ERRCODE = 'check_violation';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM contrato c WHERE c.id = NEW.contrato_id AND c.obra_id = NEW.obra_id) THEN
      RAISE EXCEPTION 'O contrato do diário não é desta obra' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.retifica_id IS NOT NULL THEN
      SELECT * INTO v_anterior FROM rdo WHERE id = NEW.retifica_id;
      IF v_anterior.status IS DISTINCT FROM 'devolvido'
         OR (v_anterior.contrato_id, v_anterior.data) IS DISTINCT FROM (NEW.contrato_id, NEW.data) THEN
        RAISE EXCEPTION 'Só se retifica diário devolvido, do mesmo contrato e do mesmo dia' USING ERRCODE = 'check_violation';
      END IF;
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF pg_trigger_depth() < 2 THEN
      RAISE EXCEPTION 'A situação do diário só muda por uma etapa registrada (rdo_etapa)' USING ERRCODE = 'check_violation';
    END IF;
  ELSIF OLD.status <> 'rascunho' THEN
    RAISE EXCEPTION 'Diário de % está "%": dia fechado não é sobrescrito', OLD.data, OLD.status USING ERRCODE = 'check_violation';
  END IF;
  IF (NEW.contrato_id, NEW.obra_id, NEW.data, NEW.retifica_id, NEW.tenant_id)
       IS DISTINCT FROM (OLD.contrato_id, OLD.obra_id, OLD.data, OLD.retifica_id, OLD.tenant_id) THEN
    RAISE EXCEPTION 'Contrato, obra e dia do diário não mudam' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_rdo_guard BEFORE INSERT OR UPDATE OR DELETE ON rdo
  FOR EACH ROW EXECUTE FUNCTION fn_rdo_guard();

-- Efetivo, equipamento, ocorrência e foto do diário: só com o diário em rascunho.
CREATE FUNCTION fn_rdo_conteudo_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_status status_rdo; v_data date;
BEGIN
  SELECT status, data INTO v_status, v_data FROM rdo WHERE id = coalesce(NEW.rdo_id, OLD.rdo_id);
  IF v_status <> 'rascunho' THEN
    RAISE EXCEPTION 'Diário de % está "%": dia fechado não é sobrescrito', v_data, v_status USING ERRCODE = 'check_violation';
  END IF;
  RETURN coalesce(NEW, OLD);
END $$;
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['rdo_efetivo', 'rdo_equipamento', 'rdo_ocorrencia', 'rdo_foto'] LOOP
    EXECUTE format('CREATE TRIGGER trg_rdo_conteudo_guard BEFORE INSERT OR UPDATE OR DELETE ON %I
                    FOR EACH ROW EXECUTE FUNCTION fn_rdo_conteudo_guard()', t);
  END LOOP;
END $$;

-- Instrução do fiscal sobre um diário que a empresa já fechou. O fiscal não edita o diário.
CREATE TABLE rdo_instrucao (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  rdo_id          uuid NOT NULL REFERENCES rdo,
  texto           text NOT NULL CHECK (btrim(texto) <> ''),
  registrada_por  uuid NOT NULL REFERENCES usuario,
  registrada_em   timestamptz NOT NULL DEFAULT now()
);
CREATE FUNCTION fn_rdo_instrucao_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_rdo rdo%ROWTYPE;
BEGIN
  SELECT * INTO v_rdo FROM rdo WHERE id = NEW.rdo_id;
  IF v_rdo.status = 'rascunho' THEN
    RAISE EXCEPTION 'Instrução só em diário que a empresa já fechou' USING ERRCODE = 'check_violation';
  END IF;
  IF app_usuario() IS NULL OR NOT fn_fiscal_do_contrato(app_usuario(), v_rdo.contrato_id, current_date) THEN
    RAISE EXCEPTION 'Só fiscal com designação vigente neste contrato registra instrução' USING ERRCODE = 'check_violation';
  END IF;
  NEW.registrada_por := app_usuario();
  NEW.registrada_em := now();
  RETURN NEW;
END $$;
CREATE TRIGGER trg_rdo_instrucao_guard BEFORE INSERT ON rdo_instrucao
  FOR EACH ROW EXECUTE FUNCTION fn_rdo_instrucao_guard();
CREATE TRIGGER trg_rdo_instrucao_imutavel BEFORE UPDATE OR DELETE ON rdo_instrucao
  FOR EACH ROW EXECUTE FUNCTION fn_imutavel('Instrução do fiscal');

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['rdo', 'rdo_etapa', 'rdo_instrucao'] LOOP
    EXECUTE format('CREATE TRIGGER trg_auditoria AFTER INSERT OR UPDATE OR DELETE ON %I
                    FOR EACH ROW EXECUTE FUNCTION fn_auditar()', t);
  END LOOP;
END $$;

SELECT prumo_fechar_migracao();
REVOKE UPDATE, DELETE ON rdo_etapa, rdo_instrucao FROM app_rw;
