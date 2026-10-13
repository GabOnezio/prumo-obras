-- Fluxo da medição (migração 0004): a situação só muda por etapa registrada, com a transição,
-- a designação e a segregação de funções conferidas pelo banco.
-- Roda sobre o seed, como app_rw, no contrato por quantidade (052/2026).
SET ROLE app_rw;
SET app.tenant_id = 'e0e0e0e0-0000-0000-0000-000000000001';
SET app.usuario = 'teste.medicao';

\set c_bm '''e0e0e0e0-0000-0000-0000-0000000000c2'''
\set m1   '''e0e0e0e0-0000-0000-0000-0000000000e1'''
\set fiscal        '''e0e0e0e0-0000-0000-0001-000000000001'''
\set substituto    '''e0e0e0e0-0000-0000-0001-000000000002'''
\set gestor        '''e0e0e0e0-0000-0000-0001-000000000003'''
\set comissao      '''e0e0e0e0-0000-0000-0001-000000000004'''
\set preposto_alfa '''e0e0e0e0-0000-0000-0001-000000000005'''
\set preposto      '''e0e0e0e0-0000-0000-0001-000000000007'''
\set orcamentista  '''e0e0e0e0-0000-0000-0001-000000000008'''

CREATE FUNCTION pg_temp.item(p_codigo text) RETURNS uuid LANGUAGE sql AS $$
  SELECT ir.item_contratual_id FROM item_revisao ir
    JOIN revisao_orcamento r ON r.id = ir.revisao_id
   WHERE r.contrato_id = 'e0e0e0e0-0000-0000-0000-0000000000c2' AND r.numero = 0 AND ir.codigo_eap = p_codigo
$$;
CREATE PROCEDURE pg_temp.etapa(p_quem uuid, p_acao acao_medicao, p_motivo text DEFAULT NULL) LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('app.usuario_id', p_quem::text, false);
  INSERT INTO medicao_etapa (medicao_id, acao, motivo) VALUES ('e0e0e0e0-0000-0000-0000-0000000000e1', p_acao, p_motivo);
END $$;
CREATE FUNCTION pg_temp.situacao() RETURNS text LANGUAGE sql AS $$
  SELECT status::text FROM medicao WHERE id = 'e0e0e0e0-0000-0000-0000-0000000000e1'
$$;

-- Medição 1: 4,50 m² de placa (1.855,66) e 100,00 m³ de escavação (943,00) = 2.798,66
INSERT INTO medicao (id, contrato_id, numero, revisao_id, periodo_inicio, periodo_fim)
SELECT :m1, :c_bm, 1, id, '2026-11-01', '2026-11-30' FROM revisao_orcamento WHERE contrato_id = :c_bm AND status = 'vigente';
INSERT INTO medicao_item (medicao_id, item_contratual_id, quantidade, valor) VALUES
  (:m1, pg_temp.item('1.1'), 4.50, 0), (:m1, pg_temp.item('2.2'), 100.00, 0);

\echo
\echo '== A situação só muda por etapa, em nome de quem está na sessão =='
CALL pg_temp.espera_erro_com('mudar a situação direto na medição', 'só muda por uma etapa registrada', ARRAY[
  format($$UPDATE medicao SET status = 'aprovada_fiscal' WHERE id = %L$$, :m1)]);
CALL pg_temp.espera_erro_com('pular para "paga" direto na medição', 'só muda por uma etapa registrada', ARRAY[
  format($$UPDATE medicao SET status = 'paga', valor_bruto = 999999 WHERE id = %L$$, :m1)]);
CALL pg_temp.espera_erro_com('etapa sem usuário na sessão', 'não diz quem está agindo', ARRAY[
  format($$INSERT INTO medicao_etapa (medicao_id, acao) VALUES (%L, 'enviar')$$, :m1)]);

\echo
\echo '== Cada ação só cabe no estado certo e só para quem tem a função =='
CALL pg_temp.espera_erro_com('aprovar medição em rascunho', 'não aceita a ação', ARRAY[
  format($$CALL pg_temp.etapa(%L, 'aprovar_fiscal')$$, :fiscal)]);
CALL pg_temp.espera_erro_com('atestar medição em rascunho', 'não aceita a ação', ARRAY[
  format($$CALL pg_temp.etapa(%L, 'atestar')$$, :gestor)]);
CALL pg_temp.espera_erro_com('fiscal enviar a medição da empresa', 'não tem, neste contrato, a função', ARRAY[
  format($$CALL pg_temp.etapa(%L, 'enviar')$$, :fiscal)]);
CALL pg_temp.espera_erro_com('empresa de outro contrato enviar', 'não tem, neste contrato, a função', ARRAY[
  format($$CALL pg_temp.etapa(%L, 'enviar')$$, :preposto_alfa)]);
CALL pg_temp.espera_erro_com('servidor sem designação enviar', 'não tem, neste contrato, a função', ARRAY[
  format($$CALL pg_temp.etapa(%L, 'enviar')$$, :orcamentista)]);
CALL pg_temp.etapa(:preposto, 'enviar');
SELECT pg_temp.confere_texto('depois de enviar', pg_temp.situacao(), 'enviada');
-- 4,50 × 412,37 = 1.855,665 → 1.855,66 (trunca) · 100,00 × 9,43 = 943,00
SELECT pg_temp.confere('valor bruto consolidado no envio', (SELECT valor_bruto FROM medicao WHERE id = :m1), 2798.66);

CALL pg_temp.espera_erro_com('empresa alterar item de medição enviada', 'itens não podem ser alterados', ARRAY[
  format($$UPDATE medicao_item SET quantidade = 1 WHERE medicao_id = %L$$, :m1)]);
CALL pg_temp.espera_erro_com('alterar o período de medição enviada', 'não pode ser alterada', ARRAY[
  format($$UPDATE medicao SET periodo_fim = '2026-12-31' WHERE id = %L$$, :m1)]);
CALL pg_temp.espera_erro_com('apagar medição enviada', 'já saiu do rascunho', ARRAY[
  format($$DELETE FROM medicao WHERE id = %L$$, :m1)]);
CALL pg_temp.espera_erro_com('empresa iniciar a análise', 'não tem, neste contrato, a função', ARRAY[
  format($$CALL pg_temp.etapa(%L, 'iniciar_analise')$$, :preposto)]);
CALL pg_temp.espera_erro_com('gestor do contrato fazer a análise do fiscal', 'não tem, neste contrato, a função', ARRAY[
  format($$CALL pg_temp.etapa(%L, 'iniciar_analise')$$, :gestor)]);
CALL pg_temp.espera_erro_com('aprovar sem ter iniciado a análise', 'não aceita a ação', ARRAY[
  format($$CALL pg_temp.etapa(%L, 'aprovar_fiscal')$$, :fiscal)]);
CALL pg_temp.espera_erro_com('abrir outra medição com esta em aberto', 'ux_medicao_aberta', ARRAY[
  format($$INSERT INTO medicao (contrato_id, numero, revisao_id, periodo_inicio, periodo_fim)
           SELECT contrato_id, 2, revisao_id, '2026-12-01', '2026-12-31' FROM medicao WHERE id = %L$$, :m1)]);
CALL pg_temp.etapa(:fiscal, 'iniciar_analise');

\echo
\echo '== Devolver exige motivo; devolvida, a empresa corrige e envia de novo =='
CALL pg_temp.espera_erro_com('devolver sem motivo', 'exige o motivo', ARRAY[
  format($$CALL pg_temp.etapa(%L, 'devolver')$$, :fiscal)]);
CALL pg_temp.espera_erro_com('devolver com motivo em branco', 'exige o motivo', ARRAY[
  format($$CALL pg_temp.etapa(%L, 'devolver', '   ')$$, :fiscal)]);
CALL pg_temp.espera_erro_com('empresa devolver a própria medição', 'não tem, neste contrato, a função', ARRAY[
  format($$CALL pg_temp.etapa(%L, 'devolver', 'x')$$, :preposto)]);
CALL pg_temp.etapa(:fiscal, 'devolver', 'Escavação medida a mais: o levantamento dá 90 m³');
SELECT pg_temp.confere_texto('depois de devolver', pg_temp.situacao(), 'devolvida');
UPDATE medicao_item SET quantidade = 90.00 WHERE medicao_id = :m1 AND item_contratual_id = pg_temp.item('2.2');
CALL pg_temp.espera_erro_com('fiscal aprovar medição devolvida', 'não aceita a ação', ARRAY[
  format($$CALL pg_temp.etapa(%L, 'aprovar_fiscal')$$, :fiscal)]);
CALL pg_temp.etapa(:preposto, 'enviar');
-- 1.855,66 + 90,00 × 9,43 = 848,70
SELECT pg_temp.confere('valor bruto refeito no reenvio', (SELECT valor_bruto FROM medicao WHERE id = :m1), 2704.36);
CALL pg_temp.etapa(:fiscal, 'iniciar_analise');

\echo
\echo '== Glosa por quantidade: do fiscal, na análise; com glosa a medição volta, não é aprovada =='
SET app.usuario_id = :preposto;
CALL pg_temp.espera_erro_com('empresa registrar glosa', 'Só fiscal', ARRAY[
  format($$INSERT INTO medicao_glosa (medicao_id, item_contratual_id, quantidade, valor, motivo)
           VALUES (%L, pg_temp.item('2.2'), 5, 47.15, 'x')$$, :m1)]);
SET app.usuario_id = :fiscal;
CALL pg_temp.espera_erro_com('glosa maior que o medido', 'maior que a quantidade medida', ARRAY[
  format($$INSERT INTO medicao_glosa (medicao_id, item_contratual_id, quantidade, valor, motivo)
           VALUES (%L, pg_temp.item('2.2'), 90.01, 1, 'x')$$, :m1)]);
CALL pg_temp.espera_erro_com('glosa de item que não está na medição', 'maior que a quantidade medida', ARRAY[
  format($$INSERT INTO medicao_glosa (medicao_id, item_contratual_id, quantidade, valor, motivo)
           VALUES (%L, pg_temp.item('3.1'), 1, 1, 'x')$$, :m1)]);
INSERT INTO medicao_glosa (medicao_id, item_contratual_id, quantidade, valor, motivo)
VALUES (:m1, pg_temp.item('2.2'), 5, 47.15, 'Trecho não executado');
CALL pg_temp.espera_erro_com('aprovar medição com glosa por quantidade', 'glosa por quantidade não é aprovada', ARRAY[
  format($$CALL pg_temp.etapa(%L, 'aprovar_fiscal')$$, :fiscal)]);
DELETE FROM medicao_glosa WHERE medicao_id = :m1;

\echo
\echo '== Segregação de funções =='
-- O banco não deixa a mesma pessoa ser da empresa e fiscal no mesmo contrato. Para provar a
-- segunda defesa, o dono desliga esse gatilho e põe o preposto também como fiscal.
RESET ROLE;
ALTER TABLE designacao DISABLE TRIGGER trg_designacao_dois_lados;
INSERT INTO usuario (id, tenant_id, nome) VALUES
  ('e0e0e0e0-0000-0000-0001-0000000000f1', 'e0e0e0e0-0000-0000-0000-000000000001', 'Servidor de teste (fictício)');
INSERT INTO servidor (id, tenant_id, usuario_id, matricula, cargo) VALUES
  ('e0e0e0e0-0000-0000-0001-0000000000f2', 'e0e0e0e0-0000-0000-0000-000000000001', :preposto, 'EX-9007', 'Cargo de teste');
INSERT INTO designacao (tenant_id, servidor_id, contrato_id, funcao, inicio, portaria_id)
SELECT 'e0e0e0e0-0000-0000-0000-000000000001', 'e0e0e0e0-0000-0000-0001-0000000000f2', :c_bm, 'fiscal_tecnico', DATE '2026-09-15', id FROM portaria;
-- e o fiscal técnico ganha também a função de gestor do contrato
INSERT INTO designacao (tenant_id, servidor_id, contrato_id, funcao, inicio, portaria_id)
SELECT 'e0e0e0e0-0000-0000-0000-000000000001', s.id, :c_bm, 'gestor_contrato', DATE '2026-09-15', p.id
  FROM servidor s, portaria p WHERE s.usuario_id = :fiscal;
ALTER TABLE designacao ENABLE TRIGGER trg_designacao_dois_lados;
SET ROLE app_rw;

CALL pg_temp.espera_erro_com('quem enviou aprovar como fiscal', 'Quem enviou a medição não pode aprová-la', ARRAY[
  format($$CALL pg_temp.etapa(%L, 'aprovar_fiscal')$$, :preposto)]);
CALL pg_temp.etapa(:fiscal, 'aprovar_fiscal');
SELECT pg_temp.confere_texto('depois de aprovar', pg_temp.situacao(), 'aprovada_fiscal');
SELECT pg_temp.confere('medido e aprovado na situação do contrato',
  (SELECT medido_aprovado FROM vw_contrato_situacao WHERE contrato_id = :c_bm), 2704.36);
CALL pg_temp.espera_erro_com('fiscal devolver depois de aprovar', 'não aceita a ação', ARRAY[
  format($$CALL pg_temp.etapa(%L, 'devolver', 'mudei de ideia')$$, :fiscal)]);
CALL pg_temp.espera_erro_com('empresa cancelar medição aprovada', 'não aceita a ação', ARRAY[
  format($$CALL pg_temp.etapa(%L, 'cancelar')$$, :preposto)]);
CALL pg_temp.espera_erro_com('quem aprovou como fiscal atestar', 'Quem aprovou a medição como fiscal não pode atestá-la', ARRAY[
  format($$CALL pg_temp.etapa(%L, 'atestar')$$, :fiscal)]);
CALL pg_temp.espera_erro_com('outro fiscal, sem função de gestor, atestar', 'não tem, neste contrato, a função', ARRAY[
  format($$CALL pg_temp.etapa(%L, 'atestar')$$, :substituto)]);
CALL pg_temp.espera_erro_com('empresa atestar', 'não tem, neste contrato, a função', ARRAY[
  format($$CALL pg_temp.etapa(%L, 'atestar')$$, :preposto_alfa)]);
CALL pg_temp.etapa(:gestor, 'atestar');
SELECT pg_temp.confere_texto('depois de atestar', pg_temp.situacao(), 'atestada');

\echo
\echo '== Liquidação e pagamento: só com a referência do documento da contabilidade =='
CALL pg_temp.espera_erro_com('registrar liquidação sem a referência', 'Sem a referência da liquidação', ARRAY[
  format($$CALL pg_temp.etapa(%L, 'registrar_liquidacao')$$, :gestor)]);
SET app.usuario_id = :gestor;
CALL pg_temp.espera_erro('referência de liquidação sem medição', ARRAY[
  format($$INSERT INTO execucao_financeira_ref (contrato_id, tipo, numero, valor, data) VALUES (%L, 'liquidacao', 'L-001', 2704.36, '2026-12-20')$$, :c_bm)]);
INSERT INTO execucao_financeira_ref (contrato_id, medicao_id, tipo, numero, valor, data) VALUES
  (:c_bm, :m1, 'liquidacao', 'L-001', 2704.36, '2026-12-20');
CALL pg_temp.espera_erro_com('registrar pagamento antes da liquidação', 'não aceita a ação', ARRAY[
  format($$CALL pg_temp.etapa(%L, 'registrar_pagamento')$$, :gestor)]);
CALL pg_temp.espera_erro_com('fiscal registrar a liquidação', 'não tem, neste contrato, a função', ARRAY[
  format($$CALL pg_temp.etapa(%L, 'registrar_liquidacao')$$, :substituto)]);
CALL pg_temp.etapa(:gestor, 'registrar_liquidacao');
CALL pg_temp.espera_erro_com('registrar pagamento sem a referência', 'Sem a referência do pagamento', ARRAY[
  format($$CALL pg_temp.etapa(%L, 'registrar_pagamento')$$, :gestor)]);
SET app.usuario_id = :gestor;
INSERT INTO execucao_financeira_ref (contrato_id, medicao_id, tipo, numero, valor, data) VALUES
  (:c_bm, :m1, 'pagamento', 'OB-001', 2569.14, '2027-01-15');
CALL pg_temp.etapa(:gestor, 'registrar_pagamento');
SELECT pg_temp.confere_texto('fim do caminho', pg_temp.situacao(), 'paga');
CALL pg_temp.espera_erro('alterar referência de execução financeira', ARRAY[
  $$UPDATE execucao_financeira_ref SET valor = 1$$]);

\echo
\echo '== Medição paga não tem saída; a trilha não se reescreve =='
CALL pg_temp.espera_erro_com('qualquer ação em medição paga', 'não aceita a ação', ARRAY[
  format($$CALL pg_temp.etapa(%L, 'devolver', 'x')$$, :fiscal)]);
CALL pg_temp.espera_erro_com('cancelar medição paga', 'não aceita a ação', ARRAY[
  format($$CALL pg_temp.etapa(%L, 'cancelar')$$, :preposto)]);
CALL pg_temp.espera_erro('aplicação alterar a trilha', ARRAY[$$UPDATE medicao_etapa SET motivo = 'outro'$$]);
CALL pg_temp.espera_erro('aplicação apagar a trilha', ARRAY[$$DELETE FROM medicao_etapa$$]);
RESET ROLE;
CALL pg_temp.espera_erro_com('nem o dono das tabelas reescreve a trilha', 'Etapa da medição não se altera', ARRAY[
  $$UPDATE medicao_etapa SET motivo = 'outro'$$]);
CALL pg_temp.espera_erro_com('nem o dono muda a situação sem etapa', 'só muda por uma etapa registrada', ARRAY[
  $$UPDATE medicao SET status = 'rascunho'$$]);
SET ROLE app_rw;

-- A trilha conta a história inteira: quem, o quê, de onde para onde.
SELECT pg_temp.confere('etapas registradas', (SELECT count(*) FROM medicao_etapa WHERE medicao_id = :m1), 9);
SELECT pg_temp.confere_texto('a história da medição',
  (SELECT string_agg(e.acao || ':' || e.de || '>' || e.para, ' ' ORDER BY e.em, e.id) FROM medicao_etapa e WHERE e.medicao_id = :m1),
  'enviar:rascunho>enviada iniciar_analise:enviada>em_analise devolver:em_analise>devolvida enviar:devolvida>enviada iniciar_analise:enviada>em_analise aprovar_fiscal:em_analise>aprovada_fiscal atestar:aprovada_fiscal>atestada registrar_liquidacao:atestada>liquidada registrar_pagamento:liquidada>paga');
SELECT pg_temp.confere_texto('quem aprovou e quem atestou',
  (SELECT string_agg(u.nome, ' / ' ORDER BY e.em) FROM medicao_etapa e JOIN usuario u ON u.id = e.usuario_id
    WHERE e.medicao_id = :m1 AND e.acao IN ('aprovar_fiscal', 'atestar')),
  'Fiscal técnico (fictício) / Gestor do contrato (fictício)');
SELECT pg_temp.confere_texto('o motivo da devolução ficou registrado',
  (SELECT motivo FROM medicao_etapa WHERE medicao_id = :m1 AND acao = 'devolver'),
  'Escavação medida a mais: o levantamento dá 90 m³');

\echo
\echo '== Cancelar: só a empresa, só antes da análise =='
INSERT INTO medicao (id, contrato_id, numero, revisao_id, periodo_inicio, periodo_fim)
SELECT 'e0e0e0e0-0000-0000-0000-0000000000e2', :c_bm, 2, id, '2026-12-01', '2026-12-31'
  FROM revisao_orcamento WHERE contrato_id = :c_bm AND status = 'vigente';
SET app.usuario_id = :fiscal;
CALL pg_temp.espera_erro_com('fiscal cancelar a medição da empresa', 'não tem, neste contrato, a função', ARRAY[
  $$INSERT INTO medicao_etapa (medicao_id, acao) VALUES ('e0e0e0e0-0000-0000-0000-0000000000e2', 'cancelar')$$]);
SET app.usuario_id = :preposto;
INSERT INTO medicao_etapa (medicao_id, acao) VALUES ('e0e0e0e0-0000-0000-0000-0000000000e2', 'cancelar');
SELECT pg_temp.confere_texto('cancelada',
  (SELECT status::text FROM medicao WHERE id = 'e0e0e0e0-0000-0000-0000-0000000000e2'), 'cancelada');
CALL pg_temp.espera_erro_com('reabrir medição cancelada', 'não aceita a ação', ARRAY[
  $$INSERT INTO medicao_etapa (medicao_id, acao) VALUES ('e0e0e0e0-0000-0000-0000-0000000000e2', 'enviar')$$]);

RESET ROLE;
