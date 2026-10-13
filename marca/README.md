# Marca do Prumo

A marca gráfica do Prumo é um símbolo só, sem o nome dentro: um "P" com capacete de obra, prédios e uma estrada. É monocromática, preta ou branca. Foi fornecida pelo autor do projeto em 13/10/2026 (ADR 0001).

**Fonte única:** `master/prumo-obras-marca.svg`. Tudo o mais nesta pasta e nos apps sai desse vetor, por `scripts/gerar-icones.sh`.

## Regras de uso

- **A marca acompanha o nome "Prumo".** O brasão é do município e acompanha o nome da cidade. Um não ocupa o lugar do outro: no cabeçalho aparece `[marca] Prumo · [brasão] Prefeitura de ___`.
- **Ícone de programa é a marca preta sobre um azulejo branco** de cantos arredondados. A marca sozinha, preta e transparente, some sobre fundo escuro, como a barra de tarefas do Windows no tema escuro.
- Sobre fundo colorido ou escuro dentro das telas, usar a versão branca. Não recolorir, não distorcer, não acrescentar texto dentro do símbolo.
- Não editar os arquivos gerados à mão. Se a marca mudar, troque o vetor, rode o script e confira o resultado.

## O que é original e o que é gerado

Os cinco arquivos abaixo vieram no pacote de marca e ficam como chegaram. `ORIGINAIS.sha256` guarda o hash de cada um, e o script para se algum mudar.

| Arquivo | O que é |
|---|---|
| `master/prumo-obras-marca.svg` | O vetor, preto, fundo transparente |
| `master/prumo-obras-marca-preta.png` | A marca em 738 × 1024 px, transparente |
| `windows/Prumo-Obras.ico` | Ícone de Windows com a marca transparente, de 16 a 256 px. **Não é o que o programa usa** (ver a regra do azulejo) |
| `macos/Prumo-Obras.icns` | Ícone de macOS com a marca transparente. Também não é o que o programa usa |
| `pwa/icons/icon-512-maskable.png` | Ícone "maskable" de 512 px, com a marca reduzida sobre branco |

Tudo o mais é gerado:

| Pasta | Conteúdo | Quem usa |
|---|---|---|
| `master/` | Marca branca (SVG e PNG), WebP, quadrado de 1024 px com margem, e `prumo-obras-icone-1024.png` (o azulejo) | Material e telas |
| `../apps/desktop/src-tauri/icons/` | `icon.ico`, `icon.icns` e os PNG do programa de desktop | O `Prumo.exe` e os pacotes de macOS e Linux |
| `../apps/desktop/previa/` | `marca-branca.svg`, `marca-preta.svg` e `favicon.svg` | As telas da prévia |
| `android/` | Ícone adaptativo (frente, fundo e monocromático), ícones do Android antigo por densidade e o de loja | O app de celular |
| `apple/AppIcon.appiconset/` | Os tamanhos de ícone de iPhone e iPad | O app de celular |
| `pwa/` | Favicons, ícones de 192 e 512 px, `apple-touch-icon.png` e um `manifest.webmanifest` de exemplo | O cliente web |
| `linux/` | Tema hicolor, o vetor e um atalho `.desktop` de exemplo | Pacote de Linux |

## O app de celular ainda não existe

`android/` e `apple/` estão prontos, mas não estão ligados a nada: `apps/mobile` ainda não foi criado. Quando for, o script passa a gravar os ícones direto na pasta do app. Até lá servem de referência e para as lojas.

O ícone adaptativo do Android mantém a marca dentro do círculo central de 66 dp, que é a única parte que todo aparelho mostra. Os ícones do Android antigo e o redondo são desenhados pelo script, porque os que o gerador do Tauri faz cortam o capacete.

Nada aqui foi conferido em aparelho, em loja, no Xcode nem no Android Studio.

## Gerar de novo

```bash
./scripts/gerar-icones.sh      # precisa do ImageMagick, do tauri-cli e do python3
git status --short marca apps/desktop
```

Rodar duas vezes dá exatamente os mesmos arquivos: o script tira datas e metadados e ordena as entradas do `.icns`. Se o `git status` mostrar ícone alterado sem a marca ter mudado, é a versão do ImageMagick ou do tauri-cli que mudou; confira o resultado antes de commitar.
