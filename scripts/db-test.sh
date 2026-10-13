#!/usr/bin/env bash
# Prova as regras do banco em PostgreSQL 16 de verdade.
#
#   scripts/db-test.sh               roda todas as suítes
#   scripts/db-test.sh referencia    o schema e o seed do engenheiro, sem alteração
#   scripts/db-test.sh porte         a migração 0001 comparada com a referência
#   scripts/db-test.sh migracoes     todas as migrações e os testes de db/tests
#   scripts/db-test.sh paridade      as regras em Rust contra o SQL, com o banco de pé
#   scripts/db-test.sh sabotagem     estraga o banco de propósito e exige que os testes acusem
#   scripts/db-test.sh registrar     anota o SHA-256 das migrações novas (não usa banco)
#
# Sem PRUMO_PG_URL, sobe um contêiner descartável (imagem postgres:16-alpine), usa o psql de
# dentro dele e o remove no fim. Não toca em nenhum outro contêiner.
# Com PRUMO_PG_URL (no CI: postgres://usuario:senha@host:porta), usa esse servidor e o psql
# da máquina. O script apaga e cria os bancos prumo_teste_* e o papel app_rw, então só aceita
# servidor externo com PRUMO_PG_DESCARTAVEL=1.
# PRUMO_DB_SAIDA=pasta guarda ali a saída completa de cada teste (o motivo de cada bloqueio).
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
cd "$RAIZ"
IMAGEM="${PRUMO_PG_IMAGEM:-postgres:16-alpine}"
CONTEINER="prumo-db-test-$$"
SAIDA="${PRUMO_DB_SAIDA:-$(mktemp -d)}"
mkdir -p "$SAIDA"
SUITE="${1:-tudo}"
MANIFESTO=db/migrations/SHA256SUMS
BLOQUEIOS_DA_REFERENCIA=12
# O que a migração 0001 tirou da referência de propósito: tabelas, visões e tipos da construtora.
FORA_DA_0001="plano_contas cotacao cotacao_item cotacao_proposta pedido_compra pedido_compra_item
  conta_bancaria titulo titulo_retencao titulo_parcela baixa rateio rateio_obra apropriacao
  vw_fluxo_caixa vw_custo_item tipo_titulo status_titulo origem_apropriacao criterio_rateio"

limpar() {
  [ -n "${PRUMO_PG_URL:-}" ] || docker rm -f "$CONTEINER" >/dev/null 2>&1 || true
  [ -n "${PRUMO_DB_SAIDA:-}" ] || rm -rf "$SAIDA"
}
trap limpar EXIT

passo() { printf '\n== %s ==\n' "$1"; }
falhar() { printf '\nFALHOU: %s\n' "$1" >&2; exit 1; }

# --- migrações: numeração e registro de SHA-256 no repositório ---------------------------------

migracoes() { find db/migrations -maxdepth 1 -name '[0-9][0-9][0-9][0-9]_*.sql' | sort; }

registrar() {
  local arquivo nome novas=0
  touch "$MANIFESTO"
  for arquivo in $(migracoes); do
    nome="$(basename "$arquivo")"
    grep -q "  $nome\$" "$MANIFESTO" && continue
    (cd db/migrations && sha256sum "$nome") >>"$MANIFESTO"
    echo "registrada: $nome"
    novas=$((novas + 1))
  done
  echo "$novas migração(ões) nova(s) no $MANIFESTO."
}

# Migração registrada não muda mais: correção é migração nova.
verificar_manifesto() {
  local arquivo nome esperado=1 sobra
  [ -f "$MANIFESTO" ] || falhar "falta o $MANIFESTO. Crie com: scripts/db-test.sh registrar"
  sobra="$(find db/migrations -maxdepth 1 -name '*.sql' ! -name '[0-9][0-9][0-9][0-9]_*.sql')"
  [ -z "$sobra" ] || falhar "arquivo .sql em db/migrations fora do padrão NNNN_nome.sql: $sobra"
  (cd db/migrations && sha256sum --check --quiet --strict SHA256SUMS) ||
    falhar "uma migração registrada foi alterada ou removida. Migração registrada não muda: crie uma nova."
  for arquivo in $(migracoes); do
    nome="$(basename "$arquivo")"
    [ "${nome%%_*}" = "$(printf '%04d' "$esperado")" ] || falhar "numeração das migrações com salto ou repetição em $nome"
    grep -q "  $nome\$" "$MANIFESTO" || falhar "$nome não está no $MANIFESTO. Registre com: scripts/db-test.sh registrar"
    esperado=$((esperado + 1))
  done
  [ "$esperado" -gt 1 ] || falhar "não há migrações em db/migrations"
  echo "  registro: $((esperado - 1)) migração(ões), todas com o SHA-256 registrado"
}

if [ "$SUITE" = registrar ]; then
  registrar
  exit 0
fi
case "$SUITE" in
  tudo | referencia | porte | migracoes | paridade | sabotagem) ;;
  *) falhar "suíte desconhecida: $SUITE" ;;
esac

# --- servidor ----------------------------------------------------------------------------------

if [ -n "${PRUMO_PG_URL:-}" ]; then
  command -v psql >/dev/null || falhar "PRUMO_PG_URL definido, mas não há psql nesta máquina."
  [ "${PRUMO_PG_DESCARTAVEL:-}" = 1 ] ||
    falhar "este script apaga e cria bancos e o papel app_rw. Para usar um servidor externo, confirme com PRUMO_PG_DESCARTAVEL=1."
  URL_BASE="${PRUMO_PG_URL%/}"
  sql() { local banco="$1"; shift; psql "$URL_BASE/$banco" -v ON_ERROR_STOP=1 "$@"; }
else
  command -v docker >/dev/null || falhar "Sem docker e sem PRUMO_PG_URL: não há onde rodar o Postgres."
  docker run -d --rm --name "$CONTEINER" -e POSTGRES_PASSWORD=descartavel -p 127.0.0.1::5432 "$IMAGEM" >/dev/null
  sql() { local banco="$1"; shift; docker exec -i "$CONTEINER" psql -U postgres -d "$banco" -v ON_ERROR_STOP=1 "$@"; }
  # A imagem sobe o servidor duas vezes na inicialização; só vale depois de três respostas seguidas.
  seguidas=0
  for _ in $(seq 1 60); do
    if sql postgres -tAc 'select 1' >/dev/null 2>&1; then seguidas=$((seguidas + 1)); else seguidas=0; fi
    [ "$seguidas" -ge 3 ] && break
    sleep 1
  done
  [ "$seguidas" -ge 3 ] || falhar "O Postgres do contêiner não respondeu."
  PORTA="$(docker port "$CONTEINER" 5432/tcp | head -n 1 | sed 's/.*://')"
  URL_BASE="postgres://postgres:descartavel@127.0.0.1:$PORTA"
fi
echo "Postgres: $(sql postgres -tAc 'show server_version')"

# Sobras de uma execução anterior no mesmo servidor. No contêiner descartável não há nenhuma.
for banco in $(sql postgres -tAc "SELECT datname FROM pg_database WHERE datname LIKE 'prumo\_teste\_%'"); do
  sql postgres -q -c "DROP DATABASE $banco" >/dev/null
done
sql postgres -q -c "DROP ROLE IF EXISTS app_rw" >/dev/null 2>&1 ||
  falhar "o papel app_rw tem permissões em outro banco deste servidor: ele não é descartável."

novo_banco() { # nome [modelo]
  sql postgres -q -c "SET client_min_messages = warning" -c "DROP DATABASE IF EXISTS $1" \
    -c "CREATE DATABASE $1 ${2:+TEMPLATE $2}" >/dev/null
}

tabelas() { sql "$1" -tAc "select count(*) from information_schema.tables where table_schema = 'public' and table_type = 'BASE TABLE'"; }

# --- migrações: aplicação com registro no banco ------------------------------------------------

# Aplica, em ordem, as migrações que o banco ainda não tem. Cada uma roda numa transação só,
# junto com a linha do registro. Se uma migração já aplicada estiver diferente, para.
aplicar_migracoes() { # banco [última versão a aplicar]
  local banco="$1" ate="${2:-9999}" arquivo nome versao hash registrado
  MIGRACOES_APLICADAS=0
  sql "$banco" -q -c "SET client_min_messages = warning" -c "
    CREATE TABLE IF NOT EXISTS migracao_aplicada (
      versao       text PRIMARY KEY CHECK (versao ~ '^[0-9]{4}\$'),
      nome         text NOT NULL UNIQUE,
      sha256       char(64) NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}\$'),
      aplicada_em  timestamptz NOT NULL DEFAULT now())" >/dev/null
  for arquivo in $(migracoes); do
    nome="$(basename "$arquivo")"
    versao="${nome%%_*}"
    [ "$versao" \> "$ate" ] && break
    hash="$(sha256sum "$arquivo" | cut -d' ' -f1)"
    registrado="$(sql "$banco" -tAc "SELECT sha256 FROM migracao_aplicada WHERE versao = '$versao'")"
    if [ -n "$registrado" ]; then
      [ "$registrado" = "$hash" ] ||
        falhar "a migração $nome está diferente da que foi aplicada em $banco. Migração aplicada não muda: crie uma nova."
      continue
    fi
    if ! {
      cat "$arquivo"
      printf "\nINSERT INTO migracao_aplicada (versao, nome, sha256) VALUES ('%s', '%s', '%s');\n" "$versao" "$nome" "$hash"
    } | sql "$banco" -q -1 -f - >"$SAIDA/migracao-$versao.log" 2>&1; then
      tail -n 25 "$SAIDA/migracao-$versao.log" >&2
      falhar "a migração $nome não aplicou em $banco"
    fi
    MIGRACOES_APLICADAS=$((MIGRACOES_APLICADAS + 1))
  done
}

# --- testes ------------------------------------------------------------------------------------

# Roda um arquivo de teste com os utilitários na frente e guarda a saída.
rodar_teste() { # banco arquivo
  local banco="$1" arquivo="$2" log
  log="$SAIDA/$(basename "$arquivo").log"
  if ! cat db/tests/_util.sql "$arquivo" | sql "$banco" -q -f - >"$log" 2>&1; then
    tail -n 25 "$log" >&2
    falhar "$arquivo"
  fi
  if grep -q "TESTE FALHOU" "$log"; then
    grep "TESTE FALHOU" "$log" >&2
    falhar "$arquivo"
  fi
  printf '  %-26s %3s bloqueios provados, %3s conferências\n' "${arquivo#db/tests/}" \
    "$(grep -c 'OK, bloqueado' "$log" || true)" "$(grep -c 'OK, confere' "$log" || true)"
}

# Roda o seed do engenheiro (ou a parte dele que cabe no banco) e exige os 12 bloqueios.
rodar_seed_de_referencia() { # banco arquivo-do-seed
  local banco="$1" seed="$2" log="$SAIDA/seed-$1.log" bloqueios
  if ! sql "$banco" -f - <"$seed" >"$log" 2>&1; then
    tail -n 25 "$log" >&2
    falhar "o seed de referência não rodou até o fim em $banco"
  fi
  bloqueios="$(grep -c 'OK, bloqueado' "$log" || true)"
  [ "$bloqueios" -eq "$BLOQUEIOS_DA_REFERENCIA" ] ||
    falhar "esperava $BLOQUEIOS_DA_REFERENCIA bloqueios do seed de referência em $banco, vieram $bloqueios"
  if grep -q "TESTE FALHOU" "$log"; then falhar "o seed de referência acusou falha em $banco"; fi
  echo "  seed de referência: $bloqueios bloqueios provados"
}

# O seed do engenheiro, cortado por máquina para caber na 0001: sai o bloco financeiro (as
# tabelas dele não existem mais) e a criação do papel app_rw (a 0001 já cria). Nada é reescrito.
seed_de_referencia_para_o_porte() { # arquivo de saída
  awk '
    /^-- Financeiro$/                          { pulando = 1; inicios++ }
    /^-- Isolamento entre empresas \(RLS\)/    { pulando = 0; fins++ }
    /^CREATE ROLE app_rw NOLOGIN;$/            { papeis++; next }
    !pulando                                   { print }
    END { if (inicios != 1 || fins != 1 || papeis != 1) exit 3 }
  ' db/reference/seed_e_testes.sql >"$1" ||
    falhar "o seed de referência mudou de formato: não achei os marcos do bloco financeiro e do papel."
}

# Compara o catálogo da 0001 com o da referência, fato a fato.
comparar_catalogos() { # banco-da-referência banco-do-porte
  local ref="$SAIDA/catalogo-referencia.txt" porte="$SAIDA/catalogo-porte.txt"
  sql "$1" -qAt -f - <db/tests/referencia/catalogo.sql |
    awk -F'|' -v fora="$FORA_DA_0001" 'BEGIN { n = split(fora, f, /[ \n]+/); for (i = 1; i <= n; i++) x[f[i]] } !($2 in x)' >"$ref"
  sql "$2" -qAt -f - <db/tests/referencia/catalogo.sql |
    awk -F'|' '$2 != "migracao_aplicada"' >"$porte"
  [ -s "$ref" ] && [ -s "$porte" ] || falhar "a impressão do catálogo veio vazia"
  if ! diff "$ref" "$porte" >"$SAIDA/catalogo.diff"; then
    head -n 40 "$SAIDA/catalogo.diff" >&2
    falhar "a migração 0001 não está igual à referência (acima: '<' é a referência, '>' é a 0001)"
  fi
  local resumo="" tipo
  for tipo in coluna restrição índice função gatilho visão tipo política; do
    resumo="$resumo, $(grep -c "^$tipo|" "$porte" || true) de $tipo"
  done
  echo "  catálogo: $(wc -l <"$porte") fatos iguais aos da referência, nenhum diferente"
  echo "    (${resumo#, }, mais a RLS de cada tabela)"
}

# --- suítes ------------------------------------------------------------------------------------

suite_referencia() {
  passo "referência: schema e seed do engenheiro, sem alteração"
  novo_banco prumo_teste_referencia
  sql prumo_teste_referencia -q -f - <db/reference/schema.sql >/dev/null
  echo "  tabelas: $(tabelas prumo_teste_referencia)"
  rodar_seed_de_referencia prumo_teste_referencia db/reference/seed_e_testes.sql
  rodar_teste prumo_teste_referencia db/tests/referencia/numeros.sql
  # O seed cria o papel app_rw, que vale para o servidor inteiro; as migrações criam o delas.
  sql prumo_teste_referencia -q -c "DROP OWNED BY app_rw" >/dev/null
  sql postgres -q -c "DROP ROLE app_rw" >/dev/null
}

suite_porte() {
  passo "porte: a migração 0001 contra a referência"
  novo_banco prumo_teste_catalogo
  sql prumo_teste_catalogo -q -f - <db/reference/schema.sql >/dev/null
  novo_banco prumo_teste_porte
  aplicar_migracoes prumo_teste_porte 0001
  echo "  tabelas: $(tabelas prumo_teste_catalogo) na referência, $(($(tabelas prumo_teste_porte) - 1)) na 0001"
  comparar_catalogos prumo_teste_catalogo prumo_teste_porte
  seed_de_referencia_para_o_porte "$SAIDA/seed-porte.sql"
  rodar_seed_de_referencia prumo_teste_porte "$SAIDA/seed-porte.sql"
  rodar_teste prumo_teste_porte db/tests/referencia/numeros.sql
}

# Banco com todas as migrações e o seed fictício, usado como modelo: cada teste roda numa
# cópia limpa dele.
MODELO_PRONTO=0
preparar_modelo() {
  [ "$MODELO_PRONTO" -eq 1 ] && return
  verificar_manifesto
  novo_banco prumo_teste_modelo
  aplicar_migracoes prumo_teste_modelo
  echo "  aplicadas: $MIGRACOES_APLICADAS; tabelas: $(($(tabelas prumo_teste_modelo) - 1))"
  if ! sql prumo_teste_modelo -q -1 -f - <db/seed/exemplo.sql >"$SAIDA/seed-exemplo.log" 2>&1; then
    tail -n 25 "$SAIDA/seed-exemplo.log" >&2
    falhar "o seed fictício (db/seed/exemplo.sql) não carregou"
  fi
  echo "  seed fictício: $(sql prumo_teste_modelo -tAc "select count(*) || ' contratos, ' || (select count(*) from item_revisao where tipo = 'servico') || ' serviços, ' || (select count(*) from evento) || ' eventos' from contrato")"
  MODELO_PRONTO=1
}

suite_migracoes() {
  local teste
  passo "migrações: registro, seed fictício e testes de db/tests"
  preparar_modelo
  aplicar_migracoes prumo_teste_modelo
  [ "$MIGRACOES_APLICADAS" -eq 0 ] || falhar "aplicar de novo não deveria fazer nada, mas aplicou $MIGRACOES_APLICADAS"
  novo_banco prumo_teste_registro prumo_teste_modelo
  sql prumo_teste_registro -q -c "UPDATE migracao_aplicada SET sha256 = repeat('0', 64) WHERE versao = '0001'" >/dev/null
  if (aplicar_migracoes prumo_teste_registro) >/dev/null 2>&1; then
    falhar "uma migração diferente da que foi aplicada passou sem erro"
  fi
  echo "  aplicar de novo não faz nada; migração diferente da aplicada é recusada"
  for teste in db/tests/[!_]*.sql; do
    novo_banco prumo_teste_caso prumo_teste_modelo
    rodar_teste prumo_teste_caso "$teste"
  done
}

# Regras em Rust contra o SQL, mesma entrada e mesmo centavo. Os testes do crate
# prumo-paridade são #[ignore]: só rodam aqui, com o banco de pé.
PARIDADES_ESPERADAS=6
suite_paridade() {
  local log="$SAIDA/paridade.log" rodados
  passo "paridade: Rust × SQL, com o banco de pé"
  preparar_modelo
  command -v cargo >/dev/null || falhar "sem cargo nesta máquina: a paridade não tem como rodar"
  novo_banco prumo_teste_paridade prumo_teste_modelo
  if ! PRUMO_PARIDADE_URL="$URL_BASE/prumo_teste_paridade" CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-2}" \
    cargo test -p prumo-paridade -- --ignored --nocapture --test-threads=1 >"$log" 2>&1; then
    tail -n 40 "$log" >&2
    falhar "paridade Rust × SQL"
  fi
  # Com --nocapture a frase do teste sai na mesma linha do nome dele.
  grep -oE "(valor de item|seed × prévia|contratos sorteados|aditivo e boletim|fator do art\. 127|percentual e preço de item novo): .*" "$log" | sed 's/^/  /' || true
  # Um filtro errado rodaria zero testes e "passaria": exige a contagem.
  rodados="$(grep -E '^test result: ok\. [0-9]+ passed' "$log" | awk '{ s += $4 } END { print s + 0 }')"
  [ "$rodados" -ge "$PARIDADES_ESPERADAS" ] ||
    falhar "esperava ao menos $PARIDADES_ESPERADAS testes de paridade, rodaram $rodados"
  echo "  $rodados testes de paridade passaram"
}

# Teste dos testes. Um teste que nunca falha não prova nada: cada caso estraga uma proteção
# numa cópia do banco e exige que o arquivo de teste indicado acuse.
SABOTAGENS=0
sabotar() { # arquivo-de-teste descrição sql [sql para desfazer o que vale para o servidor inteiro]
  local log="$SAIDA/sabotagem.log"
  novo_banco prumo_teste_caso prumo_teste_modelo
  sql prumo_teste_caso -q -c "$3" >/dev/null 2>&1 || falhar "a sabotagem \"$2\" não aplicou"
  cat db/tests/_util.sql "db/tests/$1" | sql prumo_teste_caso -q -f - >"$log" 2>&1 || true
  [ -z "${4:-}" ] || sql postgres -q -c "$4" >/dev/null
  grep -q "TESTE FALHOU" "$log" || falhar "sabotagem que o $1 não percebeu: $2"
  SABOTAGENS=$((SABOTAGENS + 1))
}

suite_sabotagem() {
  local nova="CREATE TABLE nova (id uuid, tenant_id uuid)"
  passo "sabotagem: os testes acusam quando uma proteção é retirada"
  preparar_modelo
  sabotar estrutura.sql "tabela nova com tenant_id e sem RLS" "$nova"
  sabotar estrutura.sql "tabela nova sem tenant_id" "CREATE TABLE nova (id uuid)"
  sabotar estrutura.sql "RLS desligada numa tabela" "ALTER TABLE obra DISABLE ROW LEVEL SECURITY"
  sabotar estrutura.sql "RLS ligada sem política" \
    "$nova; ALTER TABLE nova ENABLE ROW LEVEL SECURITY; GRANT SELECT ON nova TO app_rw"
  sabotar estrutura.sql "política que deixa ver tudo" "CREATE POLICY aberta ON obra USING (true)"
  sabotar estrutura.sql "política que deixa gravar linha sem tenant" \
    "CREATE POLICY publica ON base_referencia FOR INSERT WITH CHECK (tenant_id IS NULL OR tenant_id = app_tenant())"
  sabotar estrutura.sql "visão que roda como o dono" "CREATE VIEW v AS SELECT * FROM contrato; GRANT SELECT ON v TO app_rw"
  sabotar estrutura.sql "função que roda como o dono" \
    "CREATE FUNCTION f() RETURNS bigint LANGUAGE sql SECURITY DEFINER AS 'select count(*) from contrato'"
  sabotar estrutura.sql "app_rw com BYPASSRLS" "ALTER ROLE app_rw BYPASSRLS" "ALTER ROLE app_rw NOBYPASSRLS"
  sabotar estrutura.sql "app_rw membro de papel que lê tudo" \
    "GRANT pg_read_all_data TO app_rw" "REVOKE pg_read_all_data FROM app_rw"
  sabotar estrutura.sql "app_rw grava no cadastro de municípios" "GRANT INSERT ON tenant TO app_rw"
  sabotar estrutura.sql "app_rw altera a auditoria" "GRANT UPDATE ON auditoria TO app_rw"
  sabotar estrutura.sql "app_rw esvazia tabela" "GRANT TRUNCATE ON medicao TO app_rw"
  sabotar estrutura.sql "app_rw lê o registro de migrações" "GRANT SELECT ON migracao_aplicada TO app_rw"
  sabotar estrutura.sql "app_rw cria objeto no schema" "GRANT CREATE ON SCHEMA public TO app_rw"
  sabotar estrutura.sql "tabela nova sem acesso para a aplicação" \
    "$nova; ALTER TABLE nova ENABLE ROW LEVEL SECURITY; CREATE POLICY isolamento_tenant ON nova USING (tenant_id = app_tenant())"
  sabotar isolamento.sql "política que deixa ver tudo" "CREATE POLICY aberta ON obra USING (true)"
  sabotar isolamento.sql "RLS desligada nos itens da medição" "ALTER TABLE medicao_item DISABLE ROW LEVEL SECURITY"
  sabotar isolamento.sql "RLS desligada na auditoria" "ALTER TABLE auditoria DISABLE ROW LEVEL SECURITY"
  sabotar isolamento.sql "app_rw apaga a auditoria" "GRANT DELETE ON auditoria TO app_rw"
  sabotar isolamento.sql "app_rw com BYPASSRLS" "ALTER ROLE app_rw BYPASSRLS" "ALTER ROLE app_rw NOBYPASSRLS"
  sabotar isolamento.sql "visão de situação roda como o dono" "ALTER VIEW vw_contrato_situacao SET (security_invoker = false)"
  sabotar estrutura.sql "chave estrangeira sem o tenant" "ALTER TABLE contrato DROP CONSTRAINT contrato_obra_id_fkey_tnt"
  sabotar estrutura.sql "cadastro de municípios sem RLS" "ALTER TABLE tenant DISABLE ROW LEVEL SECURITY; GRANT UPDATE ON tenant TO app_rw"
  sabotar estrutura.sql "aplicação pode chamar o fecho de migração" "GRANT EXECUTE ON FUNCTION prumo_fechar_migracao() TO app_rw"
  sabotar isolamento.sql "chave estrangeira sem o tenant" "ALTER TABLE contrato DROP CONSTRAINT contrato_obra_id_fkey_tnt"
  sabotar isolamento.sql "cadastro de municípios aberto" "CREATE POLICY todos ON tenant FOR SELECT USING (true)"
  sabotar pessoas.sql "designação sem o gatilho de histórico" "DROP TRIGGER trg_designacao_guard ON designacao"
  sabotar pessoas.sql "pessoa pode estar dos dois lados" "DROP TRIGGER trg_designacao_dois_lados ON designacao"
  sabotar pessoas.sql "empresa de fora no contrato" "DROP TRIGGER trg_usuario_externo_guard ON usuario_externo"
  sabotar pessoas.sql "usuário desativado continua com função" \
    "CREATE OR REPLACE FUNCTION fn_designado(p_usuario uuid, p_contrato uuid, p_funcoes funcao_designacao[], p_em date)
       RETURNS boolean LANGUAGE sql STABLE AS 'SELECT EXISTS (SELECT 1 FROM designacao d JOIN servidor s ON s.id = d.servidor_id
         WHERE s.usuario_id = p_usuario AND d.contrato_id = p_contrato AND d.funcao = ANY (p_funcoes)
           AND d.inicio <= p_em AND (d.fim IS NULL OR d.fim >= p_em))'"
  sabotar eventos.sql "evento sem o gatilho que o trava" "DROP TRIGGER trg_evento_guard ON evento"
  sabotar eventos.sql "distribuição por frente sem gatilho" "DROP TRIGGER trg_item_frente_guard ON item_frente"
  sabotar eventos.sql "medição por eventos sem gatilho" "DROP TRIGGER trg_medicao_evento_guard ON medicao_evento"
  sabotar eventos.sql "linha de medição sem gatilho" "DROP TRIGGER trg_medicao_item_guard ON medicao_item"
  sabotar eventos.sql "planilha sem o gatilho que confere a distribuição" "DROP TRIGGER trg_revisao_guard ON revisao_orcamento"
  sabotar eventos.sql "valor de item que ignora o critério do contrato" \
    "CREATE OR REPLACE FUNCTION fn_valor_item(p_qtd numeric, p_pu numeric, p_criterio criterio_arredondamento)
       RETURNS numeric LANGUAGE sql IMMUTABLE AS 'SELECT round(p_qtd * p_pu, 2)'"
  echo "  $SABOTAGENS sabotagens aplicadas, $SABOTAGENS percebidas pelos testes"
}

case "$SUITE" in
  referencia) suite_referencia ;;
  porte) suite_porte ;;
  migracoes) suite_migracoes ;;
  paridade) suite_paridade ;;
  sabotagem) suite_sabotagem ;;
  tudo)
    suite_referencia
    suite_porte
    suite_migracoes
    suite_paridade
    suite_sabotagem
    ;;
esac

printf '\nBanco: tudo passou.\n'
