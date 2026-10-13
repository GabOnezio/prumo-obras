-- =============================================================================
-- Prumo · migração 0003 · fiscalização
--
-- Ordem de serviço, responsabilidade técnica, garantia do contrato, ocorrência, notificação,
-- plano de ação, vistoria, recebimento e garantia da obra.
--
-- Regra comum: ato da fiscalização é registrado em nome de quem está na sessão
-- (app.usuario_id) e só por quem tem designação vigente naquele contrato. O que foi emitido
-- não se reescreve.
--
-- Não está aqui: quem pode emitir ordem de serviço. Paralisar e retomar são do perfil
-- Gestor (docs/01), e perfil de usuário é da Fase 1; por ora o banco só exige que a sessão
-- diga quem é.
-- =============================================================================

-- Quem age: grava o usuário da sessão na coluna indicada e exige a designação.
--   TG_ARGV[0]  coluna que recebe o usuário
--   TG_ARGV[1]  'fiscal', 'comissao_recebimento' ou 'qualquer' (só exige usuário na sessão)
--   TG_ARGV[2]  o ato, para a mensagem
CREATE FUNCTION fn_ato_de_quem_esta_na_sessao() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_usuario uuid := app_usuario();
  v_pode boolean;
BEGIN
  IF v_usuario IS NULL THEN
    RAISE EXCEPTION 'A sessão não diz quem está agindo: não dá para %', TG_ARGV[2] USING ERRCODE = 'check_violation';
  END IF;
  NEW := jsonb_populate_record(NEW, jsonb_build_object(TG_ARGV[0], v_usuario));
  v_pode := CASE TG_ARGV[1]
    WHEN 'fiscal' THEN fn_fiscal_do_contrato(v_usuario, NEW.contrato_id, current_date)
    WHEN 'comissao_recebimento' THEN
      fn_designado(v_usuario, NEW.contrato_id, ARRAY['comissao_recebimento']::funcao_designacao[], current_date)
    ELSE true END;
  IF NOT v_pode THEN
    RAISE EXCEPTION 'Só quem tem designação vigente neste contrato (%) pode %', TG_ARGV[1], TG_ARGV[2]
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

-- Registro que não se altera nem se apaga. TG_ARGV[0] é o nome do registro, para a mensagem.
CREATE FUNCTION fn_imutavel() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION '% não se altera nem se apaga: correção é registro novo', TG_ARGV[0] USING ERRCODE = 'check_violation';
END $$;

-- -----------------------------------------------------------------------------
-- Ordem de serviço: início, paralisação e retomada
-- -----------------------------------------------------------------------------
CREATE TABLE ordem_servico (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  contrato_id  uuid NOT NULL REFERENCES contrato,
  tipo         text NOT NULL CHECK (tipo IN ('inicio', 'paralisacao', 'retomada')),
  data         date NOT NULL,
  motivo       text,
  emitida_por  uuid NOT NULL REFERENCES usuario,
  emitida_em   timestamptz NOT NULL DEFAULT now(),
  CHECK (tipo = 'inicio' OR nullif(btrim(motivo), '') IS NOT NULL)
);
CREATE INDEX ix_ordem_servico_contrato ON ordem_servico (contrato_id, data);

-- A sequência tem que fazer sentido, e a ordem muda a situação do contrato.
CREATE FUNCTION fn_ordem_servico_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_ultima record;
BEGIN
  SELECT tipo, data INTO v_ultima FROM ordem_servico
   WHERE contrato_id = NEW.contrato_id ORDER BY data DESC, emitida_em DESC LIMIT 1;
  IF (NEW.tipo = 'inicio' AND v_ultima.tipo IS NOT NULL)
     OR (NEW.tipo = 'paralisacao' AND v_ultima.tipo IS DISTINCT FROM 'inicio' AND v_ultima.tipo IS DISTINCT FROM 'retomada')
     OR (NEW.tipo = 'retomada' AND v_ultima.tipo IS DISTINCT FROM 'paralisacao') THEN
    RAISE EXCEPTION 'Ordem de "%" não cabe depois de "%"', NEW.tipo, coalesce(v_ultima.tipo, 'nenhuma ordem')
      USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.data < v_ultima.data THEN
    RAISE EXCEPTION 'Ordem de serviço com data anterior à da última ordem (%)', v_ultima.data USING ERRCODE = 'check_violation';
  END IF;
  UPDATE contrato
     SET status = CASE NEW.tipo WHEN 'paralisacao' THEN 'paralisado' ELSE 'em_execucao' END::status_contrato,
         data_inicio_obra = CASE WHEN NEW.tipo = 'inicio' THEN NEW.data ELSE data_inicio_obra END
   WHERE id = NEW.contrato_id;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_a_ordem_servico_quem BEFORE INSERT ON ordem_servico
  FOR EACH ROW EXECUTE FUNCTION fn_ato_de_quem_esta_na_sessao('emitida_por', 'qualquer', 'emitir ordem de serviço');
CREATE TRIGGER trg_b_ordem_servico_guard BEFORE INSERT ON ordem_servico
  FOR EACH ROW EXECUTE FUNCTION fn_ordem_servico_guard();
CREATE TRIGGER trg_ordem_servico_imutavel BEFORE UPDATE OR DELETE ON ordem_servico
  FOR EACH ROW EXECUTE FUNCTION fn_imutavel('Ordem de serviço');

-- -----------------------------------------------------------------------------
-- Responsabilidade técnica (ART ou RRT) e garantia do contrato
-- -----------------------------------------------------------------------------
CREATE TABLE responsabilidade_tecnica (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  contrato_id     uuid NOT NULL REFERENCES contrato,
  profissional    text NOT NULL,
  conselho        text NOT NULL,                 -- CREA, CAU...
  numero_art_rrt  text NOT NULL,
  arquivo_sha256  char(64),
  inicio          date NOT NULL,
  fim             date,
  CHECK (fim IS NULL OR fim >= inicio),
  UNIQUE (contrato_id, conselho, numero_art_rrt)
);

-- As modalidades de garantia vêm da lei e do edital; aqui o tipo é texto, sem lista fechada.
CREATE TABLE garantia_contratual (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  contrato_id     uuid NOT NULL REFERENCES contrato,
  tipo            text NOT NULL,
  valor           numeric(18,2) NOT NULL CHECK (valor > 0),
  inicio          date NOT NULL,
  fim             date NOT NULL,
  arquivo_sha256  char(64),
  CHECK (fim >= inicio)
);

-- -----------------------------------------------------------------------------
-- Ocorrência, notificação e plano de ação
-- -----------------------------------------------------------------------------
CREATE TABLE ocorrencia (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  contrato_id   uuid NOT NULL REFERENCES contrato,
  tipo          text NOT NULL,
  descricao     text NOT NULL CHECK (btrim(descricao) <> ''),
  status        text NOT NULL DEFAULT 'aberta' CHECK (status IN ('aberta', 'em_tratamento', 'resolvida', 'encerrada')),
  aberta_por    uuid NOT NULL REFERENCES usuario,
  aberta_em     timestamptz NOT NULL DEFAULT now(),
  encerrada_em  timestamptz,
  CHECK ((status = 'encerrada') = (encerrada_em IS NOT NULL))
);

-- O que foi registrado fica; só a situação anda, e para a frente.
CREATE FUNCTION fn_ocorrencia_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_ordem text[] := ARRAY['aberta', 'em_tratamento', 'resolvida', 'encerrada'];
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Ocorrência não se apaga' USING ERRCODE = 'check_violation';
  END IF;
  IF (NEW.contrato_id, NEW.tipo, NEW.descricao, NEW.aberta_por, NEW.aberta_em, NEW.tenant_id)
       IS DISTINCT FROM (OLD.contrato_id, OLD.tipo, OLD.descricao, OLD.aberta_por, OLD.aberta_em, OLD.tenant_id) THEN
    RAISE EXCEPTION 'O registro da ocorrência não se altera; só a situação' USING ERRCODE = 'check_violation';
  END IF;
  IF array_position(v_ordem, NEW.status) < array_position(v_ordem, OLD.status) THEN
    RAISE EXCEPTION 'Ocorrência "%" não volta para "%"', OLD.status, NEW.status USING ERRCODE = 'check_violation';
  END IF;
  IF NOT fn_fiscal_do_contrato(app_usuario(), NEW.contrato_id, current_date) THEN
    RAISE EXCEPTION 'Só fiscal com designação vigente neste contrato muda a situação da ocorrência' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_ocorrencia_quem BEFORE INSERT ON ocorrencia
  FOR EACH ROW EXECUTE FUNCTION fn_ato_de_quem_esta_na_sessao('aberta_por', 'fiscal', 'abrir ocorrência');
CREATE TRIGGER trg_ocorrencia_guard BEFORE UPDATE OR DELETE ON ocorrencia
  FOR EACH ROW EXECUTE FUNCTION fn_ocorrencia_guard();

CREATE TABLE notificacao (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id            uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  contrato_id          uuid NOT NULL REFERENCES contrato,
  ocorrencia_id        uuid REFERENCES ocorrencia,
  numero               integer NOT NULL CHECK (numero > 0),
  texto                text NOT NULL CHECK (btrim(texto) <> ''),
  -- o prazo vem do contrato ou da configuração do município: sem valor padrão
  prazo_resposta_dias  integer NOT NULL CHECK (prazo_resposta_dias > 0),
  emitida_por          uuid NOT NULL REFERENCES usuario,
  emitida_em           timestamptz NOT NULL DEFAULT now(),
  resposta             text,
  respondida_por       uuid REFERENCES usuario,
  respondida_em        timestamptz,
  UNIQUE (contrato_id, numero),
  CHECK ((resposta IS NULL) = (respondida_por IS NULL) AND (resposta IS NULL) = (respondida_em IS NULL))
);

-- Notificação emitida não muda. A empresa responde uma vez, e a resposta também não muda.
CREATE FUNCTION fn_notificacao_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Notificação não se apaga' USING ERRCODE = 'check_violation';
  END IF;
  IF (NEW.contrato_id, NEW.ocorrencia_id, NEW.numero, NEW.texto, NEW.prazo_resposta_dias, NEW.emitida_por, NEW.emitida_em, NEW.tenant_id)
       IS DISTINCT FROM (OLD.contrato_id, OLD.ocorrencia_id, OLD.numero, OLD.texto, OLD.prazo_resposta_dias, OLD.emitida_por, OLD.emitida_em, OLD.tenant_id)
     OR OLD.resposta IS NOT NULL THEN
    RAISE EXCEPTION 'Notificação emitida não se altera; a resposta é dada uma vez' USING ERRCODE = 'check_violation';
  END IF;
  IF nullif(btrim(NEW.resposta), '') IS NULL THEN
    RAISE EXCEPTION 'Resposta em branco' USING ERRCODE = 'check_violation';
  END IF;
  IF NOT fn_da_contratada(app_usuario(), NEW.contrato_id, current_date) THEN
    RAISE EXCEPTION 'Só a empresa contratada responde a notificação' USING ERRCODE = 'check_violation';
  END IF;
  NEW.respondida_por := app_usuario();
  NEW.respondida_em := now();
  RETURN NEW;
END $$;
CREATE TRIGGER trg_notificacao_quem BEFORE INSERT ON notificacao
  FOR EACH ROW EXECUTE FUNCTION fn_ato_de_quem_esta_na_sessao('emitida_por', 'fiscal', 'emitir notificação');
CREATE TRIGGER trg_notificacao_guard BEFORE UPDATE OR DELETE ON notificacao
  FOR EACH ROW EXECUTE FUNCTION fn_notificacao_guard();

CREATE TABLE plano_acao (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  ocorrencia_id  uuid NOT NULL REFERENCES ocorrencia,
  descricao      text NOT NULL,
  responsavel    text NOT NULL,
  prazo          date NOT NULL,
  status         text NOT NULL DEFAULT 'aberto' CHECK (status IN ('aberto', 'concluido', 'cancelado'))
);

-- -----------------------------------------------------------------------------
-- Vistoria
-- -----------------------------------------------------------------------------
CREATE TABLE vistoria (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  contrato_id   uuid NOT NULL REFERENCES contrato,
  data          date NOT NULL,
  checklist     jsonb NOT NULL DEFAULT '{}',
  observacao    text,
  feita_por     uuid NOT NULL REFERENCES usuario,
  criada_em     timestamptz NOT NULL DEFAULT now(),
  concluida_em  timestamptz
);

-- Enquanto não é concluída, só quem fez altera. Concluída, não muda mais.
CREATE FUNCTION fn_vistoria_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.concluida_em IS NOT NULL THEN
    RAISE EXCEPTION 'Vistoria concluída não se altera nem se apaga' USING ERRCODE = 'check_violation';
  END IF;
  IF OLD.feita_por IS DISTINCT FROM app_usuario() THEN
    RAISE EXCEPTION 'Só quem fez a vistoria pode alterá-la' USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'UPDATE' AND (NEW.contrato_id, NEW.feita_por, NEW.tenant_id) IS DISTINCT FROM (OLD.contrato_id, OLD.feita_por, OLD.tenant_id) THEN
    RAISE EXCEPTION 'Contrato e autor da vistoria não mudam' USING ERRCODE = 'check_violation';
  END IF;
  RETURN coalesce(NEW, OLD);
END $$;
CREATE TRIGGER trg_vistoria_quem BEFORE INSERT ON vistoria
  FOR EACH ROW EXECUTE FUNCTION fn_ato_de_quem_esta_na_sessao('feita_por', 'fiscal', 'registrar vistoria');
CREATE TRIGGER trg_vistoria_guard BEFORE UPDATE OR DELETE ON vistoria
  FOR EACH ROW EXECUTE FUNCTION fn_vistoria_guard();

-- -----------------------------------------------------------------------------
-- Recebimento provisório e definitivo; garantia da obra
-- -----------------------------------------------------------------------------
CREATE TABLE recebimento (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id            uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  contrato_id          uuid NOT NULL REFERENCES contrato,
  tipo                 text NOT NULL CHECK (tipo IN ('provisorio', 'definitivo')),
  data                 date NOT NULL,
  termo_arquivo_sha256 char(64) NOT NULL,
  pendencias           text,
  assinado_por         uuid NOT NULL REFERENCES usuario,
  registrado_em        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (contrato_id, tipo)
);

-- O provisório é do fiscal; o definitivo, da comissão de recebimento, e só depois do provisório.
CREATE FUNCTION fn_recebimento_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_usuario uuid := app_usuario();
  v_provisorio date;
BEGIN
  IF v_usuario IS NULL THEN
    RAISE EXCEPTION 'A sessão não diz quem está agindo: não dá para registrar recebimento' USING ERRCODE = 'check_violation';
  END IF;
  NEW.assinado_por := v_usuario;
  IF NEW.tipo = 'provisorio' THEN
    IF NOT fn_fiscal_do_contrato(v_usuario, NEW.contrato_id, current_date) THEN
      RAISE EXCEPTION 'Recebimento provisório é do fiscal com designação vigente neste contrato' USING ERRCODE = 'check_violation';
    END IF;
  ELSE
    IF NOT fn_designado(v_usuario, NEW.contrato_id, ARRAY['comissao_recebimento']::funcao_designacao[], current_date) THEN
      RAISE EXCEPTION 'Recebimento definitivo é da comissão de recebimento designada neste contrato' USING ERRCODE = 'check_violation';
    END IF;
    SELECT data INTO v_provisorio FROM recebimento WHERE contrato_id = NEW.contrato_id AND tipo = 'provisorio';
    IF v_provisorio IS NULL OR NEW.data < v_provisorio THEN
      RAISE EXCEPTION 'Recebimento definitivo só depois do provisório' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_recebimento_guard BEFORE INSERT ON recebimento
  FOR EACH ROW EXECUTE FUNCTION fn_recebimento_guard();
CREATE TRIGGER trg_recebimento_imutavel BEFORE UPDATE OR DELETE ON recebimento
  FOR EACH ROW EXECUTE FUNCTION fn_imutavel('Termo de recebimento');

-- TODO(jurídico): o mínimo de 5 anos vem de docs/07-conformidade.md (art. 140 §6º da
-- Lei 14.133/2021) e não foi conferido no texto oficial. O edital pode prever prazo maior.
CREATE TABLE garantia_obra (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  recebimento_id  uuid NOT NULL UNIQUE REFERENCES recebimento,
  prazo_anos      smallint NOT NULL CHECK (prazo_anos >= 5),
  inicio          date NOT NULL,
  vence_em        date NOT NULL,
  CHECK (vence_em = (inicio + make_interval(years => prazo_anos))::date)
);

CREATE FUNCTION fn_garantia_obra_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM recebimento r WHERE r.id = NEW.recebimento_id AND r.tipo = 'definitivo' AND r.data = NEW.inicio) THEN
    RAISE EXCEPTION 'A garantia da obra começa na data do recebimento definitivo' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_garantia_obra_guard BEFORE INSERT ON garantia_obra
  FOR EACH ROW EXECUTE FUNCTION fn_garantia_obra_guard();
CREATE TRIGGER trg_garantia_obra_imutavel BEFORE UPDATE OR DELETE ON garantia_obra
  FOR EACH ROW EXECUTE FUNCTION fn_imutavel('Garantia da obra');

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['ordem_servico', 'ocorrencia', 'notificacao', 'vistoria', 'recebimento', 'garantia_obra',
                           'garantia_contratual', 'responsabilidade_tecnica'] LOOP
    EXECUTE format('CREATE TRIGGER trg_auditoria AFTER INSERT OR UPDATE OR DELETE ON %I
                    FOR EACH ROW EXECUTE FUNCTION fn_auditar()', t);
  END LOOP;
END $$;

SELECT prumo_fechar_migracao();
