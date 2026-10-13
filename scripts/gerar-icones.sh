#!/usr/bin/env bash
# Gera os ícones do programa e dos apps a partir do vetor da marca.
#
#   scripts/gerar-icones.sh
#
# Precisa do ImageMagick (magick), do tauri-cli (cargo tauri) e do python3. O que sai daqui é versionado:
# rode de novo só quando a marca mudar, olhe o resultado e faça o commit.
#
# Fonte única: marca/master/prumo-obras-marca.svg. Os cinco arquivos originais do pacote de
# marca (listados em marca/ORIGINAIS.sha256) nunca são reescritos por este script.
#
# Para onde vai cada coisa:
#   marca/master/                    marca branca, WebP e os quadrados de 1024 px usados como fonte
#   apps/desktop/src-tauri/icons/    ícones do programa de desktop
#   apps/desktop/previa/             a marca que aparece na tela (branca no cabeçalho, preta no "Sobre")
#   marca/android/, marca/apple/     ícones dos apps de celular, à espera de apps/mobile
#   marca/pwa/                       ícones e manifesto do cliente web
#   marca/linux/                     tema hicolor e atalho de exemplo
#
# Ícone de programa é sempre a marca preta sobre um azulejo branco de cantos arredondados:
# a marca sozinha, preta e transparente, some na barra de tarefas escura do Windows.
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
MARCA="$RAIZ/marca"
MESTRE="$MARCA/master/prumo-obras-marca.svg"
DESKTOP="$RAIZ/apps/desktop/src-tauri"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

command -v magick >/dev/null || { echo "Falta o ImageMagick (magick)." >&2; exit 1; }
cargo tauri --version >/dev/null 2>&1 || { echo "Falta o tauri-cli (cargo tauri)." >&2; exit 1; }
command -v python3 >/dev/null || { echo "Falta o python3." >&2; exit 1; }
[ -f "$MESTRE" ] || { echo "Falta $MESTRE" >&2; exit 1; }
(cd "$MARCA" && sha256sum --check --quiet ORIGINAIS.sha256) ||
  { echo "Um arquivo original da marca foi alterado. Se a marca mudou de propósito, atualize marca/ORIGINAIS.sha256." >&2; exit 1; }

passo() { printf '%s\n' "$1"; }

# Sem data nem metadado dentro do arquivo: rodar duas vezes tem que dar os mesmos bytes,
# senão todo commit mostraria dezenas de ícones "alterados".
LIMPO=(-strip -define png:exclude-chunks=date,time)

# A marca, na altura pedida, sobre fundo transparente. O vetor é desenhado quatro vezes maior
# e reduzido, para a borda sair limpa nos tamanhos pequenos.
marca() { # vetor altura saída
  magick -background none -density 384 "$1" -resize "x$2" "${LIMPO[@]}" "$3"
}

# A marca centrada num quadrado. fundo: none, white ou "azulejo" (branco de cantos arredondados).
quadrado() { # lado  altura-da-marca-em-%  fundo  saída  [vetor]
  local lado="$1" altura=$(( $1 * $2 / 100 )) fundo="$3" saida="$4" vetor="${5:-$MESTRE}"
  marca "$vetor" "$altura" "$TMP/m.png"
  if [ "$fundo" = azulejo ]; then
    local raio=$(( lado * 20 / 100 ))
    magick -size "${lado}x${lado}" xc:none -fill white \
      -draw "roundrectangle 0,0 $((lado - 1)),$((lado - 1)) $raio,$raio" \
      "$TMP/m.png" -gravity center -composite "${LIMPO[@]}" "$saida"
  else
    magick -size "${lado}x${lado}" "xc:$fundo" "$TMP/m.png" -gravity center -composite "${LIMPO[@]}" "$saida"
  fi
}

# A marca num círculo branco, para o ícone redondo do Android antigo.
circulo() { # lado saída
  local lado="$1" meio=$(( $1 / 2 ))
  marca "$MESTRE" $(( lado * 62 / 100 )) "$TMP/m.png"
  magick -size "${lado}x${lado}" xc:none -fill white -draw "circle $meio,$meio $meio,0" \
    "$TMP/m.png" -gravity center -composite "${LIMPO[@]}" "$2"
}

# Azulejo para ícone de programa. Abaixo de 48 px a marca ocupa mais do quadrado, senão vira borrão.
azulejo() { # lado saída
  if [ "$1" -lt 48 ]; then quadrado "$1" 88 azulejo "$2"; else quadrado "$1" 70 azulejo "$2"; fi
}

passo "1/6 Versões da marca"
BRANCA="$MARCA/master/prumo-obras-marca-branca.svg"
sed 's/fill="#111111"/fill="#ffffff"/' "$MESTRE" >"$BRANCA"
[ "$(grep -o 'fill="#ffffff"' "$BRANCA" | wc -l)" -eq 1 ] || { echo "O vetor não tem mais o preenchimento #111111 esperado." >&2; exit 1; }
marca "$BRANCA" 1024 "$MARCA/master/prumo-obras-marca-branca.png"
magick "$MARCA/master/prumo-obras-marca-preta.png" -strip -define webp:lossless=true "$MARCA/master/prumo-obras-marca.webp"
quadrado 1024 80 none "$MARCA/master/prumo-obras-marca-preta-quadrada-1024.png"
azulejo 1024 "$MARCA/master/prumo-obras-icone-1024.png"

# No navegador a marca acompanha o tema: preta no claro, branca no escuro.
sed 's|<path |<style>path{fill:#111111}@media (prefers-color-scheme:dark){path{fill:#ffffff}}</style><path |; s| fill="#111111"||' \
  "$MESTRE" >"$TMP/favicon.svg"
grep -q 'prefers-color-scheme' "$TMP/favicon.svg" || { echo "Não consegui montar o favicon.svg." >&2; exit 1; }

passo "2/6 Programa de desktop"
# No ícone adaptativo do Android o sistema recorta o quadrado de 108 dp com a forma que quiser
# (círculo, gota, quadrado). Só o círculo de 66 dp no centro é garantido. Com 44% da altura,
# o canto mais distante da marca fica a 29 dp do centro, dentro dos 33 dp desse círculo.
quadrado 1024 44 none "$TMP/android-frente.png"
magick -size 1024x1024 xc:white "${LIMPO[@]}" "$TMP/branco.png"
cp "$MARCA/master/prumo-obras-icone-1024.png" "$TMP/icone.png"
cat >"$TMP/icones.json" <<JSON
{ "default": "icone.png", "bg_color": "#ffffff", "android_bg": "branco.png",
  "android_fg": "android-frente.png", "android_fg_scale": 100, "android_monochrome": "android-frente.png" }
JSON
if ! (cd "$DESKTOP" && cargo tauri icon "$TMP/icones.json" -o "$TMP/tauri") >"$TMP/tauri.log" 2>&1; then
  tail -n 20 "$TMP/tauri.log" >&2
  echo "O gerador de ícones do Tauri falhou." >&2
  exit 1
fi
mkdir -p "$DESKTOP/icons"
for arquivo in 32x32.png 64x64.png 128x128.png 128x128@2x.png icon.png; do
  cp "$TMP/tauri/$arquivo" "$DESKTOP/icons/$arquivo"
done
# O Tauri grava as entradas do .icns numa ordem que muda a cada vez. Ordenadas pelo tipo, o
# arquivo sai sempre igual; quem lê um .icns procura a entrada pelo tipo, não pela posição.
python3 -I -B - "$TMP/tauri/icon.icns" "$DESKTOP/icons/icon.icns" <<'PY'
import struct, sys
dados = open(sys.argv[1], "rb").read()
assert dados[:4] == b"icns" and struct.unpack(">I", dados[4:8])[0] == len(dados), "icon.icns inesperado"
entradas, p = [], 8
while p < len(dados):
    tamanho = struct.unpack(">I", dados[p + 4:p + 8])[0]
    entradas.append(dados[p:p + tamanho])
    p += tamanho
assert p == len(dados) and len(entradas) >= 6, "icon.icns inesperado"
corpo = b"".join(sorted(entradas, key=lambda e: e[:4]))
open(sys.argv[2], "wb").write(b"icns" + struct.pack(">I", 8 + len(corpo)) + corpo)
PY
# O .ico é montado aqui, tamanho a tamanho, para os pequenos saírem com a marca maior.
for lado in 16 24 32 48 64 128 256; do azulejo "$lado" "$TMP/ico-$lado.png"; done
magick "$TMP/ico-16.png" "$TMP/ico-24.png" "$TMP/ico-32.png" "$TMP/ico-48.png" "$TMP/ico-64.png" \
  "$TMP/ico-128.png" "$TMP/ico-256.png" -strip "$DESKTOP/icons/icon.ico" 2>"$TMP/ico.log" ||
  { cat "$TMP/ico.log" >&2; echo "Não consegui montar o icon.ico." >&2; exit 1; }
[ "$(magick identify "$DESKTOP/icons/icon.ico" | wc -l)" -eq 7 ] || { echo "O icon.ico saiu sem os 7 tamanhos." >&2; exit 1; }

cp "$BRANCA" "$RAIZ/apps/desktop/previa/marca-branca.svg"
cp "$MESTRE" "$RAIZ/apps/desktop/previa/marca-preta.svg"
cp "$TMP/favicon.svg" "$RAIZ/apps/desktop/previa/favicon.svg"

passo "3/6 Android"
rm -rf "$MARCA/android"
cp -r "$TMP/tauri/android" "$MARCA/android"
# Os ícones do Android antigo (sem ícone adaptativo) que o Tauri gera cortam a marca no
# redondo. Estes dois são refeitos aqui, com margem.
for par in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  azulejo "${par#*:}" "$MARCA/android/mipmap-${par%:*}/ic_launcher.png"
  circulo "${par#*:}" "$MARCA/android/mipmap-${par%:*}/ic_launcher_round.png"
done
quadrado 512 70 white "$MARCA/android/play-store-icon-512.png"

passo "4/6 Apple"
rm -rf "$MARCA/apple"
mkdir -p "$MARCA/apple"
cp -r "$TMP/tauri/ios" "$MARCA/apple/AppIcon.appiconset"

passo "5/6 Web"
ICONES="$MARCA/pwa/icons"
mkdir -p "$ICONES"
cp "$TMP/favicon.svg" "$ICONES/favicon.svg"
for lado in 16 32 48; do azulejo "$lado" "$ICONES/favicon-${lado}x${lado}.png"; done
magick "$ICONES/favicon-16x16.png" "$ICONES/favicon-32x32.png" "$ICONES/favicon-48x48.png" -strip "$ICONES/favicon.ico"
for lado in 192 512; do
  quadrado "$lado" 70 white "$ICONES/icon-$lado.png"
  quadrado "$lado" 80 none "$ICONES/icon-$lado-transparent.png"
done
magick "$ICONES/icon-512-maskable.png" -resize 192x192 "${LIMPO[@]}" "$ICONES/icon-192-maskable.png"
quadrado 180 70 white "$ICONES/apple-touch-icon.png"
cat >"$MARCA/pwa/manifest.webmanifest" <<'JSON'
{
  "name": "Prumo · Gestão de Obras Públicas",
  "short_name": "Prumo",
  "lang": "pt-BR",
  "display": "standalone",
  "background_color": "#ffffff",
  "theme_color": "#1F4E79",
  "icons": [
    { "src": "/icons/icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "/icons/icon-512.png", "sizes": "512x512", "type": "image/png" },
    { "src": "/icons/icon-192-maskable.png", "sizes": "192x192", "type": "image/png", "purpose": "maskable" },
    { "src": "/icons/icon-512-maskable.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" }
  ]
}
JSON

passo "6/6 Linux"
rm -rf "$MARCA/linux"
for lado in 16 24 32 48 64 128 256 512; do
  mkdir -p "$MARCA/linux/hicolor/${lado}x${lado}/apps"
  azulejo "$lado" "$MARCA/linux/hicolor/${lado}x${lado}/apps/prumo-obras.png"
done
cp "$MESTRE" "$MARCA/linux/prumo-obras.svg"
cat >"$MARCA/linux/prumo-obras.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Prumo
GenericName=Gestão de Obras Públicas
Comment=Gestão de obras públicas para prefeituras
Exec=prumo
Icon=prumo-obras
Categories=Office;
Terminal=false
DESKTOP

printf '\nPronto. Confira com: git status --short marca apps/desktop/src-tauri/icons\n'
