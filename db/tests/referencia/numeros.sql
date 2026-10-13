-- Números de aceite do cenário do engenheiro (db/reference/seed_e_testes.sql),
-- conferidos à mão em docs/plano-fase-0.md §4. Roda depois do seed, sobre o schema
-- de referência e sobre a migração 0001: os dois têm que dar os mesmos números.
\set c '''00000000-0000-0000-0000-0000000000c1'''

SELECT pg_temp.confere('escavação 42,50 × 68,93, truncado',
  (SELECT ir.valor_total FROM item_revisao ir JOIN revisao_orcamento r ON r.id = ir.revisao_id
    WHERE r.numero = 0 AND ir.codigo_eap = '2.1.1'), 2929.52);
SELECT pg_temp.confere('Rev. 0 = valor do contrato',
  (SELECT valor_total FROM revisao_orcamento WHERE numero = 0), 58551.28);
SELECT pg_temp.confere('fator do art. 127', (SELECT fator_art127 FROM contrato WHERE id = :c), 0.91059533);

SELECT pg_temp.confere('aditivo 1: acréscimo de concreto',
  (SELECT ai.valor_delta FROM aditivo_item ai JOIN aditivo a ON a.id = ai.aditivo_id
    WHERE a.numero = 1 AND ai.operacao = 'acrescimo'), 3141.60);
SELECT pg_temp.confere('aditivo 1: supressão de chapisco',
  (SELECT ai.valor_delta FROM aditivo_item ai JOIN aditivo a ON a.id = ai.aditivo_id
    WHERE a.numero = 1 AND ai.operacao = 'supressao'), -1486.00);
SELECT pg_temp.confere('aditivo 1: preço do item novo, 52,00 × fator',
  (SELECT ai.preco_unitario FROM aditivo_item ai JOIN aditivo a ON a.id = ai.aditivo_id
    WHERE a.numero = 1 AND ai.operacao = 'inclusao'), 47.35);
SELECT pg_temp.confere('aditivo 1: inclusão do dreno',
  (SELECT ai.valor_delta FROM aditivo_item ai JOIN aditivo a ON a.id = ai.aditivo_id
    WHERE a.numero = 1 AND ai.operacao = 'inclusao'), 1894.00);

SELECT pg_temp.confere('art. 125: acréscimos homologados', (SELECT acrescimos FROM fn_limites_aditivos(:c)), 5035.60);
SELECT pg_temp.confere('art. 125: supressões homologadas', (SELECT supressoes FROM fn_limites_aditivos(:c)), 1486.00);
SELECT pg_temp.confere('art. 125: % de acréscimos', (SELECT perc_acrescimos FROM fn_limites_aditivos(:c)), 8.60);
SELECT pg_temp.confere('art. 125: % de supressões', (SELECT perc_supressoes FROM fn_limites_aditivos(:c)), 2.54);
SELECT pg_temp.confere_texto('art. 125: situação', (SELECT situacao FROM fn_limites_aditivos(:c)), 'OK');
SELECT pg_temp.confere('art. 125 simulando o aditivo 2: acréscimos',
  (SELECT acrescimos FROM fn_limites_aditivos(:c, '00000000-0000-0000-0000-0000000000f2')), 15733.60);
SELECT pg_temp.confere('art. 125 simulando o aditivo 2: %',
  (SELECT perc_acrescimos FROM fn_limites_aditivos(:c, '00000000-0000-0000-0000-0000000000f2')), 26.87);
SELECT pg_temp.confere_texto('art. 125 simulando o aditivo 2: situação',
  (SELECT situacao FROM fn_limites_aditivos(:c, '00000000-0000-0000-0000-0000000000f2')), 'EXCEDE LIMITE LEGAL');

SELECT pg_temp.confere('Rev. 1', (SELECT valor_total FROM revisao_orcamento WHERE numero = 1), 62100.88);
SELECT pg_temp.confere('medição 1', (SELECT valor_bruto FROM medicao WHERE numero = 1), 6990.90);
SELECT pg_temp.confere('medição 2', (SELECT valor_bruto FROM medicao WHERE numero = 2), 11836.90);
SELECT pg_temp.confere('medição 3 = total do boletim nº 3', (SELECT valor_bruto FROM medicao WHERE numero = 3), 22619.88);

SELECT pg_temp.confere('boletim nº 3: concreto',
  (SELECT valor_atual FROM fn_boletim_medicao('00000000-0000-0000-0000-0000000000e3') WHERE codigo_eap = '2.1.2'), 9581.88);
SELECT pg_temp.confere('boletim nº 3: dreno',
  (SELECT valor_atual FROM fn_boletim_medicao('00000000-0000-0000-0000-0000000000e3') WHERE codigo_eap = '2.3'), 1894.00);
SELECT pg_temp.confere('boletim nº 3: alvenaria',
  (SELECT valor_atual FROM fn_boletim_medicao('00000000-0000-0000-0000-0000000000e3') WHERE codigo_eap = '3.1'), 8915.00);
SELECT pg_temp.confere('boletim nº 3: chapisco',
  (SELECT valor_atual FROM fn_boletim_medicao('00000000-0000-0000-0000-0000000000e3') WHERE codigo_eap = '3.2'), 2229.00);

SELECT pg_temp.confere('medido aprovado', (SELECT medido_aprovado FROM vw_contrato_situacao WHERE contrato_id = :c), 41447.68);
SELECT pg_temp.confere('saldo contratual', (SELECT saldo_contratual FROM vw_contrato_situacao WHERE contrato_id = :c), 20653.20);
SELECT pg_temp.confere('% executado', (SELECT perc_executado FROM vw_contrato_situacao WHERE contrato_id = :c), 66.74);
