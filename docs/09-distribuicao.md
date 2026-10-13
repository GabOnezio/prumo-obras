# 09 · Distribuição e releases ("tem que estar certo")

Uma prefeitura precisa saber **exatamente o que está instalando, de quem veio e que não foi alterado**. Por isso a distribuição pelo GitHub segue regras mais rígidas que um projeto comum.

Repositório: `prumo-obras`. Todo artefato usa o prefixo `prumo-`.

## 1. O que cada release entrega

| Artefato | Para quem | Observação |
|---|---|---|
| `prumo-server-<versão>-linux-x86_64.tar.gz` (+ `.deb` opcional) | Servidor da prefeitura | Binário único `prumo-api` + `prumo-worker` + migrações + exemplo de `systemd` |
| `docker-compose.yml` e imagem OCI `ghcr.io/<org>/prumo-obras:<versão>` | Quem prefere contêiner | Imagem mínima, usuário não-root, sem shell |
| `prumo-desktop-<versão>-x64.msi` / `.AppImage` | Fiscal e gestor | **Assinado** (ver §3) |
| `prumo-campo-<versão>.apk` / `.aab` | Campo: Android, GrapheneOS, LineageOS e HarmonyOS até a 4 | Assinado com chave de release; **nunca** distribuir APK de debug. O APK tem que poder ser baixado e atualizado **fora da loja do Google** (questão 29) |
| App iOS (`.ipa`), pela App Store ou TestFlight | Campo: iPhone e iPad | Assinado pela conta de desenvolvedor Apple; passa pela revisão da Apple (questão 27) |
| `SHA256SUMS` + `SHA256SUMS.sig` | Todos | Verificação de integridade |
| `sbom.cdx.json` | Controle interno / segurança | Lista de componentes (CycloneDX) |
| `provenance` (atestado de build) | Auditoria | Prova que o artefato saiu deste repositório e deste commit |
| `CHANGELOG.md`, notas da versão | Todos | O que mudou, migrações, riscos |
| `docs/homologacao/roteiro-aceite.md` | Prefeitura | Roteiro de testes de aceite assinável |

## 2. Versionamento e ritmo

- **SemVer** (`MAJOR.MINOR.PATCH`). Mudança de regra legal ou de migração destrutiva = `MAJOR`/`MINOR` com nota explícita.
- **Keep a Changelog** em `CHANGELOG.md`.
- Tags **assinadas** (`git tag -s`). Branch `main` protegida: PR obrigatório, revisão, CI verde.
- Canal **LTS** (correções de segurança e legais) separado de **current**. Prefeitura em produção fica no LTS.
- **Migrações de banco são imutáveis depois de publicadas**; correção = nova migração. Cada release declara a versão mínima da qual se pode atualizar.

## 3. Cadeia de confiança

1. **Dependências:** `Cargo.lock` e `package-lock.json` commitados; `cargo deny` (licenças e advisories) e `cargo audit` no CI; Dependabot semanal.
2. **Build:** no GitHub Actions, toolchain fixada, ações fixadas por SHA, permissões mínimas, build limpo do commit da tag.
3. **Assinatura:**
   - Windows (MSI/EXE): certificado de assinatura de código; sem ele o SmartScreen bloqueia ou alerta nos computadores da prefeitura.
   - Atualizador do Tauri: chave de assinatura do updater guardada como segredo; app só atualiza se a assinatura bater.
   - Android: keystore de release guardado fora do repositório.
   - Apple: certificado e perfil de distribuição guardados como segredo; build em macOS.
   - Demais artefatos: `SHA256SUMS` assinado (Sigstore/cosign ou GPG).
4. **Proveniência:** `actions/attest-build-provenance` (ou equivalente) no workflow de release.
5. **SBOM:** `cargo cyclonedx` + `cyclonedx-npm` anexados à release.
6. **Segredos:** nunca no repositório; `gitleaks` no CI.

## 4. Checklist antes de publicar uma versão

- [ ] CI verde (fmt, clippy, testes de domínio, **invariantes do banco em Postgres real**, testes das leis do RREIA, testes de UI).
- [ ] Testes de paridade Rust × SQL passam.
- [ ] Migrações testadas: banco novo **e** atualização a partir da versão LTS anterior.
- [ ] Backup e restauração testados com os dados de demonstração.
- [ ] CHANGELOG atualizado; nota de risco/rollback escrita.
- [ ] Artefatos assinados, `SHA256SUMS` conferido em máquina limpa.
- [ ] Nenhum dado real (nome, CPF, planilha de prefeitura, foto) no repositório.
- [ ] Licenças de dependências e de **modelos de IA** conferidas (`docs/modelos.md`).
- [ ] Roteiro de homologação atualizado.

## 5. O que acompanha a instalação na prefeitura

1. **Manual de implantação** (servidor, banco, armazenamento, TLS, usuários iniciais, `config_municipio`).
2. **Sonda de hardware do RREIA** executada e anexada (veredito L1–L3 para o modelo escolhido).
3. **Plano de backup e restauração** com responsável e periodicidade.
4. **RIPD** preenchido e **política de privacidade** revisada pelo encarregado.
5. **Termo de homologação** com o roteiro de aceite assinado por fiscal-piloto e controle interno.
6. **Procedimento de contingência** (o que fazer se o sistema cair).
7. **Contato de suporte e SLA** definidos.

## 6. Estrutura de arquivos "estilo GitHub" deste repositório

```
README.md            vitrine: o que é, status, como instalar, links
CLAUDE.md            instruções para o Claude Code/CLI (regras de ouro, comandos, ordem)
AGENTS.md            ponteiro para o CLAUDE.md (outros agentes)
RREIA.md             modelo ações/permissões/leis/atividades da IA
CHANGELOG.md  SECURITY.md  CONTRIBUTING.md  CITATION.cff  LICENSE (a definir)  .gitignore
docs/                documentação numerada + adr/ + homologacao/ + modelos/
.github/             workflows (ci, release), dependabot, templates de issue e PR, CODEOWNERS
```
