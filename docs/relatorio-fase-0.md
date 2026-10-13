# Relatório da Fase 0 · Fundação

Fechada em 13/10/2026, na branch `fase-0-fundacao` (local, sem push). O plano aprovado está em `plano-fase-0.md`; este documento diz o que saiu, o que foi provado, o que não foi e o que depende de você.

## 1. O que a fase entregou

| Parte | Entrega |
|---|---|
| Ferramentas | Rust fixado em 1.99.0; `scripts/ci-local.sh` como porteiro; política de licenças em `deny.toml` |
| Banco | 9 migrações e 74 tabelas, a partir do schema do engenheiro; registro de migrações com SHA-256; seed fictício com um contrato por eventos e um por quantidade |
| Segurança do banco | Um município não enxerga nem altera o outro (RLS, papel `app_rw`, tenant em toda chave estrangeira); trilha de auditoria que a aplicação não altera |
| Regras no banco | Medição, diário e aditivo só mudam de situação pelo caminho conferido, em nome de quem está na sessão, com designação vigente e segregação de funções; Boletim de Execução emitido é imutável; evento só é aprovado com boletim que o marque concluído |
| Domínio em Rust | Planilha, aditivo (art. 125 e 127), boletim de medição por quantidade e quatro máquinas de estado, além do que já existia (dinheiro, evento, conferência, previsão) |
| Paridade | As contas em Rust comparadas com o SQL, com o banco de pé |
| Documentação | ADRs 0006 a 0010; questões 34 a 43; lista de 14 achados em `plano-fase-0.md` §10 |

## 2. O que foi testado, e como

Tudo abaixo rodou nesta máquina (WSL2, Debian) em 13/10/2026, com `scripts/ci-local.sh --tudo`.

| O quê | Resultado |
|---|---|
| Schema e seed do engenheiro, sem alteração, em PostgreSQL 16.15 | 48 tabelas, os 12 bloqueios e os 26 números de aceite |
| Porte da migração `0001` | Catálogo igual ao da referência em 687 fatos, nenhum diferente; os mesmos 12 bloqueios e 26 números |
| Migrações `0001` a `0009` | Aplicam do zero; aplicar de novo não faz nada; arquivo diferente do aplicado é recusado; alterar migração registrada faz o teste falhar |
| Testes de banco | 12 arquivos, 347 bloqueios e 196 conferências, cada arquivo numa cópia limpa do banco migrado e semeado, a maioria como `app_rw` |
| Paridade Rust × SQL | 9 testes: valor de item (20.050 comparações), valor de evento (121 eventos sorteados), seed × prévia (6 eventos, R$ 164.039,34), aditivo e boletim (12 contratos do começo ao fim, 324 linhas de boletim), fator do art. 127 (10.013 pares), percentual e preço de item novo (20.002 casos), e as transições de medição, diário e aditivo |
| Sabotagem | 111 proteções retiradas, uma por vez; os testes perceberam as 111 |
| Domínio | 112 testes; as máquinas de estado percorrem todas as combinações de estado, ação e papel (954) |
| Workspace inteiro | `clippy -D warnings` e `cargo test --workspace`, incluindo o crate do Tauri compilado para Linux |
| Dependências | `cargo deny check` passa; `cargo audit` sai com zero erros e 2 avisos aceitos (bibliotecas GTK do Tauri no Linux, que não entram no `.exe`) |

**Números de aceite.** Os do cenário do engenheiro saem iguais no SQL de referência, na migração `0001` e em Rust: escavação 2.929,52; Rev. 0 de 58.551,28; fator 0,91059533; dreno a 47,35; aditivo 1 com 3.141,60, 1.486,00 e 1.894,00; 8,60% e 2,54%; Rev. 1 de 62.100,88; aditivo 2 simulado em 26,87%, acima do limite; medições de 6.990,90, 11.836,90 e 22.619,88; boletim nº 3 com 9.581,88, 1.894,00, 8.915,00 e 2.229,00; medido 41.447,68, saldo 20.653,20, 66,74% executado. Os do seed fictício também: pilares 26.014,74, alvenaria 16.641,60, total 164.039,34.

**Invariantes de `docs/10` §9.** 13 das 15 provadas, como combinado: tabela em `plano-fase-0.md` §5.

**Prova de que os testes pegam erro.** Além da sabotagem do banco, as contas em Rust foram estragadas de propósito duas vezes, e a paridade falhou nas duas (na segunda, só depois de eu acrescentar os casos que faltavam).

## 3. O que não foi testado

| O quê | Situação |
|---|---|
| **CI no GitHub** | **Nunca rodou.** O Actions não inicia nos repositórios privados da conta. O `ci.yml` foi reescrito e a sintaxe conferida, mas o ambiente do runner é outro; o primeiro uso real pode pedir ajuste |
| **Windows** | Só a prévia: o `Prumo.exe` foi recompilado no Windows com esta branch e aberto por máquina (§6). As telas não foram clicadas uma a uma nesta compilação. Nenhuma migração, teste de banco ou paridade rodou em Windows |
| **Celular** | Nada. `apps/mobile` não existe |
| **Banco real** | Nenhuma instalação. Só PostgreSQL 16.15 em contêiner descartável. Nenhum teste de volume, de concorrência (duas pessoas agindo na mesma medição ao mesmo tempo), de desempenho, de backup ou de restauração |
| **Dado real** | Nenhum. Tudo é fictício. Nenhuma planilha, cronograma ou contrato de prefeitura passou pelo sistema |
| **Aplicação usando o banco** | Não existe. Nada chama as máquinas de estado em Rust nem grava no banco fora dos testes. API e acesso ao banco são da Fase 1 |
| **Quem está na sessão** | O banco confia no `app.usuario_id` que a API informar. Login, senha e segundo fator não estão nesta fase, e o commit de login continua fora do repositório |
| **Migrar um banco que já tem dado** | As migrações só foram aplicadas em banco vazio |
| **Lei** | Nenhum artigo foi conferido no texto oficial. Há 10 marcas `TODO(jurídico)` no código e nas migrações |

## 4. O que foi suposto

São respostas provisórias. Cada uma está em `QUESTOES-ABERTAS.md` e muda trocando pouca coisa.

- **Quem faz o quê na medição** (questão 39): sem comissão, quem atesta é o gestor do contrato, pessoa diferente do fiscal que aprovou; ele também registra liquidação e pagamento; só a contratada cancela, e antes da análise.
- **Limites do art. 125 e preço do art. 127** (questão 40): reproduzidos do schema do engenheiro. Aditivo acima do limite não é homologado, sem exceção.
- **O que trava com a planilha vigente** (questões 37, 38 e 41): nome de frente e de agrupador, os cinco números da licitação e a forma de medir.
- **Glosa por quantidade** (questão 42): medição com glosa volta para a empresa corrigir; não há desconto.
- **Concluído com pendência não libera pagamento** (questão 19, anterior a esta fase).
- **Licenças das dependências** (questão 34): permissivas e MPL-2.0.

## 5. O que apareceu e precisa de decisão sua

1. **A soma dos eventos pode diferir do valor da planilha por centavos** (questão 36). O evento arredonda cada serviço em cada frente; a planilha arredonda o serviço inteiro. Em 8 de 12 contratos sorteados deu diferença. Pelo mesmo motivo, a revisão seguinte pode não valer "valor anterior mais valor do aditivo". O aceite da Fase 1 pede "soma dos eventos igual ao valor da revisão": do jeito que o engenheiro calcula, isso não se cumpre em contrato com serviço repartido em frentes. Vale perguntar a ele como a Caixa trata.
2. **O commit de login** (`4b1444f`) continua fora. Quando chegar, mexe em `Cargo.toml`, `ci.yml`, changelog, roadmap, questões 30 a 33 e ADR 0005, que deixei reservados.
3. **GitHub Actions.** Sem ele, a garantia de que nada quebrado entra é só o script local.
4. **Autoria e licença do schema do engenheiro** (questão 6). As nove migrações derivam dele. O repositório continua privado por isso.
5. **Conferência jurídica** dos pontos marcados, antes de qualquer uso real.
6. **Push da branch.** Não foi feito: não foi pedido.

## 6. Prévia de desktop

A fase não mexeu nas telas. Mudou uma conta que a prévia usa (`valor_item`, agora em inteiros), com os mesmos resultados.

O `Prumo.exe` da Área de Trabalho foi recompilado no Windows com esta branch em 13/10/2026, às 17:09 (1 min 21 s, Rust 1.99.0), e conferido por máquina: o executável foi aberto pela porta de depuração do WebView2 e o painel foi pedido ao Rust. Vieram o título "Prumo · Prefeitura de Exemplo (prévia)", as nove entradas do menu, o total de R$ 164.039,34 e os seis valores de evento (34.181,80, 26.014,74, 16.641,60, 38.920,00, 37.895,20 e 10.386,00). O executável anterior está em `C:\dev\prumo-anteriores`.

**Um erro meu no caminho.** A primeira tentativa de compilar não rodou: o `cmd.exe` não respondeu ao WSL. O `scripts/build-windows.sh` não percebeu, leu o log da compilação anterior e copiou para a Área de Trabalho um executável antigo, dizendo "Pronto". Vi pela data dos arquivos, corrigi o script (ele agora apaga o log antes de compilar e para se o Windows não responder) e compilei de novo. Por alguns minutos a Área de Trabalho ficou com um executável de antes desta fase, com o mesmo comportamento.

## 7. O que a Fase 1 encontra pronto, e o que não

Pronto: o banco com as regras, o seed para desenvolver, o domínio com as contas e as máquinas de estado, e uma suíte que acusa quando uma proteção some.

Não pronto, e é o começo da Fase 1: quem aplica as migrações numa instalação; a camada que liga o domínio ao banco; a API que define quem está na sessão; a autenticação; a leitura da planilha e do cronograma do órgão.
