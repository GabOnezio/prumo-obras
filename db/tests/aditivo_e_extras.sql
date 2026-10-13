-- Serviço a mais, fluxo do aditivo, previsão e relatório emitido (migração 0009).
-- Prova as invariantes 10 (parte do banco), 12, 13 (parte do banco) e 14 de docs/10 §9 e o
-- fecho do achado 9 (restabelecimento). Roda sobre o seed, como app_rw.
SET ROLE app_rw;
SET app.tenant_id = 'e0e0e0e0-0000-0000-0000-000000000001';
SET app.usuario = 'teste.aditivo';

\set c_ev   '''e0e0e0e0-0000-0000-0000-0000000000c1'''
\set c_bm   '''e0e0e0e0-0000-0000-0000-0000000000c2'''
\set rev_bm '''e0e0e0e0-0000-0000-0000-0000000000d2'''
\set ad1 '''e0e0e0e0-0000-0000-000a-000000000001'''
\set ad2 '''e0e0e0e0-0000-0000-000a-000000000002'''
\set ad3 '''e0e0e0e0-0000-0000-000a-000000000003'''
\set fiscal        '''e0e0e0e0-0000-0000-0001-000000000001'''
\set gestor        '''e0e0e0e0-0000-0000-0001-000000000003'''
\set preposto      '''e0e0e0e0-0000-0000-0001-000000000005'''
\set preposto_beta '''e0e0e0e0-0000-0000-0001-000000000007'''
\set orcamentista  '''e0e0e0e0-0000-0000-0001-000000000008'''
\set hash '''dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'''

CREATE FUNCTION pg_temp.item(p_codigo text) RETURNS uuid LANGUAGE sql AS $$
  SELECT item_contratual_id FROM item_revisao WHERE revisao_id = 'e0e0e0e0-0000-0000-0000-0000000000d2' AND codigo_eap = p_codigo
$$;

\echo
\echo '== Pleito: a empresa pede, a fiscalização decide, o pedido não se reescreve =='
SET app.usuario_id = :fiscal;
CALL pg_temp.espera_erro_com('fiscal abrir pleito no lugar da empresa', 'aberto pela empresa contratada', ARRAY[
  format($$INSERT INTO pleito (contrato_id, tipo, justificativa) VALUES (%L, 'servico_a_mais', 'x')$$, :c_bm)]);
SET app.usuario_id = :preposto;
CALL pg_temp.espera_erro_com('empresa de outro contrato abrir pleito', 'aberto pela empresa contratada', ARRAY[
  format($$INSERT INTO pleito (contrato_id, tipo, justificativa) VALUES (%L, 'servico_a_mais', 'x')$$, :c_bm)]);
SET app.usuario_id = :preposto_beta;
INSERT INTO pleito (id, contrato_id, tipo, justificativa) VALUES
  ('e0e0e0e0-0000-0000-000d-000000000001', :c_bm, 'servico_a_mais', 'Solo mole no trecho final: mais 40 m³ de escavação');
CALL pg_temp.espera_erro_com('empresa deferir o próprio pleito', 'Só a fiscalização ou o gestor', ARRAY[
  $$UPDATE pleito SET status = 'deferido'$$]);
SET app.usuario_id = :fiscal;
CALL pg_temp.espera_erro_com('reescrever a justificativa do pleito', 'não se altera', ARRAY[
  $$UPDATE pleito SET justificativa = 'outra'$$]);
CALL pg_temp.espera_erro('indeferir sem motivo', ARRAY[$$UPDATE pleito SET status = 'indeferido'$$]);
UPDATE pleito SET status = 'em_analise';

\echo
\echo '== Serviço a mais: apontado pela fiscalização, a partir de um registro do contrato =='
SET app.usuario_id = :preposto_beta;
CALL pg_temp.espera_erro_com('empresa apontar serviço a mais direto', 'Só a fiscalização ou o gestor', ARRAY[
  format($$INSERT INTO servico_extra (contrato_id, origem, origem_id, tipo, item_contratual_id, descricao, quantidade_estimada)
           VALUES (%L, 'pleito', 'e0e0e0e0-0000-0000-000d-000000000001', 'acrescimo', pg_temp.item('2.2'), 'x', 40)$$, :c_bm)]);
SET app.usuario_id = :fiscal;
CALL pg_temp.espera_erro_com('origem que não é deste contrato', 'A origem do apontamento não é', ARRAY[
  format($$INSERT INTO servico_extra (contrato_id, origem, origem_id, tipo, item_contratual_id, descricao, quantidade_estimada)
           VALUES (%L, 'vistoria', 'e0e0e0e0-0000-0000-0000-0000000000b7', 'acrescimo', pg_temp.item('2.2'), 'x', 40)$$, :c_bm)]);
CALL pg_temp.espera_erro('acréscimo sem dizer de qual item', ARRAY[
  format($$INSERT INTO servico_extra (contrato_id, origem, origem_id, tipo, descricao, quantidade_estimada)
           VALUES (%L, 'pleito', 'e0e0e0e0-0000-0000-000d-000000000001', 'acrescimo', 'x', 40)$$, :c_bm)]);
CALL pg_temp.espera_erro_com('apontamento que já nasce aceito', 'nasce como apontado', ARRAY[
  format($$INSERT INTO servico_extra (contrato_id, origem, origem_id, tipo, item_contratual_id, descricao, status, decidido_por)
           VALUES (%L, 'pleito', 'e0e0e0e0-0000-0000-000d-000000000001', 'acrescimo', pg_temp.item('2.2'), 'x', 'aceito', %L)$$, :c_bm, :fiscal)]);
INSERT INTO servico_extra (id, contrato_id, origem, origem_id, tipo, item_contratual_id, descricao, unidade, quantidade_estimada) VALUES
  ('e0e0e0e0-0000-0000-000e-000000000001', :c_bm, 'pleito', 'e0e0e0e0-0000-0000-000d-000000000001', 'acrescimo',
   pg_temp.item('2.2'), 'Escavação a mais no trecho final', 'm³', 40),
  ('e0e0e0e0-0000-0000-000e-000000000002', :c_bm, 'pleito', 'e0e0e0e0-0000-0000-000d-000000000001', 'servico_novo',
   NULL, 'Dreno de brita no trecho final', 'm', 60),
  ('e0e0e0e0-0000-0000-000e-000000000003', :c_bm, 'pleito', 'e0e0e0e0-0000-0000-000d-000000000001', 'servico_novo',
   NULL, 'Cerca provisória', 'm', 30);
CALL pg_temp.espera_erro_com('reescrever o que foi apontado', 'não se altera', ARRAY[
  $$UPDATE servico_extra SET quantidade_estimada = 400 WHERE id = 'e0e0e0e0-0000-0000-000e-000000000001'$$]);
CALL pg_temp.espera_erro_com('apagar apontamento', 'permission denied', ARRAY[$$DELETE FROM servico_extra$$]);
CALL pg_temp.espera_erro('recusar sem motivo', ARRAY[
  $$UPDATE servico_extra SET status = 'recusado' WHERE id = 'e0e0e0e0-0000-0000-000e-000000000003'$$]);
UPDATE servico_extra SET status = 'recusado', motivo = 'A cerca é obrigação da contratada' WHERE id = 'e0e0e0e0-0000-0000-000e-000000000003';
CALL pg_temp.espera_erro_com('reabrir apontamento recusado', 'não passa a', ARRAY[
  $$UPDATE servico_extra SET status = 'aceito' WHERE id = 'e0e0e0e0-0000-0000-000e-000000000003'$$]);

\echo
\echo '== Invariante 14: só é "incluído em aditivo" com o item do aditivo correspondente =='
CALL pg_temp.espera_erro('marcar como incluído em aditivo sem o item do aditivo', ARRAY[
  $$UPDATE servico_extra SET status = 'aceito' WHERE id = 'e0e0e0e0-0000-0000-000e-000000000001'$$,
  $$UPDATE servico_extra SET status = 'incluido_em_aditivo' WHERE id = 'e0e0e0e0-0000-0000-000e-000000000001'$$]);
CALL pg_temp.espera_erro_com('pular a aceitação', 'não passa a', ARRAY[
  $$UPDATE servico_extra SET status = 'incluido_em_aditivo', aditivo_item_id = gen_random_uuid()
     WHERE id = 'e0e0e0e0-0000-0000-000e-000000000001'$$]);
UPDATE servico_extra SET status = 'aceito' WHERE id IN ('e0e0e0e0-0000-0000-000e-000000000001', 'e0e0e0e0-0000-0000-000e-000000000002');
SELECT pg_temp.confere_texto('aceito em nome de quem está na sessão',
  (SELECT u.nome FROM servico_extra s JOIN usuario u ON u.id = s.decidido_por WHERE s.id = 'e0e0e0e0-0000-0000-000e-000000000001'),
  'Fiscal técnico (fictício)');

-- Aditivo 1 do contrato por quantidade: +40 m³ de escavação (40,00 × 9,43 = 377,20),
-- −20 m² de sinalização (−20,00 × 27,90 = −558,00) e o dreno novo.
-- Dreno: 30,00 × fator 0,91185334 = 27,3556... → 27,36; 60,00 × 27,36 = 1.641,60
SET app.usuario_id = :orcamentista;
INSERT INTO aditivo (id, contrato_id, numero, tipo, fundamento_legal, justificativa, revisao_base_id)
VALUES (:ad1, :c_bm, 1, 'valor', 'A conferir pelo jurídico', 'Solo mole no trecho final', :rev_bm);
INSERT INTO item_contratual (id, contrato_id) VALUES ('e0e0e0e0-0000-0000-000a-0000000000f1', :c_bm);
INSERT INTO aditivo_item (id, aditivo_id, item_contratual_id, operacao, quantidade_delta, preco_unitario, valor_delta) VALUES
  ('e0e0e0e0-0000-0000-000a-000000000011', :ad1, pg_temp.item('2.2'), 'acrescimo', 40, 0, 0),
  ('e0e0e0e0-0000-0000-000a-000000000012', :ad1, pg_temp.item('4.2'), 'supressao', -20, 0, 0);
INSERT INTO aditivo_item (id, aditivo_id, item_contratual_id, operacao, quantidade_delta, preco_unitario, valor_delta,
                          parent_item_contratual_id, codigo_eap, descricao, unidade, preco_referencia)
VALUES ('e0e0e0e0-0000-0000-000a-000000000013', :ad1, 'e0e0e0e0-0000-0000-000a-0000000000f1', 'inclusao', 60, 27.36, 0,
        pg_temp.item('2'), '2.3', 'Dreno de brita', 'm', 30.00);
SELECT pg_temp.confere('valor do acréscimo de escavação', (SELECT valor_delta FROM aditivo_item WHERE id = 'e0e0e0e0-0000-0000-000a-000000000011'), 377.20);
SELECT pg_temp.confere('valor do dreno novo', (SELECT valor_delta FROM aditivo_item WHERE id = 'e0e0e0e0-0000-0000-000a-000000000013'), 1641.60);

SET app.usuario_id = :fiscal;
CALL pg_temp.espera_erro_com('ligar o acréscimo a um item de aditivo de outra operação', 'não corresponde ao apontamento', ARRAY[
  $$UPDATE servico_extra SET status = 'incluido_em_aditivo', aditivo_item_id = 'e0e0e0e0-0000-0000-000a-000000000012'
     WHERE id = 'e0e0e0e0-0000-0000-000e-000000000001'$$]);
CALL pg_temp.espera_erro_com('ligar o serviço novo a um acréscimo', 'não corresponde ao apontamento', ARRAY[
  $$UPDATE servico_extra SET status = 'incluido_em_aditivo', aditivo_item_id = 'e0e0e0e0-0000-0000-000a-000000000011'
     WHERE id = 'e0e0e0e0-0000-0000-000e-000000000002'$$]);
CALL pg_temp.espera_erro_com('item de aditivo que não existe', 'não é deste contrato', ARRAY[
  $$UPDATE servico_extra SET status = 'incluido_em_aditivo', aditivo_item_id = gen_random_uuid()
     WHERE id = 'e0e0e0e0-0000-0000-000e-000000000001'$$]);
UPDATE servico_extra SET status = 'incluido_em_aditivo', aditivo_item_id = 'e0e0e0e0-0000-0000-000a-000000000011'
 WHERE id = 'e0e0e0e0-0000-0000-000e-000000000001';
UPDATE servico_extra SET status = 'incluido_em_aditivo', aditivo_item_id = 'e0e0e0e0-0000-0000-000a-000000000013'
 WHERE id = 'e0e0e0e0-0000-0000-000e-000000000002';
CALL pg_temp.espera_erro_com('desfazer a inclusão em aditivo', 'não passa a', ARRAY[
  $$UPDATE servico_extra SET status = 'aceito', aditivo_item_id = NULL WHERE id = 'e0e0e0e0-0000-0000-000e-000000000001'$$]);
-- O apontamento não mede nada: o contrato só muda com o aditivo homologado.
SELECT pg_temp.confere('quantidade contratada de escavação, antes da homologação',
  (SELECT quantidade FROM item_revisao WHERE revisao_id = :rev_bm AND codigo_eap = '2.2'), 378.50);

\echo
\echo '== Aditivo: rascunho → enviado → homologado ou rejeitado, com segregação, limite e parecer =='
RESET app.usuario_id;
CALL pg_temp.espera_erro_com('enviar aditivo sem usuário na sessão', 'não diz quem está agindo', ARRAY[
  format($$UPDATE aditivo SET status = 'enviado' WHERE id = %L$$, :ad1)]);
SET app.usuario_id = :orcamentista;
CALL pg_temp.espera_erro_com('homologar direto do rascunho', 'não passa a', ARRAY[
  format($$UPDATE aditivo SET status = 'homologado', data_assinatura = '2026-12-10' WHERE id = %L$$, :ad1)]);
UPDATE aditivo SET status = 'enviado' WHERE id = :ad1;
CALL pg_temp.espera_erro_com('alterar item de aditivo enviado', 'itens não podem ser alterados', ARRAY[
  $$UPDATE aditivo_item SET quantidade_delta = 4000 WHERE id = 'e0e0e0e0-0000-0000-000a-000000000011'$$]);
CALL pg_temp.espera_erro_com('alterar a justificativa de aditivo enviado', 'já foi enviado', ARRAY[
  format($$UPDATE aditivo SET justificativa = 'outra' WHERE id = %L$$, :ad1)]);
CALL pg_temp.espera_erro_com('apagar aditivo enviado', 'não se apaga', ARRAY[format($$DELETE FROM aditivo WHERE id = %L$$, :ad1)]);
CALL pg_temp.espera_erro_com('voltar aditivo enviado para rascunho', 'não passa a', ARRAY[
  format($$UPDATE aditivo SET status = 'rascunho' WHERE id = %L$$, :ad1)]);
CALL pg_temp.espera_erro_com('quem enviou homologar', 'Quem enviou o aditivo não pode homologá-lo', ARRAY[
  format($$UPDATE aditivo SET status = 'homologado', data_assinatura = '2026-12-10', parecer_sha256 = %L WHERE id = %L$$, :hash, :ad1)]);
SET app.usuario_id = :gestor;
CALL pg_temp.espera_erro_com('homologar sem o parecer que o município exige', 'sem o parecer', ARRAY[
  format($$UPDATE aditivo SET status = 'homologado', data_assinatura = '2026-12-10' WHERE id = %L$$, :ad1)]);
UPDATE config_municipio SET parecer_aditivo_exigido = NULL;
CALL pg_temp.espera_erro_com('homologar sem a configuração do parecer', 'Configuração do município ausente', ARRAY[
  format($$UPDATE aditivo SET status = 'homologado', data_assinatura = '2026-12-10', parecer_sha256 = %L WHERE id = %L$$, :hash, :ad1)]);
UPDATE config_municipio SET parecer_aditivo_exigido = true;
CALL pg_temp.espera_erro('homologar sem a data de assinatura do termo', ARRAY[
  format($$UPDATE aditivo SET status = 'homologado', parecer_sha256 = %L WHERE id = %L$$, :hash, :ad1)]);
UPDATE aditivo SET parecer_sha256 = :hash WHERE id = :ad1;
UPDATE aditivo SET status = 'homologado', data_assinatura = '2026-12-10', homologado_em = now() WHERE id = :ad1;
SELECT pg_temp.confere_texto('homologado em nome de quem está na sessão',
  (SELECT u.nome FROM aditivo a JOIN usuario u ON u.id = a.decidido_por WHERE a.id = :ad1), 'Gestor do contrato (fictício)');
CALL pg_temp.espera_erro_com('alterar aditivo homologado', 'é imutável', ARRAY[
  format($$UPDATE aditivo SET justificativa = 'outra' WHERE id = %L$$, :ad1)]);
-- 377,20 + 1.641,60 = 2.018,80 de acréscimos; 558,00 de supressões; sobre 136.595,63
SELECT pg_temp.confere('acréscimos homologados', (SELECT acrescimos FROM fn_limites_aditivos(:c_bm)), 2018.80);
SELECT pg_temp.confere('% de acréscimos', (SELECT perc_acrescimos FROM fn_limites_aditivos(:c_bm)), 1.48);
SELECT pg_temp.confere('% de supressões', (SELECT perc_supressoes FROM fn_limites_aditivos(:c_bm)), 0.41);

\echo
\echo '== Restabelecimento só devolve o que foi suprimido; aditivo acima do limite não é homologado =='
SET app.usuario_id = :orcamentista;
INSERT INTO aditivo (id, contrato_id, numero, tipo, fundamento_legal, justificativa, revisao_base_id)
VALUES (:ad2, :c_bm, 2, 'valor', 'A conferir pelo jurídico', 'Ajuste de quantidades', :rev_bm);
CALL pg_temp.espera_erro_com('restabelecer item que nunca foi suprimido', 'só há 0 suprimidos para restabelecer', ARRAY[
  format($$INSERT INTO aditivo_item (aditivo_id, item_contratual_id, operacao, quantidade_delta, preco_unitario, valor_delta)
           VALUES (%L, pg_temp.item('3.3'), 'restabelecimento', 500, 0, 0)$$, :ad2)]);
CALL pg_temp.espera_erro_com('restabelecer mais do que foi suprimido (20,0001 de 20)', 'suprimidos para restabelecer', ARRAY[
  format($$INSERT INTO aditivo_item (aditivo_id, item_contratual_id, operacao, quantidade_delta, preco_unitario, valor_delta)
           VALUES (%L, pg_temp.item('4.2'), 'restabelecimento', 20.0001, 0, 0)$$, :ad2)]);
INSERT INTO aditivo_item (aditivo_id, item_contratual_id, operacao, quantidade_delta, preco_unitario, valor_delta)
VALUES (:ad2, pg_temp.item('4.2'), 'restabelecimento', 20, 0, 0);
-- e um acréscimo que estoura o limite: 80,00 t de asfalto a 468,90 = 37.512,00 → 28,94% com o aditivo 1
INSERT INTO aditivo_item (aditivo_id, item_contratual_id, operacao, quantidade_delta, preco_unitario, valor_delta)
VALUES (:ad2, pg_temp.item('3.3'), 'acrescimo', 80, 0, 0);
SELECT pg_temp.confere('% de acréscimos simulando o aditivo 2', (SELECT perc_acrescimos FROM fn_limites_aditivos(:c_bm, :ad2)), 28.94);
SELECT pg_temp.confere('o restabelecimento fica fora da conta de acréscimos',
  (SELECT restabelecimentos FROM fn_limites_aditivos(:c_bm, :ad2)), 558.00);
UPDATE aditivo SET status = 'enviado' WHERE id = :ad2;
SET app.usuario_id = :gestor;
CALL pg_temp.espera_erro_com('homologar aditivo acima do limite legal', 'passa do limite legal', ARRAY[
  format($$UPDATE aditivo SET status = 'homologado', data_assinatura = '2026-12-20', parecer_sha256 = %L WHERE id = %L$$, :hash, :ad2)]);
CALL pg_temp.espera_erro_com('rejeitar sem motivo', 'exige o motivo', ARRAY[
  format($$UPDATE aditivo SET status = 'rejeitado' WHERE id = %L$$, :ad2)]);
UPDATE aditivo SET status = 'rejeitado', motivo_rejeicao = 'Passa do limite de acréscimos' WHERE id = :ad2;
CALL pg_temp.espera_erro_com('reabrir aditivo rejeitado', 'é imutável', ARRAY[
  format($$UPDATE aditivo SET status = 'enviado' WHERE id = %L$$, :ad2)]);

\echo
\echo '== Invariante 10: a previsão guardada tem método e cálculo, e não se reescreve =='
INSERT INTO previsao_calculo (id, contrato_id, versao_algoritmo, cronograma_versao_id, boletim_execucao_id, parametros,
                              fator_ritmo, termino_previsto, desvio_dias)
VALUES ('e0e0e0e0-0000-0000-0010-000000000001', :c_ev, 'previsao-0.1', 'e0e0e0e0-0000-0000-0000-0000000000a1',
        'e0e0e0e0-0000-0000-000b-000000000002', '{"prazo_pagamento_dias": 30}', 1.1500, '2027-05-13', 9);
CALL pg_temp.espera_erro('previsão de evento sem método', ARRAY[
  $$INSERT INTO previsao_evento (calculo_id, evento_id, termino_previsto)
    SELECT 'e0e0e0e0-0000-0000-0010-000000000001', id, '2027-02-02' FROM evento LIMIT 1$$]);
CALL pg_temp.espera_erro('previsão de evento sem o cálculo de origem', ARRAY[
  $$INSERT INTO previsao_evento (evento_id, termino_previsto, metodo) SELECT id, '2027-02-02', 'ritmo' FROM evento LIMIT 1$$]);
CALL pg_temp.espera_erro('método de previsão fora da lista (não há "ia")', ARRAY[
  $$INSERT INTO previsao_evento (calculo_id, evento_id, termino_previsto, metodo)
    SELECT 'e0e0e0e0-0000-0000-0010-000000000001', id, '2027-02-02', 'ia' FROM evento LIMIT 1$$]);
INSERT INTO previsao_evento (calculo_id, evento_id, termino_previsto, metodo, pagamento_previsto_em, valor_bruto, retencoes, valor_liquido)
SELECT 'e0e0e0e0-0000-0000-0010-000000000001', e.id, '2027-02-02', 'ritmo', '2027-03-19', 38920.00, 4281.20, 34638.80
  FROM evento e JOIN agrupador_evento a ON a.id = e.agrupador_id WHERE a.contrato_id = :c_ev AND a.numero = 4;
CALL pg_temp.espera_erro_com('aplicação reescrever uma previsão', 'permission denied', ARRAY[$$UPDATE previsao_evento SET termino_previsto = '2027-01-01'$$]);
CALL pg_temp.espera_erro_com('aplicação apagar um cálculo de previsão', 'permission denied', ARRAY[$$DELETE FROM previsao_calculo$$]);
RESET ROLE;
CALL pg_temp.espera_erro_com('nem o dono reescreve uma previsão', 'não se altera', ARRAY[$$UPDATE previsao_evento SET termino_previsto = '2027-01-01'$$]);
SET ROLE app_rw;
-- a previsão não mexe em nada oficial: o cronograma e o evento continuam como estavam
SELECT pg_temp.confere_texto('término da cobertura na linha de base, depois da previsão',
  (SELECT ce.termino_previsto::text FROM cronograma_evento ce JOIN evento e ON e.id = ce.evento_id
     JOIN agrupador_evento a ON a.id = e.agrupador_id
    WHERE ce.cronograma_versao_id = 'e0e0e0e0-0000-0000-0000-0000000000a1' AND a.numero = 4), '2027-01-29');

\echo
\echo '== Invariantes 12 e 13: relatório emitido não muda; relatório fotográfico só com foto confirmada =='
SET app.usuario_id = :fiscal;
INSERT INTO foto (id, contrato_id, origem, sha256, chave_arquivo, tirada_em, evento_id, vinculo_origem)
SELECT 'e0e0e0e0-0000-0000-000f-0000000000c1', :c_ev, 'camera_app', repeat('5', 64), 'ficticio/pilares.jpg', '2026-12-11 10:00-03', e.id, 'captura'
  FROM evento e JOIN agrupador_evento a ON a.id = e.agrupador_id WHERE a.contrato_id = :c_ev AND a.numero = 2;
INSERT INTO foto (id, contrato_id, origem, sha256, chave_arquivo, tirada_em)
VALUES ('e0e0e0e0-0000-0000-000f-0000000000c2', :c_ev, 'camera_app', repeat('6', 64), 'ficticio/solta.jpg', '2026-12-11 10:05-03');
CALL pg_temp.espera_erro_com('relatório fotográfico sem lista de fotos', 'tem que listar as fotos', ARRAY[
  format($$INSERT INTO relatorio_emitido (contrato_id, tipo, numero, versao_modelo, arquivo_sha256, chave_arquivo, origem)
           VALUES (%L, 'relatorio_fotografico', 1, 'm1', %L, 'x', '{}')$$, :c_ev, :hash)]);
CALL pg_temp.espera_erro_com('relatório fotográfico com foto sem vínculo confirmado', 'não tem vínculo confirmado por pessoa', ARRAY[
  format($$INSERT INTO relatorio_emitido (contrato_id, tipo, numero, versao_modelo, arquivo_sha256, chave_arquivo, origem)
           VALUES (%L, 'relatorio_fotografico', 1, 'm1', %L, 'x',
                   '{"fotos": ["e0e0e0e0-0000-0000-000f-0000000000c1", "e0e0e0e0-0000-0000-000f-0000000000c2"]}')$$, :c_ev, :hash)]);
CALL pg_temp.espera_erro_com('relatório fotográfico com foto de outro contrato', 'não é deste contrato', ARRAY[
  format($$INSERT INTO relatorio_emitido (contrato_id, tipo, numero, versao_modelo, arquivo_sha256, chave_arquivo, origem)
           VALUES (%L, 'relatorio_fotografico', 1, 'm1', %L, 'x', '{"fotos": ["e0e0e0e0-0000-0000-000f-0000000000c1"]}')$$, :c_bm, :hash)]);
CALL pg_temp.espera_erro('relatório sem hash do arquivo', ARRAY[
  format($$INSERT INTO relatorio_emitido (contrato_id, tipo, numero, versao_modelo, chave_arquivo, origem)
           VALUES (%L, 'planilha_medicao', 1, 'm1', 'x', '{}')$$, :c_ev)]);
INSERT INTO relatorio_emitido (id, contrato_id, tipo, numero, versao_modelo, arquivo_sha256, chave_arquivo, origem)
VALUES ('e0e0e0e0-0000-0000-0011-000000000001', :c_ev, 'relatorio_fotografico', 1, 'modelo-1', :hash, 'ficticio/rf-1.pdf',
        '{"fotos": ["e0e0e0e0-0000-0000-000f-0000000000c1"]}');
SELECT pg_temp.confere_texto('emitido em nome de quem está na sessão',
  (SELECT u.nome FROM relatorio_emitido r JOIN usuario u ON u.id = r.emitido_por), 'Fiscal técnico (fictício)');
CALL pg_temp.espera_erro_com('aplicação alterar relatório emitido', 'permission denied', ARRAY[$$UPDATE relatorio_emitido SET numero = 2$$]);
CALL pg_temp.espera_erro('dois relatórios com o mesmo número', ARRAY[
  format($$INSERT INTO relatorio_emitido (contrato_id, tipo, numero, versao_modelo, arquivo_sha256, chave_arquivo, origem)
           VALUES (%L, 'relatorio_fotografico', 1, 'modelo-1', %L, 'x', '{"fotos": ["e0e0e0e0-0000-0000-000f-0000000000c1"]}')$$, :c_ev, :hash)]);
RESET ROLE;
CALL pg_temp.espera_erro_com('nem o dono altera relatório emitido', 'Relatório emitido não se altera', ARRAY[$$UPDATE relatorio_emitido SET arquivo_sha256 = repeat('0', 64)$$]);
CALL pg_temp.espera_erro_com('nem o dono apaga relatório emitido', 'Relatório emitido não se altera', ARRAY[$$DELETE FROM relatorio_emitido$$]);
SET ROLE app_rw;
-- a foto que entrou no relatório não troca mais de legenda nem de vínculo
CALL pg_temp.espera_erro_com('mudar a legenda de foto que está em relatório emitido', 'já está em relatório emitido', ARRAY[
  $$UPDATE foto SET legenda = 'outra' WHERE id = 'e0e0e0e0-0000-0000-000f-0000000000c1'$$]);
UPDATE foto SET legenda = 'Sem uso em relatório' WHERE id = 'e0e0e0e0-0000-0000-000f-0000000000c2';
-- correção de relatório é outro relatório, que aponta para o primeiro
CALL pg_temp.espera_erro_com('substituir relatório de outro tipo', 'mesmo contrato e do mesmo tipo', ARRAY[
  format($$INSERT INTO relatorio_emitido (contrato_id, tipo, numero, versao_modelo, arquivo_sha256, chave_arquivo, origem, substitui_id)
           VALUES (%L, 'planilha_medicao', 1, 'm1', %L, 'x', '{}', 'e0e0e0e0-0000-0000-0011-000000000001')$$, :c_ev, :hash)]);
INSERT INTO relatorio_emitido (contrato_id, tipo, numero, versao_modelo, arquivo_sha256, chave_arquivo, origem, substitui_id)
VALUES (:c_ev, 'relatorio_fotografico', 2, 'modelo-1', repeat('e', 64), 'ficticio/rf-2.pdf',
        '{"fotos": ["e0e0e0e0-0000-0000-000f-0000000000c1"]}', 'e0e0e0e0-0000-0000-0011-000000000001');
SELECT pg_temp.confere('os dois relatórios continuam guardados', (SELECT count(*) FROM relatorio_emitido), 2);

RESET ROLE;
