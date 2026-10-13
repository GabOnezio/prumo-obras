-- Diário de obras (migração 0005). Roda sobre o seed, como app_rw, no contrato 045/2026.
SET ROLE app_rw;
SET app.tenant_id = 'e0e0e0e0-0000-0000-0000-000000000001';
SET app.usuario = 'teste.diario';

\set c_ev  '''e0e0e0e0-0000-0000-0000-0000000000c1'''
\set obra  '''e0e0e0e0-0000-0000-0000-0000000000b1'''
\set obra2 '''e0e0e0e0-0000-0000-0000-0000000000b2'''
\set d1    '''e0e0e0e0-0000-0000-0006-000000000001'''
\set d2    '''e0e0e0e0-0000-0000-0006-000000000002'''
\set fiscal     '''e0e0e0e0-0000-0000-0001-000000000001'''
\set substituto '''e0e0e0e0-0000-0000-0001-000000000002'''
\set preposto   '''e0e0e0e0-0000-0000-0001-000000000005'''
\set apontador  '''e0e0e0e0-0000-0000-0001-000000000006'''
\set preposto_beta '''e0e0e0e0-0000-0000-0001-000000000007'''

CREATE PROCEDURE pg_temp.etapa(p_rdo uuid, p_quem uuid, p_acao acao_rdo, p_motivo text DEFAULT NULL) LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('app.usuario_id', p_quem::text, false);
  INSERT INTO rdo_etapa (rdo_id, acao, motivo) VALUES (p_rdo, p_acao, p_motivo);
END $$;

\echo
\echo '== O diário é de um contrato da obra e nasce em rascunho =='
CALL pg_temp.espera_erro_com('diário com contrato de outra obra', 'não é desta obra', ARRAY[
  format($$INSERT INTO rdo (obra_id, contrato_id, data, responsavel) VALUES (%L, %L, '2026-12-01', 'Apontador')$$, :obra2, :c_ev)]);
CALL pg_temp.espera_erro_com('diário que já nasce fechado', 'nasce em rascunho', ARRAY[
  format($$INSERT INTO rdo (obra_id, contrato_id, data, responsavel, status) VALUES (%L, %L, '2026-12-01', 'Apontador', 'validado')$$, :obra, :c_ev)]);
INSERT INTO rdo (id, obra_id, contrato_id, data, clima_manha, responsavel) VALUES (:d1, :obra, :c_ev, '2026-12-01', 'bom', 'Apontador');
INSERT INTO rdo_efetivo (rdo_id, funcao, quantidade) VALUES (:d1, 'Pedreiro', 4), (:d1, 'Servente', 6);
INSERT INTO rdo_ocorrencia (rdo_id, tipo, descricao) VALUES (:d1, 'servico_executado', 'Alvenaria do térreo, eixo A');
CALL pg_temp.espera_erro('dois diários no mesmo dia e contrato', ARRAY[
  format($$INSERT INTO rdo (obra_id, contrato_id, data, responsavel) VALUES (%L, %L, '2026-12-01', 'Outro')$$, :obra, :c_ev)]);

\echo
\echo '== A situação só muda por etapa; a empresa fecha, o fiscal valida =='
CALL pg_temp.espera_erro_com('mudar a situação direto no diário', 'só muda por uma etapa registrada', ARRAY[
  format($$UPDATE rdo SET status = 'validado' WHERE id = %L$$, :d1)]);
CALL pg_temp.espera_erro_com('fiscal fechar o diário da empresa', 'não tem, neste contrato, a função', ARRAY[
  format($$CALL pg_temp.etapa(%L, %L, 'fechar')$$, :d1, :fiscal)]);
CALL pg_temp.espera_erro_com('empresa de outro contrato fechar', 'não tem, neste contrato, a função', ARRAY[
  format($$CALL pg_temp.etapa(%L, %L, 'fechar')$$, :d1, :preposto_beta)]);
CALL pg_temp.espera_erro_com('validar diário em rascunho', 'não aceita a ação', ARRAY[
  format($$CALL pg_temp.etapa(%L, %L, 'validar')$$, :d1, :fiscal)]);
CALL pg_temp.espera_erro_com('instrução do fiscal em diário ainda em rascunho', 'já fechou', ARRAY[
  format($$INSERT INTO rdo_instrucao (rdo_id, texto) VALUES (%L, 'x')$$, :d1)]);
CALL pg_temp.etapa(:d1, :apontador, 'fechar');

\echo
\echo '== Dia fechado não é sobrescrito =='
CALL pg_temp.espera_erro_com('alterar o clima do dia fechado', 'dia fechado não é sobrescrito', ARRAY[
  format($$UPDATE rdo SET clima_manha = 'chuva_forte' WHERE id = %L$$, :d1)]);
CALL pg_temp.espera_erro_com('trocar o efetivo do dia fechado', 'dia fechado não é sobrescrito', ARRAY[
  format($$UPDATE rdo_efetivo SET quantidade = 40 WHERE rdo_id = %L$$, :d1)]);
CALL pg_temp.espera_erro_com('acrescentar serviço ao dia fechado', 'dia fechado não é sobrescrito', ARRAY[
  format($$INSERT INTO rdo_ocorrencia (rdo_id, tipo, descricao) VALUES (%L, 'servico_executado', 'Cobertura')$$, :d1)]);
CALL pg_temp.espera_erro_com('apagar ocorrência do dia fechado', 'dia fechado não é sobrescrito', ARRAY[
  format($$DELETE FROM rdo_ocorrencia WHERE rdo_id = %L$$, :d1)]);
CALL pg_temp.espera_erro_com('acrescentar foto ao dia fechado', 'dia fechado não é sobrescrito', ARRAY[
  format($$INSERT INTO rdo_foto (rdo_id, s3_key, tirada_em) VALUES (%L, 'x', now())$$, :d1)]);
CALL pg_temp.espera_erro_com('apagar o diário fechado', 'não se apaga', ARRAY[format($$DELETE FROM rdo WHERE id = %L$$, :d1)]);
CALL pg_temp.espera_erro_com('fechar de novo', 'não aceita a ação', ARRAY[
  format($$CALL pg_temp.etapa(%L, %L, 'fechar')$$, :d1, :apontador)]);

\echo
\echo '== Validação: do fiscal designado, que não é quem fechou; devolver exige motivo =='
CALL pg_temp.espera_erro_com('empresa iniciar a validação', 'não tem, neste contrato, a função', ARRAY[
  format($$CALL pg_temp.etapa(%L, %L, 'iniciar_validacao')$$, :d1, :preposto)]);
CALL pg_temp.espera_erro_com('validar sem iniciar a validação', 'não aceita a ação', ARRAY[
  format($$CALL pg_temp.etapa(%L, %L, 'validar')$$, :d1, :fiscal)]);
CALL pg_temp.etapa(:d1, :fiscal, 'iniciar_validacao');
CALL pg_temp.espera_erro_com('devolver sem motivo', 'exige o motivo', ARRAY[
  format($$CALL pg_temp.etapa(%L, %L, 'devolver')$$, :d1, :fiscal)]);
-- Para provar a segunda defesa, o dono põe o apontador também como fiscal.
RESET ROLE;
ALTER TABLE designacao DISABLE TRIGGER trg_designacao_dois_lados;
INSERT INTO servidor (id, tenant_id, usuario_id, matricula, cargo) VALUES
  ('e0e0e0e0-0000-0000-0001-0000000000f6', 'e0e0e0e0-0000-0000-0000-000000000001', :apontador, 'EX-9006', 'Cargo de teste');
INSERT INTO designacao (tenant_id, servidor_id, contrato_id, funcao, inicio, portaria_id)
SELECT 'e0e0e0e0-0000-0000-0000-000000000001', 'e0e0e0e0-0000-0000-0001-0000000000f6', :c_ev, 'fiscal_tecnico', DATE '2026-09-15', id FROM portaria;
ALTER TABLE designacao ENABLE TRIGGER trg_designacao_dois_lados;
SET ROLE app_rw;
CALL pg_temp.espera_erro_com('quem fechou validar', 'Quem fechou o diário não pode validá-lo', ARRAY[
  format($$CALL pg_temp.etapa(%L, %L, 'validar')$$, :d1, :apontador)]);

SET app.usuario_id = :fiscal;
INSERT INTO rdo_instrucao (rdo_id, texto) VALUES (:d1, 'Informar a frente de cada serviço');
SET app.usuario_id = :preposto;
CALL pg_temp.espera_erro_com('empresa registrar instrução', 'Só fiscal', ARRAY[
  format($$INSERT INTO rdo_instrucao (rdo_id, texto) VALUES (%L, 'x')$$, :d1)]);
CALL pg_temp.espera_erro('aplicação alterar instrução do fiscal', ARRAY[$$UPDATE rdo_instrucao SET texto = 'outro'$$]);

CALL pg_temp.etapa(:d1, :fiscal, 'devolver', 'Faltou a frente de cada serviço');
SELECT pg_temp.confere_texto('diário devolvido', (SELECT status::text FROM rdo WHERE id = :d1), 'devolvido');

\echo
\echo '== Devolvido não volta: a empresa retifica com um registro novo =='
CALL pg_temp.espera_erro_com('reabrir diário devolvido', 'não aceita a ação', ARRAY[
  format($$CALL pg_temp.etapa(%L, %L, 'fechar')$$, :d1, :apontador)]);
CALL pg_temp.espera_erro_com('alterar diário devolvido', 'dia fechado não é sobrescrito', ARRAY[
  format($$UPDATE rdo SET clima_manha = 'nublado' WHERE id = %L$$, :d1)]);
CALL pg_temp.espera_erro_com('retificar apontando para diário de outro dia', 'Só se retifica diário devolvido', ARRAY[
  format($$INSERT INTO rdo (obra_id, contrato_id, data, responsavel, retifica_id) VALUES (%L, %L, '2026-12-02', 'Apontador', %L)$$, :obra, :c_ev, :d1)]);
INSERT INTO rdo (id, obra_id, contrato_id, data, clima_manha, responsavel, retifica_id)
VALUES (:d2, :obra, :c_ev, '2026-12-01', 'bom', 'Apontador', :d1);
INSERT INTO rdo_ocorrencia (rdo_id, tipo, descricao) VALUES (:d2, 'servico_executado', 'Alvenaria do térreo, eixo A, frente Térreo');
CALL pg_temp.espera_erro('retificar duas vezes o mesmo diário', ARRAY[
  format($$INSERT INTO rdo (obra_id, contrato_id, data, responsavel, retifica_id) VALUES (%L, %L, '2026-12-01', 'x', %L)$$, :obra, :c_ev, :d1)]);
CALL pg_temp.espera_erro_com('retificar diário que não foi devolvido', 'Só se retifica diário devolvido', ARRAY[
  format($$INSERT INTO rdo (obra_id, contrato_id, data, responsavel, retifica_id) VALUES (%L, %L, '2026-12-01', 'x', %L)$$, :obra, :c_ev, :d2)]);
CALL pg_temp.etapa(:d2, :apontador, 'fechar');
CALL pg_temp.etapa(:d2, :substituto, 'iniciar_validacao');
CALL pg_temp.etapa(:d2, :substituto, 'validar');
SELECT pg_temp.confere_texto('retificador validado', (SELECT status::text FROM rdo WHERE id = :d2), 'validado');
SELECT pg_temp.confere_texto('o devolvido continua lá, devolvido', (SELECT status::text FROM rdo WHERE id = :d1), 'devolvido');
SELECT pg_temp.confere('o conteúdo do devolvido continua lá', (SELECT count(*) FROM rdo_efetivo WHERE rdo_id = :d1), 2);
CALL pg_temp.espera_erro_com('qualquer ação em diário validado', 'não aceita a ação', ARRAY[
  format($$CALL pg_temp.etapa(%L, %L, 'devolver', 'x')$$, :d2, :fiscal)]);
CALL pg_temp.espera_erro('aplicação reescrever a trilha do diário', ARRAY[$$UPDATE rdo_etapa SET motivo = 'outro'$$]);

SELECT pg_temp.confere_texto('a história do primeiro diário',
  (SELECT string_agg(e.acao || ':' || e.de || '>' || e.para, ' ' ORDER BY e.em, e.id) FROM rdo_etapa e WHERE e.rdo_id = :d1),
  'fechar:rascunho>fechado iniciar_validacao:fechado>em_validacao devolver:em_validacao>devolvido');

RESET ROLE;
