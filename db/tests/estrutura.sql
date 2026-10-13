-- Estrutura de segurança do banco, conferida no catálogo depois de todas as migrações.
-- Não usa dado nenhum: falha quando uma migração nova deixa algo fora da regra.
\echo
\echo '== Isolamento por município (RLS) =='

SELECT pg_temp.confere_vazio('tabela com tenant_id e RLS desligada', $$
  SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p') AND NOT c.relrowsecurity
     AND EXISTS (SELECT FROM pg_attribute a
                  WHERE a.attrelid = c.oid AND a.attname = 'tenant_id' AND NOT a.attisdropped)$$);

SELECT pg_temp.confere_vazio('tabela com RLS ligada e nenhuma política', $$
  SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p') AND c.relrowsecurity
     AND NOT EXISTS (SELECT FROM pg_policy p WHERE p.polrelid = c.oid)$$);

-- Sem WITH CHECK, o PostgreSQL usa a condição de USING também na gravação.
SELECT pg_temp.confere_vazio('política que não filtra pelo tenant da sessão', $$
  SELECT tablename || '.' || policyname FROM pg_policies
   WHERE schemaname = 'public'
     AND (coalesce(qual, with_check) !~ 'app_tenant\(\)' OR coalesce(with_check, qual) !~ 'app_tenant\(\)')$$);

-- Linha com tenant_id nulo é dado público da plataforma (bases de preço): a aplicação lê, não grava.
SELECT pg_temp.confere_vazio('política que deixa gravar linha sem tenant', $$
  SELECT tablename || '.' || policyname FROM pg_policies
   WHERE schemaname = 'public' AND cmd <> 'SELECT' AND coalesce(with_check, qual) ~* 'tenant_id is null'$$);

SELECT pg_temp.confere_vazio('política restritiva ou limitada a um papel (revisar à mão)', $$
  SELECT tablename || '.' || policyname FROM pg_policies
   WHERE schemaname = 'public' AND (permissive <> 'PERMISSIVE' OR roles <> '{public}')$$);

-- A conferência de chave estrangeira não passa pela RLS. Sem o tenant na chave, uma linha
-- de um município poderia apontar para registro de outro (ADR 0007).
SELECT pg_temp.confere_vazio('chave estrangeira entre tabelas com tenant que não leva o tenant', $$
  SELECT origem.relname || '.' || k.conname
    FROM pg_constraint k
    JOIN pg_class origem  ON origem.oid = k.conrelid
    JOIN pg_class destino ON destino.oid = k.confrelid
    JOIN pg_namespace n   ON n.oid = origem.relnamespace
   WHERE n.nspname = 'public' AND k.contype = 'f' AND destino.relname <> 'tenant'
     AND EXISTS (SELECT FROM pg_attribute a WHERE a.attrelid = k.conrelid AND a.attname = 'tenant_id' AND a.attnotnull)
     AND EXISTS (SELECT FROM pg_attribute a WHERE a.attrelid = k.confrelid AND a.attname = 'tenant_id' AND a.attnotnull)
     AND NOT EXISTS (SELECT FROM pg_attribute a WHERE a.attrelid = k.conrelid AND a.attname = 'tenant_id'
                        AND a.attnum = ANY (k.conkey))
     -- a chave original fica; a que leva o tenant tem o mesmo nome mais "_tnt"
     AND NOT EXISTS (SELECT FROM pg_constraint j
                      JOIN pg_attribute a ON a.attrelid = j.conrelid AND a.attname = 'tenant_id' AND a.attnum = ANY (j.conkey)
                     WHERE j.conrelid = k.conrelid AND j.contype = 'f' AND j.confrelid = k.confrelid
                       AND j.conkey @> k.conkey)$$);

-- Tabela sem tenant_id só entra aqui de propósito:
--   tenant             o cadastro dos municípios; tem RLS própria (cada um só lê a sua linha)
--   config_municipio   uma linha por município: a chave é o próprio tenant
--   migracao_aplicada  registro das migrações, que a aplicação não acessa
SELECT pg_temp.confere_vazio('tabela sem tenant_id fora da lista conhecida', $$
  SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')
     AND c.relname NOT IN ('tenant', 'migracao_aplicada')
     AND NOT EXISTS (SELECT FROM pg_attribute a
                      WHERE a.attrelid = c.oid AND a.attname = 'tenant_id' AND NOT a.attisdropped)$$);

-- A IA propõe e o registro guarda. Dado de negócio não pode depender de uma linha desse registro.
SELECT pg_temp.confere_vazio('tabela que aponta para o registro de decisões de IA', $$
  SELECT origem.relname FROM pg_constraint k JOIN pg_class origem ON origem.oid = k.conrelid
   WHERE k.contype = 'f' AND k.confrelid = 'ia_decisao'::regclass$$);
SELECT pg_temp.confere_vazio('gatilho ou função de regra que lê o registro de decisões de IA', $$
  SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.prosrc ~* 'ia_decisao' AND p.proname <> 'fn_ia_decisao_guard'$$);

-- Visão comum roda com a permissão do dono e passaria por cima da RLS.
SELECT pg_temp.confere_vazio('visão que não roda com a permissão de quem consulta', $$
  SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind IN ('v', 'm')
     AND NOT coalesce(c.reloptions @> ARRAY['security_invoker=true'], false)$$);

-- Função SECURITY DEFINER também roda como o dono.
SELECT pg_temp.confere_vazio('função que roda com a permissão do dono', $$
  SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.prosecdef
     AND NOT EXISTS (SELECT FROM pg_depend x WHERE x.objid = p.oid AND x.deptype = 'e')$$);

\echo
\echo '== Papel da aplicação (app_rw) =='

SELECT pg_temp.confere('o papel app_rw existe', (SELECT count(*) FROM pg_roles WHERE rolname = 'app_rw'), 1);

SELECT pg_temp.confere_vazio('app_rw com atributo que passa por cima da RLS', $$
  SELECT concat_ws(' ', CASE WHEN rolsuper THEN 'superusuário' END, CASE WHEN rolbypassrls THEN 'BYPASSRLS' END,
                   CASE WHEN rolcreaterole THEN 'CREATEROLE' END, CASE WHEN rolcreatedb THEN 'CREATEDB' END,
                   CASE WHEN rolreplication THEN 'REPLICATION' END)
    FROM pg_roles
   WHERE rolname = 'app_rw' AND (rolsuper OR rolbypassrls OR rolcreaterole OR rolcreatedb OR rolreplication)$$);

SELECT pg_temp.confere_vazio('app_rw é membro de outro papel', $$
  SELECT r.rolname FROM pg_auth_members m JOIN pg_roles r ON r.oid = m.roleid
   WHERE m.member = 'app_rw'::regrole$$);

SELECT pg_temp.confere_vazio('objeto que pertence ao app_rw', $$
  SELECT c.relname FROM pg_class c WHERE c.relowner = 'app_rw'::regrole
  UNION ALL SELECT p.proname FROM pg_proc p WHERE p.proowner = 'app_rw'::regrole
  UNION ALL SELECT n.nspname FROM pg_namespace n WHERE n.nspowner = 'app_rw'::regrole$$);

SELECT pg_temp.confere_texto('app_rw cria objeto no schema public',
  has_schema_privilege('app_rw', 'public', 'CREATE')::text, 'false');

SELECT pg_temp.confere_vazio('app_rw grava em tabela sem RLS', $$
  SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p') AND NOT c.relrowsecurity
     AND (has_table_privilege('app_rw', c.oid, 'INSERT') OR has_table_privilege('app_rw', c.oid, 'UPDATE')
          OR has_table_privilege('app_rw', c.oid, 'DELETE'))$$);

SELECT pg_temp.confere_vazio('app_rw executa a função de fecho de migração', $$
  SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'prumo_fechar_migracao'
     AND has_function_privilege('app_rw', p.oid, 'EXECUTE')$$);

SELECT pg_temp.confere_vazio('app_rw com TRUNCATE, REFERENCES ou TRIGGER em alguma tabela', $$
  SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')
     AND (has_table_privilege('app_rw', c.oid, 'TRUNCATE') OR has_table_privilege('app_rw', c.oid, 'REFERENCES')
          OR has_table_privilege('app_rw', c.oid, 'TRIGGER'))$$);

SELECT pg_temp.confere_vazio('app_rw acessa o registro de migrações', $$
  SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relname = 'migracao_aplicada'
     AND (has_table_privilege('app_rw', c.oid, 'SELECT') OR has_table_privilege('app_rw', c.oid, 'INSERT')
          OR has_table_privilege('app_rw', c.oid, 'UPDATE') OR has_table_privilege('app_rw', c.oid, 'DELETE'))$$);

-- Uma migração que cria tabela e esquece de dar acesso deixaria a aplicação quebrada em silêncio.
SELECT pg_temp.confere_vazio('tabela com RLS que a aplicação não consegue ler', $$
  SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p') AND c.relrowsecurity
     AND NOT has_table_privilege('app_rw', c.oid, 'SELECT')$$);

SELECT pg_temp.confere_vazio('visão que a aplicação não consegue ler', $$
  SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind = 'v' AND NOT has_table_privilege('app_rw', c.oid, 'SELECT')$$);

-- Cadastrar e alterar município é da instalação, não da aplicação.
SELECT pg_temp.confere_vazio('app_rw grava no cadastro de municípios', $$
  SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relname = 'tenant'
     AND (has_table_privilege('app_rw', c.oid, 'INSERT') OR has_table_privilege('app_rw', c.oid, 'UPDATE')
          OR has_table_privilege('app_rw', c.oid, 'DELETE'))$$);

-- Registros que só crescem: a aplicação lê e acrescenta, nunca altera nem apaga.
SELECT pg_temp.confere_vazio('app_rw apaga registro que não se apaga', $$
  SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relname IN ('ia_decisao', 'publicacao', 'denuncia', 'config_municipio')
     AND has_table_privilege('app_rw', c.oid, 'DELETE')$$);

SELECT pg_temp.confere_vazio('app_rw altera ou apaga registro que só cresce', $$
  SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relname IN ('auditoria', 'medicao_etapa', 'execucao_financeira_ref', 'rdo_etapa', 'rdo_instrucao')
     AND (has_table_privilege('app_rw', c.oid, 'UPDATE') OR has_table_privilege('app_rw', c.oid, 'DELETE'))$$);
