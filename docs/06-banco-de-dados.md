# 06 · Banco de dados: como adaptar o schema de referência

`db/reference/schema.sql` e `db/reference/seed_e_testes.sql` foram escritos por um engenheiro civil para um **SaaS do lado da construtora** (PostgreSQL 16). São um ótimo ponto de partida porque já resolvem as partes mais difíceis e fáceis de errar em obra pública: revisão de planilha, medição, aditivo, limites legais, RLS e auditoria. **Não são o banco final da prefeitura.**

> Antes de publicar o repositório: confirmar autoria e licença desses arquivos com quem os escreveu. O teste `teste_hospital_quitandinha.sql` (382 KB, gerado a partir de planilhas reais) **não** foi copiado para o repositório; anonimizar antes de qualquer publicação.

## 1. O que o schema de referência já tem (reaproveitar)

| Bloco | Tabelas / objetos | Observação |
|---|---|---|
| Tenancy | `tenant`, `app_tenant()`, políticas RLS | Reaproveitar, mudando o significado do tenant |
| Cadastros | `orgao`, `fornecedor`, `funcionario`, `equipamento`, `obra`, `convenio` | Ajustar papéis (ver §3) |
| Contrato | `contrato`, `contrato_retencao` | Já guarda regime (art. 46), data-base, BDI, arredondamento, **`reforma`**, `fator_art127` gerado, repasse/convênio |
| Planilha | `revisao_orcamento`, `item_contratual`, `item_revisao` (com `ltree`) | **Revisão imutável** + item que atravessa revisões: excelente |
| Medição | `medicao`, `medicao_item`, `medicao_glosa`, `fn_boletim_medicao` | Invariantes por trigger; boletim por revisão |
| **Eventos** (modelo Caixa) | `frente_obra`, `agrupador_evento`, `item_frente`, `evento`, `medicao_evento`, `cronograma_parcela`, `vw_rre_medicao`, `fn_recalcular_eventos`, `fn_aplicar_eventos` | É a **forma prioritária** do Prumo. Na referência chama-se `ple`; aqui vira `eventos` (ver §2 e §4) |
| Aditivo | `aditivo`, `aditivo_item`, `fn_limites_aditivos` | Acréscimo, supressão, inclusão, **restabelecimento** (TCU 66/2021) |
| Bases de preço | `base_referencia`, `preco_referencia` | SINAPI e afins |
| Importação | `importacao`, `importacao_linha`, `classe_linha` | Heurística + staging + revisão; ponto de entrada da IA-12 |
| RDO | `rdo`, `rdo_efetivo`, `rdo_equipamento`, `rdo_ocorrencia`, `rdo_foto` | Fotos com GPS e hora |
| Financeiro da empresa | `plano_contas`, `titulo*`, `baixa`, `cotacao*`, `pedido_compra*`, `rateio*`, `apropriacao` | **Específico de construtora** (ver §2) |
| Infra | `auditoria`, `outbox`, `fn_auditar` | Reaproveitar integralmente |

O arquivo de teste usa o utilitário `pg_temp.espera_erro(...)`: executa comandos e **exige** que sejam bloqueados. Esse estilo é a base da suíte de invariantes do novo projeto (CI roda contra Postgres real).

## 2. O que muda de lado (construtora → prefeitura)

| Assunto | Schema de referência | Sistema da prefeitura |
|---|---|---|
| **Quem é o tenant** | A construtora; `orgao` é cliente | **O município**. `orgao` vira "unidade gestora"; empresas viram `empresa` com usuários externos |
| **Quem aprova a medição** | `aprovada_por text` (nome do fiscal, informado) | **Usuário designado** (`designacao_fiscal`), com perfil, portaria e data; `aprovada_por` vira FK |
| **Financeiro** | Contas a pagar/receber, rateio, fluxo de caixa **da empresa** | Fica **fora do núcleo**. A prefeitura precisa de *execução financeira do contrato* (empenho, liquidação, pagamento como **referências**) |
| **Suprimentos** | Cotação, pedido de compra, apropriação de custo | Vira módulo opcional **E04 da empresa**, não da prefeitura |
| **Status da medição** | `rascunho → enviada → aprovada` | `rascunho → enviada → em_analise → devolvida/aprovada_fiscal → (comissão) → atestada → liquidada → paga` |
| **Diário** | `rdo` com `status` `rascunho/fechado/assinado` | Acrescentar `em_validacao/validado/devolvido` e **instruções do fiscal** como entradas separadas |
| **Serviço executado no diário** | Linha de `rdo_ocorrencia` com `tipo = 'servico_executado'` | Tabela própria `rdo_servico`, com `item_contratual_id`, `frente_id`, quantidade e unidade. É o vínculo que alimenta boletim, relatórios e a detecção de serviço a mais |
| **Ocorrências** | `rdo_ocorrencia` (dentro do diário) | Tabelas próprias de **fiscalização**: `ocorrencia`, `notificacao`, `vistoria` |
| **Forma de medir** | Enum `forma_acompanhamento ('bm', 'ple')`, padrão `'bm'` | Enum `('eventos', 'bm')`. A forma é **escolhida** no cadastro do contrato, com `eventos` sugerida conforme o regime; `ple`, `cronople` e `rre` passam a ser nomes de layout de exportação |
| **Quem diz que o evento está concluído** | A empresa marca `medicao_evento` | A empresa declara; o **Boletim de Execução** do fiscal confirma; a aprovação exige o boletim |
| **Cronograma** | `evento.periodo_previsto` (número do período) e `cronograma_parcela` (% por grupo e período) | Acrescentar **datas** e **versões** (linha de base imutável, reprogramações), necessárias para a previsão |
| **Fotos** | `rdo_foto` (chave do arquivo, legenda, hora, coordenada) | Tabela única `foto` para diário, vistoria e boletim, com hash, precisão do GPS, autor e vínculo com frente, serviço e evento |

## 3. O que acrescentar (novo)

```
servidor (matrícula, cargo, cpf_hash)               ← pessoas do poder público
portaria (número, data, objeto, arquivo)            ← ato que designa
designacao (servidor_id, contrato_id, funcao, inicio, fim, portaria_id)
   funcao ∈ {gestor_contrato, fiscal_tecnico, fiscal_administrativo, fiscal_substituto, comissao_medicao, comissao_recebimento}
empresa (cnpj, razao_social, ...)  +  usuario_externo (empresa_id, contrato_id, papel)
responsabilidade_tecnica (contrato_id, profissional, conselho, numero_art_rrt, arquivo, vigencia)
garantia_contratual / seguro (tipo, valor, vigencia, arquivo)
ordem_servico (contrato_id, tipo{inicio,paralisacao,retomada}, data, motivo)
ocorrencia, notificacao (prazo_resposta_dias, status), vistoria (checklist jsonb), plano_acao
recebimento (tipo{provisorio,definitivo}, termo_arquivo, data, pendencias)
garantia_obra (recebimento_definitivo_id, prazo_anos >= 5, vence_em)       ← art. 140 §6º
medicao_etapa (medicao_id, etapa, usuario_id, decisao, em, parecer)        ← trilha de aprovação
medicao_item_analise (glosa por item, motivo estruturado, evidência)
rdo_validacao, rdo_instrucao, rdo_retificacao
pleito (tipo, justificativa, anexos, status)                               ← E06
execucao_financeira_ref (contrato_id, empenho, liquidacao, pagamento, valor, data)
publicacao (alvo{pncp,tce,portal}, payload, status, protocolo)
denuncia (canal, texto, obra_id?, status, ocorrencia_id?)
ia_decisao (acao, classe, modelo, versao, confianca, desfecho, contrato_id, ...)   ← L6/LP5
config_municipio (prazos de recebimento, comissão exigida?, limiares de IA, ...)   ← nada disso hardcoded
```

### 3.1 Eventos, boletim, previsão e relatórios (ver `10-execucao-eventos-previsao.md`)

```
-- o que o órgão fornece
documento_orgao (contrato_id, tipo{planilha, cronograma, eventograma, projeto, memorial, outro},
                 nome, arquivo_sha256, recebido_em, enviado_por, importacao_id?)
prancha (documento_id, numero, titulo, disciplina, revisao, escala, data, pagina)
prancha_vinculo (prancha_id, alvo{grupo_eap, frente, agrupador}, alvo_id,
                 origem{manual, sugestao_aceita})

-- cronograma com datas e versões
cronograma_versao (contrato_id, revisao_id, numero, tipo{linha_de_base, reprogramacao},
                   status{rascunho, vigente, substituida}, documento_id?, aditivo_id?, motivo, autor)
cronograma_evento (cronograma_versao_id, evento_id, inicio_previsto, termino_previsto, periodo)
cronograma_predecessora (cronograma_versao_id, evento_id, predecessora_evento_id)
calendario_obra (contrato_id, data, trabalhavel, motivo)   ← feriados e dias sem expediente;
                                                              chuva vem do `rdo.praticavel` validado

-- fiscalização
boletim_execucao (contrato_id, numero, periodo_inicio, periodo_fim, status{rascunho, emitido},
                  emitido_por → designacao, emitido_em, retifica_id?, cronograma_versao_id)
boletim_execucao_linha (boletim_id, evento_id | item_contratual_id, situacao, avanco_percentual,
                        verificado_em, observacao)
   situacao ∈ {nao_iniciado, em_andamento, concluido, concluido_com_pendencia, paralisado}
boletim_execucao_evidencia (linha_id, tipo{foto, vistoria, rdo}, ref_id)
medicao_evento_analise (medicao_evento_id, decisao{aceito, glosado}, motivo,
                        boletim_execucao_linha_id?, usuario_id, em)   ← glosa do evento inteiro

-- evidência e diário
foto (origem{camera_app}, sha256, chave_arquivo, tirada_em, offset_relogio, latitude, longitude,
      precisao_m, autor, legenda, rdo_id?, vistoria_id?, boletim_linha_id?,
      item_contratual_id?, frente_id?, evento_id?,
      vinculo_origem{captura, manual, sugestao_aceita}, vinculo_confirmado_por)
rdo_servico (rdo_id, item_contratual_id?, frente_id?, descricao, quantidade, unidade)

-- serviços a mais
servico_extra (contrato_id, origem{diario, vistoria, boletim_execucao, pleito}, origem_id,
               tipo{acrescimo, servico_novo}, item_contratual_id?, frente_id?, descricao, unidade,
               quantidade_estimada, status{apontado, em_analise, aceito, recusado, incluido_em_aditivo},
               decidido_por, motivo, aditivo_item_id?)

-- previsão (nunca é dado oficial)
previsao_calculo (contrato_id, calculado_em, versao_algoritmo, cronograma_versao_id,
                  boletim_execucao_id, parametros jsonb, fator_ritmo, termino_previsto, desvio_dias)
previsao_evento (calculo_id, evento_id, inicio_previsto, termino_previsto,
                 metodo{real, ritmo, linha_de_base_ajustada},
                 medicao_prevista_em, pagamento_previsto_em, valor_bruto, retencoes, valor_liquido)

-- relatórios
relatorio_emitido (contrato_id, tipo{boletim_execucao, planilha_medicao, relatorio_fotografico,
                   caderno_medicao, planilha_aditivo, previsao, rdo}, numero, versao_modelo,
                   arquivo_sha256, emitido_por, emitido_em, substitui_id?, origem jsonb)

-- config_municipio / contrato ganham (nada disso no código):
--   periodicidade do boletim de execução; evidência mínima para "concluído";
--   prazos de processo (envio, análise, comissão, atesto e liquidação, pagamento) e se são dias úteis ou corridos;
--   regra de fechamento do período de medição; limiares da previsão (avanço mínimo, eventos mínimos, faixa do fator)
```

## 4. Pontos de cuidado já visíveis no schema

1. `medicao.revisao_id` fixa a medição à revisão vigente quando aberta. **Manter.** Uma medição não migra de revisão.
2. `EXCLUDE USING gist` impede períodos sobrepostos. **Manter.**
3. `aditivo.revisao_base_id` + `revisao_resultante_id` ligam aditivo a revisão. **Manter**, e o caso de uso `HomologarAditivo` fica na camada de aplicação (o seed mostra em SQL só para provar o modelo).
4. `casas_decimais_preco` e `criterio_arredondamento` por contrato: o cálculo **tem que usar os mesmos** no Rust e no SQL; criar testes de paridade (mesmas entradas, mesmo centavo).
5. `rdo.sincronizado_em` já antecipa o app offline.
6. `rdo_foto.s3_key`: padronizar armazenamento de arquivos (hash + chave) e **guardar o hash** no banco.
7. O `auditoria.usuario` é `text` vindo de `app.usuario`: garantir que a API sempre define essa variável na sessão.
8. Tabelas sem `tenant_id` (ex.: bases de referência públicas) têm política de leitura própria; revisar a política de escrita.
9. **Evento glosado tem que poder voltar.** O trigger `fn_medicao_evento_guard` da referência bloqueia qualquer evento que já esteja em medição não cancelada ("Evento já medido anteriormente"). Com a glosa do evento inteiro, a regra passa a ser: já medido = presente em medição não cancelada **e não glosado**. Sem esse ajuste, um evento glosado nunca mais poderia ser pago.
10. **Evento medido não muda.** `fn_evento_guard` já impede mudar valor e composição fora do rascunho. Na Rev. N+1 gerada por aditivo, acréscimo em frente já medida entra como evento novo (frente ou agrupador complementar), nunca recalculando o evento medido (questão 20).
11. **`evento.periodo_previsto` não basta para a previsão.** A referência guarda só o número do período e permite reprogramar sem histórico. As datas e as versões ficam em `cronograma_versao` e `cronograma_evento`; o campo antigo vira derivado.
12. **A aprovação da medição lê o boletim, mas a previsão não entra em regra nenhuma.** Nenhum trigger ou caso de uso de aprovação, glosa ou pagamento pode consultar `previsao_*`.
13. **`fn_recalcular_eventos` e o cálculo em Rust têm que dar o mesmo centavo.** Entra na suíte de paridade junto com `fn_valor_item`.
14. **O modelo de eventos da referência não tem teste neste repositório.** `seed_e_testes.sql` não cria frente, agrupador nem evento; o teste que os exercitava usava dados reais e não foi copiado. Como eventos são a forma prioritária, a Fase 0 precisa de seed fictício e de testes de bloqueio para todos os triggers de eventos antes de qualquer outra coisa depender deles.

## 5. Plano de migração

1. Criar `db/migrations/0001_base.sql` a partir de `reference/schema.sql` **sem** o bloco financeiro da empresa.
2. `0002_prefeitura_pessoas.sql`: servidor, portaria, designação, empresa, usuário externo.
3. `0003_fiscalizacao.sql`: ocorrência, notificação, vistoria, recebimento, garantia.
4. `0004_medicao_fluxo.sql`: novos estados e trilha de aprovação.
5. `0005_rdo_fluxo.sql`: validação, instruções, retificação.
6. `0006_publicacao_ia.sql`: publicação, `ia_decisao`, config do município.
7. `0007_documentos_cronograma.sql`: `documento_orgao`, pranchas e vínculos, cronograma com datas e versões, calendário da obra; enum `forma_acompanhamento` como `('eventos', 'bm')`.
8. `0008_boletim_execucao.sql`: boletim, linhas, evidências, `foto` unificada, `rdo_servico`, `medicao_evento_analise` e o ajuste do item 9 do §4.
9. `0009_servico_extra_previsao_relatorios.sql`: `servico_extra`, `previsao_*`, `relatorio_emitido`.
10. Cada migração tem **testes de invariante** no estilo `espera_erro`, rodados em CI contra Postgres 16 real. As invariantes novas estão listadas em `10-execucao-eventos-previsao.md` §9.
11. Seed de demonstração **fictício** (município de Exemplo), nunca dados reais. O seed inclui um contrato por eventos e um por quantidade.

A ordem de 0007 a 0009 segue a prioridade do produto: como eventos vêm primeiro, 0007 e 0008 são pré-requisito da Fase 2 do roadmap.

## 6. Como as migrações são aplicadas e provadas

Decisões em `adr/0006-migracoes-sql-com-registro.md` e `adr/0007-tenant-municipio-rls-app-rw.md`.

- Cada migração é um arquivo SQL sem `BEGIN` nem `COMMIT`. Quem aplica abre a transação e grava, junto, a linha em `migracao_aplicada` (versão, nome, SHA-256, hora).
- `db/migrations/SHA256SUMS` guarda o SHA-256 de cada migração. Arquivo registrado não muda.
- `scripts/db-test.sh` sobe um PostgreSQL 16 descartável e roda cinco suítes:

| Suíte | O que prova |
|---|---|
| `referencia` | O schema e o seed do engenheiro rodam sem alteração: 12 bloqueios e os 26 números de aceite |
| `porte` | A `0001` tem o mesmo catálogo da referência (tirando o que saiu de propósito) e dá os mesmos 12 bloqueios e 26 números |
| `migracoes` | Numeração e registro; aplicar duas vezes não faz nada; arquivo diferente do aplicado é recusado; o seed fictício carrega; e cada arquivo de `db/tests/*.sql` roda numa cópia limpa do banco migrado e semeado |
| `paridade` | As contas em Rust dão o mesmo centavo que o SQL (`crates/paridade`, ADR 0008) |
| `sabotagem` | Retira uma proteção por vez e exige que o teste correspondente acuse |

- Arquivos de teste: `estrutura.sql` (regras de RLS e do papel `app_rw`, conferidas no catálogo), `isolamento.sql` (dois municípios fictícios) e `eventos.sql` (valores do seed e bloqueio de cada gatilho de eventos). Os próximos entram na mesma pasta, um por assunto.
- `db/seed/exemplo.sql` é o seed fictício: município de Exemplo, um contrato por eventos (a mesma planilha da prévia de desktop) e um por quantidade. É SQL puro e não guarda valor calculado: o banco calcula.
- `db/tests/_util.sql` traz os utilitários: `espera_erro` (exige o bloqueio), `espera_erro_com` (exige o bloqueio e o motivo), `confere` e `confere_texto` (exigem o valor exato) e `confere_vazio` (exige que uma consulta não devolva nada).
- `PRUMO_DB_SAIDA=pasta` guarda a saída completa de cada teste, com o motivo de cada bloqueio. Vale ler: `espera_erro` aceita qualquer erro, inclusive erro de digitação no próprio teste.

