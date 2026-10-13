-- =============================================================================
-- Prumo · migração 0008 · Boletim de Execução, evidência e glosa de evento
--
-- 1. boletim_execucao: o documento do fiscal. Rascunho → emitido; emitido é imutável e só
--    um boletim retificador o corrige (invariante 2 de docs/10 §9).
-- 2. Evento só é aprovado na medição se o último boletim emitido que o cita o marca
--    "concluído", com verificação até o fim do período da medição (invariante 1).
-- 3. Glosa do evento inteiro (medicao_evento_analise). Evento glosado sai da conta da
--    medição e pode voltar numa medição seguinte (invariante 6).
-- 4. foto: uma tabela só para diário, vistoria e boletim. Só foto da câmera do app, com
--    hash; vínculo com a planilha só confirmado por pessoa. Substitui rdo_foto.
-- 5. rdo_servico: o serviço executado no dia, com frente e item da planilha.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Foto de evidência (substitui rdo_foto) e serviço do diário
-- -----------------------------------------------------------------------------
DROP TABLE rdo_foto;

CREATE TABLE foto (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id               uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  contrato_id             uuid NOT NULL REFERENCES contrato,
  -- só entra foto tirada pela câmera do app; arquivo da galeria não é evidência
  origem                  text NOT NULL CHECK (origem = 'camera_app'),
  sha256                  char(64) NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  chave_arquivo           text NOT NULL,
  tirada_em               timestamptz NOT NULL,
  offset_relogio_s        integer,                -- diferença entre o relógio do aparelho e o do servidor
  latitude                numeric(9,6) CHECK (latitude BETWEEN -90 AND 90),
  longitude               numeric(9,6) CHECK (longitude BETWEEN -180 AND 180),
  precisao_m              numeric(8,2) CHECK (precisao_m >= 0),
  autor                   uuid NOT NULL REFERENCES usuario,
  legenda                 text,
  -- de onde veio
  rdo_id                  uuid REFERENCES rdo,
  vistoria_id             uuid REFERENCES vistoria,
  -- a que parte da planilha se refere
  item_contratual_id      uuid REFERENCES item_contratual,
  frente_id               uuid REFERENCES frente_obra,
  evento_id               uuid REFERENCES evento,
  vinculo_origem          text CHECK (vinculo_origem IN ('captura', 'manual', 'sugestao_aceita')),
  vinculo_confirmado_por  uuid REFERENCES usuario,
  registrada_em           timestamptz NOT NULL DEFAULT now(),
  UNIQUE (contrato_id, sha256),
  CHECK ((latitude IS NULL) = (longitude IS NULL)),
  CHECK ((vinculo_origem IS NULL) = (vinculo_confirmado_por IS NULL)),
  -- sem confirmação de pessoa a foto não fica ligada a serviço, frente nem evento
  CHECK (vinculo_origem IS NOT NULL OR num_nonnulls(item_contratual_id, frente_id, evento_id) = 0)
);
CREATE INDEX ix_foto_contrato ON foto (contrato_id, tirada_em);

-- A foto é de quem a tirou e não muda. Só a legenda e o vínculo com a planilha podem ser
-- informados depois, e o vínculo fica em nome de quem confirmou.
CREATE FUNCTION fn_foto_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_usuario uuid := app_usuario();
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Foto de evidência não se apaga' USING ERRCODE = 'check_violation';
  END IF;
  IF v_usuario IS NULL THEN
    RAISE EXCEPTION 'A sessão não diz quem está agindo: foto tem autor' USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF NOT (fn_da_contratada(v_usuario, NEW.contrato_id, current_date) OR fn_fiscal_do_contrato(v_usuario, NEW.contrato_id, current_date)) THEN
      RAISE EXCEPTION 'Só a empresa contratada e a fiscalização deste contrato registram foto' USING ERRCODE = 'check_violation';
    END IF;
    NEW.autor := v_usuario;
    NEW.registrada_em := now();
    IF NEW.rdo_id IS NOT NULL AND NOT EXISTS (
         SELECT 1 FROM rdo WHERE id = NEW.rdo_id AND contrato_id = NEW.contrato_id AND status = 'rascunho') THEN
      RAISE EXCEPTION 'Foto de diário só entra com o diário deste contrato em rascunho: dia fechado não é sobrescrito'
        USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.vistoria_id IS NOT NULL AND NOT EXISTS (
         SELECT 1 FROM vistoria WHERE id = NEW.vistoria_id AND contrato_id = NEW.contrato_id AND concluida_em IS NULL) THEN
      RAISE EXCEPTION 'Foto de vistoria só entra com a vistoria deste contrato ainda aberta' USING ERRCODE = 'check_violation';
    END IF;
  ELSIF (to_jsonb(NEW) - ARRAY['legenda', 'item_contratual_id', 'frente_id', 'evento_id', 'vinculo_origem', 'vinculo_confirmado_por'])
          IS DISTINCT FROM
        (to_jsonb(OLD) - ARRAY['legenda', 'item_contratual_id', 'frente_id', 'evento_id', 'vinculo_origem', 'vinculo_confirmado_por']) THEN
    RAISE EXCEPTION 'A foto registrada não se altera; só a legenda e o vínculo com a planilha' USING ERRCODE = 'check_violation';
  END IF;
  -- vínculo: confere que é deste contrato e grava quem confirmou
  IF NEW.vinculo_origem IS NOT NULL THEN
    NEW.vinculo_confirmado_por := v_usuario;
    IF (NEW.item_contratual_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM item_contratual WHERE id = NEW.item_contratual_id AND contrato_id = NEW.contrato_id))
       OR (NEW.frente_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM frente_obra WHERE id = NEW.frente_id AND contrato_id = NEW.contrato_id))
       OR (NEW.evento_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM evento e JOIN revisao_orcamento r ON r.id = e.revisao_id
                                                      WHERE e.id = NEW.evento_id AND r.contrato_id = NEW.contrato_id)) THEN
      RAISE EXCEPTION 'A foto só se liga a serviço, frente e evento do próprio contrato' USING ERRCODE = 'check_violation';
    END IF;
  ELSE
    NEW.vinculo_confirmado_por := NULL;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_foto_guard BEFORE INSERT OR UPDATE OR DELETE ON foto
  FOR EACH ROW EXECUTE FUNCTION fn_foto_guard();

-- Serviço executado no dia: o que liga o diário à planilha.
CREATE TABLE rdo_servico (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  rdo_id              uuid NOT NULL REFERENCES rdo ON DELETE CASCADE,
  item_contratual_id  uuid REFERENCES item_contratual,   -- vazio = serviço que a empresa não achou na planilha
  frente_id           uuid REFERENCES frente_obra,
  descricao           text NOT NULL CHECK (btrim(descricao) <> ''),
  quantidade          numeric(18,4) CHECK (quantidade > 0),
  unidade             text
);
CREATE FUNCTION fn_rdo_servico_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_contrato uuid;
BEGIN
  SELECT contrato_id INTO v_contrato FROM rdo WHERE id = NEW.rdo_id;
  IF (NEW.item_contratual_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM item_contratual WHERE id = NEW.item_contratual_id AND contrato_id = v_contrato))
     OR (NEW.frente_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM frente_obra WHERE id = NEW.frente_id AND contrato_id = v_contrato)) THEN
    RAISE EXCEPTION 'Serviço do diário aponta para item ou frente de outro contrato' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_rdo_conteudo_guard BEFORE INSERT OR UPDATE OR DELETE ON rdo_servico
  FOR EACH ROW EXECUTE FUNCTION fn_rdo_conteudo_guard();
CREATE TRIGGER trg_rdo_servico_guard BEFORE INSERT OR UPDATE ON rdo_servico
  FOR EACH ROW EXECUTE FUNCTION fn_rdo_servico_guard();

-- -----------------------------------------------------------------------------
-- 2. Boletim de Execução
-- -----------------------------------------------------------------------------
CREATE TYPE situacao_evento AS ENUM ('nao_iniciado', 'em_andamento', 'concluido', 'concluido_com_pendencia', 'paralisado');

CREATE TABLE boletim_execucao (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id             uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  contrato_id           uuid NOT NULL REFERENCES contrato,
  numero                integer NOT NULL CHECK (numero > 0),
  periodo_inicio        date NOT NULL,
  periodo_fim           date NOT NULL,
  status                text NOT NULL DEFAULT 'rascunho' CHECK (status IN ('rascunho', 'emitido')),
  retifica_id           uuid UNIQUE REFERENCES boletim_execucao,   -- boletim que este corrige
  cronograma_versao_id  uuid REFERENCES cronograma_versao,         -- versão vigente na emissão
  elaborado_por         uuid NOT NULL REFERENCES usuario,
  emitido_por           uuid REFERENCES usuario,
  emitido_em            timestamptz,
  UNIQUE (contrato_id, numero),
  CHECK (periodo_fim >= periodo_inicio),
  CHECK ((status = 'emitido') = (emitido_em IS NOT NULL) AND (status = 'emitido') = (emitido_por IS NOT NULL))
);

CREATE TABLE boletim_execucao_linha (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  boletim_id          uuid NOT NULL REFERENCES boletim_execucao ON DELETE CASCADE,
  evento_id           uuid REFERENCES evento,            -- contrato por eventos
  item_contratual_id  uuid REFERENCES item_contratual,   -- contrato por quantidade
  situacao            situacao_evento NOT NULL,
  avanco_percentual   smallint CHECK (avanco_percentual BETWEEN 1 AND 99),
  verificado_em       date,
  observacao          text,
  UNIQUE (boletim_id, evento_id),
  UNIQUE (boletim_id, item_contratual_id),
  CHECK (num_nonnulls(evento_id, item_contratual_id) = 1),
  CHECK ((situacao = 'em_andamento') = (avanco_percentual IS NOT NULL)),
  CHECK ((situacao IN ('concluido', 'concluido_com_pendencia')) = (verificado_em IS NOT NULL)),
  CHECK (situacao <> 'concluido_com_pendencia' OR nullif(btrim(observacao), '') IS NOT NULL)
);

CREATE TABLE boletim_execucao_evidencia (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id  uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  linha_id   uuid NOT NULL REFERENCES boletim_execucao_linha ON DELETE CASCADE,
  tipo       text NOT NULL CHECK (tipo IN ('foto', 'vistoria', 'rdo')),
  ref_id     uuid NOT NULL,
  UNIQUE (linha_id, tipo, ref_id)
);

-- Quantas evidências uma linha precisa para "concluído". Vem da configuração; sem ela, erro.
CREATE FUNCTION fn_evidencias_para_concluido() RETURNS smallint LANGUAGE plpgsql STABLE AS $$
DECLARE v smallint;
BEGIN
  SELECT boletim_evidencias_para_concluido INTO v FROM config_municipio WHERE tenant_id = app_tenant();
  IF v IS NULL THEN
    RAISE EXCEPTION 'Configuração do município ausente: evidência mínima para marcar "concluído" no boletim' USING ERRCODE = 'check_violation';
  END IF;
  RETURN v;
END $$;

-- boletim: do fiscal designado; nasce em rascunho com o número seguinte; emitir confere as
-- linhas; emitido não muda nem para o dono das tabelas.
CREATE FUNCTION fn_boletim_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_usuario  uuid := app_usuario();
  v_ordem    int;
  v_minimo   smallint;
BEGIN
  IF TG_OP <> 'INSERT' AND OLD.status = 'emitido' THEN
    RAISE EXCEPTION 'Boletim de Execução nº % foi emitido e é imutável: a correção é um boletim retificador', OLD.numero
      USING ERRCODE = 'check_violation';
  END IF;
  IF v_usuario IS NULL OR NOT fn_fiscal_do_contrato(v_usuario, coalesce(NEW.contrato_id, OLD.contrato_id), current_date) THEN
    RAISE EXCEPTION 'Boletim de Execução é do fiscal com designação vigente neste contrato' USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.elaborado_por := v_usuario;
    IF NEW.status <> 'rascunho' THEN
      RAISE EXCEPTION 'Boletim de Execução nasce em rascunho' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.numero <> (SELECT coalesce(max(numero), 0) + 1 FROM boletim_execucao WHERE contrato_id = NEW.contrato_id) THEN
      RAISE EXCEPTION 'O número do boletim tem que ser o seguinte ao último' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.retifica_id IS NOT NULL AND NOT EXISTS (
         SELECT 1 FROM boletim_execucao WHERE id = NEW.retifica_id AND contrato_id = NEW.contrato_id AND status = 'emitido') THEN
      RAISE EXCEPTION 'Só se retifica boletim emitido, do mesmo contrato' USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;

  IF (NEW.contrato_id, NEW.numero, NEW.retifica_id, NEW.elaborado_por, NEW.tenant_id)
       IS DISTINCT FROM (OLD.contrato_id, OLD.numero, OLD.retifica_id, OLD.elaborado_por, OLD.tenant_id) THEN
    RAISE EXCEPTION 'Contrato, número e autor do boletim não mudam' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.status = 'emitido' THEN
    IF NOT EXISTS (SELECT 1 FROM boletim_execucao_linha WHERE boletim_id = NEW.id) THEN
      RAISE EXCEPTION 'Boletim sem nenhuma linha não é emitido' USING ERRCODE = 'check_violation';
    END IF;
    v_minimo := fn_evidencias_para_concluido();
    SELECT x.ordem INTO v_ordem FROM (
      SELECT l.id, l.verificado_em, row_number() OVER (ORDER BY l.id) AS ordem,
             (SELECT count(*) FROM boletim_execucao_evidencia e WHERE e.linha_id = l.id) AS evidencias
        FROM boletim_execucao_linha l
       WHERE l.boletim_id = NEW.id AND l.situacao IN ('concluido', 'concluido_com_pendencia')) x
     WHERE x.evidencias < v_minimo LIMIT 1;
    IF v_ordem IS NOT NULL THEN
      RAISE EXCEPTION 'Linha marcada como concluída tem menos evidências que o mínimo do município (%)', v_minimo
        USING ERRCODE = 'check_violation';
    END IF;
    IF EXISTS (SELECT 1 FROM boletim_execucao_linha WHERE boletim_id = NEW.id AND verificado_em > NEW.periodo_fim) THEN
      RAISE EXCEPTION 'Linha com conclusão verificada depois do fim do período do boletim' USING ERRCODE = 'check_violation';
    END IF;
    NEW.emitido_por := v_usuario;
    NEW.emitido_em := now();
    NEW.cronograma_versao_id := (SELECT id FROM cronograma_versao WHERE contrato_id = NEW.contrato_id AND status = 'vigente');
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_boletim_guard BEFORE INSERT OR UPDATE OR DELETE ON boletim_execucao
  FOR EACH ROW EXECUTE FUNCTION fn_boletim_guard();

-- Linhas e evidências: só com o boletim em rascunho, pelo fiscal, sobre coisas do contrato.
CREATE FUNCTION fn_boletim_conteudo_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_bol    boletim_execucao%ROWTYPE;
  v_forma  forma_acompanhamento;
  v_ok     boolean;
BEGIN
  IF TG_TABLE_NAME = 'boletim_execucao_linha' THEN
    SELECT * INTO v_bol FROM boletim_execucao WHERE id = coalesce(NEW.boletim_id, OLD.boletim_id);
  ELSE
    SELECT b.* INTO v_bol FROM boletim_execucao b JOIN boletim_execucao_linha l ON l.boletim_id = b.id
     WHERE l.id = coalesce(NEW.linha_id, OLD.linha_id);
  END IF;
  -- o boletim em rascunho foi apagado e as linhas vão junto
  IF v_bol.id IS NULL AND TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  IF v_bol.status = 'emitido' THEN
    RAISE EXCEPTION 'Boletim de Execução nº % foi emitido e é imutável: a correção é um boletim retificador', v_bol.numero
      USING ERRCODE = 'check_violation';
  END IF;
  IF app_usuario() IS NULL OR NOT fn_fiscal_do_contrato(app_usuario(), v_bol.contrato_id, current_date) THEN
    RAISE EXCEPTION 'Boletim de Execução é do fiscal com designação vigente neste contrato' USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;

  IF TG_TABLE_NAME = 'boletim_execucao_linha' THEN
    SELECT forma_acompanhamento INTO v_forma FROM contrato WHERE id = v_bol.contrato_id;
    IF v_forma = 'eventos' THEN
      v_ok := NEW.evento_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM evento e JOIN revisao_orcamento r ON r.id = e.revisao_id
         WHERE e.id = NEW.evento_id AND r.contrato_id = v_bol.contrato_id AND r.status = 'vigente');
    ELSE
      v_ok := NEW.item_contratual_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM item_revisao ir JOIN revisao_orcamento r ON r.id = ir.revisao_id
         WHERE ir.item_contratual_id = NEW.item_contratual_id AND r.contrato_id = v_bol.contrato_id
           AND r.status = 'vigente' AND ir.tipo = 'servico');
    END IF;
    IF NOT v_ok THEN
      RAISE EXCEPTION 'A linha do boletim tem que ser de evento (contrato por eventos) ou de serviço (por quantidade) da planilha vigente deste contrato'
        USING ERRCODE = 'check_violation';
    END IF;
  ELSE
    v_ok := CASE NEW.tipo
      WHEN 'foto'     THEN EXISTS (SELECT 1 FROM foto WHERE id = NEW.ref_id AND contrato_id = v_bol.contrato_id)
      WHEN 'vistoria' THEN EXISTS (SELECT 1 FROM vistoria WHERE id = NEW.ref_id AND contrato_id = v_bol.contrato_id AND concluida_em IS NOT NULL)
      ELSE EXISTS (SELECT 1 FROM rdo WHERE id = NEW.ref_id AND contrato_id = v_bol.contrato_id AND status = 'validado') END;
    IF NOT v_ok THEN
      RAISE EXCEPTION 'Evidência tem que ser foto, vistoria concluída ou diário validado deste contrato' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_boletim_conteudo_guard BEFORE INSERT OR UPDATE OR DELETE ON boletim_execucao_linha
  FOR EACH ROW EXECUTE FUNCTION fn_boletim_conteudo_guard();
CREATE TRIGGER trg_boletim_conteudo_guard BEFORE INSERT OR UPDATE OR DELETE ON boletim_execucao_evidencia
  FOR EACH ROW EXECUTE FUNCTION fn_boletim_conteudo_guard();

-- O que a fiscalização diz de um evento: a linha do último boletim emitido que cita o par
-- agrupador × frente. Boletim que foi retificado sai da conta; vale o retificador.
CREATE FUNCTION fn_situacao_do_evento(p_evento uuid)
RETURNS TABLE (linha_id uuid, boletim_numero integer, situacao situacao_evento, verificado_em date)
LANGUAGE sql STABLE AS $$
  SELECT l.id, b.numero, l.situacao, l.verificado_em
    FROM evento alvo
    JOIN evento citado            ON citado.agrupador_id = alvo.agrupador_id AND citado.frente_id = alvo.frente_id
    JOIN boletim_execucao_linha l ON l.evento_id = citado.id
    JOIN boletim_execucao b       ON b.id = l.boletim_id AND b.status = 'emitido'
   WHERE alvo.id = p_evento
     AND NOT EXISTS (SELECT 1 FROM boletim_execucao r WHERE r.retifica_id = b.id AND r.status = 'emitido')
   ORDER BY b.numero DESC
   LIMIT 1
$$;

-- -----------------------------------------------------------------------------
-- 3. Glosa do evento inteiro
-- -----------------------------------------------------------------------------
CREATE TABLE medicao_evento_analise (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id          uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  medicao_evento_id  uuid NOT NULL UNIQUE REFERENCES medicao_evento ON DELETE CASCADE,
  decisao            text NOT NULL CHECK (decisao IN ('aceito', 'glosado')),
  motivo             text,
  usuario_id         uuid NOT NULL REFERENCES usuario,
  em                 timestamptz NOT NULL DEFAULT now(),
  CHECK (decisao <> 'glosado' OR nullif(btrim(motivo), '') IS NOT NULL)
);

-- Refaz as linhas de serviço da medição a partir dos eventos marcados e não glosados.
CREATE FUNCTION fn_regerar_linhas_de_evento(p_medicao uuid) RETURNS void LANGUAGE sql AS $$
  DELETE FROM medicao_item WHERE medicao_id = p_medicao AND origem = 'eventos';
  INSERT INTO medicao_item (tenant_id, medicao_id, item_contratual_id, quantidade, valor, origem)
  SELECT ir.tenant_id, p_medicao, ir.item_contratual_id, sum(f.quantidade), 0, 'eventos'
    FROM medicao_evento me
    JOIN evento e        ON e.id = me.evento_id
    JOIN item_revisao ir ON ir.revisao_id = e.revisao_id AND ir.agrupador_evento_id = e.agrupador_id
                        AND ir.tipo = 'servico'
    JOIN item_frente f   ON f.item_revisao_id = ir.id AND f.frente_id = e.frente_id
   WHERE me.medicao_id = p_medicao
     AND NOT EXISTS (SELECT 1 FROM medicao_evento_analise a WHERE a.medicao_evento_id = me.id AND a.decisao = 'glosado')
   GROUP BY ir.tenant_id, ir.item_contratual_id;
$$;

CREATE OR REPLACE FUNCTION fn_aplicar_eventos() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  PERFORM fn_regerar_linhas_de_evento(coalesce(NEW.medicao_id, OLD.medicao_id));
  RETURN NULL;
END $$;

-- A análise do evento é do fiscal, durante a análise da medição. Glosar ou desfazer a glosa
-- refaz as linhas de serviço.
CREATE FUNCTION fn_medicao_evento_analise_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_med medicao%ROWTYPE;
BEGIN
  SELECT m.* INTO v_med FROM medicao m JOIN medicao_evento me ON me.medicao_id = m.id
   WHERE me.id = coalesce(NEW.medicao_evento_id, OLD.medicao_evento_id);
  -- a empresa tirou o evento da medição devolvida: a análise dele vai junto
  IF TG_OP = 'DELETE' AND pg_trigger_depth() >= 2 THEN RETURN OLD; END IF;
  IF TG_OP = 'UPDATE' THEN
    RAISE EXCEPTION 'Análise de evento não se altera: desfaça e registre de novo' USING ERRCODE = 'check_violation';
  END IF;
  IF v_med.status <> 'em_analise' THEN
    RAISE EXCEPTION 'Evento só é aceito ou glosado com a medição em análise' USING ERRCODE = 'check_violation';
  END IF;
  IF app_usuario() IS NULL OR NOT fn_fiscal_do_contrato(app_usuario(), v_med.contrato_id, current_date) THEN
    RAISE EXCEPTION 'Só fiscal com designação vigente neste contrato aceita ou glosa evento' USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  NEW.usuario_id := app_usuario();
  NEW.em := now();
  RETURN NEW;
END $$;
CREATE FUNCTION fn_medicao_evento_analise_aplicar() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_medicao uuid;
BEGIN
  SELECT medicao_id INTO v_medicao FROM medicao_evento WHERE id = coalesce(NEW.medicao_evento_id, OLD.medicao_evento_id);
  IF v_medicao IS NOT NULL THEN
    PERFORM fn_regerar_linhas_de_evento(v_medicao);
  END IF;
  RETURN NULL;
END $$;
CREATE TRIGGER trg_medicao_evento_analise_guard BEFORE INSERT OR UPDATE OR DELETE ON medicao_evento_analise
  FOR EACH ROW EXECUTE FUNCTION fn_medicao_evento_analise_guard();
CREATE TRIGGER trg_medicao_evento_analise_aplicar AFTER INSERT OR DELETE ON medicao_evento_analise
  FOR EACH ROW EXECUTE FUNCTION fn_medicao_evento_analise_aplicar();

ALTER TABLE medicao ADD COLUMN valor_glosado numeric(18,2) NOT NULL DEFAULT 0 CHECK (valor_glosado >= 0);
COMMENT ON COLUMN medicao.valor_bruto IS 'Soma das linhas de serviço: o declarado, no envio; o aprovado (sem os eventos glosados), depois da aprovação do fiscal.';
COMMENT ON COLUMN medicao.valor_glosado IS 'Soma dos eventos glosados, gravada na aprovação do fiscal.';

-- A etapa aplica a nova situação e, na aprovação, grava quanto foi glosado.
CREATE OR REPLACE FUNCTION fn_medicao_etapa_aplicar() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  UPDATE medicao m
     SET status = NEW.para,
         valor_glosado = CASE WHEN NEW.para = 'aprovada_fiscal' THEN
             (SELECT coalesce(sum(e.valor), 0) FROM medicao_evento me
                JOIN evento e ON e.id = me.evento_id
                JOIN medicao_evento_analise a ON a.medicao_evento_id = me.id AND a.decisao = 'glosado'
               WHERE me.medicao_id = m.id)
           ELSE m.valor_glosado END
   WHERE m.id = NEW.medicao_id;
  RETURN NULL;
END $$;

-- O que a aprovação exige: agora também a conferência contra o Boletim de Execução.
CREATE OR REPLACE FUNCTION fn_medicao_pronta_para(p_medicao uuid, p_acao acao_medicao) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  v_fim     date;
  v_evento  text;
BEGIN
  IF p_acao = 'aprovar_fiscal' THEN
    IF EXISTS (SELECT 1 FROM medicao_glosa WHERE medicao_id = p_medicao) THEN
      RAISE EXCEPTION 'Medição com glosa por quantidade não é aprovada: devolva para a empresa corrigir a quantidade'
        USING ERRCODE = 'check_violation';
    END IF;
    -- Evento que não foi glosado tem que estar "concluído" no último boletim emitido que o
    -- cita, com verificação até o fim do período da medição. "Concluído com pendência" não libera.
    SELECT periodo_fim INTO v_fim FROM medicao WHERE id = p_medicao;
    SELECT a.titulo || ' × ' || f.nome INTO v_evento
      FROM medicao_evento me
      JOIN evento e           ON e.id = me.evento_id
      JOIN agrupador_evento a ON a.id = e.agrupador_id
      JOIN frente_obra f      ON f.id = e.frente_id
      LEFT JOIN LATERAL fn_situacao_do_evento(e.id) s ON true
     WHERE me.medicao_id = p_medicao
       AND NOT EXISTS (SELECT 1 FROM medicao_evento_analise x WHERE x.medicao_evento_id = me.id AND x.decisao = 'glosado')
       AND (s.situacao IS DISTINCT FROM 'concluido' OR s.verificado_em > v_fim)
     ORDER BY a.numero, f.ordem LIMIT 1;
    IF v_evento IS NOT NULL THEN
      RAISE EXCEPTION 'O evento "%" não tem Boletim de Execução emitido que o marque concluído até o fim do período: glose o evento ou devolva a medição', v_evento
        USING ERRCODE = 'check_violation';
    END IF;
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

-- Linhas de serviço: a empresa mexe em rascunho e em devolvida; durante a análise só o
-- banco refaz as linhas de evento, quando o fiscal glosa ou desfaz a glosa.
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
  IF NOT fn_medicao_editavel(v_med.status)
     AND NOT (v_med.status = 'em_analise' AND pg_trigger_depth() >= 2 AND coalesce(NEW.origem, OLD.origem) = 'eventos') THEN
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
    -- quantidade e valor vêm das frentes dos eventos marcados e não glosados nesta medição
    SELECT coalesce(sum(f.quantidade), 0),
           coalesce(sum(fn_valor_item(f.quantidade, v_item.preco_unitario, v_crit)), 0)
      INTO v_qtd_ev, NEW.valor
      FROM medicao_evento me
      JOIN evento e      ON e.id = me.evento_id
      JOIN item_frente f ON f.frente_id = e.frente_id AND f.item_revisao_id = v_item.id
     WHERE me.medicao_id = NEW.medicao_id AND e.agrupador_id = v_item.agrupador_evento_id
       AND NOT EXISTS (SELECT 1 FROM medicao_evento_analise a WHERE a.medicao_evento_id = me.id AND a.decisao = 'glosado');
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

-- Evento marcado em medição: o que já foi medido não entra de novo; o que foi glosado pode voltar.
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
                AND me.id <> NEW.id
                AND NOT EXISTS (SELECT 1 FROM medicao_evento_analise a
                                 WHERE a.medicao_evento_id = me.id AND a.decisao = 'glosado')) THEN
    RAISE EXCEPTION 'Evento já medido anteriormente' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['boletim_execucao', 'boletim_execucao_linha', 'boletim_execucao_evidencia', 'medicao_evento_analise', 'foto'] LOOP
    EXECUTE format('CREATE TRIGGER trg_auditoria AFTER INSERT OR UPDATE OR DELETE ON %I
                    FOR EACH ROW EXECUTE FUNCTION fn_auditar()', t);
  END LOOP;
END $$;

SELECT prumo_fechar_migracao();
REVOKE DELETE ON foto FROM app_rw;
