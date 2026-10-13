#!/usr/bin/env bash
# Verificação local: os mesmos passos do CI, nesta máquina.
# É o porteiro antes de cada commit enquanto o GitHub Actions não inicia na conta.
#
#   scripts/ci-local.sh          formatação, clippy e testes dos crates leves (rápido)
#   scripts/ci-local.sh --tudo   mais: workspace inteiro (compila o Tauri), banco, avisos de
#                                segurança e licenças. Rodar uma vez por etapa.
set -euo pipefail
cd "$(dirname "$0")/.."

# Crates que não dependem do Tauri. Compilam e testam em segundos.
LEVES=(-p prumo-dominio -p prumo-demonstracao)
# A máquina tem pouca memória; dois processos do compilador por vez.
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-2}"

passo() { printf '\n== %s ==\n' "$1"; }

passo "formatação"
cargo fmt --all -- --check
passo "clippy (crates leves)"
cargo clippy "${LEVES[@]}" --all-targets -- -D warnings
passo "testes (crates leves)"
cargo test "${LEVES[@]}"

if [ "${1:-}" = "--tudo" ]; then
  passo "clippy (workspace)"
  cargo clippy --workspace --all-targets -- -D warnings
  passo "testes (workspace)"
  cargo test --workspace
  if [ -x scripts/db-test.sh ]; then
    passo "banco (Postgres 16 real)"
    ./scripts/db-test.sh
  fi
  passo "avisos de segurança (cargo audit)"
  cargo audit
  passo "licenças e origens (cargo deny)"
  cargo deny check
fi

printf '\nTudo passou.\n'
