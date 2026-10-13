-- Medição por eventos: valores do seed fictício e bloqueio de cada gatilho de eventos.
-- Roda sobre o seed (db/seed/exemplo.sql), como app_rw, no município de Exemplo.
-- Os valores esperados foram calculados à mão; a conta de cada um está no comentário.
-- Os bloqueios exigem o motivo (espera_erro_com): várias destas regras têm mais de uma camada
-- de proteção, e sem o motivo o teste passaria mesmo com o gatilho certo desligado.
-- Até a migração 0007 o banco chama a medição por eventos de 'ple' e a por quantidade de 'bm'.
SET ROLE app_rw;
SET app.tenant_id = 'e0e0e0e0-0000-0000-0000-000000000001';
SET app.usuario = 'teste.eventos';

SELECT id AS c_ev FROM contrato WHERE numero = '045/2026' \gset
SELECT id AS c_bm FROM contrato WHERE numero = '052/2026' \gset
SELECT id AS rev_ev FROM revisao_orcamento WHERE contrato_id = :'c_ev' AND numero = 0 \gset
SELECT id AS rev_bm FROM revisao_orcamento WHERE contrato_id = :'c_bm' AND numero = 0 \gset

-- Valor do evento de um agrupador do contrato por eventos (o seed tem uma frente só).
CREATE FUNCTION pg_temp.valor_do_evento(p_numero int) RETURNS numeric LANGUAGE sql AS $$
  SELECT e.valor FROM evento e
    JOIN agrupador_evento a ON a.id = e.agrupador_id
    JOIN contrato c         ON c.id = a.contrato_id
   WHERE c.numero = '045/2026' AND a.numero = p_numero
$$;
CREATE FUNCTION pg_temp.evento_do_agrupador(p_contrato text, p_numero int, p_frente text) RETURNS uuid LANGUAGE sql AS $$
  SELECT e.id FROM evento e
    JOIN agrupador_evento a ON a.id = e.agrupador_id
    JOIN frente_obra f      ON f.id = e.frente_id
    JOIN contrato c         ON c.id = a.contrato_id
   WHERE c.numero = p_contrato AND a.numero = p_numero AND f.nome = p_frente
$$;
CREATE FUNCTION pg_temp.item(p_contrato text, p_codigo text) RETURNS uuid LANGUAGE sql AS $$
  SELECT ir.item_contratual_id FROM item_revisao ir
    JOIN revisao_orcamento r ON r.id = ir.revisao_id
    JOIN contrato c          ON c.id = r.contrato_id
   WHERE c.numero = p_contrato AND r.numero = 0 AND ir.codigo_eap = p_codigo
$$;

\echo
\echo '== Seed: valor de cada evento do contrato 045/2026 (critério: arredondar) =='
-- 86,00 × 68,45 = 5.886,70 · 920,00 × 9,84 = 9.052,80 · 24,50 × 785,40 = 19.242,30
SELECT pg_temp.confere('Fundações × Térreo', pg_temp.valor_do_evento(1), 34181.80);
-- 96,00 × 62,30 = 5.980,80 · 1.150,00 × 9,84 = 11.316,00 · 11,10 × 785,40 = 8.717,94
SELECT pg_temp.confere('Estrutura: pilares × Térreo', pg_temp.valor_do_evento(2), 26014.74);
-- 160,00 × 89,15 = 14.264,00 · 320,00 × 7,43 = 2.377,60
SELECT pg_temp.confere('Alvenaria × Térreo', pg_temp.valor_do_evento(3), 16641.60);
-- 280,00 × 74,50 = 20.860,00 · 280,00 × 64,50 = 18.060,00
SELECT pg_temp.confere('Cobertura × Térreo', pg_temp.valor_do_evento(4), 38920.00);
-- 64,00 × 142,80 = 9.139,20 · 38,00 × 168,50 = 6.403,00 · 320,00 × 31,20 = 9.984,00 · 210,00 × 58,90 = 12.369,00
SELECT pg_temp.confere('Instalações e revestimentos × Térreo', pg_temp.valor_do_evento(5), 37895.20);
-- 640,00 × 14,85 = 9.504,00 · 210,00 × 4,20 = 882,00
SELECT pg_temp.confere('Pintura e limpeza final × Térreo', pg_temp.valor_do_evento(6), 10386.00);
SELECT pg_temp.confere('eventos do contrato', (SELECT count(*) FROM evento WHERE revisao_id = :'rev_ev'), 6);
SELECT pg_temp.confere('soma dos eventos', (SELECT sum(valor) FROM evento WHERE revisao_id = :'rev_ev'), 164039.34);
SELECT pg_temp.confere('valor da planilha (Rev. 0)', (SELECT valor_total FROM revisao_orcamento WHERE id = :'rev_ev'), 164039.34);
-- 164.039,34 ÷ 178.000,00 = 0,921569325...
SELECT pg_temp.confere('fator do art. 127', (SELECT fator_art127 FROM contrato WHERE id = :'c_ev'), 0.92156933);

\echo
\echo '== Seed: contrato 052/2026, por quantidade (critério: truncar) =='
-- 4,50 × 412,37 = 1.855,665 (arredondado daria 1.855,67)
SELECT pg_temp.confere('1.1 placa de obra', (SELECT valor_total FROM item_revisao WHERE revisao_id = :'rev_bm' AND codigo_eap = '1.1'), 1855.66);
-- 378,50 × 9,43 = 3.569,255
SELECT pg_temp.confere('2.2 escavação e carga', (SELECT valor_total FROM item_revisao WHERE revisao_id = :'rev_bm' AND codigo_eap = '2.2'), 3569.25);
-- 189,25 × 142,55 = 26.977,5875
SELECT pg_temp.confere('3.1 base de brita', (SELECT valor_total FROM item_revisao WHERE revisao_id = :'rev_bm' AND codigo_eap = '3.1'), 26977.58);
-- 63,35 × 27,90 = 1.767,465
SELECT pg_temp.confere('4.2 sinalização horizontal', (SELECT valor_total FROM item_revisao WHERE revisao_id = :'rev_bm' AND codigo_eap = '4.2'), 1767.46);
-- 1.855,66 + 3.850,00 + 3.616,20 + 3.569,25 + 26.977,58 + 7.786,80 + 70.897,68 + 16.275,00 + 1.767,46
-- (com arredondamento daria 136.595,67: os quatro itens acima perderiam um centavo cada)
SELECT pg_temp.confere('valor da planilha (Rev. 0)', (SELECT valor_total FROM revisao_orcamento WHERE id = :'rev_bm'), 136595.63);
SELECT pg_temp.confere('eventos em contrato por quantidade', (SELECT count(*) FROM evento WHERE revisao_id = :'rev_bm'), 0);
-- 136.595,63 ÷ 149.800,00 = 0,911853337...
SELECT pg_temp.confere('fator do art. 127', (SELECT fator_art127 FROM contrato WHERE id = :'c_bm'), 0.91185334);

-- -----------------------------------------------------------------------------
-- Contrato de teste, em rascunho, com dois serviços e duas frentes.
--   1.1 Serviço A   3,00 m² × 0,33  = 0,99      frentes: 1,50 e 1,50
--   1.2 Serviço B  10,00 m  × 12,50 = 125,00    frentes: 4,00 e 6,00
--   planilha: 125,99
-- -----------------------------------------------------------------------------
INSERT INTO contrato (id, obra_id, orgao_id, numero, processo_licitatorio, objeto, regime_execucao, data_assinatura,
                      data_base_orcamento, prazo_execucao_dias, vigencia_fim, valor_inicial, valor_orcamento_base,
                      bdi_percentual, criterio_arredondamento, forma_acompanhamento)
SELECT 'e0e0e0e0-0000-0000-0000-0000000000c9', obra_id, orgao_id, 'T-01/2026', 'Teste', 'Contrato de teste',
       'empreitada_preco_global', '2026-09-14', '2026-05-01', 60, '2027-01-31', 125.99, 130.00, 20, 'arredondar', 'ple'
  FROM contrato WHERE id = :'c_ev';
INSERT INTO revisao_orcamento (id, contrato_id, numero, origem) VALUES
  ('e0e0e0e0-0000-0000-0000-0000000000d9', 'e0e0e0e0-0000-0000-0000-0000000000c9', 0, 'importacao');
INSERT INTO frente_obra (id, contrato_id, ordem, nome) VALUES
  ('e0e0e0e0-0000-0000-0000-000000000fa9', 'e0e0e0e0-0000-0000-0000-0000000000c9', 1, 'Bloco A'),
  ('e0e0e0e0-0000-0000-0000-000000000fb9', 'e0e0e0e0-0000-0000-0000-0000000000c9', 2, 'Bloco B');
INSERT INTO agrupador_evento (id, contrato_id, numero, titulo) VALUES
  ('e0e0e0e0-0000-0000-0000-000000000a99', 'e0e0e0e0-0000-0000-0000-0000000000c9', 1, 'Piso');
INSERT INTO item_contratual (id, contrato_id) VALUES
  ('e0e0e0e0-0000-0000-0000-000000000109', 'e0e0e0e0-0000-0000-0000-0000000000c9'),
  ('e0e0e0e0-0000-0000-0000-000000000119', 'e0e0e0e0-0000-0000-0000-0000000000c9'),
  ('e0e0e0e0-0000-0000-0000-000000000129', 'e0e0e0e0-0000-0000-0000-0000000000c9');
INSERT INTO item_revisao (id, revisao_id, item_contratual_id, parent_id, ordem, codigo_eap, tipo, descricao) VALUES
  ('e0e0e0e0-0000-0000-0000-000000000209', 'e0e0e0e0-0000-0000-0000-0000000000d9',
   'e0e0e0e0-0000-0000-0000-000000000109', NULL, 1, '1', 'grupo', 'PISO');
-- O serviço B nasce sem agrupador e com 9,00 nas frentes, de propósito.
INSERT INTO item_revisao (id, revisao_id, item_contratual_id, parent_id, ordem, codigo_eap, tipo, descricao,
                          unidade, quantidade, preco_unitario, agrupador_evento_id) VALUES
  ('e0e0e0e0-0000-0000-0000-000000000219', 'e0e0e0e0-0000-0000-0000-0000000000d9', 'e0e0e0e0-0000-0000-0000-000000000119',
   'e0e0e0e0-0000-0000-0000-000000000209', 1, '1.1', 'servico', 'Serviço A', 'm²', 3.00, 0.33,
   'e0e0e0e0-0000-0000-0000-000000000a99'),
  ('e0e0e0e0-0000-0000-0000-000000000229', 'e0e0e0e0-0000-0000-0000-0000000000d9', 'e0e0e0e0-0000-0000-0000-000000000129',
   'e0e0e0e0-0000-0000-0000-000000000209', 2, '1.2', 'servico', 'Serviço B', 'm', 10.00, 12.50, NULL);
INSERT INTO item_frente (item_revisao_id, frente_id, quantidade) VALUES
  ('e0e0e0e0-0000-0000-0000-000000000219', 'e0e0e0e0-0000-0000-0000-000000000fa9', 1.50),
  ('e0e0e0e0-0000-0000-0000-000000000219', 'e0e0e0e0-0000-0000-0000-000000000fb9', 1.50),
  ('e0e0e0e0-0000-0000-0000-000000000229', 'e0e0e0e0-0000-0000-0000-000000000fa9', 4.00),
  ('e0e0e0e0-0000-0000-0000-000000000229', 'e0e0e0e0-0000-0000-0000-000000000fb9', 5.00);

\echo
\echo '== Planilha por eventos só fica vigente com tudo distribuído =='
CALL pg_temp.espera_erro_com('serviço sem agrupador',
  'sem agrupador ou com quantidade não distribuída', ARRAY[
  $$UPDATE revisao_orcamento SET status = 'vigente' WHERE id = 'e0e0e0e0-0000-0000-0000-0000000000d9'$$]);
UPDATE item_revisao SET agrupador_evento_id = 'e0e0e0e0-0000-0000-0000-000000000a99'
 WHERE id = 'e0e0e0e0-0000-0000-0000-000000000229';
CALL pg_temp.espera_erro_com('quantidade nas frentes menor que a da planilha (9,00 de 10,00)',
  'sem agrupador ou com quantidade não distribuída', ARRAY[
  $$UPDATE revisao_orcamento SET status = 'vigente' WHERE id = 'e0e0e0e0-0000-0000-0000-0000000000d9'$$]);
CALL pg_temp.espera_erro_com('quantidade nas frentes maior que a da planilha (11,00 de 10,00)',
  'sem agrupador ou com quantidade não distribuída', ARRAY[
  $$UPDATE item_frente SET quantidade = 7.00
     WHERE item_revisao_id = 'e0e0e0e0-0000-0000-0000-000000000229' AND frente_id = 'e0e0e0e0-0000-0000-0000-000000000fb9'$$,
  $$UPDATE revisao_orcamento SET status = 'vigente' WHERE id = 'e0e0e0e0-0000-0000-0000-0000000000d9'$$]);
CALL pg_temp.espera_erro_com('distribuir um grupo em frente',
  'Só serviços são distribuídos em frentes', ARRAY[
  $$INSERT INTO item_frente (item_revisao_id, frente_id, quantidade) VALUES
      ('e0e0e0e0-0000-0000-0000-000000000209', 'e0e0e0e0-0000-0000-0000-000000000fa9', 1)$$]);
CALL pg_temp.espera_erro('quantidade zero numa frente', ARRAY[
  $$UPDATE item_frente SET quantidade = 0 WHERE item_revisao_id = 'e0e0e0e0-0000-0000-0000-000000000229'$$]);
CALL pg_temp.espera_erro('o mesmo serviço duas vezes na mesma frente', ARRAY[
  $$INSERT INTO item_frente (item_revisao_id, frente_id, quantidade) VALUES
      ('e0e0e0e0-0000-0000-0000-000000000219', 'e0e0e0e0-0000-0000-0000-000000000fa9', 1)$$]);

-- Valor de evento digitado com a planilha em rascunho não sobrevive: ao ficar vigente, o banco recalcula.
INSERT INTO evento (revisao_id, agrupador_id, frente_id, valor) VALUES
  ('e0e0e0e0-0000-0000-0000-0000000000d9', 'e0e0e0e0-0000-0000-0000-000000000a99',
   'e0e0e0e0-0000-0000-0000-000000000fa9', 999.99);
UPDATE item_frente SET quantidade = 6.00
 WHERE item_revisao_id = 'e0e0e0e0-0000-0000-0000-000000000229' AND frente_id = 'e0e0e0e0-0000-0000-0000-000000000fb9';
UPDATE revisao_orcamento SET status = 'vigente', data_vigencia = DATE '2026-09-14'
 WHERE id = 'e0e0e0e0-0000-0000-0000-0000000000d9';

\echo
\echo '== O valor do evento arredonda serviço a serviço, em cada frente =='
-- Bloco A: 1,50 × 0,33 = 0,495 → 0,50 · 4,00 × 12,50 = 50,00 (e não os 999,99 digitados)
SELECT pg_temp.confere('Piso × Bloco A', (SELECT valor FROM evento WHERE id = pg_temp.evento_do_agrupador('T-01/2026', 1, 'Bloco A')), 50.50);
-- Bloco B: 1,50 × 0,33 = 0,495 → 0,50 · 6,00 × 12,50 = 75,00
SELECT pg_temp.confere('Piso × Bloco B', (SELECT valor FROM evento WHERE id = pg_temp.evento_do_agrupador('T-01/2026', 1, 'Bloco B')), 75.50);
SELECT pg_temp.confere('valor da planilha', (SELECT valor_total FROM revisao_orcamento WHERE id = 'e0e0e0e0-0000-0000-0000-0000000000d9'), 125.99);
-- O serviço A vale 0,99 na planilha e 0,50 + 0,50 nos eventos: um centavo de diferença.
SELECT pg_temp.confere('soma dos eventos menos o valor da planilha',
  (SELECT sum(valor) FROM evento WHERE revisao_id = 'e0e0e0e0-0000-0000-0000-0000000000d9') - 125.99, 0.01);

\echo
\echo '== Com a planilha vigente, evento e distribuição não mudam =='
CALL pg_temp.espera_erro_com('alterar a quantidade de um serviço numa frente',
  'só muda com a revisão em rascunho', ARRAY[
  format($$UPDATE item_frente SET quantidade = quantidade + 1 WHERE item_revisao_id IN
            (SELECT id FROM item_revisao WHERE revisao_id = %L)$$, :'rev_ev')]);
CALL pg_temp.espera_erro_com('apagar a distribuição por frente',
  'só muda com a revisão em rascunho', ARRAY[
  format($$DELETE FROM item_frente WHERE item_revisao_id IN (SELECT id FROM item_revisao WHERE revisao_id = %L)$$, :'rev_ev')]);
CALL pg_temp.espera_erro_com('acrescentar frente a um serviço',
  'só muda com a revisão em rascunho', ARRAY[
  $$INSERT INTO item_frente (item_revisao_id, frente_id, quantidade)
    SELECT id, 'e0e0e0e0-0000-0000-0000-000000000fb9', 1 FROM item_revisao
     WHERE id = 'e0e0e0e0-0000-0000-0000-000000000219'$$]);
CALL pg_temp.espera_erro_com('alterar o valor de um evento',
  'só têm o período previsto alterável', ARRAY[
  format($$UPDATE evento SET valor = valor + 0.01 WHERE revisao_id = %L$$, :'rev_ev')]);
CALL pg_temp.espera_erro_com('trocar a frente de um evento',
  'só têm o período previsto alterável', ARRAY[
  $$UPDATE evento SET frente_id = 'e0e0e0e0-0000-0000-0000-000000000fb9'
     WHERE id = pg_temp.evento_do_agrupador('T-01/2026', 1, 'Bloco A')$$]);
CALL pg_temp.espera_erro_com('apagar um evento',
  'só têm o período previsto alterável', ARRAY[format($$DELETE FROM evento WHERE revisao_id = %L$$, :'rev_ev')]);
CALL pg_temp.espera_erro_com('criar um evento à mão',
  'só têm o período previsto alterável', ARRAY[
  format($$INSERT INTO evento (revisao_id, agrupador_id, frente_id, valor)
           SELECT %L, a.id, 'e0e0e0e0-0000-0000-0000-0000000000f1', 1 FROM agrupador_evento a
            WHERE a.contrato_id = %L AND a.numero = 1$$, :'rev_ev', :'c_ev')]);
CALL pg_temp.espera_erro_com('recalcular os eventos de planilha vigente',
  'só têm o período previsto alterável', ARRAY[
  format($$SELECT fn_recalcular_eventos(%L)$$, :'rev_ev')]);
CALL pg_temp.espera_erro_com('trocar o agrupador de um serviço',
  'itens só podem mudar em rascunho', ARRAY[
  format($$UPDATE item_revisao SET agrupador_evento_id = NULL WHERE revisao_id = %L AND codigo_eap = '3.1'$$, :'rev_ev')]);
CALL pg_temp.espera_erro_com('alterar a quantidade de um serviço da planilha',
  'itens só podem mudar em rascunho', ARRAY[
  format($$UPDATE item_revisao SET quantidade = quantidade + 1 WHERE revisao_id = %L AND codigo_eap = '3.1'$$, :'rev_ev')]);
-- O período previsto é a única coisa que a referência deixa reprogramar num evento vigente.
UPDATE evento SET periodo_previsto = 9 WHERE id = pg_temp.evento_do_agrupador('045/2026', 6, 'Térreo');
SELECT pg_temp.confere('período previsto reprogramado',
  (SELECT periodo_previsto FROM evento WHERE id = pg_temp.evento_do_agrupador('045/2026', 6, 'Térreo')), 9);
SELECT pg_temp.confere('valor do evento depois de reprogramar', pg_temp.valor_do_evento(6), 10386.00);

\echo
\echo '== Medição por eventos: o evento entra inteiro, uma vez só =='
INSERT INTO medicao (id, contrato_id, numero, revisao_id, periodo_inicio, periodo_fim) VALUES
  ('e0e0e0e0-0000-0000-0000-0000000000e1', :'c_ev', 1, :'rev_ev', '2026-10-01', '2026-10-31');
INSERT INTO medicao_evento (medicao_id, evento_id) VALUES
  ('e0e0e0e0-0000-0000-0000-0000000000e1', pg_temp.evento_do_agrupador('045/2026', 1, 'Térreo'));
-- As linhas de serviço da medição saem do evento: quantidade da frente e valor calculado.
SELECT pg_temp.confere('medição 1: linhas de serviço geradas pelo evento',
  (SELECT count(*) FROM medicao_item WHERE medicao_id = 'e0e0e0e0-0000-0000-0000-0000000000e1'), 3);
SELECT pg_temp.confere('medição 1: quantidade de escavação (1.1)',
  (SELECT quantidade FROM medicao_item WHERE medicao_id = 'e0e0e0e0-0000-0000-0000-0000000000e1'
      AND item_contratual_id = pg_temp.item('045/2026', '1.1')), 86.00);
SELECT pg_temp.confere('medição 1: valor das linhas = valor do evento',
  (SELECT sum(valor) FROM medicao_item WHERE medicao_id = 'e0e0e0e0-0000-0000-0000-0000000000e1'), 34181.80);

CALL pg_temp.espera_erro_com('lançar serviço por quantidade em contrato por eventos',
  'lançamento por BM não é permitido', ARRAY[
  $$INSERT INTO medicao_item (medicao_id, item_contratual_id, quantidade, valor)
    VALUES ('e0e0e0e0-0000-0000-0000-0000000000e1', pg_temp.item('045/2026', '3.1'), 10, 0)$$]);
CALL pg_temp.espera_erro_com('alterar a quantidade de linha gerada pelo evento',
  'a quantidade é a soma das frentes concluídas', ARRAY[
  $$UPDATE medicao_item SET quantidade = 80 WHERE medicao_id = 'e0e0e0e0-0000-0000-0000-0000000000e1'
      AND item_contratual_id = pg_temp.item('045/2026', '1.1')$$]);
CALL pg_temp.espera_erro_com('o mesmo evento duas vezes na mesma medição',
  'Evento já medido anteriormente', ARRAY[
  $$INSERT INTO medicao_evento (medicao_id, evento_id) VALUES
      ('e0e0e0e0-0000-0000-0000-0000000000e1', pg_temp.evento_do_agrupador('045/2026', 1, 'Térreo'))$$]);
CALL pg_temp.espera_erro_com('evento de outro contrato',
  'Evento não pertence à revisão da medição', ARRAY[
  $$INSERT INTO medicao_evento (medicao_id, evento_id) VALUES
      ('e0e0e0e0-0000-0000-0000-0000000000e1', pg_temp.evento_do_agrupador('T-01/2026', 1, 'Bloco A'))$$]);

UPDATE medicao SET status = 'enviada' WHERE id = 'e0e0e0e0-0000-0000-0000-0000000000e1';
CALL pg_temp.espera_erro_com('incluir evento em medição enviada',
  'eventos não podem ser alterados', ARRAY[
  $$INSERT INTO medicao_evento (medicao_id, evento_id) VALUES
      ('e0e0e0e0-0000-0000-0000-0000000000e1', pg_temp.evento_do_agrupador('045/2026', 2, 'Térreo'))$$]);
UPDATE medicao SET status = 'aprovada', aprovada_por = 'Fiscal fictício' WHERE id = 'e0e0e0e0-0000-0000-0000-0000000000e1';
SELECT pg_temp.confere('medição 1 aprovada: valor bruto = valor do evento',
  (SELECT valor_bruto FROM medicao WHERE id = 'e0e0e0e0-0000-0000-0000-0000000000e1'), 34181.80);
CALL pg_temp.espera_erro_com('tirar evento de medição aprovada',
  'eventos não podem ser alterados', ARRAY[
  $$DELETE FROM medicao_evento WHERE medicao_id = 'e0e0e0e0-0000-0000-0000-0000000000e1'$$]);
CALL pg_temp.espera_erro_com('incluir evento em medição aprovada',
  'eventos não podem ser alterados', ARRAY[
  $$INSERT INTO medicao_evento (medicao_id, evento_id) VALUES
      ('e0e0e0e0-0000-0000-0000-0000000000e1', pg_temp.evento_do_agrupador('045/2026', 2, 'Térreo'))$$]);
CALL pg_temp.espera_erro_com('alterar linha de serviço de medição aprovada',
  'itens não podem ser alterados', ARRAY[
  $$UPDATE medicao_item SET memoria_calculo = 'x' WHERE medicao_id = 'e0e0e0e0-0000-0000-0000-0000000000e1'$$]);

INSERT INTO medicao (id, contrato_id, numero, revisao_id, periodo_inicio, periodo_fim) VALUES
  ('e0e0e0e0-0000-0000-0000-0000000000e2', :'c_ev', 2, :'rev_ev', '2026-11-01', '2026-11-30');
CALL pg_temp.espera_erro_com('medir de novo um evento já medido',
  'Evento já medido anteriormente', ARRAY[
  $$INSERT INTO medicao_evento (medicao_id, evento_id) VALUES
      ('e0e0e0e0-0000-0000-0000-0000000000e2', pg_temp.evento_do_agrupador('045/2026', 1, 'Térreo'))$$]);

-- Em rascunho, marcar e desmarcar um evento refaz as linhas de serviço.
INSERT INTO medicao_evento (medicao_id, evento_id) VALUES
  ('e0e0e0e0-0000-0000-0000-0000000000e2', pg_temp.evento_do_agrupador('045/2026', 2, 'Térreo'));
SELECT pg_temp.confere('medição 2: pilares marcados',
  (SELECT sum(valor) FROM medicao_item WHERE medicao_id = 'e0e0e0e0-0000-0000-0000-0000000000e2'), 26014.74);
DELETE FROM medicao_evento WHERE medicao_id = 'e0e0e0e0-0000-0000-0000-0000000000e2';
SELECT pg_temp.confere('medição 2: pilares desmarcados, linhas de serviço',
  (SELECT count(*) FROM medicao_item WHERE medicao_id = 'e0e0e0e0-0000-0000-0000-0000000000e2'), 0);

-- Medição cancelada solta o evento para uma medição seguinte.
INSERT INTO medicao_evento (medicao_id, evento_id) VALUES
  ('e0e0e0e0-0000-0000-0000-0000000000e2', pg_temp.evento_do_agrupador('045/2026', 2, 'Térreo'));
UPDATE medicao SET status = 'cancelada' WHERE id = 'e0e0e0e0-0000-0000-0000-0000000000e2';
INSERT INTO medicao (id, contrato_id, numero, revisao_id, periodo_inicio, periodo_fim) VALUES
  ('e0e0e0e0-0000-0000-0000-0000000000e3', :'c_ev', 3, :'rev_ev', '2026-11-01', '2026-12-31');
INSERT INTO medicao_evento (medicao_id, evento_id) VALUES
  ('e0e0e0e0-0000-0000-0000-0000000000e3', pg_temp.evento_do_agrupador('045/2026', 2, 'Térreo')),
  ('e0e0e0e0-0000-0000-0000-0000000000e3', pg_temp.evento_do_agrupador('045/2026', 3, 'Térreo'));
-- 26.014,74 + 16.641,60
SELECT pg_temp.confere('medição 3: pilares e alvenaria',
  (SELECT sum(valor) FROM medicao_item WHERE medicao_id = 'e0e0e0e0-0000-0000-0000-0000000000e3'), 42656.34);
-- 34.181,80 aprovados de 164.039,34
SELECT pg_temp.confere('situação do contrato: percentual executado',
  (SELECT perc_executado FROM vw_contrato_situacao WHERE contrato_id = :'c_ev'), 20.84);

\echo
\echo '== Contrato por quantidade não mede evento =='
INSERT INTO medicao (id, contrato_id, numero, revisao_id, periodo_inicio, periodo_fim) VALUES
  ('e0e0e0e0-0000-0000-0000-0000000000e9', :'c_bm', 1, :'rev_bm', '2026-11-01', '2026-11-30');
CALL pg_temp.espera_erro_com('marcar evento em contrato por quantidade',
  'não mede eventos', ARRAY[
  $$INSERT INTO medicao_evento (medicao_id, evento_id) VALUES
      ('e0e0e0e0-0000-0000-0000-0000000000e9', pg_temp.evento_do_agrupador('045/2026', 4, 'Térreo'))$$]);
CALL pg_temp.espera_erro_com('lançar linha de evento em contrato por quantidade',
  'lançamento por PLE não é permitido', ARRAY[
  $$INSERT INTO medicao_item (medicao_id, item_contratual_id, quantidade, valor, origem)
    VALUES ('e0e0e0e0-0000-0000-0000-0000000000e9', pg_temp.item('052/2026', '1.1'), 1, 0, 'ple')$$]);
INSERT INTO medicao_item (medicao_id, item_contratual_id, quantidade, valor) VALUES
  ('e0e0e0e0-0000-0000-0000-0000000000e9', pg_temp.item('052/2026', '1.1'), 4.50, 0),
  ('e0e0e0e0-0000-0000-0000-0000000000e9', pg_temp.item('052/2026', '2.2'), 100.00, 0);
-- 4,50 × 412,37 = 1.855,665 → truncado · 100,00 × 9,43 = 943,00
SELECT pg_temp.confere('medição por quantidade: placa de obra, truncado',
  (SELECT valor FROM medicao_item WHERE medicao_id = 'e0e0e0e0-0000-0000-0000-0000000000e9'
      AND item_contratual_id = pg_temp.item('052/2026', '1.1')), 1855.66);
SELECT pg_temp.confere('medição por quantidade: total',
  (SELECT sum(valor) FROM medicao_item WHERE medicao_id = 'e0e0e0e0-0000-0000-0000-0000000000e9'), 2798.66);

RESET ROLE;
