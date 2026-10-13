#!/usr/bin/env bash
# Prova as regras do banco em PostgreSQL 16 de verdade.
#
#   scripts/db-test.sh               roda todas as suítes que existirem
#   scripts/db-test.sh referencia    só o schema e o seed de referência, sem alteração
#
# Sem PRUMO_PG_URL, sobe um contêiner descartável (imagem postgres:16-alpine), usa o psql de
# dentro dele e o remove no fim. Não toca em nenhum outro contêiner.
# Com PRUMO_PG_URL (no CI: postgres://usuario:senha@host:porta), usa esse servidor e o psql
# da máquina. O usuário precisa poder criar bancos e papéis.
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
cd "$RAIZ"
IMAGEM="${PRUMO_PG_IMAGEM:-postgres:16-alpine}"
CONTEINER="prumo-db-test-$$"
SAIDA="$(mktemp -d)"
SUITE="${1:-tudo}"
BLOQUEIOS_DA_REFERENCIA=12

limpar() {
  [ -n "${PRUMO_PG_URL:-}" ] || docker rm -f "$CONTEINER" >/dev/null 2>&1 || true
  rm -rf "$SAIDA"
}
trap limpar EXIT

passo() { printf '\n== %s ==\n' "$1"; }
falhar() { printf '\nFALHOU: %s\n' "$1" >&2; exit 1; }

if [ -n "${PRUMO_PG_URL:-}" ]; then
  command -v psql >/dev/null || falhar "PRUMO_PG_URL definido, mas não há psql nesta máquina."
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

novo_banco() {
  sql postgres -q -c "SET client_min_messages = warning" -c "DROP DATABASE IF EXISTS $1" -c "CREATE DATABASE $1" >/dev/null
}

# O seed de referência cria o papel app_rw, que vale para o servidor inteiro. Para poder
# rodá-lo de novo em outro banco, o papel é removido depois de cada execução.
remover_papel_do_seed() {
  sql "$1" -q -c "DROP OWNED BY app_rw" >/dev/null
  sql postgres -q -c "DROP ROLE app_rw" >/dev/null
}

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
  printf '  %-34s %3s bloqueios, %3s números conferidos\n' "$(basename "$arquivo")" \
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
  remover_papel_do_seed "$banco"
}

suite_referencia() {
  passo "referência: schema e seed do engenheiro, sem alteração"
  novo_banco prumo_referencia
  sql prumo_referencia -q -f - <db/reference/schema.sql >/dev/null
  echo "  tabelas: $(sql prumo_referencia -tAc "select count(*) from information_schema.tables where table_schema = 'public' and table_type = 'BASE TABLE'")"
  rodar_seed_de_referencia prumo_referencia db/reference/seed_e_testes.sql
  rodar_teste prumo_referencia db/tests/referencia_numeros.sql
}

case "$SUITE" in
  referencia) suite_referencia ;;
  tudo) suite_referencia ;;
  *) falhar "suíte desconhecida: $SUITE" ;;
esac

printf '\nBanco: tudo passou.\n'
