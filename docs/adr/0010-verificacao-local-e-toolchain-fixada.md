# ADR 0010 · Verificação local como porteiro e toolchain fixada

- **Estado:** aceito (decisões 4 e 5 do plano da Fase 0, aprovado em 13/10/2026). A primeira parte é provisória: vale enquanto o GitHub Actions não rodar
- **Data:** 13/10/2026
- **Decisor:** Gabriel Onezio Ferreira

## Contexto

O repositório é privado, e nos repositórios privados desta conta o GitHub Actions não inicia: toda execução termina em `startup_failure`, sem rodar nenhum passo. O mesmo acontece em outros cinco repositórios da conta. A causa provável é cobrança ou cota do Actions; não foi confirmada.

Sem CI, nada impediria um commit com teste quebrado. E o WSL e o Windows desta máquina tinham versões diferentes do Rust (1.98.1 e 1.99.0), o que já basta para o `clippy` aceitar num lado o que recusa no outro.

## Decisão

1. **`scripts/ci-local.sh` é o porteiro.** Roda os mesmos passos do CI nesta máquina:
   - sem argumento, antes de cada commit: formatação, `clippy -D warnings` e testes dos crates que não dependem do Tauri;
   - com `--tudo`, uma vez por etapa: o workspace inteiro, `scripts/db-test.sh` em PostgreSQL 16 real, `cargo audit` e `cargo deny`.
2. **`.github/workflows/ci.yml` descreve os mesmos passos**, para o dia em que o Actions rodar. Até lá ele não é prova de nada: nunca foi executado.
3. **A versão do Rust é fixada em `rust-toolchain.toml`** (1.99.0, com `rustfmt` e `clippy`). Vale para o WSL, para o build do Windows e para o CI.
4. **`deny.toml` fixa a política de dependências:** só licenças permissivas e a MPL-2.0, só o crates.io como origem. A lista é provisória até a licença do repositório ser definida (questões 7 e 34).

## Consequências

- **O porteiro depende de quem o roda.** Nada no repositório obriga a rodar o script antes de um commit. Enquanto o Actions não funcionar, a garantia é de processo, não de máquina.
- **O workflow pode estar errado e ninguém saber.** A sintaxe foi conferida, e os passos são os do script que passa aqui, mas o ambiente do runner é outro (pacotes do sistema, PostgreSQL como serviço). O primeiro uso real pode pedir ajuste.
- Mudar a versão do Rust passa a ser um commit, com o `clippy` rodando de novo no código inteiro.
- Uma dependência com licença fora da lista faz `cargo deny` falhar: a decisão de aceitar é explícita.

## O que resolveria a parte provisória

Regularizar o Actions na conta (cobrança ou cota para repositórios privados), ou tornar o repositório público, o que hoje não pode ser feito: faltam a licença (questão 7) e a confirmação de autoria do schema de referência (questão 6).
