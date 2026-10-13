# ADR 0001 · Nome e marca: Prumo

- **Estado:** aceito
- **Data:** 12/10/2026
- **Decisor:** Gabriel Onezio Ferreira

## Contexto

O projeto usava o nome de trabalho "SGOP" e a pasta `gestao-obras-publicas`. O nome aparece no README, na interface, no atualizador e em todo artefato de distribuição, então precisava ser decidido antes da Fase 0.

## Decisão

| Item | Decisão |
|---|---|
| Nome | **Prumo**, com a chamada "Gestão de Obras Públicas" |
| Repositório | `prumo-obras` |
| Artefatos | Prefixo `prumo-` (`prumo-api`, `prumo-worker`, `prumo-server-…`, `prumo-desktop-…`, `prumo-campo-…`) |
| IA | "Prumo + RREIA" na documentação técnica; "Prumo IA Local" na linguagem de venda. O RREIA fica como a arquitetura por trás |
| Marca da cidade | Na tela aparece "Prumo · Prefeitura de ___", com o brasão do município |
| Marca gráfica | Um símbolo só, sem o nome dentro: um "P" com capacete de obra, prédios e estrada. Monocromática. Fornecida pelo autor em 13/10/2026; arquivos e regras em `marca/README.md` |

## Alternativas consideradas

| Nome | A favor | Contra |
|---|---|---|
| Canteiro | Nome de obra, forte e simples | Genérico para buscar |
| ObraClara | Reforça a transparência, argumento forte para o tribunal de contas e a população | — |
| Atesta | Vem de "atestar" a medição, o ato central do fiscal | Pode soar restrito à fiscalização |
| Medida Certa | Fácil de lembrar | Foca só na medição |

## Consequências

- "SGOP" sai de todos os arquivos; a pasta do projeto passa a ser `prumo-obras`.
- O nome e o brasão do município são configuração por município; "Prumo" é fixo na interface.
- O usuário final continua vendo só o selo "Sugestão"; "RREIA" aparece no console do Admin e na documentação.
- **Pendente** (questão 12): busca da marca "Prumo" no INPI e escolha do domínio. Nenhuma das duas foi feita. Desde 13/10/2026 a busca tem que cobrir também a marca gráfica.
- **Marca e brasão não se misturam** (13/10/2026). A marca gráfica acompanha o nome "Prumo"; o brasão acompanha o nome do município. No cabeçalho: `[marca] Prumo · [brasão] Prefeitura de ___`.
- **Ícone de programa é a marca sobre um azulejo branco.** A marca preta e transparente some sobre fundo escuro, como a barra de tarefas do Windows no tema escuro. Os ícones são gerados do vetor por `scripts/gerar-icones.sh`.
