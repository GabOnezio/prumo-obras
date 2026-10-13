-- =============================================================================
-- Prumo · migração 0007 · documentos do órgão, cronograma com versões e travas do contrato
--
-- 1. O que o órgão fornece: documento_orgao (planilha, cronograma, eventograma, projeto,
--    memorial), prancha e o vínculo da prancha com a planilha.
-- 2. Cronograma com datas e versões: linha de base imutável, reprogramação como versão nova
--    com motivo e autor, calendário da obra. Ao ficar vigente, o cronograma tem que cobrir a
--    planilha inteira (invariantes 8 e 9 de docs/10 §9).
-- 3. Travas que a referência não tinha (docs/plano-fase-0.md §10):
--    - a forma de medir não muda depois de a planilha ficar vigente nem depois da primeira
--      medição enviada (invariante 7);
--    - valor inicial, orçamento-base, critério de arredondamento, casas do preço e marca de
--      reforma do contrato não mudam depois de a planilha ficar vigente (questão 38);
--    - frente e agrupador não são renomeados nem apagados depois de virarem evento de
--      planilha vigente (questão 37);
--    - evento é sempre calculado: não se cria, altera nem apaga à mão.
-- A forma de medir deixa de ter valor padrão: é escolhida no cadastro do contrato.
-- A troca de "ple" por "eventos" já foi feita na 0004.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Travas do contrato, das frentes, dos agrupadores e dos eventos
-- -----------------------------------------------------------------------------
ALTER TABLE contrato ALTER COLUMN forma_acompanhamento DROP DEFAULT;

CREATE FUNCTION fn_contrato_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_publicada boolean;
BEGIN
  v_publicada := EXISTS (SELECT 1 FROM revisao_orcamento WHERE contrato_id = OLD.id AND status <> 'rascunho');
  IF v_publicada AND (NEW.valor_inicial, NEW.valor_orcamento_base, NEW.criterio_arredondamento, NEW.casas_decimais_preco, NEW.reforma)
       IS DISTINCT FROM (OLD.valor_inicial, OLD.valor_orcamento_base, OLD.criterio_arredondamento, OLD.casas_decimais_preco, OLD.reforma) THEN
    RAISE EXCEPTION 'Contrato %: valor, orçamento-base, critério de arredondamento, casas do preço e marca de reforma não mudam depois de a planilha ficar vigente',
      OLD.numero USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.forma_acompanhamento IS DISTINCT FROM OLD.forma_acompanhamento
     AND (v_publicada OR EXISTS (SELECT 1 FROM medicao m JOIN medicao_etapa e ON e.medicao_id = m.id
                                  WHERE m.contrato_id = OLD.id AND e.acao = 'enviar')) THEN
    RAISE EXCEPTION 'Contrato %: a forma de medir não muda depois de a planilha ficar vigente nem depois da primeira medição enviada',
      OLD.numero USING ERRCODE = 'check_violation';
  END IF;
  IF (NEW.tenant_id, NEW.obra_id, NEW.orgao_id) IS DISTINCT FROM (OLD.tenant_id, OLD.obra_id, OLD.orgao_id) THEN
    RAISE EXCEPTION 'Contrato %: município, obra e órgão não mudam', OLD.numero USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_contrato_guard BEFORE UPDATE ON contrato
  FOR EACH ROW EXECUTE FUNCTION fn_contrato_guard();

-- Evento = agrupador × frente. Depois de virar evento de planilha vigente, o nome é parte
-- do que boletins e medições dizem: não muda.
CREATE FUNCTION fn_frente_ou_agrupador_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_em_uso boolean;
BEGIN
  IF TG_TABLE_NAME = 'frente_obra' THEN
    v_em_uso := EXISTS (SELECT 1 FROM evento e JOIN revisao_orcamento r ON r.id = e.revisao_id
                         WHERE e.frente_id = OLD.id AND r.status <> 'rascunho');
  ELSE
    v_em_uso := EXISTS (SELECT 1 FROM evento e JOIN revisao_orcamento r ON r.id = e.revisao_id
                         WHERE e.agrupador_id = OLD.id AND r.status <> 'rascunho');
  END IF;
  IF v_em_uso THEN
    RAISE EXCEPTION '% já faz parte de evento de planilha vigente: não muda nem se apaga',
      CASE TG_TABLE_NAME WHEN 'frente_obra' THEN 'A frente' ELSE 'O agrupador' END USING ERRCODE = 'check_violation';
  END IF;
  RETURN coalesce(NEW, OLD);
END $$;
CREATE TRIGGER trg_frente_guard BEFORE UPDATE OR DELETE ON frente_obra
  FOR EACH ROW EXECUTE FUNCTION fn_frente_ou_agrupador_guard();
CREATE TRIGGER trg_agrupador_guard BEFORE UPDATE OR DELETE ON agrupador_evento
  FOR EACH ROW EXECUTE FUNCTION fn_frente_ou_agrupador_guard();

-- Evento só nasce do cálculo feito ao publicar a planilha (fn_recalcular_eventos, chamada
-- pelo gatilho da revisão). À mão só se reprograma o período previsto.
CREATE OR REPLACE FUNCTION fn_evento_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_status status_revisao;
BEGIN
  IF TG_OP = 'UPDATE' AND (NEW.valor, NEW.agrupador_id, NEW.frente_id, NEW.revisao_id, NEW.tenant_id)
       IS NOT DISTINCT FROM (OLD.valor, OLD.agrupador_id, OLD.frente_id, OLD.revisao_id, OLD.tenant_id) THEN
    RETURN NEW;
  END IF;
  IF pg_trigger_depth() < 2 THEN
    RAISE EXCEPTION 'Evento é calculado pelo sistema ao publicar a planilha: não se cria, altera nem apaga à mão'
      USING ERRCODE = 'check_violation';
  END IF;
  SELECT status INTO v_status FROM revisao_orcamento WHERE id = coalesce(NEW.revisao_id, OLD.revisao_id);
  IF v_status <> 'rascunho' THEN
    RAISE EXCEPTION 'Eventos de revisão % só têm o período previsto alterável', v_status USING ERRCODE = 'check_violation';
  END IF;
  RETURN coalesce(NEW, OLD);
END $$;

-- -----------------------------------------------------------------------------
-- 2. O que o órgão fornece
-- -----------------------------------------------------------------------------
-- O arquivo original é prova: fica guardado pelo hash e o registro não se altera.
CREATE TABLE documento_orgao (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  contrato_id     uuid NOT NULL REFERENCES contrato,
  tipo            text NOT NULL CHECK (tipo IN ('planilha', 'cronograma', 'eventograma', 'projeto', 'memorial', 'outro')),
  nome            text NOT NULL CHECK (btrim(nome) <> ''),
  arquivo_sha256  char(64) NOT NULL CHECK (arquivo_sha256 ~ '^[0-9a-f]{64}$'),
  chave_arquivo   text NOT NULL,
  recebido_em     date NOT NULL,
  importacao_id   uuid REFERENCES importacao,
  enviado_por     uuid NOT NULL REFERENCES usuario,
  registrado_em   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (contrato_id, arquivo_sha256)
);
CREATE TRIGGER trg_documento_orgao_quem BEFORE INSERT ON documento_orgao
  FOR EACH ROW EXECUTE FUNCTION fn_ato_de_quem_esta_na_sessao('enviado_por', 'qualquer', 'registrar documento do órgão');
CREATE TRIGGER trg_documento_orgao_imutavel BEFORE UPDATE OR DELETE ON documento_orgao
  FOR EACH ROW EXECUTE FUNCTION fn_imutavel('Documento do órgão');

-- Folha de projeto. Os dados vêm do carimbo, lidos por código; quantidade nunca sai do desenho.
CREATE TABLE prancha (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  documento_id  uuid NOT NULL REFERENCES documento_orgao,
  numero        text NOT NULL,
  titulo        text,
  disciplina    text,
  revisao       text NOT NULL DEFAULT '0',
  escala        text,
  data          date,
  pagina        integer CHECK (pagina > 0),
  UNIQUE (documento_id, numero, revisao)
);

-- Ligação da prancha com a planilha. Sugestão de IA só entra depois de aceita por pessoa.
CREATE TABLE prancha_vinculo (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  prancha_id      uuid NOT NULL REFERENCES prancha ON DELETE CASCADE,
  alvo            text NOT NULL CHECK (alvo IN ('grupo_eap', 'frente', 'agrupador')),
  alvo_id         uuid NOT NULL,
  origem          text NOT NULL CHECK (origem IN ('manual', 'sugestao_aceita')),
  confirmado_por  uuid NOT NULL REFERENCES usuario,
  criado_em       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (prancha_id, alvo, alvo_id)
);
CREATE FUNCTION fn_prancha_vinculo_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_contrato uuid; v_existe boolean;
BEGIN
  IF app_usuario() IS NULL THEN
    RAISE EXCEPTION 'Vínculo de prancha é confirmado por uma pessoa identificada na sessão' USING ERRCODE = 'check_violation';
  END IF;
  NEW.confirmado_por := app_usuario();
  SELECT d.contrato_id INTO v_contrato FROM prancha p JOIN documento_orgao d ON d.id = p.documento_id WHERE p.id = NEW.prancha_id;
  v_existe := CASE NEW.alvo
    WHEN 'frente'    THEN EXISTS (SELECT 1 FROM frente_obra WHERE id = NEW.alvo_id AND contrato_id = v_contrato)
    WHEN 'agrupador' THEN EXISTS (SELECT 1 FROM agrupador_evento WHERE id = NEW.alvo_id AND contrato_id = v_contrato)
    ELSE EXISTS (SELECT 1 FROM item_contratual ic JOIN item_revisao ir ON ir.item_contratual_id = ic.id
                  WHERE ic.id = NEW.alvo_id AND ic.contrato_id = v_contrato AND ir.tipo = 'grupo') END;
  IF NOT v_existe THEN
    RAISE EXCEPTION 'O alvo do vínculo não é % deste contrato', NEW.alvo USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_prancha_vinculo_guard BEFORE INSERT OR UPDATE ON prancha_vinculo
  FOR EACH ROW EXECUTE FUNCTION fn_prancha_vinculo_guard();

-- -----------------------------------------------------------------------------
-- 3. Cronograma com datas e versões
-- -----------------------------------------------------------------------------
CREATE TABLE cronograma_versao (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  contrato_id   uuid NOT NULL REFERENCES contrato,
  revisao_id    uuid NOT NULL,
  numero        smallint NOT NULL CHECK (numero >= 0),      -- 0 = linha de base
  tipo          text NOT NULL CHECK (tipo IN ('linha_de_base', 'reprogramacao')),
  status        text NOT NULL DEFAULT 'rascunho' CHECK (status IN ('rascunho', 'vigente', 'substituida')),
  documento_id  uuid REFERENCES documento_orgao,
  aditivo_id    uuid REFERENCES aditivo,
  motivo        text,
  autor         uuid NOT NULL REFERENCES usuario,
  criado_em     timestamptz NOT NULL DEFAULT now(),
  vigente_em    timestamptz,
  UNIQUE (contrato_id, numero),
  FOREIGN KEY (contrato_id, revisao_id) REFERENCES revisao_orcamento (contrato_id, id),
  CHECK ((numero = 0) = (tipo = 'linha_de_base')),
  CHECK (tipo = 'linha_de_base' OR nullif(btrim(motivo), '') IS NOT NULL)
);
-- uma versão vigente por contrato
CREATE UNIQUE INDEX ux_cronograma_vigente ON cronograma_versao (contrato_id) WHERE status = 'vigente';

CREATE TABLE cronograma_evento (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id             uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  cronograma_versao_id  uuid NOT NULL REFERENCES cronograma_versao ON DELETE CASCADE,
  evento_id             uuid NOT NULL REFERENCES evento,
  inicio_previsto       date NOT NULL,
  termino_previsto      date NOT NULL,
  UNIQUE (cronograma_versao_id, evento_id),
  CHECK (termino_previsto >= inicio_previsto)
);

CREATE TABLE cronograma_predecessora (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id               uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  cronograma_versao_id    uuid NOT NULL REFERENCES cronograma_versao ON DELETE CASCADE,
  evento_id               uuid NOT NULL REFERENCES evento,
  predecessora_evento_id  uuid NOT NULL REFERENCES evento,
  UNIQUE (cronograma_versao_id, evento_id, predecessora_evento_id),
  CHECK (evento_id <> predecessora_evento_id)
);

-- O cronograma por quantidade (percentual de cada grupo por período) passa a ser de uma versão.
ALTER TABLE cronograma_parcela ADD COLUMN cronograma_versao_id uuid NOT NULL REFERENCES cronograma_versao ON DELETE CASCADE;
ALTER TABLE cronograma_parcela DROP CONSTRAINT cronograma_parcela_revisao_id_item_contratual_id_periodo_key;
ALTER TABLE cronograma_parcela ADD UNIQUE (cronograma_versao_id, item_contratual_id, periodo);

-- Dias sem trabalho por decisão (feriado, ponto facultativo). Chuva vem do diário validado.
CREATE TABLE calendario_obra (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  contrato_id  uuid NOT NULL REFERENCES contrato,
  data         date NOT NULL,
  trabalhavel  boolean NOT NULL,
  motivo       text NOT NULL CHECK (btrim(motivo) <> ''),
  UNIQUE (contrato_id, data)
);

-- Versão do cronograma: nasce em rascunho, com número seguinte, sobre a planilha vigente.
-- Ao ficar vigente tem que cobrir a planilha inteira e substitui a anterior. Depois não muda.
CREATE FUNCTION fn_cronograma_versao_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_forma   forma_acompanhamento;
  v_falta   text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.status <> 'rascunho' THEN
      RAISE EXCEPTION 'Cronograma % não se apaga: versão publicada é histórico', OLD.numero USING ERRCODE = 'check_violation';
    END IF;
    RETURN OLD;
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF app_usuario() IS NULL THEN
      RAISE EXCEPTION 'A sessão não diz quem está agindo: cronograma tem autor' USING ERRCODE = 'check_violation';
    END IF;
    NEW.autor := app_usuario();
    IF NEW.status <> 'rascunho' THEN
      RAISE EXCEPTION 'Cronograma nasce em rascunho' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.numero <> (SELECT coalesce(max(numero) + 1, 0) FROM cronograma_versao WHERE contrato_id = NEW.contrato_id) THEN
      RAISE EXCEPTION 'A versão do cronograma tem que ser a seguinte à última' USING ERRCODE = 'check_violation';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM revisao_orcamento WHERE id = NEW.revisao_id AND status = 'vigente') THEN
      RAISE EXCEPTION 'O cronograma é feito sobre a planilha vigente' USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;

  IF (NEW.contrato_id, NEW.revisao_id, NEW.numero, NEW.tipo, NEW.autor, NEW.tenant_id)
       IS DISTINCT FROM (OLD.contrato_id, OLD.revisao_id, OLD.numero, OLD.tipo, OLD.autor, OLD.tenant_id) THEN
    RAISE EXCEPTION 'Contrato, planilha, número, tipo e autor do cronograma não mudam' USING ERRCODE = 'check_violation';
  END IF;
  IF OLD.status = 'substituida' THEN
    RAISE EXCEPTION 'Cronograma % já foi substituído e é somente leitura', OLD.numero USING ERRCODE = 'check_violation';
  END IF;
  IF OLD.status = 'vigente' THEN
    IF NEW.status <> 'substituida' OR pg_trigger_depth() < 2
       OR (to_jsonb(NEW) - 'status') IS DISTINCT FROM (to_jsonb(OLD) - 'status') THEN
      RAISE EXCEPTION 'Cronograma vigente não se altera: mudança é uma versão nova, com motivo e autor'
        USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.status = 'substituida' THEN
    RAISE EXCEPTION 'Cronograma em rascunho não vai direto para substituído' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.status = 'vigente' THEN
    SELECT forma_acompanhamento INTO v_forma FROM contrato WHERE id = NEW.contrato_id;
    IF v_forma = 'eventos' THEN
      -- todo evento da planilha tem que estar no cronograma, e só eles
      SELECT a.titulo || ' × ' || f.nome INTO v_falta
        FROM evento e JOIN agrupador_evento a ON a.id = e.agrupador_id JOIN frente_obra f ON f.id = e.frente_id
       WHERE e.revisao_id = NEW.revisao_id
         AND NOT EXISTS (SELECT 1 FROM cronograma_evento ce WHERE ce.cronograma_versao_id = NEW.id AND ce.evento_id = e.id)
       ORDER BY a.numero, f.ordem LIMIT 1;
      IF v_falta IS NOT NULL THEN
        RAISE EXCEPTION 'Cronograma incompleto: o evento "%" não tem datas', v_falta USING ERRCODE = 'check_violation';
      END IF;
      IF EXISTS (SELECT 1 FROM cronograma_evento ce JOIN evento e ON e.id = ce.evento_id
                  WHERE ce.cronograma_versao_id = NEW.id AND e.revisao_id <> NEW.revisao_id)
         OR EXISTS (SELECT 1 FROM cronograma_predecessora cp
                     WHERE cp.cronograma_versao_id = NEW.id
                       AND (NOT EXISTS (SELECT 1 FROM cronograma_evento ce WHERE ce.cronograma_versao_id = NEW.id AND ce.evento_id = cp.evento_id)
                         OR NOT EXISTS (SELECT 1 FROM cronograma_evento ce WHERE ce.cronograma_versao_id = NEW.id AND ce.evento_id = cp.predecessora_evento_id))) THEN
        RAISE EXCEPTION 'Cronograma cita evento que não é da planilha vigente' USING ERRCODE = 'check_violation';
      END IF;
    ELSE
      -- por quantidade: cada grupo do primeiro nível soma 100%, e nenhum fica de fora
      SELECT ir.codigo_eap INTO v_falta
        FROM item_revisao ir
       WHERE ir.revisao_id = NEW.revisao_id AND ir.tipo = 'grupo' AND ir.parent_id IS NULL
         AND (SELECT coalesce(sum(p.percentual), 0) FROM cronograma_parcela p
               WHERE p.cronograma_versao_id = NEW.id AND p.item_contratual_id = ir.item_contratual_id) <> 100
       ORDER BY ir.path LIMIT 1;
      IF v_falta IS NOT NULL THEN
        RAISE EXCEPTION 'Cronograma incompleto: as parcelas do grupo % não somam 100%%', v_falta USING ERRCODE = 'check_violation';
      END IF;
      IF EXISTS (SELECT 1 FROM cronograma_parcela p
                  WHERE p.cronograma_versao_id = NEW.id
                    AND NOT EXISTS (SELECT 1 FROM item_revisao ir WHERE ir.revisao_id = NEW.revisao_id
                                       AND ir.item_contratual_id = p.item_contratual_id
                                       AND ir.tipo = 'grupo' AND ir.parent_id IS NULL)) THEN
        RAISE EXCEPTION 'Cronograma tem parcela de item que não é grupo do primeiro nível da planilha' USING ERRCODE = 'check_violation';
      END IF;
    END IF;
    UPDATE cronograma_versao SET status = 'substituida' WHERE contrato_id = NEW.contrato_id AND status = 'vigente';
    NEW.vigente_em := now();
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_cronograma_versao_guard BEFORE INSERT OR UPDATE OR DELETE ON cronograma_versao
  FOR EACH ROW EXECUTE FUNCTION fn_cronograma_versao_guard();

-- Datas, predecessoras e parcelas só mudam com a versão em rascunho.
CREATE FUNCTION fn_cronograma_conteudo_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_status text; v_numero smallint; v_revisao uuid;
BEGIN
  SELECT status, numero, revisao_id INTO v_status, v_numero, v_revisao
    FROM cronograma_versao WHERE id = coalesce(NEW.cronograma_versao_id, OLD.cronograma_versao_id);
  -- quando a versão em rascunho é apagada, as linhas dela vão junto (a versão já não existe)
  IF v_status IS NULL AND TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  IF v_status <> 'rascunho' THEN
    RAISE EXCEPTION 'Cronograma % está "%": datas e parcelas não mudam; reprogramar é criar versão nova', v_numero, v_status
      USING ERRCODE = 'check_violation';
  END IF;
  -- só a tabela de parcelas tem a coluna da planilha; por isso a leitura pelo nome
  IF TG_OP <> 'DELETE' AND (to_jsonb(NEW) ->> 'revisao_id')::uuid <> v_revisao THEN
    RAISE EXCEPTION 'A parcela tem que ser da mesma planilha do cronograma' USING ERRCODE = 'check_violation';
  END IF;
  RETURN coalesce(NEW, OLD);
END $$;
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['cronograma_evento', 'cronograma_predecessora', 'cronograma_parcela'] LOOP
    EXECUTE format('CREATE TRIGGER trg_cronograma_conteudo_guard BEFORE INSERT OR UPDATE OR DELETE ON %I
                    FOR EACH ROW EXECUTE FUNCTION fn_cronograma_conteudo_guard()', t);
  END LOOP;
  FOREACH t IN ARRAY ARRAY['documento_orgao', 'prancha_vinculo', 'cronograma_versao', 'calendario_obra', 'frente_obra', 'agrupador_evento'] LOOP
    EXECUTE format('CREATE TRIGGER trg_auditoria AFTER INSERT OR UPDATE OR DELETE ON %I
                    FOR EACH ROW EXECUTE FUNCTION fn_auditar()', t);
  END LOOP;
END $$;

SELECT prumo_fechar_migracao();
REVOKE UPDATE, DELETE ON documento_orgao FROM app_rw;
