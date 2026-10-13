-- =============================================================================
-- Cenário de teste do esquema: contrato → Rev. 0 → 2 medições → aditivo → Rev. 1
-- → 3ª medição → financeiro (CR da medição, compras apropriadas, rateio, fluxo).
-- Rodar após schema.sql:  psql -d obras -v ON_ERROR_STOP=1 -f seed_e_testes.sql
-- Os blocos "espera_erro" provam que as invariantes barram operações inválidas.
-- Valores e alíquotas são ilustrativos.
-- =============================================================================
\set ON_ERROR_STOP on
\pset footer off
SET client_min_messages = notice;

SET app.tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001';
SET app.usuario   = 'eng.teste';

-- Utilitário: executa comandos e exige que algum deles seja bloqueado
CREATE PROCEDURE pg_temp.espera_erro(p_desc text, p_cmds text[])
LANGUAGE plpgsql AS $$
DECLARE c text;
BEGIN
  BEGIN
    FOREACH c IN ARRAY p_cmds LOOP EXECUTE c; END LOOP;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'OK, bloqueado | % | %', p_desc, SQLERRM;
    RETURN;
  END;
  RAISE EXCEPTION 'TESTE FALHOU: "%" deveria ter sido bloqueado', p_desc;
END $$;

-- -----------------------------------------------------------------------------
-- Cadastros
-- -----------------------------------------------------------------------------
INSERT INTO tenant (id, razao_social, cnpj) VALUES
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Construtora Exemplo Ltda', '11222333000181'),
  ('bbbbbbbb-0000-0000-0000-000000000001', 'Outra Construtora Ltda',   '44555666000199');

INSERT INTO orgao (id, nome, cnpj, esfera, uf, municipio) VALUES
  ('00000000-0000-0000-0000-0000000000a1', 'Prefeitura Municipal de Exemplo', '00111222000133', 'municipal', 'PR', 'Exemplo');

INSERT INTO obra (id, nome, municipio, uf) VALUES
  ('00000000-0000-0000-0000-0000000000b1', 'Ampliação da Escola Municipal', 'Exemplo', 'PR'),
  ('00000000-0000-0000-0000-0000000000b2', 'Pavimentação Rua das Flores',   'Exemplo', 'PR');

INSERT INTO contrato (id, obra_id, orgao_id, numero, processo_licitatorio, objeto, regime_execucao,
                      data_assinatura, data_base_orcamento, prazo_execucao_dias, vigencia_fim,
                      valor_inicial, valor_orcamento_base, bdi_percentual, criterio_arredondamento)
VALUES ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000b1',
        '00000000-0000-0000-0000-0000000000a1', '045/2026', 'Concorrência Eletrônica nº 07/2026',
        'Ampliação da Escola Municipal', 'empreitada_preco_unitario',
        '2026-09-15', '2026-05-01', 180, '2027-06-30', 58551.28, 64300.00, 24.5, 'truncar');

-- Retenção na nota: só ISS (base 50% do valor, alíquota 5% — ilustrativo; varia por município)
INSERT INTO contrato_retencao (contrato_id, tipo, aliquota, base_percentual) VALUES
  ('00000000-0000-0000-0000-0000000000c1', 'ISS', 5, 50);

-- -----------------------------------------------------------------------------
-- Revisão 0 (o que o commit da importação grava)
-- -----------------------------------------------------------------------------
INSERT INTO revisao_orcamento (id, contrato_id, numero, origem) VALUES
  ('00000000-0000-0000-0000-0000000000d0', '00000000-0000-0000-0000-0000000000c1', 0, 'importacao');

INSERT INTO item_contratual (id, contrato_id)
SELECT ('10000000-0000-0000-0000-' || lpad(x, 12, '0'))::uuid, '00000000-0000-0000-0000-0000000000c1'
  FROM unnest(ARRAY['1','11','12','2','21','211','212','22','3','31','32','23']) x;

-- nível 1
INSERT INTO item_revisao (revisao_id, item_contratual_id, parent_id, ordem, codigo_eap, tipo, descricao, linha_origem) VALUES
  ('00000000-0000-0000-0000-0000000000d0', '10000000-0000-0000-0000-000000000001', NULL, 1, '1', 'grupo', 'SERVIÇOS PRELIMINARES', 8),
  ('00000000-0000-0000-0000-0000000000d0', '10000000-0000-0000-0000-000000000002', NULL, 2, '2', 'grupo', 'INFRAESTRUTURA', 11),
  ('00000000-0000-0000-0000-0000000000d0', '10000000-0000-0000-0000-000000000003', NULL, 3, '3', 'grupo', 'SUPERESTRUTURA E VEDAÇÕES', 16);

-- nível 2
INSERT INTO item_revisao (revisao_id, item_contratual_id, parent_id, ordem, codigo_eap, tipo, descricao, unidade, quantidade, preco_unitario, fonte, codigo_referencia, linha_origem)
SELECT '00000000-0000-0000-0000-0000000000d0', v.ic::uuid,
       (SELECT id FROM item_revisao WHERE revisao_id = '00000000-0000-0000-0000-0000000000d0' AND item_contratual_id = v.pai::uuid),
       v.ordem, v.cod, v.tipo::tipo_item, v.descr, v.un, v.qtd, v.pu, v.fonte, v.ref, v.linha
  FROM (VALUES
    ('10000000-0000-0000-0000-000000000011', '10000000-0000-0000-0000-000000000001', 1, '1.1', 'servico', 'Placa de obra em chapa galvanizada', 'm²', 6.00,  450.00, 'PROPRIA', 'CP-001', 9),
    ('10000000-0000-0000-0000-000000000012', '10000000-0000-0000-0000-000000000001', 2, '1.2', 'servico', 'Locação da obra com gabarito de madeira', 'm²', 180.00, 12.35, 'PROPRIA', 'CP-002', 10),
    ('10000000-0000-0000-0000-000000000021', '10000000-0000-0000-0000-000000000002', 1, '2.1', 'grupo',   'FUNDAÇÕES', NULL, NULL, NULL, NULL, NULL, 12),
    ('10000000-0000-0000-0000-000000000022', '10000000-0000-0000-0000-000000000002', 2, '2.2', 'servico', 'Impermeabilização de viga baldrame', 'm²', 64.00, 48.77, 'PROPRIA', 'CP-005', 15),
    ('10000000-0000-0000-0000-000000000031', '10000000-0000-0000-0000-000000000003', 1, '3.1', 'servico', 'Alvenaria de vedação com bloco cerâmico', 'm²', 320.00, 89.15, 'PROPRIA', 'CP-006', 17),
    ('10000000-0000-0000-0000-000000000032', '10000000-0000-0000-0000-000000000003', 2, '3.2', 'servico', 'Chapisco em alvenaria', 'm²', 640.00, 7.43, 'PROPRIA', 'CP-007', 18)
  ) AS v(ic, pai, ordem, cod, tipo, descr, un, qtd, pu, fonte, ref, linha);

-- nível 3
INSERT INTO item_revisao (revisao_id, item_contratual_id, parent_id, ordem, codigo_eap, tipo, descricao, unidade, quantidade, preco_unitario, fonte, codigo_referencia, linha_origem)
SELECT '00000000-0000-0000-0000-0000000000d0', v.ic::uuid,
       (SELECT id FROM item_revisao WHERE revisao_id = '00000000-0000-0000-0000-0000000000d0' AND item_contratual_id = v.pai::uuid),
       v.ordem, v.cod, 'servico', v.descr, v.un, v.qtd, v.pu, 'PROPRIA', v.ref, v.linha
  FROM (VALUES
    ('10000000-0000-0000-0000-000000000211', '10000000-0000-0000-0000-000000000021', 1, '2.1.1', 'Escavação manual de vala', 'm³', 42.50, 68.93, 'CP-003', 13),
    ('10000000-0000-0000-0000-000000000212', '10000000-0000-0000-0000-000000000021', 2, '2.1.2', 'Concreto fck 25 MPa, lançado e adensado', 'm³', 18.20, 785.40, 'CP-004', 14)
  ) AS v(ic, pai, ordem, cod, descr, un, qtd, pu, ref, linha);

\echo
\echo '== Invariantes da planilha =='
CALL pg_temp.espera_erro('Rev. 0 com soma diferente do valor do contrato', ARRAY[
  $$UPDATE item_revisao SET quantidade = 7 WHERE codigo_eap = '1.1' AND revisao_id = '00000000-0000-0000-0000-0000000000d0'$$,
  $$UPDATE revisao_orcamento SET status = 'vigente' WHERE id = '00000000-0000-0000-0000-0000000000d0'$$]);
CALL pg_temp.espera_erro('Preço unitário com 3 casas num contrato de 2', ARRAY[
  $$UPDATE item_revisao SET preco_unitario = 12.355 WHERE codigo_eap = '1.2' AND revisao_id = '00000000-0000-0000-0000-0000000000d0'$$]);

UPDATE revisao_orcamento SET status = 'vigente', data_vigencia = DATE '2026-09-15' WHERE id = '00000000-0000-0000-0000-0000000000d0';

CALL pg_temp.espera_erro('Editar item de revisão vigente', ARRAY[
  $$UPDATE item_revisao SET quantidade = 50 WHERE codigo_eap = '2.1.1'$$]);

\echo
\echo '== Rev. 0: escavação 42,50 × 68,93 = 2.929,525 → truncado em 2.929,52 =='
SELECT codigo_eap, valor_total FROM item_revisao WHERE codigo_eap = '2.1.1';
SELECT numero, status, valor_total FROM revisao_orcamento;

-- -----------------------------------------------------------------------------
-- Medições 1 e 2 (sobre a Rev. 0)
-- -----------------------------------------------------------------------------
INSERT INTO medicao (id, contrato_id, numero, revisao_id, periodo_inicio, periodo_fim) VALUES
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000c1', 1,
   '00000000-0000-0000-0000-0000000000d0', '2026-10-01', '2026-10-31');
INSERT INTO medicao_item (medicao_id, item_contratual_id, quantidade, valor) VALUES
  ('00000000-0000-0000-0000-0000000000e1', '10000000-0000-0000-0000-000000000011', 6.00,   0),
  ('00000000-0000-0000-0000-0000000000e1', '10000000-0000-0000-0000-000000000012', 180.00, 0),
  ('00000000-0000-0000-0000-0000000000e1', '10000000-0000-0000-0000-000000000211', 30.00,  0);
UPDATE medicao SET status = 'enviada' WHERE id = '00000000-0000-0000-0000-0000000000e1';
UPDATE medicao SET status = 'aprovada', aprovada_por = 'Fiscal do contrato' WHERE id = '00000000-0000-0000-0000-0000000000e1';

\echo
\echo '== Invariantes da medição =='
CALL pg_temp.espera_erro('Alterar item de medição aprovada', ARRAY[
  $$UPDATE medicao_item SET quantidade = 31 WHERE medicao_id = '00000000-0000-0000-0000-0000000000e1' AND quantidade = 30$$]);
CALL pg_temp.espera_erro('Medição com período sobreposto', ARRAY[
  $$INSERT INTO medicao (contrato_id, numero, revisao_id, periodo_inicio, periodo_fim) VALUES
    ('00000000-0000-0000-0000-0000000000c1', 2, '00000000-0000-0000-0000-0000000000d0', '2026-10-15', '2026-11-30')$$]);

INSERT INTO medicao (id, contrato_id, numero, revisao_id, periodo_inicio, periodo_fim) VALUES
  ('00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000c1', 2,
   '00000000-0000-0000-0000-0000000000d0', '2026-11-01', '2026-11-30');
INSERT INTO medicao_item (medicao_id, item_contratual_id, quantidade, valor) VALUES
  ('00000000-0000-0000-0000-0000000000e2', '10000000-0000-0000-0000-000000000211', 12.50, 0),
  ('00000000-0000-0000-0000-0000000000e2', '10000000-0000-0000-0000-000000000212', 10.00, 0),
  ('00000000-0000-0000-0000-0000000000e2', '10000000-0000-0000-0000-000000000022', 64.00, 0);

CALL pg_temp.espera_erro('Medir acima do contratado (escavação 42,60 > 42,50)', ARRAY[
  $$UPDATE medicao_item SET quantidade = 12.60 WHERE medicao_id = '00000000-0000-0000-0000-0000000000e2'
      AND item_contratual_id = '10000000-0000-0000-0000-000000000211'$$]);
CALL pg_temp.espera_erro('Abrir segunda medição com uma já em aberto', ARRAY[
  $$INSERT INTO medicao (contrato_id, numero, revisao_id, periodo_inicio, periodo_fim) VALUES
    ('00000000-0000-0000-0000-0000000000c1', 3, '00000000-0000-0000-0000-0000000000d0', '2026-12-01', '2026-12-31')$$]);

UPDATE medicao SET status = 'enviada'  WHERE id = '00000000-0000-0000-0000-0000000000e2';
UPDATE medicao SET status = 'aprovada', aprovada_por = 'Fiscal do contrato' WHERE id = '00000000-0000-0000-0000-0000000000e2';

-- Evento → Financeiro gera a conta a receber da medição 2 (o handler faz isto)
INSERT INTO outbox (agregado, agregado_id, evento, payload) VALUES
  ('medicao', '00000000-0000-0000-0000-0000000000e2', 'MedicaoAprovada', '{"numero": 2}');

-- -----------------------------------------------------------------------------
-- Aditivo 1: +60 dias, acréscimo, supressão e item novo (art. 127)
-- -----------------------------------------------------------------------------
INSERT INTO aditivo (id, contrato_id, numero, tipo, fundamento_legal, justificativa,
                     dias_prazo_execucao, nova_vigencia_fim, revisao_base_id) VALUES
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000c1', 1, 'prazo_valor',
   'Art. 124, I, b, e art. 125 da Lei 14.133/2021',
   'Sondagem revelou solo com baixa capacidade; aumento de fundações e drenagem',
   60, '2027-08-31', '00000000-0000-0000-0000-0000000000d0');

INSERT INTO aditivo_item (aditivo_id, item_contratual_id, operacao, quantidade_delta, preco_unitario, valor_delta) VALUES
  ('00000000-0000-0000-0000-0000000000f1', '10000000-0000-0000-0000-000000000212', 'acrescimo',   4.00, 0, 0),
  ('00000000-0000-0000-0000-0000000000f1', '10000000-0000-0000-0000-000000000032', 'supressao', -200.00, 0, 0);

-- Item novo: PU = preço de referência × fator do art. 127 (proposta ÷ orçamento-base)
INSERT INTO aditivo_item (aditivo_id, item_contratual_id, operacao, quantidade_delta, preco_unitario, valor_delta,
                          parent_item_contratual_id, codigo_eap, descricao, unidade, fonte, codigo_referencia, preco_referencia)
SELECT '00000000-0000-0000-0000-0000000000f1', '10000000-0000-0000-0000-000000000023', 'inclusao', 40.00,
       round(52.00 * c.fator_art127, 2), 0,
       '10000000-0000-0000-0000-000000000002', '2.3', 'Dreno com brita nº 2 e manta geotêxtil', 'm', 'PROPRIA', 'CP-008', 52.00
  FROM contrato c WHERE c.id = '00000000-0000-0000-0000-0000000000c1';

\echo
\echo '== Invariantes do aditivo =='
CALL pg_temp.espera_erro('Suprimir abaixo do já medido (escavação toda medida)', ARRAY[
  $$INSERT INTO aditivo_item (aditivo_id, item_contratual_id, operacao, quantidade_delta, preco_unitario, valor_delta)
    VALUES ('00000000-0000-0000-0000-0000000000f1', '10000000-0000-0000-0000-000000000211', 'supressao', -1, 0, 0)$$]);

\echo
\echo '== Fator do art. 127 e itens do aditivo =='
SELECT fator_art127 FROM contrato;
SELECT operacao, quantidade_delta, preco_unitario, valor_delta FROM aditivo_item ORDER BY operacao;

\echo
\echo '== Limites do art. 125 simulando o aditivo 1 antes de homologar =='
SELECT * FROM fn_limites_aditivos('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000f1');

-- -----------------------------------------------------------------------------
-- Caso de uso HomologarAditivo (no sistema fica na camada de aplicação; aqui em SQL
-- para provar o modelo): Rev. 1 = Rev. 0 ⊕ itens do aditivo
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_ad    aditivo%ROWTYPE;
  v_nova  uuid;
  v_nivel int;
  r       record;
BEGIN
  SELECT * INTO v_ad FROM aditivo WHERE id = '00000000-0000-0000-0000-0000000000f1';

  INSERT INTO revisao_orcamento (contrato_id, numero, origem, aditivo_id)
  VALUES (v_ad.contrato_id,
          (SELECT max(numero) + 1 FROM revisao_orcamento WHERE contrato_id = v_ad.contrato_id),
          'aditivo', v_ad.id)
  RETURNING id INTO v_nova;

  -- copia a árvore nível a nível aplicando os deltas
  FOR v_nivel IN 1 .. (SELECT max(nlevel(path)) FROM item_revisao WHERE revisao_id = v_ad.revisao_base_id) LOOP
    INSERT INTO item_revisao (revisao_id, item_contratual_id, parent_id, ordem, codigo_eap, tipo, descricao,
                              unidade, quantidade, custo_unitario, bdi_percentual, preco_unitario, fonte,
                              codigo_referencia, data_base_referencia, fonte_recurso, agrupador_evento_id,
                              codigo_original, linha_origem)
    SELECT v_nova, b.item_contratual_id,
           (SELECT n.id FROM item_revisao n
              JOIN item_revisao bp ON bp.item_contratual_id = n.item_contratual_id
             WHERE n.revisao_id = v_nova AND bp.id = b.parent_id),
           b.ordem, b.codigo_eap, b.tipo, b.descricao, b.unidade,
           b.quantidade + coalesce((SELECT sum(ai.quantidade_delta) FROM aditivo_item ai
                                     WHERE ai.aditivo_id = v_ad.id AND ai.item_contratual_id = b.item_contratual_id), 0),
           b.custo_unitario, b.bdi_percentual, b.preco_unitario, b.fonte, b.codigo_referencia,
           b.data_base_referencia, b.fonte_recurso, b.agrupador_evento_id, b.codigo_original, b.linha_origem
      FROM item_revisao b
     WHERE b.revisao_id = v_ad.revisao_base_id AND nlevel(b.path) = v_nivel;
  END LOOP;

  -- inclusões entram no fim do grupo pai
  FOR r IN SELECT * FROM aditivo_item WHERE aditivo_id = v_ad.id AND operacao = 'inclusao' ORDER BY codigo_eap LOOP
    INSERT INTO item_revisao (revisao_id, item_contratual_id, parent_id, ordem, codigo_eap, tipo, descricao,
                              unidade, quantidade, preco_unitario, fonte, codigo_referencia)
    SELECT v_nova, r.item_contratual_id, p.id,
           (SELECT coalesce(max(ordem), 0) + 1 FROM item_revisao WHERE revisao_id = v_nova AND parent_id = p.id),
           r.codigo_eap, 'servico', r.descricao, r.unidade, r.quantidade_delta, r.preco_unitario, r.fonte, r.codigo_referencia
      FROM item_revisao p
     WHERE p.revisao_id = v_nova AND p.item_contratual_id = r.parent_item_contratual_id;
  END LOOP;

  UPDATE revisao_orcamento SET status = 'substituida' WHERE id = v_ad.revisao_base_id;
  UPDATE revisao_orcamento SET status = 'vigente', data_vigencia = DATE '2026-11-28' WHERE id = v_nova;
  UPDATE aditivo SET status = 'homologado', revisao_resultante_id = v_nova,
                     data_assinatura = DATE '2026-11-28', homologado_em = now()
   WHERE id = v_ad.id;
  INSERT INTO outbox (agregado, agregado_id, evento, payload)
  VALUES ('aditivo', v_ad.id, 'AditivoHomologado', jsonb_build_object('revisao_nova', v_nova));
END $$;

\echo
\echo '== Revisões após a homologação =='
SELECT numero, origem, status, data_vigencia, valor_total FROM revisao_orcamento ORDER BY numero;

-- Aditivo 2 (rascunho, sobre a Rev. 1) só para simular estouro do limite de 25%
INSERT INTO aditivo (id, contrato_id, numero, tipo, fundamento_legal, justificativa, revisao_base_id)
SELECT '00000000-0000-0000-0000-0000000000f2', contrato_id, 2, 'valor', 'Art. 124, I, b', 'Simulação', id
  FROM revisao_orcamento WHERE contrato_id = '00000000-0000-0000-0000-0000000000c1' AND status = 'vigente';
INSERT INTO aditivo_item (aditivo_id, item_contratual_id, operacao, quantidade_delta, preco_unitario, valor_delta) VALUES
  ('00000000-0000-0000-0000-0000000000f2', '10000000-0000-0000-0000-000000000031', 'acrescimo', 120.00, 0, 0);

\echo
\echo '== Limites do art. 125: homologados x homologados + aditivo 2 simulado =='
SELECT 'homologados' AS cenario, * FROM fn_limites_aditivos('00000000-0000-0000-0000-0000000000c1')
UNION ALL
SELECT '+ aditivo 2', * FROM fn_limites_aditivos('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000f2');

UPDATE aditivo SET status = 'rejeitado' WHERE id = '00000000-0000-0000-0000-0000000000f2';

-- -----------------------------------------------------------------------------
-- Medição 3 (sobre a Rev. 1)
-- -----------------------------------------------------------------------------
\echo
\echo '== Invariantes após o aditivo =='
CALL pg_temp.espera_erro('Abrir medição sobre revisão substituída', ARRAY[
  $$INSERT INTO medicao (contrato_id, numero, revisao_id, periodo_inicio, periodo_fim) VALUES
    ('00000000-0000-0000-0000-0000000000c1', 3, '00000000-0000-0000-0000-0000000000d0', '2026-12-01', '2026-12-31')$$]);
CALL pg_temp.espera_erro('Alterar aditivo homologado', ARRAY[
  $$UPDATE aditivo SET dias_prazo_execucao = 90 WHERE id = '00000000-0000-0000-0000-0000000000f1'$$]);

INSERT INTO medicao (id, contrato_id, numero, revisao_id, periodo_inicio, periodo_fim)
SELECT '00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000000c1', 3, id, '2026-12-01', '2026-12-31'
  FROM revisao_orcamento WHERE contrato_id = '00000000-0000-0000-0000-0000000000c1' AND status = 'vigente';
INSERT INTO medicao_item (medicao_id, item_contratual_id, quantidade, valor) VALUES
  ('00000000-0000-0000-0000-0000000000e3', '10000000-0000-0000-0000-000000000212', 12.20, 0),  -- 22,20 = 18,20 + 4,00
  ('00000000-0000-0000-0000-0000000000e3', '10000000-0000-0000-0000-000000000023', 40.00, 0),  -- item novo
  ('00000000-0000-0000-0000-0000000000e3', '10000000-0000-0000-0000-000000000031', 100.00, 0);

CALL pg_temp.espera_erro('Medir chapisco acima da quantidade suprimida (450 > 440)', ARRAY[
  $$INSERT INTO medicao_item (medicao_id, item_contratual_id, quantidade, valor)
    VALUES ('00000000-0000-0000-0000-0000000000e3', '10000000-0000-0000-0000-000000000032', 450, 0)$$]);
INSERT INTO medicao_item (medicao_id, item_contratual_id, quantidade, valor) VALUES
  ('00000000-0000-0000-0000-0000000000e3', '10000000-0000-0000-0000-000000000032', 300.00, 0);

\echo
\echo '== BOLETIM DE MEDIÇÃO Nº 3 (Rev. 1) =='
SELECT lpad('', (nivel - 1) * 2) || codigo_eap AS item,
       left(descricao, 34)              AS descricao,
       unidade                          AS un,
       qtd_contratada::numeric(12,2)    AS qtd_contr,
       qtd_anterior::numeric(12,2)      AS qtd_ant,
       qtd_atual::numeric(12,2)         AS qtd_atual,
       qtd_saldo::numeric(12,2)         AS qtd_saldo,
       valor_contratado                 AS vlr_contr,
       valor_anterior                   AS vlr_ant,
       valor_atual                      AS vlr_atual,
       valor_saldo                      AS vlr_saldo,
       perc_acumulado                   AS "%_acum"
  FROM fn_boletim_medicao('00000000-0000-0000-0000-0000000000e3');

UPDATE medicao SET status = 'enviada'  WHERE id = '00000000-0000-0000-0000-0000000000e3';
UPDATE medicao SET status = 'aprovada', aprovada_por = 'Fiscal do contrato' WHERE id = '00000000-0000-0000-0000-0000000000e3';

\echo
\echo '== Situação do contrato =='
SELECT numero, valor_inicial, valor_atual, revisao_vigente, prazo_atual_dias, vigencia_atual,
       medido_aprovado, saldo_contratual, perc_executado
  FROM vw_contrato_situacao;
SELECT numero, periodo_inicio, periodo_fim, status, valor_bruto FROM medicao ORDER BY numero;

-- -----------------------------------------------------------------------------
-- Financeiro
-- -----------------------------------------------------------------------------
INSERT INTO plano_contas (id, codigo, descricao, natureza) VALUES
  ('00000000-0000-0000-0000-000000000101', '1.01', 'Receita de obras públicas',  'receita'),
  ('00000000-0000-0000-0000-000000000201', '2.01', 'Materiais aplicados',         'despesa'),
  ('00000000-0000-0000-0000-000000000301', '3.01', 'Despesas administrativas',    'despesa');
INSERT INTO fornecedor (id, razao_social, cnpj_cpf) VALUES
  ('00000000-0000-0000-0000-000000000f01', 'Concreteira Alfa Ltda',     '77888999000110'),
  ('00000000-0000-0000-0000-000000000f02', 'Concreteira Beta Ltda',     '77888999000290'),
  ('00000000-0000-0000-0000-000000000f03', 'Asfaltos Gama Ltda',        '77888999000370'),
  ('00000000-0000-0000-0000-000000000f04', 'Imobiliária Delta Ltda',    '77888999000450');
INSERT INTO conta_bancaria (id, descricao, banco) VALUES
  ('00000000-0000-0000-0000-000000000cb1', 'Conta movimento', '341');

-- Conta a receber da medição 2, com retenções do contrato (handler de MedicaoAprovada)
WITH m AS (SELECT * FROM medicao WHERE id = '00000000-0000-0000-0000-0000000000e2'),
t AS (
  INSERT INTO titulo (id, tipo, orgao_id, obra_id, medicao_id, plano_conta_id, documento, emissao, valor_bruto)
  SELECT '00000000-0000-0000-0000-00000000aa01', 'receber', c.orgao_id, c.obra_id, m.id,
         '00000000-0000-0000-0000-000000000101', 'NFS-e 102', DATE '2026-12-02', m.valor_bruto
    FROM m JOIN contrato c ON c.id = m.contrato_id
  RETURNING *)
INSERT INTO titulo_retencao (titulo_id, tipo, base, aliquota, valor)
SELECT t.id, r.tipo, round(t.valor_bruto * r.base_percentual / 100, 2), r.aliquota,
       round(round(t.valor_bruto * r.base_percentual / 100, 2) * r.aliquota / 100, 2)
  FROM t JOIN medicao m ON m.id = t.medicao_id
  JOIN contrato_retencao r ON r.contrato_id = m.contrato_id;

INSERT INTO titulo_parcela (id, titulo_id, numero, vencimento, valor)
SELECT '00000000-0000-0000-0000-00000000ab01', t.id, 1, DATE '2027-01-05',
       t.valor_bruto - (SELECT sum(valor) FROM titulo_retencao WHERE titulo_id = t.id)
  FROM titulo t WHERE t.id = '00000000-0000-0000-0000-00000000aa01';

-- Cotação → pedido de compra apropriado ao item 2.1.2 (concreto)
INSERT INTO cotacao (id, obra_id, numero, data_limite, status) VALUES
  ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-0000000000b1', 1, '2026-11-05', 'concluida');
INSERT INTO cotacao_item (id, cotacao_id, descricao, unidade, quantidade, item_contratual_id) VALUES
  ('00000000-0000-0000-0000-00000000c011', '00000000-0000-0000-0000-00000000c001', 'Concreto usinado fck 25 MPa', 'm³', 10,
   '10000000-0000-0000-0000-000000000212');
INSERT INTO cotacao_proposta (cotacao_item_id, fornecedor_id, preco_unitario, prazo_entrega_dias, vencedora) VALUES
  ('00000000-0000-0000-0000-00000000c011', '00000000-0000-0000-0000-000000000f01', 520.00, 2, true),
  ('00000000-0000-0000-0000-00000000c011', '00000000-0000-0000-0000-000000000f02', 545.00, 1, false);
INSERT INTO pedido_compra (id, obra_id, fornecedor_id, cotacao_id, numero, emissao, status) VALUES
  ('00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000f01',
   '00000000-0000-0000-0000-00000000c001', 1, '2026-11-06', 'aprovado');
INSERT INTO pedido_compra_item (pedido_id, cotacao_item_id, item_contratual_id, plano_conta_id, descricao, unidade, quantidade, preco_unitario)
SELECT '00000000-0000-0000-0000-00000000d001', ci.id, ci.item_contratual_id, '00000000-0000-0000-0000-000000000201',
       ci.descricao, ci.unidade, ci.quantidade, cp.preco_unitario
  FROM cotacao_item ci JOIN cotacao_proposta cp ON cp.cotacao_item_id = ci.id AND cp.vencedora;

-- Contas a pagar (handler de PedidoCompraAprovado + lançamentos diretos)
INSERT INTO titulo (id, tipo, fornecedor_id, obra_id, pedido_compra_id, plano_conta_id, documento, emissao, valor_bruto) VALUES
  ('00000000-0000-0000-0000-00000000aa02', 'pagar', '00000000-0000-0000-0000-000000000f01', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-000000000201', 'NF 5510', '2026-11-10',
   (SELECT sum(valor) FROM pedido_compra_item WHERE pedido_id = '00000000-0000-0000-0000-00000000d001')),
  ('00000000-0000-0000-0000-00000000aa03', 'pagar', '00000000-0000-0000-0000-000000000f03', '00000000-0000-0000-0000-0000000000b2',
   NULL, '00000000-0000-0000-0000-000000000201', 'NF 880', '2026-11-12', 8000.00),
  ('00000000-0000-0000-0000-00000000aa04', 'pagar', '00000000-0000-0000-0000-000000000f04', NULL,
   NULL, '00000000-0000-0000-0000-000000000301', 'Aluguel nov/2026', '2026-11-05', 3000.00);

INSERT INTO titulo_parcela (id, titulo_id, numero, vencimento, valor) VALUES
  ('00000000-0000-0000-0000-00000000ab02', '00000000-0000-0000-0000-00000000aa02', 1, '2026-12-10', 5200.00),
  ('00000000-0000-0000-0000-00000000ab03', '00000000-0000-0000-0000-00000000aa03', 1, '2026-12-12', 8000.00),
  ('00000000-0000-0000-0000-00000000ab04', '00000000-0000-0000-0000-00000000aa04', 1, '2026-11-10', 3000.00);

INSERT INTO apropriacao (titulo_id, obra_id, item_contratual_id, plano_conta_id, origem, valor)
SELECT '00000000-0000-0000-0000-00000000aa02', p.obra_id, pi.item_contratual_id, pi.plano_conta_id, 'pedido', pi.valor
  FROM pedido_compra_item pi JOIN pedido_compra p ON p.id = pi.pedido_id;
INSERT INTO apropriacao (titulo_id, obra_id, plano_conta_id, origem, valor) VALUES
  ('00000000-0000-0000-0000-00000000aa03', '00000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000201', 'direta', 8000.00);

-- Baixas
INSERT INTO baixa (parcela_id, conta_bancaria_id, data_pagamento, valor) VALUES
  ('00000000-0000-0000-0000-00000000ab04', '00000000-0000-0000-0000-000000000cb1', '2026-11-10', 3000.00),
  ('00000000-0000-0000-0000-00000000ab02', '00000000-0000-0000-0000-000000000cb1', '2026-12-10', 5200.00);

-- Rateio de nov/2026 pelo custo direto: o aluguel vai para as obras na proporção do custo apropriado
INSERT INTO rateio (id, competencia, criterio) VALUES
  ('00000000-0000-0000-0000-00000000ee01', '2026-11-01', 'custo_direto');
INSERT INTO rateio_obra (rateio_id, obra_id, base_calculo, percentual)
SELECT '00000000-0000-0000-0000-00000000ee01', ap.obra_id, sum(ap.valor),
       round(100 * sum(ap.valor) / sum(sum(ap.valor)) OVER (), 6)
  FROM apropriacao ap JOIN titulo t ON t.id = ap.titulo_id
 WHERE t.tipo = 'pagar' AND ap.origem IN ('direta', 'pedido')
   AND date_trunc('month', t.emissao) = DATE '2026-11-01'
 GROUP BY ap.obra_id;

-- valor por obra arredondado; a diferença de centavos vai para a maior base
WITH adm AS (SELECT * FROM titulo WHERE obra_id IS NULL AND tipo = 'pagar'
                                    AND date_trunc('month', emissao) = DATE '2026-11-01'),
ro AS (SELECT *, row_number() OVER (ORDER BY base_calculo DESC) AS ordem
         FROM rateio_obra WHERE rateio_id = '00000000-0000-0000-0000-00000000ee01'),
calc AS (
  SELECT adm.id AS titulo_id, adm.plano_conta_id, adm.valor_bruto, ro.obra_id, ro.ordem,
         round(adm.valor_bruto * ro.percentual / 100, 2) AS valor
    FROM adm CROSS JOIN ro)
INSERT INTO apropriacao (titulo_id, obra_id, plano_conta_id, origem, rateio_id, valor)
SELECT titulo_id, obra_id, plano_conta_id, 'rateio', '00000000-0000-0000-0000-00000000ee01',
       valor + CASE WHEN ordem = 1
                    THEN valor_bruto - sum(valor) OVER (PARTITION BY titulo_id) ELSE 0 END
  FROM calc;
UPDATE rateio SET status = 'aplicado' WHERE id = '00000000-0000-0000-0000-00000000ee01';

\echo
\echo '== Conta a receber da medição 2 (bruto, retenções, líquido) =='
SELECT t.documento, t.valor_bruto, r.tipo, r.base, r.aliquota, r.valor AS retido,
       (SELECT valor FROM titulo_parcela WHERE titulo_id = t.id) AS liquido_a_receber
  FROM titulo t JOIN titulo_retencao r ON r.titulo_id = t.id
 WHERE t.medicao_id IS NOT NULL ORDER BY r.tipo;

\echo
\echo '== Rateio do aluguel (R$ 3.000,00) pelo custo direto de nov/2026 =='
SELECT o.nome, ro.base_calculo, ro.percentual::numeric(9,2) AS "%", ap.valor AS rateado
  FROM rateio_obra ro JOIN obra o ON o.id = ro.obra_id
  JOIN apropriacao ap ON ap.rateio_id = ro.rateio_id AND ap.obra_id = ro.obra_id
 ORDER BY o.nome;
SELECT CASE WHEN sum(valor) = 3000 THEN 'OK, rateio fecha em R$ 3.000,00' ELSE 'ERRO no rateio' END AS conferencia
  FROM apropriacao WHERE origem = 'rateio';

\echo
\echo '== Custo apropriado x orçado sem BDI (itens com custo) =='
SELECT codigo_eap, descricao, custo_orcado_sem_bdi, custo_apropriado, perc_consumido
  FROM vw_custo_item WHERE custo_apropriado > 0;

\echo
\echo '== Fluxo de caixa mensal =='
SELECT * FROM vw_fluxo_caixa;

-- -----------------------------------------------------------------------------
-- Isolamento entre empresas (RLS) com o papel que a aplicação usa
-- -----------------------------------------------------------------------------
CREATE ROLE app_rw NOLOGIN;
GRANT USAGE ON SCHEMA public TO app_rw;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_rw;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO app_rw;

SET ROLE app_rw;
\echo
\echo '== RLS: o que cada empresa enxerga =='
SET app.tenant_id = 'bbbbbbbb-0000-0000-0000-000000000001';
SELECT 'empresa B' AS sessao, (SELECT count(*) FROM contrato) AS contratos, (SELECT count(*) FROM medicao) AS medicoes,
       (SELECT count(*) FROM vw_contrato_situacao) AS linhas_na_view;
CALL pg_temp.espera_erro('Empresa B gravar linha com tenant da empresa A', ARRAY[
  $$INSERT INTO obra (tenant_id, nome, municipio, uf) VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'Intrusa', 'X', 'PR')$$]);
SET app.tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001';
SELECT 'empresa A' AS sessao, (SELECT count(*) FROM contrato) AS contratos, (SELECT count(*) FROM medicao) AS medicoes,
       (SELECT count(*) FROM vw_contrato_situacao) AS linhas_na_view;
RESET ROLE;

\echo
\echo '== Trilha de auditoria e eventos =='
SELECT tabela, acao, count(*) FROM auditoria GROUP BY tabela, acao ORDER BY tabela, acao;
SELECT id, evento, agregado, publicado_em IS NOT NULL AS publicado FROM outbox ORDER BY id;
