-- O que deixa de mudar depois de a planilha ficar vigente (migração 0007; questões 37 e 38;
-- invariante 7 de docs/10 §9). Roda sobre o seed, como app_rw, no município de Exemplo.
SET ROLE app_rw;
SET app.tenant_id = 'e0e0e0e0-0000-0000-0000-000000000001';
SET app.usuario = 'teste.contrato';

\set c_ev '''e0e0e0e0-0000-0000-0000-0000000000c1'''
\set c_bm '''e0e0e0e0-0000-0000-0000-0000000000c2'''
\set c_novo '''e0e0e0e0-0000-0000-0000-0000000000c8'''

\echo
\echo '== Contrato com planilha vigente: os números da licitação não mudam =='
CALL pg_temp.espera_erro_com('mudar o valor inicial', 'não mudam depois de a planilha ficar vigente', ARRAY[
  format($$UPDATE contrato SET valor_inicial = 1 WHERE id = %L$$, :c_bm)]);
CALL pg_temp.espera_erro_com('mudar o orçamento-base (e com ele o fator do art. 127)', 'não mudam depois de a planilha ficar vigente', ARRAY[
  format($$UPDATE contrato SET valor_orcamento_base = valor_orcamento_base * 2 WHERE id = %L$$, :c_bm)]);
CALL pg_temp.espera_erro_com('mudar o critério de arredondamento', 'não mudam depois de a planilha ficar vigente', ARRAY[
  format($$UPDATE contrato SET criterio_arredondamento = 'arredondar' WHERE id = %L$$, :c_bm)]);
CALL pg_temp.espera_erro_com('mudar as casas decimais do preço', 'não mudam depois de a planilha ficar vigente', ARRAY[
  format($$UPDATE contrato SET casas_decimais_preco = 4 WHERE id = %L$$, :c_bm)]);
CALL pg_temp.espera_erro_com('marcar como reforma (o teto de acréscimos iria de 25% para 50%)', 'não mudam depois de a planilha ficar vigente', ARRAY[
  format($$UPDATE contrato SET reforma = true WHERE id = %L$$, :c_bm)]);
CALL pg_temp.espera_erro_com('trocar a forma de medir de quantidade para eventos', 'a forma de medir não muda', ARRAY[
  format($$UPDATE contrato SET forma_acompanhamento = 'eventos' WHERE id = %L$$, :c_bm)]);
CALL pg_temp.espera_erro_com('trocar a forma de medir de eventos para quantidade', 'a forma de medir não muda', ARRAY[
  format($$UPDATE contrato SET forma_acompanhamento = 'bm' WHERE id = %L$$, :c_ev)]);
CALL pg_temp.espera_erro_com('levar o contrato para outra obra', 'obra e órgão não mudam', ARRAY[
  format($$UPDATE contrato SET obra_id = 'e0e0e0e0-0000-0000-0000-0000000000b1' WHERE id = %L$$, :c_bm)]);
SELECT pg_temp.confere('fator do art. 127 intacto', (SELECT fator_art127 FROM contrato WHERE id = :c_bm), 0.91185334);
-- o que não é número da licitação continua editável
UPDATE contrato SET objeto = 'Pavimentação da Rua das Acácias, trecho 1' WHERE id = :c_bm;
SELECT pg_temp.confere_texto('o objeto pode ser corrigido', (SELECT objeto FROM contrato WHERE id = :c_bm), 'Pavimentação da Rua das Acácias, trecho 1');

\echo
\echo '== Contrato novo: a forma de medir é escolhida, e tudo muda enquanto a planilha é rascunho =='
CALL pg_temp.espera_erro('contrato sem forma de medir (não há padrão)', ARRAY[
  format($$INSERT INTO contrato (obra_id, orgao_id, numero, processo_licitatorio, objeto, regime_execucao, data_assinatura,
                                data_base_orcamento, prazo_execucao_dias, vigencia_fim, valor_inicial, valor_orcamento_base, bdi_percentual)
           SELECT obra_id, orgao_id, 'N-01/2026', 'x', 'x', 'empreitada_preco_global', '2026-09-14', '2026-05-01', 60, '2027-01-31',
                  100, 100, 0 FROM contrato WHERE id = %L$$, :c_ev)]);
INSERT INTO contrato (id, obra_id, orgao_id, numero, processo_licitatorio, objeto, regime_execucao, data_assinatura,
                      data_base_orcamento, prazo_execucao_dias, vigencia_fim, valor_inicial, valor_orcamento_base, bdi_percentual,
                      forma_acompanhamento)
SELECT :c_novo, obra_id, orgao_id, 'N-01/2026', 'Teste', 'Contrato novo', 'empreitada_preco_global', '2026-09-14', '2026-05-01',
       60, '2027-01-31', 100, 100, 0, 'bm' FROM contrato WHERE id = :c_ev;
INSERT INTO revisao_orcamento (id, contrato_id, numero, origem) VALUES ('e0e0e0e0-0000-0000-0000-0000000000d8', :c_novo, 0, 'importacao');
UPDATE contrato SET valor_inicial = 150, valor_orcamento_base = 160, criterio_arredondamento = 'truncar', reforma = true,
                    forma_acompanhamento = 'eventos' WHERE id = :c_novo;
SELECT pg_temp.confere_texto('forma de medir trocada com a planilha em rascunho',
  (SELECT forma_acompanhamento::text FROM contrato WHERE id = :c_novo), 'eventos');

-- Frente e agrupador do contrato novo: livres enquanto não viram evento de planilha vigente.
INSERT INTO frente_obra (id, contrato_id, ordem, nome) VALUES ('e0e0e0e0-0000-0000-0000-000000000fa8', :c_novo, 1, 'Bloco A');
INSERT INTO agrupador_evento (id, contrato_id, numero, titulo) VALUES ('e0e0e0e0-0000-0000-0000-000000000a98', :c_novo, 1, 'Piso');
UPDATE frente_obra SET nome = 'Bloco 1' WHERE id = 'e0e0e0e0-0000-0000-0000-000000000fa8';
UPDATE agrupador_evento SET titulo = 'Pisos' WHERE id = 'e0e0e0e0-0000-0000-0000-000000000a98';
INSERT INTO item_contratual (id, contrato_id) VALUES
  ('e0e0e0e0-0000-0000-0000-000000000108', :c_novo), ('e0e0e0e0-0000-0000-0000-000000000118', :c_novo);
INSERT INTO item_revisao (id, revisao_id, item_contratual_id, parent_id, ordem, codigo_eap, tipo, descricao) VALUES
  ('e0e0e0e0-0000-0000-0000-000000000208', 'e0e0e0e0-0000-0000-0000-0000000000d8', 'e0e0e0e0-0000-0000-0000-000000000108', NULL, 1, '1', 'grupo', 'PISO');
INSERT INTO item_revisao (id, revisao_id, item_contratual_id, parent_id, ordem, codigo_eap, tipo, descricao, unidade, quantidade,
                          preco_unitario, agrupador_evento_id) VALUES
  ('e0e0e0e0-0000-0000-0000-000000000218', 'e0e0e0e0-0000-0000-0000-0000000000d8', 'e0e0e0e0-0000-0000-0000-000000000118',
   'e0e0e0e0-0000-0000-0000-000000000208', 1, '1.1', 'servico', 'Piso', 'm²', 10, 15.00, 'e0e0e0e0-0000-0000-0000-000000000a98');
INSERT INTO item_frente (item_revisao_id, frente_id, quantidade) VALUES
  ('e0e0e0e0-0000-0000-0000-000000000218', 'e0e0e0e0-0000-0000-0000-000000000fa8', 10);
UPDATE revisao_orcamento SET status = 'vigente', data_vigencia = DATE '2026-09-14' WHERE id = 'e0e0e0e0-0000-0000-0000-0000000000d8';
-- 10,00 × 15,00
SELECT pg_temp.confere('evento calculado na publicação', (SELECT valor FROM evento WHERE revisao_id = 'e0e0e0e0-0000-0000-0000-0000000000d8'), 150.00);
CALL pg_temp.espera_erro_com('depois de publicada, o contrato novo também trava', 'não mudam depois de a planilha ficar vigente', ARRAY[
  format($$UPDATE contrato SET valor_inicial = 151 WHERE id = %L$$, :c_novo)]);

\echo
\echo '== Frente e agrupador que viraram evento de planilha vigente não mudam =='
CALL pg_temp.espera_erro_com('renomear frente de evento vigente', 'A frente já faz parte de evento', ARRAY[
  $$UPDATE frente_obra SET nome = 'Outro pavimento' WHERE nome = 'Térreo'$$]);
CALL pg_temp.espera_erro_com('renomear agrupador de evento vigente', 'O agrupador já faz parte de evento', ARRAY[
  $$UPDATE agrupador_evento SET titulo = 'Outra coisa' WHERE titulo = 'Fundações'$$]);
CALL pg_temp.espera_erro_com('apagar frente de evento vigente', 'A frente já faz parte de evento', ARRAY[
  $$DELETE FROM frente_obra WHERE nome = 'Térreo'$$]);
CALL pg_temp.espera_erro_com('renomear a frente do contrato novo, agora publicada', 'A frente já faz parte de evento', ARRAY[
  $$UPDATE frente_obra SET nome = 'Bloco 2' WHERE id = 'e0e0e0e0-0000-0000-0000-000000000fa8'$$]);
-- frente nova, para uma próxima revisão, continua livre até virar evento
INSERT INTO frente_obra (id, contrato_id, ordem, nome) VALUES ('e0e0e0e0-0000-0000-0000-000000000fb8', :c_ev, 2, '1º pavimento');
UPDATE frente_obra SET nome = 'Primeiro pavimento' WHERE id = 'e0e0e0e0-0000-0000-0000-000000000fb8';
DELETE FROM frente_obra WHERE id = 'e0e0e0e0-0000-0000-0000-000000000fb8';
SELECT pg_temp.confere('frentes do contrato 045/2026 depois do ensaio', (SELECT count(*) FROM frente_obra WHERE contrato_id = :c_ev), 1);

RESET ROLE;
