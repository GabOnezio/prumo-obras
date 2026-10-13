-- =============================================================================
-- Prumo · migração 0004 · fluxo da medição
--
-- 1. A medição ganha os estados do Prumo (ADR 0009):
--      rascunho → enviada → em_analise → devolvida | aprovada_fiscal → atestada → liquidada → paga
--    O estado "aprovada" da referência vira "aprovada_fiscal".
-- 2. O estado só muda por uma ETAPA registrada (medicao_etapa). A etapa diz quem agiu, e o
--    banco confere a transição, a designação e a segregação de funções. A trilha de
--    aprovação deixa de ser um texto livre ("aprovada por").
-- 3. Liquidação e pagamento só são registrados com a referência do documento da contabilidade.
-- 4. A medição por eventos deixa de se chamar "ple" no banco e passa a "eventos". Estava
--    prevista para a 0007; veio para cá porque os mesmos gatilhos são reescritos aqui, e
--    reescrevê-los uma vez só é menos risco. A trava da forma de medir continua na 0007.
--
-- As transições são as mesmas de crates/dominio::fluxo::medicao; crates/paridade compara.
-- Glosa por quantidade ainda não desconta valor: medição com glosa registrada não é
-- aprovada, é devolvida para a empresa corrigir a quantidade.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. "ple" passa a se chamar "eventos"
-- -----------------------------------------------------------------------------
ALTER TYPE forma_acompanhamento RENAME VALUE 'ple' TO 'eventos';

-- -----------------------------------------------------------------------------
-- 2. Estados da medição: tipo novo no lugar do antigo
-- -----------------------------------------------------------------------------
DROP VIEW vw_rre_medicao;
DROP VIEW vw_contrato_situacao;
DROP INDEX ux_medicao_aberta;
DO $$
DECLARE v_nome text;
BEGIN
  SELECT conname INTO STRICT v_nome FROM pg_constraint WHERE conrelid = 'medicao'::regclass AND contype = 'x';
  EXECUTE format('ALTER TABLE medicao DROP CONSTRAINT %I', v_nome);
END $$;

ALTER TYPE status_medicao RENAME TO status_medicao_da_referencia;
CREATE TYPE status_medicao AS ENUM (
  'rascunho', 'enviada', 'em_analise', 'devolvida', 'aprovada_fiscal', 'atestada', 'liquidada', 'paga', 'cancelada');
ALTER TABLE medicao ALTER COLUMN status DROP DEFAULT;
ALTER TABLE medicao ALTER COLUMN status TYPE status_medicao
  USING (CASE status::text WHEN 'aprovada' THEN 'aprovada_fiscal' ELSE status::text END)::status_medicao;
ALTER TABLE medicao ALTER COLUMN status SET DEFAULT 'rascunho';
DROP TYPE status_medicao_da_referencia;

-- Quem aprovou passa a estar na trilha (medicao_etapa), com o id do usuário.
ALTER TABLE medicao DROP COLUMN aprovada_por;

-- períodos de medições válidas não se sobrepõem
ALTER TABLE medicao ADD CONSTRAINT medicao_periodo_sem_sobreposicao
  EXCLUDE USING gist (contrato_id WITH =, daterange(periodo_inicio, periodo_fim, '[]') WITH &&)
  WHERE (status <> 'cancelada');
-- só uma medição em aberto por contrato: da abertura até a decisão do fiscal
CREATE UNIQUE INDEX ux_medicao_aberta ON medicao (contrato_id)
  WHERE status IN ('rascunho', 'enviada', 'em_analise', 'devolvida');

-- A empresa só mexe no conteúdo da medição nestes estados.
CREATE FUNCTION fn_medicao_editavel(p_status status_medicao) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$ SELECT p_status IN ('rascunho', 'devolvida') $$;

-- -----------------------------------------------------------------------------
-- 3. Trilha de etapas: o único caminho para mudar o estado
-- -----------------------------------------------------------------------------
CREATE TYPE acao_medicao AS ENUM (
  'enviar', 'cancelar', 'iniciar_analise', 'devolver', 'aprovar_fiscal', 'atestar',
  'registrar_liquidacao', 'registrar_pagamento');

-- A tabela de transições. É a mesma de crates/dominio::fluxo::medicao (ADR 0009).
CREATE FUNCTION fn_transicao_medicao(p_de status_medicao, p_acao acao_medicao) RETURNS status_medicao
LANGUAGE sql IMMUTABLE AS $$
  SELECT (CASE
    WHEN p_acao = 'enviar'               AND p_de IN ('rascunho', 'devolvida') THEN 'enviada'
    WHEN p_acao = 'cancelar'             AND p_de IN ('rascunho', 'devolvida') THEN 'cancelada'
    WHEN p_acao = 'iniciar_analise'      AND p_de = 'enviada'                  THEN 'em_analise'
    WHEN p_acao = 'devolver'             AND p_de = 'em_analise'               THEN 'devolvida'
    WHEN p_acao = 'aprovar_fiscal'       AND p_de = 'em_analise'               THEN 'aprovada_fiscal'
    WHEN p_acao = 'atestar'              AND p_de = 'aprovada_fiscal'          THEN 'atestada'
    WHEN p_acao = 'registrar_liquidacao' AND p_de = 'atestada'                 THEN 'liquidada'
    WHEN p_acao = 'registrar_pagamento'  AND p_de = 'liquidada'                THEN 'paga'
  END)::status_medicao
$$;

-- Referência do que a contabilidade fez. O Prumo não empenha, não liquida e não paga: anota.
CREATE TABLE execucao_financeira_ref (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  contrato_id     uuid NOT NULL REFERENCES contrato,
  medicao_id      uuid REFERENCES medicao,
  tipo            text NOT NULL CHECK (tipo IN ('empenho', 'liquidacao', 'pagamento')),
  numero          text NOT NULL CHECK (btrim(numero) <> ''),
  valor           numeric(18,2) NOT NULL CHECK (valor > 0),
  data            date NOT NULL,
  registrado_por  uuid NOT NULL REFERENCES usuario,
  registrado_em   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (contrato_id, tipo, numero),
  CHECK (tipo = 'empenho' OR medicao_id IS NOT NULL)
);
CREATE TRIGGER trg_execucao_financeira_quem BEFORE INSERT ON execucao_financeira_ref
  FOR EACH ROW EXECUTE FUNCTION fn_ato_de_quem_esta_na_sessao('registrado_por', 'qualquer', 'registrar execução financeira');
CREATE TRIGGER trg_execucao_financeira_imutavel BEFORE UPDATE OR DELETE ON execucao_financeira_ref
  FOR EACH ROW EXECUTE FUNCTION fn_imutavel('Referência de execução financeira');

CREATE TABLE medicao_etapa (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  medicao_id  uuid NOT NULL REFERENCES medicao,
  acao        acao_medicao NOT NULL,
  de          status_medicao NOT NULL,           -- preenchidos pelo banco
  para        status_medicao NOT NULL,
  usuario_id  uuid NOT NULL REFERENCES usuario,  -- quem está na sessão
  motivo      text,
  em          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_medicao_etapa_medicao ON medicao_etapa (medicao_id, em);

-- Quem enviou a medição pela última vez (o autor) e quem a aprovou como fiscal.
CREATE FUNCTION fn_quem_fez_a_etapa(p_medicao uuid, p_acao acao_medicao) RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT usuario_id FROM medicao_etapa WHERE medicao_id = p_medicao AND acao = p_acao ORDER BY em DESC, id DESC LIMIT 1
$$;

-- Confere a etapa antes de gravar: transição, quem pode, motivo, segregação de funções e
-- o que cada ação exige. Preenche de, para e o usuário; o que vier nesses campos é ignorado.
CREATE FUNCTION fn_medicao_etapa() RETURNS trigger LANGUAGE plpgsql AS $$
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
    -- quem atesta depende de o município exigir comissão; a configuração entra na 0006
    WHEN NEW.acao = 'atestar' THEN
      fn_designado(v_usuario, v_med.contrato_id, ARRAY['gestor_contrato', 'comissao_medicao']::funcao_designacao[], v_hoje)
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

  IF NEW.acao = 'aprovar_fiscal' AND EXISTS (SELECT 1 FROM medicao_glosa WHERE medicao_id = v_med.id) THEN
    RAISE EXCEPTION 'Medição com glosa por quantidade não é aprovada: devolva para a empresa corrigir a quantidade'
      USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.acao = 'registrar_liquidacao' AND NOT EXISTS (
       SELECT 1 FROM execucao_financeira_ref WHERE medicao_id = v_med.id AND tipo = 'liquidacao') THEN
    RAISE EXCEPTION 'Sem a referência da liquidação desta medição não há o que registrar' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.acao = 'registrar_pagamento' AND NOT EXISTS (
       SELECT 1 FROM execucao_financeira_ref WHERE medicao_id = v_med.id AND tipo = 'pagamento') THEN
    RAISE EXCEPTION 'Sem a referência do pagamento desta medição não há o que registrar' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

CREATE FUNCTION fn_medicao_etapa_aplicar() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  UPDATE medicao SET status = NEW.para WHERE id = NEW.medicao_id;
  RETURN NULL;
END $$;

CREATE TRIGGER trg_medicao_etapa BEFORE INSERT ON medicao_etapa
  FOR EACH ROW EXECUTE FUNCTION fn_medicao_etapa();
CREATE TRIGGER trg_medicao_etapa_aplicar AFTER INSERT ON medicao_etapa
  FOR EACH ROW EXECUTE FUNCTION fn_medicao_etapa_aplicar();
CREATE TRIGGER trg_medicao_etapa_imutavel BEFORE UPDATE OR DELETE ON medicao_etapa
  FOR EACH ROW EXECUTE FUNCTION fn_imutavel('Etapa da medição');

-- medicao: nasce em rascunho sobre a revisão vigente; a situação só muda pela etapa;
-- o conteúdo só muda enquanto a empresa pode editar; consolida o valor ao enviar e ao aprovar
CREATE OR REPLACE FUNCTION fn_medicao_guard() RETURNS trigger LANGUAGE plpgsql AS $$
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
    IF OLD.status <> 'rascunho' OR EXISTS (SELECT 1 FROM medicao_etapa WHERE medicao_id = OLD.id) THEN
      RAISE EXCEPTION 'Medição nº % não pode ser excluída: já saiu do rascunho', OLD.numero USING ERRCODE = 'check_violation';
    END IF;
    RETURN OLD;
  END IF;
  IF (NEW.contrato_id, NEW.numero, NEW.revisao_id, NEW.tenant_id)
       IS DISTINCT FROM (OLD.contrato_id, OLD.numero, OLD.revisao_id, OLD.tenant_id) THEN
    RAISE EXCEPTION 'Contrato, número e revisão da medição não mudam' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    -- o único UPDATE de situação aceito é o que vem do gatilho da etapa
    IF pg_trigger_depth() < 2 THEN
      RAISE EXCEPTION 'A situação da medição só muda por uma etapa registrada (medicao_etapa)' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.status IN ('enviada', 'aprovada_fiscal') THEN
      SELECT coalesce(sum(valor), 0) INTO NEW.valor_bruto FROM medicao_item WHERE medicao_id = NEW.id;
    END IF;
    IF NEW.status = 'enviada' THEN NEW.enviada_em := now(); END IF;
    IF NEW.status = 'aprovada_fiscal' THEN NEW.aprovada_em := now(); END IF;
  ELSIF NOT fn_medicao_editavel(OLD.status) THEN
    RAISE EXCEPTION 'Medição nº % está "%" e não pode ser alterada', OLD.numero, OLD.status USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

-- -----------------------------------------------------------------------------
-- 4. Gatilhos da referência reescritos: "eventos" no lugar de "ple" e conteúdo editável
--    em rascunho e em devolvida. As regras são as mesmas.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_revisao_guard() RETURNS trigger LANGUAGE plpgsql AS $$
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
    IF v_forma = 'eventos' THEN
      -- todo serviço precisa de agrupador e da quantidade inteira distribuída nas frentes
      SELECT ir.codigo_eap INTO v_cod
        FROM item_revisao ir
       WHERE ir.revisao_id = NEW.id AND ir.tipo = 'servico'
         AND (ir.agrupador_evento_id IS NULL
              OR ir.quantidade <> (SELECT coalesce(sum(f.quantidade), 0) FROM item_frente f
                                    WHERE f.item_revisao_id = ir.id))
       ORDER BY ir.path LIMIT 1;
      IF v_cod IS NOT NULL THEN
        RAISE EXCEPTION 'Planilha por eventos: item % sem agrupador ou com quantidade não distribuída nas frentes', v_cod
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

CREATE OR REPLACE FUNCTION fn_medicao_item_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_med    medicao%ROWTYPE;
  v_item   item_revisao%ROWTYPE;
  v_crit   criterio_arredondamento;
  v_forma  forma_acompanhamento;
  v_qtd_ev numeric;
  v_acum   numeric;
BEGIN
  SELECT * INTO v_med FROM medicao WHERE id = coalesce(NEW.medicao_id, OLD.medicao_id);
  IF NOT fn_medicao_editavel(v_med.status) THEN
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
    RAISE EXCEPTION 'Contrato medido por %: linha lançada por % não é aceita',
      CASE v_forma WHEN 'eventos' THEN 'eventos' ELSE 'quantidade' END,
      CASE NEW.origem WHEN 'eventos' THEN 'evento' ELSE 'quantidade' END
      USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.origem = 'eventos' THEN
    -- quantidade e valor vêm das frentes dos eventos marcados nesta medição
    SELECT coalesce(sum(f.quantidade), 0),
           coalesce(sum(fn_valor_item(f.quantidade, v_item.preco_unitario, v_crit)), 0)
      INTO v_qtd_ev, NEW.valor
      FROM medicao_evento me
      JOIN evento e      ON e.id = me.evento_id
      JOIN item_frente f ON f.frente_id = e.frente_id AND f.item_revisao_id = v_item.id
     WHERE me.medicao_id = NEW.medicao_id AND e.agrupador_id = v_item.agrupador_evento_id;
    IF NEW.quantidade <> v_qtd_ev THEN
      RAISE EXCEPTION 'Item %: na medição por eventos a quantidade é a soma das frentes concluídas (%)', v_item.codigo_eap, v_qtd_ev
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

CREATE OR REPLACE FUNCTION fn_medicao_evento_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_med   medicao%ROWTYPE;
  v_ev    evento%ROWTYPE;
  v_forma forma_acompanhamento;
BEGIN
  SELECT * INTO v_med FROM medicao WHERE id = coalesce(NEW.medicao_id, OLD.medicao_id);
  IF NOT fn_medicao_editavel(v_med.status) THEN
    RAISE EXCEPTION 'Medição nº % está "%": eventos não podem ser alterados', v_med.numero, v_med.status
      USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  SELECT forma_acompanhamento INTO v_forma FROM contrato WHERE id = v_med.contrato_id;
  IF v_forma <> 'eventos' THEN
    RAISE EXCEPTION 'Contrato medido por quantidade não mede eventos' USING ERRCODE = 'check_violation';
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

CREATE OR REPLACE FUNCTION fn_aplicar_eventos() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_medicao uuid := coalesce(NEW.medicao_id, OLD.medicao_id);
BEGIN
  DELETE FROM medicao_item WHERE medicao_id = v_medicao AND origem = 'eventos';
  INSERT INTO medicao_item (tenant_id, medicao_id, item_contratual_id, quantidade, valor, origem)
  SELECT ir.tenant_id, v_medicao, ir.item_contratual_id, sum(f.quantidade), 0, 'eventos'
    FROM medicao_evento me
    JOIN evento e        ON e.id = me.evento_id
    JOIN item_revisao ir ON ir.revisao_id = e.revisao_id AND ir.agrupador_evento_id = e.agrupador_id
                        AND ir.tipo = 'servico'
    JOIN item_frente f   ON f.item_revisao_id = ir.id AND f.frente_id = e.frente_id
   WHERE me.medicao_id = v_medicao
   GROUP BY ir.tenant_id, ir.item_contratual_id;
  RETURN NULL;
END $$;

-- Glosa por quantidade: registrada pelo fiscal durante a análise, sobre item desta medição.
ALTER TABLE medicao_glosa ADD COLUMN registrada_por uuid REFERENCES usuario;
ALTER TABLE medicao_glosa ADD COLUMN registrada_em timestamptz NOT NULL DEFAULT now();

CREATE FUNCTION fn_medicao_glosa_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_med  medicao%ROWTYPE;
  v_qtd  numeric;
BEGIN
  SELECT * INTO v_med FROM medicao WHERE id = coalesce(NEW.medicao_id, OLD.medicao_id);
  IF v_med.status <> 'em_analise' THEN
    RAISE EXCEPTION 'Glosa só é registrada ou alterada com a medição em análise' USING ERRCODE = 'check_violation';
  END IF;
  IF app_usuario() IS NULL OR NOT fn_fiscal_do_contrato(app_usuario(), v_med.contrato_id, current_date) THEN
    RAISE EXCEPTION 'Só fiscal com designação vigente neste contrato registra glosa' USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  NEW.registrada_por := app_usuario();
  SELECT quantidade INTO v_qtd FROM medicao_item
   WHERE medicao_id = NEW.medicao_id AND item_contratual_id = NEW.item_contratual_id;
  IF v_qtd IS NULL OR NEW.quantidade > v_qtd THEN
    RAISE EXCEPTION 'Glosa maior que a quantidade medida do item nesta medição' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_medicao_glosa_guard BEFORE INSERT OR UPDATE OR DELETE ON medicao_glosa
  FOR EACH ROW EXECUTE FUNCTION fn_medicao_glosa_guard();

-- -----------------------------------------------------------------------------
-- 5. Visões que dependiam do tipo antigo
-- -----------------------------------------------------------------------------
-- Situação atual do contrato. "Medido e aprovado" conta da aprovação do fiscal em diante.
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
      FROM medicao m WHERE m.contrato_id = c.id
       AND m.status IN ('aprovada_fiscal', 'atestada', 'liquidada', 'paga')) med ON true;

-- RRE: cada medição dividida em repasse, contrapartida e outros (igual à referência).
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

GRANT SELECT ON vw_contrato_situacao, vw_rre_medicao TO app_rw;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['medicao_etapa', 'execucao_financeira_ref'] LOOP
    EXECUTE format('CREATE TRIGGER trg_auditoria AFTER INSERT OR UPDATE OR DELETE ON %I
                    FOR EACH ROW EXECUTE FUNCTION fn_auditar()', t);
  END LOOP;
END $$;

SELECT prumo_fechar_migracao();

-- A trilha e as referências só crescem: a aplicação lê e acrescenta.
REVOKE UPDATE, DELETE ON medicao_etapa, execucao_financeira_ref FROM app_rw;
