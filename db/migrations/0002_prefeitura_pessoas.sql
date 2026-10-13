-- =============================================================================
-- Prumo · migração 0002 · o tenant é o município; pessoas e designação
--
-- 1. O tenant passa a ser o município: a tabela continua se chamando "tenant" (34 tabelas
--    apontam para ela), ganha UF e código do IBGE e passa a ter RLS.
-- 2. Quem é quem: usuario, servidor, portaria, designacao (fiscal, gestor do contrato e
--    comissões, por contrato e por período), empresa e usuario_externo.
-- 3. A sessão passa a dizer QUEM age (app.usuario_id), e não só um texto.
-- 4. Chave estrangeira entre tabelas com tenant_id passa a levar o tenant: uma linha de um
--    município não aponta mais para registro de outro (ADR 0007, questão 35).
--
-- Login, senha e segundo fator não estão aqui: a identidade é da Fase 1.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Município
-- -----------------------------------------------------------------------------
COMMENT ON TABLE tenant IS 'Município. Cada linha é uma prefeitura; tenant_id nas outras tabelas aponta para cá.';
ALTER TABLE tenant ADD COLUMN uf char(2);
ALTER TABLE tenant ADD COLUMN codigo_ibge char(7) CHECK (codigo_ibge ~ '^[0-9]{7}$');

ALTER TABLE tenant ENABLE ROW LEVEL SECURITY;
CREATE POLICY proprio_municipio ON tenant FOR SELECT USING (id = app_tenant());

-- -----------------------------------------------------------------------------
-- 2. Quem age na sessão
-- -----------------------------------------------------------------------------
-- A API define app.usuario_id em toda sessão, junto com app.tenant_id. O banco não tem como
-- conferir quem está do outro lado da conexão: confia na API e usa o id para aplicar as
-- regras de designação e de segregação de funções, como última defesa.
CREATE FUNCTION app_usuario() RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('app.usuario_id', true), '')::uuid
$$;

-- -----------------------------------------------------------------------------
-- 3. Pessoas
-- -----------------------------------------------------------------------------
CREATE TABLE usuario (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id  uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  nome       text NOT NULL,
  ativo      boolean NOT NULL DEFAULT true,
  criado_em  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE servidor (                           -- pessoa do poder público
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  usuario_id   uuid NOT NULL UNIQUE REFERENCES usuario,
  matricula    text NOT NULL,
  cargo        text NOT NULL,
  cpf_cifrado  bytea,                             -- LGPD: cifrado na aplicação
  cpf_hash     char(64),                          -- busca sem decifrar
  UNIQUE (tenant_id, matricula)
);

CREATE TABLE portaria (                           -- ato que designa
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  numero          text NOT NULL,
  data            date NOT NULL,
  objeto          text NOT NULL,
  arquivo_sha256  char(64),
  UNIQUE (tenant_id, numero, data)
);

CREATE TYPE funcao_designacao AS ENUM (
  'gestor_contrato', 'fiscal_tecnico', 'fiscal_administrativo', 'fiscal_substituto',
  'comissao_medicao', 'comissao_recebimento');

-- Quem responde por quê, em qual contrato e de quando até quando.
CREATE TABLE designacao (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  servidor_id  uuid NOT NULL REFERENCES servidor,
  contrato_id  uuid NOT NULL REFERENCES contrato,
  funcao       funcao_designacao NOT NULL,
  inicio       date NOT NULL,
  fim          date,                              -- NULL = em vigor
  portaria_id  uuid NOT NULL REFERENCES portaria,
  CHECK (fim IS NULL OR fim >= inicio),
  -- a mesma pessoa não tem a mesma função duas vezes no mesmo período
  EXCLUDE USING gist (servidor_id WITH =, contrato_id WITH =, funcao WITH =,
                      daterange(inicio, fim, '[]') WITH &&)
);
CREATE INDEX ix_designacao_contrato ON designacao (contrato_id, funcao);

-- Designação é histórico: não se apaga nem se reescreve. Só se encerra, pondo a data de fim.
CREATE FUNCTION fn_designacao_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Designação não é apagada: encerre com a data de fim' USING ERRCODE = 'check_violation';
  END IF;
  IF (NEW.servidor_id, NEW.contrato_id, NEW.funcao, NEW.inicio, NEW.portaria_id, NEW.tenant_id)
       IS DISTINCT FROM (OLD.servidor_id, OLD.contrato_id, OLD.funcao, OLD.inicio, OLD.portaria_id, OLD.tenant_id)
     OR OLD.fim IS NOT NULL THEN
    RAISE EXCEPTION 'Designação só muda para receber a data de fim, uma vez' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_designacao_guard BEFORE UPDATE OR DELETE ON designacao
  FOR EACH ROW EXECUTE FUNCTION fn_designacao_guard();

-- O usuário tem, nesta data, alguma destas funções neste contrato?
CREATE FUNCTION fn_designado(p_usuario uuid, p_contrato uuid, p_funcoes funcao_designacao[], p_em date)
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM designacao d
      JOIN servidor s ON s.id = d.servidor_id
      JOIN usuario u  ON u.id = s.usuario_id
     WHERE u.id = p_usuario AND u.ativo
       AND d.contrato_id = p_contrato AND d.funcao = ANY (p_funcoes)
       AND d.inicio <= p_em AND (d.fim IS NULL OR d.fim >= p_em))
$$;

-- As três funções de fiscal contam como "fiscal do contrato".
CREATE FUNCTION fn_fiscal_do_contrato(p_usuario uuid, p_contrato uuid, p_em date)
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT fn_designado(p_usuario, p_contrato,
                      ARRAY['fiscal_tecnico', 'fiscal_administrativo', 'fiscal_substituto']::funcao_designacao[], p_em)
$$;

-- -----------------------------------------------------------------------------
-- 4. Empresa contratada e as pessoas dela
-- -----------------------------------------------------------------------------
CREATE TABLE empresa (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  razao_social  text NOT NULL,
  cnpj          char(14) NOT NULL,
  UNIQUE (tenant_id, cnpj)
);
ALTER TABLE contrato ADD COLUMN empresa_id uuid REFERENCES empresa;
COMMENT ON COLUMN contrato.papel_empresa IS 'Herdado da referência (SaaS da construtora). Sem uso no Prumo.';

-- Pessoa da empresa com acesso a um contrato.
CREATE TABLE usuario_externo (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid NOT NULL DEFAULT app_tenant() REFERENCES tenant,
  usuario_id   uuid NOT NULL REFERENCES usuario,
  empresa_id   uuid NOT NULL REFERENCES empresa,
  contrato_id  uuid NOT NULL REFERENCES contrato,
  papel        text NOT NULL CHECK (papel IN ('preposto', 'responsavel_tecnico', 'apontador')),
  inicio       date NOT NULL,
  fim          date,
  CHECK (fim IS NULL OR fim >= inicio),
  UNIQUE (usuario_id, contrato_id, papel)
);

CREATE FUNCTION fn_usuario_externo_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM contrato c WHERE c.id = NEW.contrato_id AND c.empresa_id = NEW.empresa_id) THEN
    RAISE EXCEPTION 'A empresa não é a contratada deste contrato' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_usuario_externo_guard BEFORE INSERT OR UPDATE ON usuario_externo
  FOR EACH ROW EXECUTE FUNCTION fn_usuario_externo_guard();

-- O usuário age, nesta data, pela empresa contratada deste contrato?
CREATE FUNCTION fn_da_contratada(p_usuario uuid, p_contrato uuid, p_em date)
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM usuario_externo x
      JOIN usuario u ON u.id = x.usuario_id
     WHERE u.id = p_usuario AND u.ativo AND x.contrato_id = p_contrato
       AND x.inicio <= p_em AND (x.fim IS NULL OR x.fim >= p_em))
$$;

-- A mesma pessoa não é servidor que fiscaliza e pessoa da empresa no mesmo contrato.
CREATE FUNCTION fn_sem_dois_lados() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_usuario uuid;
BEGIN
  IF TG_TABLE_NAME = 'designacao' THEN
    SELECT usuario_id INTO v_usuario FROM servidor WHERE id = NEW.servidor_id;
    IF EXISTS (SELECT 1 FROM usuario_externo x WHERE x.usuario_id = v_usuario AND x.contrato_id = NEW.contrato_id) THEN
      RAISE EXCEPTION 'Esta pessoa já age pela empresa neste contrato' USING ERRCODE = 'check_violation';
    END IF;
  ELSIF EXISTS (SELECT 1 FROM designacao d JOIN servidor s ON s.id = d.servidor_id
                 WHERE s.usuario_id = NEW.usuario_id AND d.contrato_id = NEW.contrato_id) THEN
    RAISE EXCEPTION 'Esta pessoa já tem designação da prefeitura neste contrato' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_designacao_dois_lados BEFORE INSERT ON designacao
  FOR EACH ROW EXECUTE FUNCTION fn_sem_dois_lados();
CREATE TRIGGER trg_usuario_externo_dois_lados BEFORE INSERT ON usuario_externo
  FOR EACH ROW EXECUTE FUNCTION fn_sem_dois_lados();

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['designacao', 'portaria', 'usuario_externo', 'empresa', 'servidor', 'usuario'] LOOP
    EXECUTE format('CREATE TRIGGER trg_auditoria AFTER INSERT OR UPDATE OR DELETE ON %I
                    FOR EACH ROW EXECUTE FUNCTION fn_auditar()', t);
  END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- 5. Fecho de toda migração: RLS, acesso da aplicação e tenant nas chaves estrangeiras
-- -----------------------------------------------------------------------------
-- Chamada no fim de cada migração. Para toda tabela com tenant_id que ainda não tem:
--   a) liga a RLS e cria a política pelo tenant da sessão;
--   b) concede leitura e gravação ao papel da aplicação (quem só cresce perde UPDATE e DELETE
--      na própria migração, depois desta chamada);
--   c) acrescenta o tenant a cada chave estrangeira entre duas tabelas com tenant_id, para
--      a linha de um município não poder apontar para registro de outro. A conferência de
--      chave estrangeira não passa pela RLS; por isso o tenant tem que estar na chave.
-- Só o dono das tabelas executa.
CREATE FUNCTION prumo_fechar_migracao() RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  tab record;
  fk record;
  v_colunas text;
  v_referidas text;
  v_indice text;
BEGIN
  FOR tab IN
    SELECT c.relname, c.relrowsecurity
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relkind = 'r'
       AND EXISTS (SELECT FROM pg_attribute a WHERE a.attrelid = c.oid AND a.attname = 'tenant_id'
                      AND NOT a.attisdropped AND a.attnotnull)
  LOOP
    IF NOT tab.relrowsecurity THEN
      EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', tab.relname);
      EXECUTE format('CREATE POLICY isolamento_tenant ON %I USING (tenant_id = app_tenant())
                      WITH CHECK (tenant_id = app_tenant())', tab.relname);
      EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON %I TO app_rw', tab.relname);
    END IF;
  END LOOP;

  FOR fk IN
    SELECT con.conname, origem.relname AS origem, destino.relname AS destino,
           con.conkey, con.confkey, con.conrelid, con.confrelid
      FROM pg_constraint con
      JOIN pg_class origem  ON origem.oid = con.conrelid
      JOIN pg_class destino ON destino.oid = con.confrelid
      JOIN pg_namespace n   ON n.oid = origem.relnamespace
     WHERE n.nspname = 'public' AND con.contype = 'f' AND destino.relname <> 'tenant'
       -- as duas pontas têm tenant_id obrigatório, e a chave ainda não o inclui
       AND EXISTS (SELECT FROM pg_attribute a WHERE a.attrelid = con.conrelid AND a.attname = 'tenant_id' AND a.attnotnull)
       AND EXISTS (SELECT FROM pg_attribute a WHERE a.attrelid = con.confrelid AND a.attname = 'tenant_id' AND a.attnotnull)
       AND NOT EXISTS (SELECT FROM pg_attribute a WHERE a.attrelid = con.conrelid AND a.attname = 'tenant_id'
                          AND a.attnum = ANY (con.conkey))
       AND NOT EXISTS (SELECT FROM pg_constraint feita WHERE feita.conrelid = con.conrelid
                          AND feita.conname = left(con.conname, 58) || '_tnt')
  LOOP
    SELECT string_agg(quote_ident(a.attname), ', ' ORDER BY x.ord) INTO v_colunas
      FROM unnest(fk.conkey) WITH ORDINALITY AS x(num, ord)
      JOIN pg_attribute a ON a.attrelid = fk.conrelid AND a.attnum = x.num;
    SELECT string_agg(quote_ident(a.attname), ', ' ORDER BY x.ord) INTO v_referidas
      FROM unnest(fk.confkey) WITH ORDINALITY AS x(num, ord)
      JOIN pg_attribute a ON a.attrelid = fk.confrelid AND a.attnum = x.num;
    v_indice := 'ux_' || left(fk.destino, 40) || '_tnt_' || left(md5(v_referidas), 8);
    EXECUTE format('CREATE UNIQUE INDEX IF NOT EXISTS %I ON %I (tenant_id, %s)', v_indice, fk.destino, v_referidas);
    EXECUTE format('ALTER TABLE %I ADD CONSTRAINT %I FOREIGN KEY (tenant_id, %s) REFERENCES %I (tenant_id, %s)',
                   fk.origem, left(fk.conname, 58) || '_tnt', v_colunas, fk.destino, v_referidas);
  END LOOP;
END $$;
REVOKE ALL ON FUNCTION prumo_fechar_migracao() FROM PUBLIC;

SELECT prumo_fechar_migracao();

