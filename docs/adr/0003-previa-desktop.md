# ADR 0003 · Prévia de desktop antes do núcleo

- **Estado:** aceito, provisório
- **Data:** 13/10/2026
- **Decisor:** Gabriel Onezio Ferreira

## Contexto

O autor pediu um executável de Windows na Área de Trabalho, em Tauri e Rust, para ver como o Prumo está ficando. O roadmap manda começar pelo domínio e pelo banco e deixar as telas para depois, e até aqui o repositório só tinha documentação.

## Decisão

1. **Uma prévia navegável, não o sistema.** `apps/desktop` é uma casca Tauri 2 que abre as telas com uma obra fictícia. Não tem banco, usuário, designação, assinatura nem trilha, e nada é gravado.
2. **As regras da prévia são as de verdade.** Valor de evento, conferência da medição contra o Boletim de Execução e previsão moram em `crates/dominio`, puro e testado, e são o começo da Fase 0. A prévia só as chama.
3. **O que é provisório fica separado.** A obra fictícia e o estado em memória estão em `crates/demonstracao`; a interface, em `apps/desktop/previa`, é HTML, CSS e JavaScript sem etapa de build. Os dois saem quando houver banco e a interface em React (`ui/`).
4. **O `.exe` é compilado no Windows.** `scripts/build-windows.sh` roda no WSL, copia as fontes para `C:\dev\prumo-build` e chama o Rust do Windows (MSVC). Sai só o executável (`bundle.active = false`), copiado como `Prumo.exe` para a Área de Trabalho; o anterior vai para `C:\dev\prumo-anteriores`.

## Alternativas descartadas

| Alternativa | Por que não |
|---|---|
| Esperar as Fases 0 a 2 para mostrar algo | O autor quer acompanhar agora |
| Interface da prévia já em React + Vite | Seria começar o design system sem os tokens e os componentes revisados que `05-ux-ui.md` §8 pede; a prévia reusa o HTML do canvas de telas |
| Compilação cruzada pelo WSL | Em outros projetos desta máquina o alvo `windows-gnu` falhou no link do WebView2 e o `cargo-xwin` parou na falta do `llvm-rc`. Não foi tentado de novo aqui |
| Regras escritas no JavaScript da prévia | Número e regra vêm do código do domínio (regra de ouro 2 e lei LP2) |

## Consequências

- Existe código antes de existir CI que o cubra. O workflow de CI ainda espera `scripts/db-test.sh` e `cargo deny`, que não existem; ele não foi ajustado.
- O diário de obras da empresa não está na prévia: é tela só do app de celular (ADR 0004).
- A prévia mostra telas que parecem prontas. O menu marca "desenho" nas que têm números fixos, e a primeira tela diz o que é cálculo, o que é desenho e o que não existe.
- Nenhum modelo de IA roda na prévia. Onde haverá sugestão, aparece o cartão "desligada nesta prévia".
- A fonte é a do sistema (Segoe UI) em vez da Source Sans 3 do canvas: a prévia não carrega nada da rede.
- O ícone deixou de ser provisório em 13/10/2026: é a marca do Prumo (`marca/README.md`). O identificador do app é `io.github.gabonezio.prumo`, até haver domínio (questão 12).
- O executável não é assinado e não tem instalador. Assinatura e instalador são da Fase 6 (`09-distribuicao.md`).
- Não há `rust-toolchain.toml`: a prévia compila com o Rust estável instalado no WSL e no Windows.
