-- =============================================================================
-- Prumo · migração 0009 · serviço a mais, previsão, relatórios e fluxo do aditivo
--
-- 1. pleito e servico_extra: o apontamento de serviço a mais, da origem até o item do
--    aditivo. Só passa a "incluído em aditivo" com o item do aditivo correspondente
--    (invariante 14 de docs/10 §9).
-- 2. Aditivo: as transições passam a ser conferidas (rascunho → enviado → homologado ou
--    rejeitado), em nome de quem está na sessão; quem enviou não homologa; aditivo acima do
--    limite legal ou sem o parecer exigido não é homologado. Restabelecimento só devolve o
--    que foi suprimido antes (docs/plano-fase-0.md §10, achado 9).
-- 3. previsao_calculo e previsao_evento: a previsão calculada fica guardada, com o método e
--    o id do cálculo. Não é dado oficial: nenhuma tabela, função de regra ou visão oficial
--    lê daqui (invariante 10; db/tests/estrutura.sql confere).
-- 4. relatorio_emitido: o que foi emitido não muda (invariante 13, a parte do banco).
--    Relatório fotográfico só leva foto com vínculo confirmado por pessoa (invariante 12).
--
-- Quem pode homologar aditivo é o perfil Gestor (docs/01), e perfil de usuário é da Fase 1:
-- por ora o banco exige usuário na sessão e a segregação, não o perfil.
-- TODO(jurídico): o bloqueio de aditivo acima do limite não tem exceção (questão 40).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Pleito da empresa e serviço a mais
-- -----------------------------------------------------------------------------
CREATE TABLE pleito (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  contrato_id    uuid NOT NULL REFERENCES contrato,
  tipo           text NOT NULL CHECK (tipo IN ('servico_a_mais', 'prazo', 'reequilibrio', 'outro')),
  justificativa  text NOT NULL CHECK (btrim(justificativa) <> ''),
  status         text NOT NULL DEFAULT 'aberto' CHECK (status IN ('aberto', 'em_analise', 'deferido', 'indeferido')),
  aberto_por     uuid NOT NULL REFERENCES usuario,
  aberto_em      timestamptz NOT NULL DEFAULT now(),
  decidido_por   uuid REFERENCES usuario,
  decidido_em    timestamptz,
  motivo         text,
  CHECK ((status IN ('deferido', 'indeferido')) = (decidido_por IS NOT NULL)),
  CHECK (status <> 'indeferido' OR nullif(btrim(motivo), '') IS NOT NULL)
);

-- A empresa abre; a fiscalização ou o gestor do contrato decide. O pedido não se reescreve.
CREATE FUNCTION fn_pleito_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_usuario uuid := app_usuario();
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Pleito não se apaga' USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF v_usuario IS NULL OR NOT fn_da_contratada(v_usuario, NEW.contrato_id, current_date) THEN
      RAISE EXCEPTION 'Pleito é aberto pela empresa contratada deste contrato' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.status <> 'aberto' THEN
      RAISE EXCEPTION 'Pleito nasce aberto' USING ERRCODE = 'check_violation';
    END IF;
    NEW.aberto_por := v_usuario;
    NEW.aberto_em := now();
    RETURN NEW;
  END IF;
  IF (NEW.contrato_id, NEW.tipo, NEW.justificativa, NEW.aberto_por, NEW.aberto_em, NEW.tenant_id)
       IS DISTINCT FROM (OLD.contrato_id, OLD.tipo, OLD.justificativa, OLD.aberto_por, OLD.aberto_em, OLD.tenant_id) THEN
    RAISE EXCEPTION 'O pedido do pleito não se altera' USING ERRCODE = 'check_violation';
  END IF;
  IF OLD.status IN ('deferido', 'indeferido') THEN
    RAISE EXCEPTION 'Pleito já decidido não muda' USING ERRCODE = 'check_violation';
  END IF;
  IF v_usuario IS NULL OR NOT (fn_fiscal_do_contrato(v_usuario, NEW.contrato_id, current_date)
       OR fn_designado(v_usuario, NEW.contrato_id, ARRAY['gestor_contrato']::funcao_designacao[], current_date)) THEN
    RAISE EXCEPTION 'Só a fiscalização ou o gestor deste contrato analisa pleito' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.status IN ('deferido', 'indeferido') THEN
    NEW.decidido_por := v_usuario;
    NEW.decidido_em := now();
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_pleito_guard BEFORE INSERT OR UPDATE OR DELETE ON pleito
  FOR EACH ROW EXECUTE FUNCTION fn_pleito_guard();

-- Serviço executado, ou a executar, que não está na planilha ou passa da quantidade dela.
-- O apontamento não altera o contrato: só o aditivo homologado altera.
CREATE TABLE servico_extra (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id            uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  contrato_id          uuid NOT NULL REFERENCES contrato,
  origem               text NOT NULL CHECK (origem IN ('diario', 'vistoria', 'boletim_execucao', 'pleito')),
  origem_id            uuid NOT NULL,
  tipo                 text NOT NULL CHECK (tipo IN ('acrescimo', 'servico_novo')),
  item_contratual_id   uuid REFERENCES item_contratual,
  frente_id            uuid REFERENCES frente_obra,
  descricao            text NOT NULL CHECK (btrim(descricao) <> ''),
  unidade              text,
  quantidade_estimada  numeric(18,4) CHECK (quantidade_estimada > 0),
  status               text NOT NULL DEFAULT 'apontado'
                         CHECK (status IN ('apontado', 'em_analise', 'aceito', 'recusado', 'incluido_em_aditivo')),
  apontado_por         uuid NOT NULL REFERENCES usuario,
  apontado_em          timestamptz NOT NULL DEFAULT now(),
  decidido_por         uuid REFERENCES usuario,
  decidido_em          timestamptz,
  motivo               text,
  aditivo_item_id      uuid REFERENCES aditivo_item,
  -- acréscimo é sobre item que existe; serviço novo ainda não tem item
  CHECK ((tipo = 'acrescimo') = (item_contratual_id IS NOT NULL)),
  -- só é "incluído em aditivo" com o item do aditivo, e vice-versa
  CHECK ((status = 'incluido_em_aditivo') = (aditivo_item_id IS NOT NULL)),
  CHECK ((status IN ('aceito', 'recusado', 'incluido_em_aditivo')) = (decidido_por IS NOT NULL)),
  CHECK (status <> 'recusado' OR nullif(btrim(motivo), '') IS NOT NULL)
);

CREATE FUNCTION fn_servico_extra_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_usuario  uuid := app_usuario();
  v_existe   boolean;
  v_item     aditivo_item%ROWTYPE;
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Apontamento de serviço a mais não se apaga: recuse, com o motivo' USING ERRCODE = 'check_violation';
  END IF;
  IF v_usuario IS NULL OR NOT (fn_fiscal_do_contrato(v_usuario, NEW.contrato_id, current_date)
       OR fn_designado(v_usuario, NEW.contrato_id, ARRAY['gestor_contrato']::funcao_designacao[], current_date)) THEN
    RAISE EXCEPTION 'Só a fiscalização ou o gestor deste contrato aponta e analisa serviço a mais' USING ERRCODE = 'check_violation';
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'apontado' THEN
      RAISE EXCEPTION 'Serviço a mais nasce como apontado' USING ERRCODE = 'check_violation';
    END IF;
    NEW.apontado_por := v_usuario;
    NEW.apontado_em := now();
    v_existe := CASE NEW.origem
      WHEN 'diario'           THEN EXISTS (SELECT 1 FROM rdo WHERE id = NEW.origem_id AND contrato_id = NEW.contrato_id)
      WHEN 'vistoria'         THEN EXISTS (SELECT 1 FROM vistoria WHERE id = NEW.origem_id AND contrato_id = NEW.contrato_id)
      WHEN 'boletim_execucao' THEN EXISTS (SELECT 1 FROM boletim_execucao WHERE id = NEW.origem_id AND contrato_id = NEW.contrato_id)
      ELSE EXISTS (SELECT 1 FROM pleito WHERE id = NEW.origem_id AND contrato_id = NEW.contrato_id) END;
    IF NOT v_existe THEN
      RAISE EXCEPTION 'A origem do apontamento não é % deste contrato', NEW.origem USING ERRCODE = 'check_violation';
    END IF;
    IF (NEW.item_contratual_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM item_contratual WHERE id = NEW.item_contratual_id AND contrato_id = NEW.contrato_id))
       OR (NEW.frente_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM frente_obra WHERE id = NEW.frente_id AND contrato_id = NEW.contrato_id)) THEN
      RAISE EXCEPTION 'Item e frente do apontamento têm que ser deste contrato' USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;

  IF (to_jsonb(NEW) - ARRAY['status', 'decidido_por', 'decidido_em', 'motivo', 'aditivo_item_id'])
       IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['status', 'decidido_por', 'decidido_em', 'motivo', 'aditivo_item_id']) THEN
    RAISE EXCEPTION 'O que foi apontado não se altera; só a situação anda' USING ERRCODE = 'check_violation';
  END IF;
  IF NOT ((OLD.status, NEW.status) IN (('apontado', 'em_analise'), ('apontado', 'aceito'), ('apontado', 'recusado'),
                                       ('em_analise', 'aceito'), ('em_analise', 'recusado'),
                                       ('aceito', 'incluido_em_aditivo'))) THEN
    RAISE EXCEPTION 'Serviço a mais "%" não passa a "%"', OLD.status, NEW.status USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.status IN ('aceito', 'recusado') THEN
    NEW.decidido_por := v_usuario;
    NEW.decidido_em := now();
  END IF;
  IF NEW.status = 'incluido_em_aditivo' THEN
    -- o item do aditivo tem que ser deste contrato e corresponder ao apontamento
    SELECT ai.* INTO v_item FROM aditivo_item ai JOIN aditivo a ON a.id = ai.aditivo_id
     WHERE ai.id = NEW.aditivo_item_id AND a.contrato_id = NEW.contrato_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'O item de aditivo informado não é deste contrato' USING ERRCODE = 'check_violation';
    END IF;
    IF (NEW.tipo = 'acrescimo' AND (v_item.operacao NOT IN ('acrescimo', 'restabelecimento') OR v_item.item_contratual_id <> NEW.item_contratual_id))
       OR (NEW.tipo = 'servico_novo' AND v_item.operacao <> 'inclusao') THEN
      RAISE EXCEPTION 'O item de aditivo não corresponde ao apontamento (% em vez de %)', v_item.operacao, NEW.tipo
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_servico_extra_guard BEFORE INSERT OR UPDATE OR DELETE ON servico_extra
  FOR EACH ROW EXECUTE FUNCTION fn_servico_extra_guard();

-- -----------------------------------------------------------------------------
-- 2. Aditivo: transições, segregação, limite, parecer e restabelecimento
-- -----------------------------------------------------------------------------
ALTER TABLE aditivo ADD COLUMN enviado_por uuid REFERENCES usuario;
ALTER TABLE aditivo ADD COLUMN decidido_por uuid REFERENCES usuario;
ALTER TABLE aditivo ADD COLUMN motivo_rejeicao text;
ALTER TABLE aditivo ADD COLUMN parecer_sha256 char(64) CHECK (parecer_sha256 ~ '^[0-9a-f]{64}$');

-- As mesmas transições de crates/dominio::fluxo::aditivo.
CREATE FUNCTION fn_transicao_aditivo(p_de status_aditivo, p_para status_aditivo) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
  SELECT (p_de, p_para) IN (('rascunho', 'enviado'), ('enviado', 'homologado'), ('enviado', 'rejeitado'))
$$;

CREATE OR REPLACE FUNCTION fn_aditivo_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_usuario  uuid := app_usuario();
  v_parecer  boolean;
BEGIN
  IF OLD.status IN ('homologado', 'rejeitado') THEN
    RAISE EXCEPTION 'Aditivo nº % está "%" e é imutável', OLD.numero, OLD.status USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'DELETE' THEN
    IF OLD.status <> 'rascunho' THEN
      RAISE EXCEPTION 'Aditivo nº % já foi enviado e não se apaga', OLD.numero USING ERRCODE = 'check_violation';
    END IF;
    RETURN OLD;
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NOT fn_transicao_aditivo(OLD.status, NEW.status) THEN
      RAISE EXCEPTION 'Aditivo nº % em "%" não passa a "%"', OLD.numero, OLD.status, NEW.status USING ERRCODE = 'check_violation';
    END IF;
    IF v_usuario IS NULL THEN
      RAISE EXCEPTION 'A sessão não diz quem está agindo: o aditivo não muda de situação' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.status = 'enviado' THEN
      NEW.enviado_por := v_usuario;
    ELSE
      NEW.decidido_por := v_usuario;
    END IF;
    IF NEW.status = 'rejeitado' AND nullif(btrim(NEW.motivo_rejeicao), '') IS NULL THEN
      RAISE EXCEPTION 'Rejeitar o aditivo exige o motivo por escrito' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.status = 'homologado' THEN
      IF v_usuario = OLD.enviado_por THEN
        RAISE EXCEPTION 'Quem enviou o aditivo não pode homologá-lo' USING ERRCODE = 'check_violation';
      END IF;
      -- TODO(jurídico): limite sem exceção (questão 40)
      IF (SELECT situacao FROM fn_limites_aditivos(NEW.contrato_id, NEW.id)) = 'EXCEDE LIMITE LEGAL' THEN
        RAISE EXCEPTION 'Aditivo nº % passa do limite legal de acréscimos ou de supressões e não é homologado', OLD.numero
          USING ERRCODE = 'check_violation';
      END IF;
      SELECT parecer_aditivo_exigido INTO v_parecer FROM config_municipio WHERE tenant_id = app_tenant();
      IF v_parecer IS NULL THEN
        RAISE EXCEPTION 'Configuração do município ausente: se o aditivo exige parecer' USING ERRCODE = 'check_violation';
      END IF;
      IF v_parecer AND NEW.parecer_sha256 IS NULL THEN
        RAISE EXCEPTION 'Aditivo nº % está sem o parecer do controle interno ou do jurídico', OLD.numero USING ERRCODE = 'check_violation';
      END IF;
    END IF;
  ELSIF OLD.status = 'enviado'
        AND (to_jsonb(NEW) - ARRAY['parecer_sha256', 'data_assinatura', 'revisao_resultante_id', 'homologado_em', 'motivo_rejeicao'])
            IS DISTINCT FROM
            (to_jsonb(OLD) - ARRAY['parecer_sha256', 'data_assinatura', 'revisao_resultante_id', 'homologado_em', 'motivo_rejeicao']) THEN
    RAISE EXCEPTION 'Aditivo nº % já foi enviado: só o parecer e os dados da assinatura são acrescentados', OLD.numero
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

-- aditivo_item: como na referência, mais a conferência do restabelecimento
CREATE OR REPLACE FUNCTION fn_aditivo_item_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_ad         aditivo%ROWTYPE;
  v_ctr        contrato%ROWTYPE;
  v_base       item_revisao%ROWTYPE;
  v_suprimido  numeric;
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
    IF NEW.operacao = 'restabelecimento' THEN
      -- só se devolve o que aditivos homologados suprimiram e ainda não foi devolvido.
      -- Sem isso, um acréscimo lançado como restabelecimento ficaria fora do limite legal.
      SELECT coalesce(-sum(ai.quantidade_delta) FILTER (WHERE ai.operacao = 'supressao'), 0)
             - coalesce(sum(ai.quantidade_delta) FILTER (WHERE ai.operacao = 'restabelecimento'), 0)
        INTO v_suprimido
        FROM aditivo_item ai JOIN aditivo a ON a.id = ai.aditivo_id
       WHERE a.contrato_id = v_ad.contrato_id AND a.status = 'homologado'
         AND ai.item_contratual_id = NEW.item_contratual_id;
      IF NEW.quantidade_delta > v_suprimido THEN
        RAISE EXCEPTION 'Item %: só há % suprimidos para restabelecer', v_base.codigo_eap, v_suprimido
          USING ERRCODE = 'check_violation';
      END IF;
    END IF;
  END IF;
  NEW.valor_delta := fn_valor_item(NEW.quantidade_delta, NEW.preco_unitario, v_ctr.criterio_arredondamento);
  RETURN NEW;
END $$;

-- -----------------------------------------------------------------------------
-- 3. Previsão: guardada para consulta e auditoria, fora dos dados oficiais
-- -----------------------------------------------------------------------------
CREATE TABLE previsao_calculo (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id             uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  contrato_id           uuid NOT NULL REFERENCES contrato,
  calculado_em          timestamptz NOT NULL DEFAULT now(),
  versao_algoritmo      text NOT NULL,
  cronograma_versao_id  uuid NOT NULL REFERENCES cronograma_versao,
  boletim_execucao_id   uuid REFERENCES boletim_execucao,      -- vazio: ainda sem boletim emitido
  parametros            jsonb NOT NULL,                        -- prazos e limiares usados no cálculo
  fator_ritmo           numeric(6,4),
  termino_previsto      date,
  desvio_dias           integer
);

CREATE TABLE previsao_evento (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id             uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  calculo_id            uuid NOT NULL REFERENCES previsao_calculo,
  evento_id             uuid NOT NULL REFERENCES evento,
  inicio_previsto       date,
  termino_previsto      date NOT NULL,
  metodo                text NOT NULL CHECK (metodo IN ('real', 'ritmo', 'linha_de_base_ajustada')),
  medicao_prevista_em   date,
  pagamento_previsto_em date,
  valor_bruto           numeric(18,2),
  retencoes             numeric(18,2),
  valor_liquido         numeric(18,2),
  UNIQUE (calculo_id, evento_id)
);
-- Cada cálculo é uma fotografia: novo cálculo é linha nova, e as antigas não mudam.
CREATE TRIGGER trg_previsao_calculo_imutavel BEFORE UPDATE OR DELETE ON previsao_calculo
  FOR EACH ROW EXECUTE FUNCTION fn_imutavel('Cálculo de previsão');
CREATE TRIGGER trg_previsao_evento_imutavel BEFORE UPDATE OR DELETE ON previsao_evento
  FOR EACH ROW EXECUTE FUNCTION fn_imutavel('Previsão de evento');

-- -----------------------------------------------------------------------------
-- 4. Relatório emitido
-- -----------------------------------------------------------------------------
CREATE TABLE relatorio_emitido (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  contrato_id     uuid NOT NULL REFERENCES contrato,
  tipo            text NOT NULL CHECK (tipo IN ('boletim_execucao', 'planilha_medicao', 'relatorio_fotografico',
                                                'caderno_medicao', 'planilha_aditivo', 'previsao', 'rdo')),
  numero          integer NOT NULL CHECK (numero > 0),
  versao_modelo   text NOT NULL,
  arquivo_sha256  char(64) NOT NULL CHECK (arquivo_sha256 ~ '^[0-9a-f]{64}$'),
  chave_arquivo   text NOT NULL,
  -- de que registros o relatório saiu, para poder refazê-lo com os mesmos números
  origem          jsonb NOT NULL CHECK (jsonb_typeof(origem) = 'object'),
  substitui_id    uuid UNIQUE REFERENCES relatorio_emitido,
  emitido_por     uuid NOT NULL REFERENCES usuario,
  emitido_em      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (contrato_id, tipo, numero)
);

CREATE FUNCTION fn_relatorio_emitido_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_foto text;
BEGIN
  IF app_usuario() IS NULL THEN
    RAISE EXCEPTION 'A sessão não diz quem está agindo: relatório tem emissor' USING ERRCODE = 'check_violation';
  END IF;
  NEW.emitido_por := app_usuario();
  NEW.emitido_em := now();
  IF NEW.substitui_id IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM relatorio_emitido WHERE id = NEW.substitui_id AND contrato_id = NEW.contrato_id AND tipo = NEW.tipo) THEN
    RAISE EXCEPTION 'Só se substitui relatório do mesmo contrato e do mesmo tipo' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.tipo = 'relatorio_fotografico' THEN
    IF jsonb_typeof(NEW.origem -> 'fotos') IS DISTINCT FROM 'array' OR jsonb_array_length(NEW.origem -> 'fotos') = 0 THEN
      RAISE EXCEPTION 'Relatório fotográfico tem que listar as fotos em origem.fotos' USING ERRCODE = 'check_violation';
    END IF;
    -- só foto deste contrato com vínculo confirmado por pessoa (a tabela foto já garante câmera e hash)
    SELECT x.id INTO v_foto
      FROM jsonb_array_elements_text(NEW.origem -> 'fotos') AS x(id)
     WHERE NOT EXISTS (SELECT 1 FROM foto f WHERE f.id::text = x.id AND f.contrato_id = NEW.contrato_id
                          AND f.vinculo_confirmado_por IS NOT NULL)
     LIMIT 1;
    IF v_foto IS NOT NULL THEN
      RAISE EXCEPTION 'A foto % não é deste contrato ou não tem vínculo confirmado por pessoa: não entra em relatório fotográfico', v_foto
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_relatorio_emitido_guard BEFORE INSERT ON relatorio_emitido
  FOR EACH ROW EXECUTE FUNCTION fn_relatorio_emitido_guard();
CREATE TRIGGER trg_relatorio_emitido_imutavel BEFORE UPDATE OR DELETE ON relatorio_emitido
  FOR EACH ROW EXECUTE FUNCTION fn_imutavel('Relatório emitido');

-- Foto que entrou em relatório emitido não troca mais de vínculo: o relatório tem que
-- poder ser refeito com os mesmos registros.
CREATE FUNCTION fn_foto_em_relatorio_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF (NEW.item_contratual_id, NEW.frente_id, NEW.evento_id, NEW.vinculo_origem, NEW.legenda)
       IS DISTINCT FROM (OLD.item_contratual_id, OLD.frente_id, OLD.evento_id, OLD.vinculo_origem, OLD.legenda)
     AND EXISTS (SELECT 1 FROM relatorio_emitido r WHERE r.contrato_id = OLD.contrato_id
                    AND r.origem -> 'fotos' ? OLD.id::text) THEN
    RAISE EXCEPTION 'A foto já está em relatório emitido: legenda e vínculo não mudam mais' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_a_foto_em_relatorio_guard BEFORE UPDATE ON foto
  FOR EACH ROW EXECUTE FUNCTION fn_foto_em_relatorio_guard();

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['pleito', 'servico_extra', 'relatorio_emitido'] LOOP
    EXECUTE format('CREATE TRIGGER trg_auditoria AFTER INSERT OR UPDATE OR DELETE ON %I
                    FOR EACH ROW EXECUTE FUNCTION fn_auditar()', t);
  END LOOP;
END $$;

SELECT prumo_fechar_migracao();
REVOKE UPDATE, DELETE ON previsao_calculo, previsao_evento, relatorio_emitido FROM app_rw;
REVOKE DELETE ON pleito, servico_extra FROM app_rw;
