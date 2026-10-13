# Como contribuir

1. Leia `CLAUDE.md` (regras de ouro e definição de pronto) e `docs/08-roadmap.md`.
2. Abra uma issue antes de mudanças grandes. Mudança em regra legal exige **ADR** (`docs/adr/`) e teste novo.
3. Branch a partir de `main`; PR pequeno; CI verde; ao menos uma revisão. Mudanças em `crates/dominio`, `db/migrations` e `crates/rreia-gate` exigem revisão de um responsável (ver `CODEOWNERS`).
4. Commits em português, imperativo, com escopo: `dominio: limita acréscimo de reforma a 50%`.
5. **Nunca** inclua dados reais (nomes, CPFs, planilhas de prefeitura, fotos, dumps, `.apk`, chaves).
6. Migrações publicadas são imutáveis: corrija com uma nova.
7. Mudou comportamento? Atualize `CHANGELOG.md` e a documentação.

Código de conduta: respeito, foco no problema, sem assédio.
