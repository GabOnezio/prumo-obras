#!/usr/bin/env bash
# Gera o executável de Windows da prévia do Prumo e o copia para a Área de Trabalho.
#
# Roda no WSL, mas quem compila é o Rust instalado no Windows (MSVC): a
# compilação cruzada de app com WebView2 a partir do Linux não fecha o link
# (ver docs/adr/0003-previa-desktop.md). As fontes são copiadas para uma pasta
# descartável no disco do Windows; a pasta `target` de lá é reaproveitada.
#
# Uso:
#   scripts/build-windows.sh              compila e copia para a Área de Trabalho
#   scripts/build-windows.sh --sem-copiar só compila
#
# Variáveis: PRUMO_JOBS (padrão 4) limita os processos do compilador. A máquina
# tem pouca memória livre; aumentar deixa mais rápido e mais arriscado.
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
COPIA="/mnt/c/dev/prumo-build"
COPIA_WIN='C:\dev\prumo-build'
ANTERIORES="/mnt/c/dev/prumo-anteriores"
JOBS="${PRUMO_JOBS:-4}"
COPIAR=1
[ "${1:-}" = "--sem-copiar" ] && COPIAR=0

command -v cmd.exe >/dev/null || { echo "cmd.exe não encontrado: este script roda no WSL." >&2; exit 1; }
[ -f "$RAIZ/Cargo.lock" ] || { echo "Falta o Cargo.lock: rode 'cargo generate-lockfile' na raiz." >&2; exit 1; }

echo "1/3 Copiando as fontes para $COPIA_WIN"
mkdir -p "$COPIA"
for item in Cargo.toml Cargo.lock rust-toolchain.toml crates apps; do
  rm -rf "${COPIA:?}/$item"
  cp -r "$RAIZ/$item" "$COPIA/$item"
done

printf '%s\r\n' \
  '@echo off' \
  "cd /d $COPIA_WIN" \
  'set "PATH=%USERPROFILE%\.cargo\bin;%PATH%"' \
  "cargo build --release --locked -p prumo-desktop --features custom-protocol -j $JOBS > build.log 2>&1" \
  '(echo CODIGO_DE_SAIDA=%ERRORLEVEL%)>> build.log' \
  > "$COPIA/build.cmd"

echo "2/3 Compilando no Windows (log em $COPIA_WIN\\build.log; a primeira vez leva uns 10 minutos)"
# O log da compilação anterior sai antes: se o Windows não responder, não pode sobrar um
# "CODIGO_DE_SAIDA=0" antigo dizendo que deu certo.
rm -f "$COPIA/build.log"
(cd /mnt/c && cmd.exe /c "$COPIA_WIN\\build.cmd") || true
if [ ! -f "$COPIA/build.log" ]; then
  echo "O Windows não rodou a compilação: o cmd.exe não respondeu ao WSL. Nada foi copiado. Tente de novo." >&2
  exit 1
fi
if ! grep -q '^CODIGO_DE_SAIDA=0' "$COPIA/build.log"; then
  echo "A compilação falhou. Fim do log:" >&2
  tail -n 40 "$COPIA/build.log" >&2
  exit 1
fi
EXE="$COPIA/target/release/prumo.exe"
[ -f "$EXE" ] || { echo "Compilou, mas não achei $EXE" >&2; exit 1; }

if [ "$COPIAR" -eq 0 ]; then
  echo "3/3 Pronto, sem copiar: $COPIA_WIN\\target\\release\\prumo.exe"
  exit 0
fi

POWERSHELL="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
DESKTOP_WIN="$("$POWERSHELL" -NoProfile -Command "[Environment]::GetFolderPath('Desktop')" | tr -d '\r')"
DESKTOP="$(wslpath "$DESKTOP_WIN")"
DESTINO="$DESKTOP/Prumo.exe"
echo "3/3 Copiando para $DESKTOP_WIN\\Prumo.exe"
if [ -e "$DESTINO" ]; then
  # O Windows deixa mover um executável aberto, mas não sobrescrever.
  mkdir -p "$ANTERIORES"
  mv "$DESTINO" "$ANTERIORES/Prumo-$(date +%Y%m%d-%H%M%S).exe"
  echo "    o anterior foi guardado em C:\\dev\\prumo-anteriores"
fi
cp "$EXE" "$DESTINO"
cmp -s "$EXE" "$DESTINO" || { echo "A cópia não confere com o original." >&2; exit 1; }
echo "Pronto: $(du -h "$DESTINO" | cut -f1) em $DESKTOP_WIN\\Prumo.exe. Se o Prumo estiver aberto, feche e abra de novo."
