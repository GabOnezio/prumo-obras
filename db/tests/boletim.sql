-- Boletim de Execução, foto de evidência e glosa de evento (migração 0008).
-- Prova as invariantes 1, 2 e 6 de docs/10 §9 e a parte do banco da 12.
-- Roda sobre o seed, como app_rw, no contrato por eventos (045/2026). O seed já traz os
-- boletins nº 1 e nº 2 emitidos: fundações concluídas em 28/10, pilares em 11/12 e
-- alvenaria em 70%.
SET ROLE app_rw;
SET app.tenant_id = 'e0e0e0e0-0000-0000-0000-000000000001';
SET app.usuario = 'teste.boletim';

\set c_ev   '''e0e0e0e0-0000-0000-0000-0000000000c1'''
\set c_bm   '''e0e0e0e0-0000-0000-0000-0000000000c2'''
\set rev_ev '''e0e0e0e0-0000-0000-0000-0000000000d1'''
\set m1 '''e0e0e0e0-0000-0000-0000-0000000000e1'''
\set m2 '''e0e0e0e0-0000-0000-0000-0000000000e2'''
\set m3 '''e0e0e0e0-0000-0000-0000-0000000000e3'''
\set b3 '''e0e0e0e0-0000-0000-000b-000000000003'''
\set b4 '''e0e0e0e0-0000-0000-000b-000000000004'''
\set b5 '''e0e0e0e0-0000-0000-000b-000000000005'''
\set fiscal        '''e0e0e0e0-0000-0000-0001-000000000001'''
\set substituto    '''e0e0e0e0-0000-0000-0001-000000000002'''
\set gestor        '''e0e0e0e0-0000-0000-0001-000000000003'''
\set preposto      '''e0e0e0e0-0000-0000-0001-000000000005'''
\set apontador     '''e0e0e0e0-0000-0000-0001-000000000006'''
\set preposto_beta '''e0e0e0e0-0000-0000-0001-000000000007'''
\set orcamentista  '''e0e0e0e0-0000-0000-0001-000000000008'''

CREATE FUNCTION pg_temp.evento(p_agrupador int) RETURNS uuid LANGUAGE sql AS $$
  SELECT e.id FROM evento e JOIN agrupador_evento a ON a.id = e.agrupador_id
   WHERE e.revisao_id = 'e0e0e0e0-0000-0000-0000-0000000000d1' AND a.numero = p_agrupador
$$;
CREATE PROCEDURE pg_temp.etapa(p_medicao uuid, p_quem uuid, p_acao acao_medicao, p_motivo text DEFAULT NULL) LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('app.usuario_id', p_quem::text, false);
  INSERT INTO medicao_etapa (medicao_id, acao, motivo) VALUES (p_medicao, p_acao, p_motivo);
END $$;
CREATE FUNCTION pg_temp.linhas(p_medicao uuid) RETURNS numeric LANGUAGE sql AS $$
  SELECT coalesce(sum(valor), 0) FROM medicao_item WHERE medicao_id = p_medicao
$$;
CREATE FUNCTION pg_temp.marcado(p_medicao uuid, p_agrupador int) RETURNS uuid LANGUAGE sql AS $$
  SELECT id FROM medicao_evento WHERE medicao_id = p_medicao AND evento_id = pg_temp.evento(p_agrupador)
$$;
-- O que o último boletim emitido diz de um evento.
CREATE FUNCTION pg_temp.situacao(p_agrupador int) RETURNS text LANGUAGE sql AS $$
  SELECT s.situacao || ' (boletim ' || s.boletim_numero || ')' FROM fn_situacao_do_evento(pg_temp.evento(p_agrupador)) s
$$;

\echo
\echo '== Seed: o que os boletins emitidos dizem de cada evento =='
SELECT pg_temp.confere_texto('fundações', pg_temp.situacao(1), 'concluido (boletim 2)');
SELECT pg_temp.confere_texto('pilares', pg_temp.situacao(2), 'concluido (boletim 2)');
SELECT pg_temp.confere_texto('alvenaria', pg_temp.situacao(3), 'em_andamento (boletim 2)');
SELECT pg_temp.confere_texto('cobertura', pg_temp.situacao(4), 'nao_iniciado (boletim 2)');

\echo
\echo '== Invariante 1: evento sem boletim que o marque concluído não é aprovado =='
-- Medição nº 1, de 01 a 15/12: a empresa declara pilares, alvenaria e cobertura.
INSERT INTO medicao (id, contrato_id, numero, revisao_id, periodo_inicio, periodo_fim)
VALUES (:m1, :c_ev, 1, :rev_ev, '2026-12-01', '2026-12-15');
INSERT INTO medicao_evento (medicao_id, evento_id) VALUES
  (:m1, pg_temp.evento(2)), (:m1, pg_temp.evento(3)), (:m1, pg_temp.evento(4));
CALL pg_temp.etapa(:m1, :preposto, 'enviar');
-- 26.014,74 + 16.641,60 + 38.920,00
SELECT pg_temp.confere('valor declarado no envio', (SELECT valor_bruto FROM medicao WHERE id = :m1), 81576.34);
CALL pg_temp.etapa(:m1, :fiscal, 'iniciar_analise');
CALL pg_temp.espera_erro_com('aprovar com a alvenaria em 70% no boletim', 'O evento "Alvenaria × Térreo" não tem Boletim de Execução', ARRAY[
  format($$CALL pg_temp.etapa(%L, %L, 'aprovar_fiscal')$$, :m1, :fiscal)]);

\echo
\echo '== Glosa do evento inteiro: do fiscal, na análise, com motivo =='
SET app.usuario_id = :preposto;
CALL pg_temp.espera_erro_com('empresa glosar ou aceitar evento', 'Só fiscal', ARRAY[
  format($$INSERT INTO medicao_evento_analise (medicao_evento_id, decisao) VALUES (pg_temp.marcado(%L, 2), 'aceito')$$, :m1)]);
SET app.usuario_id = :gestor;
CALL pg_temp.espera_erro_com('gestor do contrato glosar evento', 'Só fiscal', ARRAY[
  format($$INSERT INTO medicao_evento_analise (medicao_evento_id, decisao, motivo) VALUES (pg_temp.marcado(%L, 3), 'glosado', 'x')$$, :m1)]);
SET app.usuario_id = :fiscal;
CALL pg_temp.espera_erro('glosar sem motivo', ARRAY[
  format($$INSERT INTO medicao_evento_analise (medicao_evento_id, decisao) VALUES (pg_temp.marcado(%L, 3), 'glosado')$$, :m1)]);
INSERT INTO medicao_evento_analise (medicao_evento_id, decisao, motivo)
VALUES (pg_temp.marcado(:m1, 3), 'glosado', 'Alvenaria em 70% no Boletim de Execução nº 2');
-- a glosa tira o evento inteiro das linhas de serviço: sobram pilares e cobertura
SELECT pg_temp.confere('linhas depois de glosar a alvenaria', pg_temp.linhas(:m1), 64934.74);
CALL pg_temp.espera_erro_com('aprovar com a cobertura não iniciada no boletim', 'O evento "Cobertura × Térreo" não tem Boletim de Execução', ARRAY[
  format($$CALL pg_temp.etapa(%L, %L, 'aprovar_fiscal')$$, :m1, :fiscal)]);
SET app.usuario_id = :fiscal;
INSERT INTO medicao_evento_analise (medicao_evento_id, decisao, motivo)
VALUES (pg_temp.marcado(:m1, 4), 'glosado', 'Cobertura não iniciada');
SELECT pg_temp.confere('linhas depois de glosar a cobertura', pg_temp.linhas(:m1), 26014.74);
CALL pg_temp.espera_erro_com('alterar a análise já registrada', 'não se altera', ARRAY[
  format($$UPDATE medicao_evento_analise SET decisao = 'aceito' WHERE medicao_evento_id = pg_temp.marcado(%L, 3)$$, :m1)]);
CALL pg_temp.espera_erro('duas análises do mesmo evento', ARRAY[
  format($$INSERT INTO medicao_evento_analise (medicao_evento_id, decisao, motivo) VALUES (pg_temp.marcado(%L, 3), 'glosado', 'de novo')$$, :m1)]);
-- desfazer a glosa devolve o evento às linhas, e a aprovação volta a ser barrada
DELETE FROM medicao_evento_analise WHERE medicao_evento_id = pg_temp.marcado(:m1, 3);
SELECT pg_temp.confere('linhas depois de desfazer a glosa da alvenaria', pg_temp.linhas(:m1), 42656.34);
CALL pg_temp.espera_erro_com('aprovar depois de desfazer a glosa', 'O evento "Alvenaria × Térreo"', ARRAY[
  format($$CALL pg_temp.etapa(%L, %L, 'aprovar_fiscal')$$, :m1, :fiscal)]);
SET app.usuario_id = :fiscal;
INSERT INTO medicao_evento_analise (medicao_evento_id, decisao, motivo)
VALUES (pg_temp.marcado(:m1, 3), 'glosado', 'Alvenaria em 70% no Boletim de Execução nº 2');
INSERT INTO medicao_evento_analise (medicao_evento_id, decisao) VALUES (pg_temp.marcado(:m1, 2), 'aceito');
CALL pg_temp.espera_erro_com('empresa alterar linha de serviço durante a análise', 'itens não podem ser alterados', ARRAY[
  format($$UPDATE medicao_item SET memoria_calculo = 'x' WHERE medicao_id = %L$$, :m1)]);

CALL pg_temp.etapa(:m1, :fiscal, 'aprovar_fiscal');
SELECT pg_temp.confere('aprovado: só os pilares', (SELECT valor_bruto FROM medicao WHERE id = :m1), 26014.74);
-- 16.641,60 + 38.920,00
SELECT pg_temp.confere('glosado: alvenaria e cobertura', (SELECT valor_glosado FROM medicao WHERE id = :m1), 55561.60);
SELECT pg_temp.confere('medido e aprovado na situação do contrato',
  (SELECT medido_aprovado FROM vw_contrato_situacao WHERE contrato_id = :c_ev), 26014.74);
SET app.usuario_id = :fiscal;
CALL pg_temp.espera_erro_com('desfazer glosa de medição aprovada', 'com a medição em análise', ARRAY[
  format($$DELETE FROM medicao_evento_analise WHERE medicao_evento_id = pg_temp.marcado(%L, 3)$$, :m1)]);

\echo
\echo '== Boletim de Execução: do fiscal designado, em rascunho, com número seguinte =='
SET app.usuario_id = :preposto;
CALL pg_temp.espera_erro_com('empresa criar Boletim de Execução', 'é do fiscal com designação vigente', ARRAY[
  format($$INSERT INTO boletim_execucao (contrato_id, numero, periodo_inicio, periodo_fim) VALUES (%L, 3, '2026-12-16', '2026-12-31')$$, :c_ev)]);
SET app.usuario_id = :gestor;
CALL pg_temp.espera_erro_com('gestor do contrato criar Boletim de Execução', 'é do fiscal com designação vigente', ARRAY[
  format($$INSERT INTO boletim_execucao (contrato_id, numero, periodo_inicio, periodo_fim) VALUES (%L, 3, '2026-12-16', '2026-12-31')$$, :c_ev)]);
SET app.usuario_id = :fiscal;
CALL pg_temp.espera_erro_com('boletim que já nasce emitido', 'nasce em rascunho', ARRAY[
  format($$INSERT INTO boletim_execucao (contrato_id, numero, periodo_inicio, periodo_fim, status, emitido_por, emitido_em)
           VALUES (%L, 3, '2026-12-16', '2026-12-31', 'emitido', %L, now())$$, :c_ev, :fiscal)]);
CALL pg_temp.espera_erro_com('pular o número do boletim', 'tem que ser o seguinte', ARRAY[
  format($$INSERT INTO boletim_execucao (contrato_id, numero, periodo_inicio, periodo_fim) VALUES (%L, 9, '2026-12-16', '2026-12-31')$$, :c_ev)]);
CALL pg_temp.espera_erro('período com fim antes do início', ARRAY[
  format($$INSERT INTO boletim_execucao (contrato_id, numero, periodo_inicio, periodo_fim) VALUES (%L, 3, '2026-12-31', '2026-12-16')$$, :c_ev)]);
INSERT INTO boletim_execucao (id, contrato_id, numero, periodo_inicio, periodo_fim) VALUES (:b3, :c_ev, 3, '2026-12-16', '2026-12-31');

CALL pg_temp.espera_erro_com('linha de serviço em boletim de contrato por eventos', 'tem que ser de evento', ARRAY[
  format($$INSERT INTO boletim_execucao_linha (boletim_id, item_contratual_id, situacao)
           SELECT %L, item_contratual_id, 'nao_iniciado' FROM item_revisao WHERE revisao_id = %L AND codigo_eap = '3.1'$$, :b3, :rev_ev)]);
CALL pg_temp.espera_erro('em andamento sem o percentual', ARRAY[
  format($$INSERT INTO boletim_execucao_linha (boletim_id, evento_id, situacao) VALUES (%L, pg_temp.evento(4), 'em_andamento')$$, :b3)]);
CALL pg_temp.espera_erro('em andamento com 100%', ARRAY[
  format($$INSERT INTO boletim_execucao_linha (boletim_id, evento_id, situacao, avanco_percentual) VALUES (%L, pg_temp.evento(4), 'em_andamento', 100)$$, :b3)]);
CALL pg_temp.espera_erro('concluído sem a data da verificação', ARRAY[
  format($$INSERT INTO boletim_execucao_linha (boletim_id, evento_id, situacao) VALUES (%L, pg_temp.evento(3), 'concluido')$$, :b3)]);
CALL pg_temp.espera_erro('concluído com pendência sem dizer qual', ARRAY[
  format($$INSERT INTO boletim_execucao_linha (boletim_id, evento_id, situacao, verificado_em)
           VALUES (%L, pg_temp.evento(3), 'concluido_com_pendencia', '2026-12-22')$$, :b3)]);
INSERT INTO boletim_execucao_linha (id, boletim_id, evento_id, situacao, avanco_percentual, verificado_em) VALUES
  ('e0e0e0e0-0000-0000-000c-000000000033', :b3, pg_temp.evento(3), 'concluido', NULL, '2026-12-22'),
  ('e0e0e0e0-0000-0000-000c-000000000034', :b3, pg_temp.evento(4), 'em_andamento', 10, NULL);
CALL pg_temp.espera_erro('o mesmo evento duas vezes no boletim', ARRAY[
  format($$INSERT INTO boletim_execucao_linha (boletim_id, evento_id, situacao) VALUES (%L, pg_temp.evento(4), 'paralisado')$$, :b3)]);
SET app.usuario_id = :preposto;
CALL pg_temp.espera_erro_com('empresa alterar linha do boletim em rascunho', 'é do fiscal com designação vigente', ARRAY[
  $$UPDATE boletim_execucao_linha SET situacao = 'concluido', avanco_percentual = NULL, verificado_em = '2026-12-22'
     WHERE id = 'e0e0e0e0-0000-0000-000c-000000000034'$$]);

\echo
\echo '== Emitir exige evidência; a evidência mínima vem da configuração do município =='
SET app.usuario_id = :fiscal;
CALL pg_temp.espera_erro_com('emitir com linha concluída sem evidência', 'menos evidências que o mínimo', ARRAY[
  format($$UPDATE boletim_execucao SET status = 'emitido' WHERE id = %L$$, :b3)]);
-- evidências que não servem: vistoria aberta, diário não validado, foto de outro contrato
INSERT INTO vistoria (id, contrato_id, data, observacao) VALUES
  ('e0e0e0e0-0000-0000-0004-000000000003', :c_ev, '2026-12-22', 'Alvenaria do térreo concluída');
CALL pg_temp.espera_erro_com('vistoria ainda aberta como evidência', 'Evidência tem que ser', ARRAY[
  $$INSERT INTO boletim_execucao_evidencia (linha_id, tipo, ref_id)
    VALUES ('e0e0e0e0-0000-0000-000c-000000000033', 'vistoria', 'e0e0e0e0-0000-0000-0004-000000000003')$$]);
INSERT INTO rdo (id, obra_id, contrato_id, data, responsavel)
VALUES ('e0e0e0e0-0000-0000-0006-000000000009', 'e0e0e0e0-0000-0000-0000-0000000000b1', :c_ev, '2026-12-22', 'Apontador');
CALL pg_temp.espera_erro_com('diário não validado como evidência', 'Evidência tem que ser', ARRAY[
  $$INSERT INTO boletim_execucao_evidencia (linha_id, tipo, ref_id)
    VALUES ('e0e0e0e0-0000-0000-000c-000000000033', 'rdo', 'e0e0e0e0-0000-0000-0006-000000000009')$$]);
SET app.usuario_id = :preposto_beta;
INSERT INTO foto (id, contrato_id, origem, sha256, chave_arquivo, tirada_em)
VALUES ('e0e0e0e0-0000-0000-000f-0000000000b1', :c_bm, 'camera_app', repeat('b', 64), 'ficticio/beta.jpg', '2026-12-22 10:00-03');
SET app.usuario_id = :fiscal;
CALL pg_temp.espera_erro_com('foto de outro contrato como evidência', 'Evidência tem que ser', ARRAY[
  $$INSERT INTO boletim_execucao_evidencia (linha_id, tipo, ref_id)
    VALUES ('e0e0e0e0-0000-0000-000c-000000000033', 'foto', 'e0e0e0e0-0000-0000-000f-0000000000b1')$$]);
CALL pg_temp.espera_erro('tipo de evidência fora da lista', ARRAY[
  $$INSERT INTO boletim_execucao_evidencia (linha_id, tipo, ref_id)
    VALUES ('e0e0e0e0-0000-0000-000c-000000000033', 'depoimento', gen_random_uuid())$$]);
-- evidência que serve: foto do fiscal tirada na vistoria, ligada ao evento
INSERT INTO foto (id, contrato_id, origem, sha256, chave_arquivo, tirada_em, latitude, longitude, precisao_m, vistoria_id,
                  evento_id, frente_id, vinculo_origem)
VALUES ('e0e0e0e0-0000-0000-000f-0000000000a1', :c_ev, 'camera_app', repeat('1', 64), 'ficticio/alvenaria.jpg',
        '2026-12-22 15:10-03', -25.000000, -49.000000, 4.50, 'e0e0e0e0-0000-0000-0004-000000000003',
        pg_temp.evento(3), 'e0e0e0e0-0000-0000-0000-0000000000f1', 'captura');
INSERT INTO boletim_execucao_evidencia (linha_id, tipo, ref_id)
VALUES ('e0e0e0e0-0000-0000-000c-000000000033', 'foto', 'e0e0e0e0-0000-0000-000f-0000000000a1');

-- a exigência é a do município: sem configuração, erro; com duas exigidas, uma não basta
UPDATE config_municipio SET boletim_evidencias_para_concluido = NULL;
CALL pg_temp.espera_erro_com('emitir sem a evidência mínima configurada', 'Configuração do município ausente', ARRAY[
  format($$UPDATE boletim_execucao SET status = 'emitido' WHERE id = %L$$, :b3)]);
UPDATE config_municipio SET boletim_evidencias_para_concluido = 2;
CALL pg_temp.espera_erro_com('emitir com uma evidência onde o município exige duas', 'menos evidências que o mínimo do município (2)', ARRAY[
  format($$UPDATE boletim_execucao SET status = 'emitido' WHERE id = %L$$, :b3)]);
UPDATE config_municipio SET boletim_evidencias_para_concluido = 1;

UPDATE boletim_execucao_linha SET verificado_em = '2027-01-05' WHERE id = 'e0e0e0e0-0000-0000-000c-000000000033';
CALL pg_temp.espera_erro_com('emitir com conclusão verificada depois do período', 'depois do fim do período do boletim', ARRAY[
  format($$UPDATE boletim_execucao SET status = 'emitido' WHERE id = %L$$, :b3)]);
UPDATE boletim_execucao_linha SET verificado_em = '2026-12-22' WHERE id = 'e0e0e0e0-0000-0000-000c-000000000033';
SET app.usuario_id = :preposto;
CALL pg_temp.espera_erro_com('empresa emitir o boletim do fiscal', 'é do fiscal com designação vigente', ARRAY[
  format($$UPDATE boletim_execucao SET status = 'emitido' WHERE id = %L$$, :b3)]);
SET app.usuario_id = :fiscal;
-- o rascunho ainda não vale: a alvenaria continua em 70% para a medição
SELECT pg_temp.confere_texto('boletim em rascunho não conta', pg_temp.situacao(3), 'em_andamento (boletim 2)');
UPDATE boletim_execucao SET status = 'emitido' WHERE id = :b3;
SELECT pg_temp.confere_texto('emitido em nome do fiscal da sessão',
  (SELECT u.nome FROM boletim_execucao b JOIN usuario u ON u.id = b.emitido_por WHERE b.id = :b3), 'Fiscal técnico (fictício)');
SELECT pg_temp.confere_texto('guarda a versão do cronograma vigente na emissão',
  (SELECT v.tipo FROM boletim_execucao b JOIN cronograma_versao v ON v.id = b.cronograma_versao_id WHERE b.id = :b3), 'linha_de_base');
SELECT pg_temp.confere_texto('alvenaria depois do boletim nº 3', pg_temp.situacao(3), 'concluido (boletim 3)');

\echo
\echo '== Invariante 2: boletim emitido é imutável =='
CALL pg_temp.espera_erro_com('alterar o período do boletim emitido', 'foi emitido e é imutável', ARRAY[
  format($$UPDATE boletim_execucao SET periodo_fim = '2027-01-31' WHERE id = %L$$, :b3)]);
CALL pg_temp.espera_erro_com('voltar o boletim emitido para rascunho', 'foi emitido e é imutável', ARRAY[
  format($$UPDATE boletim_execucao SET status = 'rascunho', emitido_por = NULL, emitido_em = NULL WHERE id = %L$$, :b3)]);
CALL pg_temp.espera_erro_com('apagar boletim emitido', 'foi emitido e é imutável', ARRAY[
  format($$DELETE FROM boletim_execucao WHERE id = %L$$, :b3)]);
CALL pg_temp.espera_erro_com('mudar a situação de uma linha emitida', 'foi emitido e é imutável', ARRAY[
  $$UPDATE boletim_execucao_linha SET situacao = 'paralisado', verificado_em = NULL WHERE id = 'e0e0e0e0-0000-0000-000c-000000000033'$$]);
CALL pg_temp.espera_erro_com('apagar linha emitida', 'foi emitido e é imutável', ARRAY[
  $$DELETE FROM boletim_execucao_linha WHERE id = 'e0e0e0e0-0000-0000-000c-000000000034'$$]);
CALL pg_temp.espera_erro_com('acrescentar linha a boletim emitido', 'foi emitido e é imutável', ARRAY[
  format($$INSERT INTO boletim_execucao_linha (boletim_id, evento_id, situacao) VALUES (%L, pg_temp.evento(5), 'nao_iniciado')$$, :b3)]);
CALL pg_temp.espera_erro_com('tirar evidência de boletim emitido', 'foi emitido e é imutável', ARRAY[
  $$DELETE FROM boletim_execucao_evidencia WHERE linha_id = 'e0e0e0e0-0000-0000-000c-000000000033'$$]);
CALL pg_temp.espera_erro_com('alterar boletim emitido do seed', 'foi emitido e é imutável', ARRAY[
  $$UPDATE boletim_execucao SET periodo_inicio = '2026-09-01' WHERE numero = 1$$]);
RESET ROLE;
CALL pg_temp.espera_erro_com('nem o dono das tabelas altera boletim emitido', 'foi emitido e é imutável', ARRAY[
  format($$UPDATE boletim_execucao SET periodo_fim = '2027-01-31' WHERE id = %L$$, :b3)]);
CALL pg_temp.espera_erro_com('nem o dono altera linha de boletim emitido', 'foi emitido e é imutável', ARRAY[
  $$UPDATE boletim_execucao_linha SET observacao = 'x' WHERE id = 'e0e0e0e0-0000-0000-000c-000000000033'$$]);
SET ROLE app_rw;

\echo
\echo '== Invariante 6: evento glosado volta em medição seguinte; a data da verificação conta =='
-- Medição nº 2, de 16 a 20/12: a alvenaria, glosada na nº 1, é declarada de novo.
INSERT INTO medicao (id, contrato_id, numero, revisao_id, periodo_inicio, periodo_fim)
VALUES (:m2, :c_ev, 2, :rev_ev, '2026-12-16', '2026-12-20');
CALL pg_temp.espera_erro_com('pilares, já medidos e aprovados, de novo', 'Evento já medido anteriormente', ARRAY[
  format($$INSERT INTO medicao_evento (medicao_id, evento_id) VALUES (%L, pg_temp.evento(2))$$, :m2)]);
INSERT INTO medicao_evento (medicao_id, evento_id) VALUES (:m2, pg_temp.evento(3));
SELECT pg_temp.confere('alvenaria glosada antes entra na medição seguinte', pg_temp.linhas(:m2), 16641.60);
CALL pg_temp.etapa(:m2, :preposto, 'enviar');
CALL pg_temp.etapa(:m2, :fiscal, 'iniciar_analise');
-- o boletim marca concluído em 22/12, e o período desta medição termina em 20/12
CALL pg_temp.espera_erro_com('aprovar evento concluído depois do fim do período da medição', 'até o fim do período', ARRAY[
  format($$CALL pg_temp.etapa(%L, %L, 'aprovar_fiscal')$$, :m2, :fiscal)]);
CALL pg_temp.etapa(:m2, :fiscal, 'devolver', 'A alvenaria foi verificada em 22/12: o período tem que ir até lá');
UPDATE medicao SET periodo_fim = '2026-12-31' WHERE id = :m2;
CALL pg_temp.etapa(:m2, :preposto, 'enviar');
CALL pg_temp.etapa(:m2, :fiscal, 'iniciar_analise');
CALL pg_temp.etapa(:m2, :fiscal, 'aprovar_fiscal');
SELECT pg_temp.confere('medição 2 aprovada: a alvenaria', (SELECT valor_bruto FROM medicao WHERE id = :m2), 16641.60);
SELECT pg_temp.confere('medição 2: nada glosado', (SELECT valor_glosado FROM medicao WHERE id = :m2), 0);

\echo
\echo '== Concluído com pendência não libera; o boletim retificador substitui o retificado =='
SET app.usuario_id = :fiscal;
INSERT INTO vistoria (id, contrato_id, data, observacao) VALUES
  ('e0e0e0e0-0000-0000-0004-000000000004', :c_ev, '2027-01-29', 'Cobertura concluída; falta um trecho de calha');
UPDATE vistoria SET concluida_em = now() WHERE id = 'e0e0e0e0-0000-0000-0004-000000000004';
INSERT INTO boletim_execucao (id, contrato_id, numero, periodo_inicio, periodo_fim) VALUES (:b4, :c_ev, 4, '2027-01-01', '2027-01-31');
INSERT INTO boletim_execucao_linha (id, boletim_id, evento_id, situacao, verificado_em, observacao) VALUES
  ('e0e0e0e0-0000-0000-000c-000000000044', :b4, pg_temp.evento(4), 'concluido_com_pendencia', '2027-01-29', 'Falta um trecho de calha');
INSERT INTO boletim_execucao_evidencia (linha_id, tipo, ref_id) VALUES
  ('e0e0e0e0-0000-0000-000c-000000000044', 'vistoria', 'e0e0e0e0-0000-0000-0004-000000000004');
UPDATE boletim_execucao SET status = 'emitido' WHERE id = :b4;
SELECT pg_temp.confere_texto('cobertura depois do boletim nº 4', pg_temp.situacao(4), 'concluido_com_pendencia (boletim 4)');

INSERT INTO medicao (id, contrato_id, numero, revisao_id, periodo_inicio, periodo_fim)
VALUES (:m3, :c_ev, 3, :rev_ev, '2027-01-01', '2027-01-31');
INSERT INTO medicao_evento (medicao_id, evento_id) VALUES (:m3, pg_temp.evento(4));
CALL pg_temp.etapa(:m3, :preposto, 'enviar');
CALL pg_temp.etapa(:m3, :fiscal, 'iniciar_analise');
CALL pg_temp.espera_erro_com('aprovar evento concluído com pendência', 'O evento "Cobertura × Térreo" não tem Boletim de Execução', ARRAY[
  format($$CALL pg_temp.etapa(%L, %L, 'aprovar_fiscal')$$, :m3, :fiscal)]);

-- A calha foi feita no dia 30. O boletim nº 4 não muda: sai um retificador.
SET app.usuario_id = :fiscal;
CALL pg_temp.espera_erro_com('retificar boletim de outro contrato', 'Só se retifica boletim emitido, do mesmo contrato', ARRAY[
  format($$INSERT INTO boletim_execucao (contrato_id, numero, periodo_inicio, periodo_fim, retifica_id)
           SELECT %L, 1, '2027-01-01', '2027-01-31', %L$$, :c_bm, :b4)]);
INSERT INTO boletim_execucao (id, contrato_id, numero, periodo_inicio, periodo_fim, retifica_id)
VALUES (:b5, :c_ev, 5, '2027-01-01', '2027-01-31', :b4);
CALL pg_temp.espera_erro_com('retificar boletim que ainda é rascunho', 'Só se retifica boletim emitido', ARRAY[
  format($$INSERT INTO boletim_execucao (contrato_id, numero, periodo_inicio, periodo_fim, retifica_id)
           VALUES (%L, 6, '2027-01-01', '2027-01-31', %L)$$, :c_ev, :b5)]);
CALL pg_temp.espera_erro('dois retificadores do mesmo boletim', ARRAY[
  format($$INSERT INTO boletim_execucao (contrato_id, numero, periodo_inicio, periodo_fim, retifica_id)
           VALUES (%L, 6, '2027-01-01', '2027-01-31', %L)$$, :c_ev, :b4)]);
INSERT INTO boletim_execucao_linha (id, boletim_id, evento_id, situacao, verificado_em) VALUES
  ('e0e0e0e0-0000-0000-000c-000000000054', :b5, pg_temp.evento(4), 'concluido', '2027-01-30');
INSERT INTO boletim_execucao_evidencia (linha_id, tipo, ref_id) VALUES
  ('e0e0e0e0-0000-0000-000c-000000000054', 'vistoria', 'e0e0e0e0-0000-0000-0004-000000000004');
-- enquanto o retificador é rascunho, vale o nº 4
SELECT pg_temp.confere_texto('retificador em rascunho ainda não vale', pg_temp.situacao(4), 'concluido_com_pendencia (boletim 4)');
UPDATE boletim_execucao SET status = 'emitido' WHERE id = :b5;
SELECT pg_temp.confere_texto('cobertura depois do retificador', pg_temp.situacao(4), 'concluido (boletim 5)');
SELECT pg_temp.confere_texto('o boletim retificado continua emitido e intacto',
  (SELECT b.status || ': ' || l.situacao FROM boletim_execucao b JOIN boletim_execucao_linha l ON l.boletim_id = b.id WHERE b.id = :b4),
  'emitido: concluido_com_pendencia');
CALL pg_temp.etapa(:m3, :fiscal, 'aprovar_fiscal');
SELECT pg_temp.confere('medição 3 aprovada: a cobertura', (SELECT valor_bruto FROM medicao WHERE id = :m3), 38920.00);
-- 26.014,74 + 16.641,60 + 38.920,00
SELECT pg_temp.confere('medido e aprovado nas três medições',
  (SELECT medido_aprovado FROM vw_contrato_situacao WHERE contrato_id = :c_ev), 81576.34);

\echo
\echo '== Foto de evidência: só da câmera do app, com hash, e vínculo confirmado por pessoa =='
SET app.usuario_id = :apontador;
CALL pg_temp.espera_erro_com('foto que não veio da câmera do app', 'foto_origem_check', ARRAY[
  format($$INSERT INTO foto (contrato_id, origem, sha256, chave_arquivo, tirada_em)
           VALUES (%L, 'galeria', repeat('2', 64), 'x', now())$$, :c_ev)]);
CALL pg_temp.espera_erro('foto sem hash', ARRAY[
  format($$INSERT INTO foto (contrato_id, origem, chave_arquivo, tirada_em) VALUES (%L, 'camera_app', 'x', now())$$, :c_ev)]);
CALL pg_temp.espera_erro_com('hash que não é SHA-256', 'foto_sha256_check', ARRAY[
  format($$INSERT INTO foto (contrato_id, origem, sha256, chave_arquivo, tirada_em) VALUES (%L, 'camera_app', 'abc', 'x', now())$$, :c_ev)]);
CALL pg_temp.espera_erro('latitude sem longitude', ARRAY[
  format($$INSERT INTO foto (contrato_id, origem, sha256, chave_arquivo, tirada_em, latitude)
           VALUES (%L, 'camera_app', repeat('2', 64), 'x', now(), -25)$$, :c_ev)]);
CALL pg_temp.espera_erro('foto ligada a evento sem confirmação de pessoa', ARRAY[
  format($$INSERT INTO foto (contrato_id, origem, sha256, chave_arquivo, tirada_em, evento_id)
           VALUES (%L, 'camera_app', repeat('2', 64), 'x', now(), pg_temp.evento(5))$$, :c_ev)]);
CALL pg_temp.espera_erro_com('foto ligada a serviço de outro contrato', 'do próprio contrato', ARRAY[
  format($$INSERT INTO foto (contrato_id, origem, sha256, chave_arquivo, tirada_em, item_contratual_id, vinculo_origem)
           SELECT %L, 'camera_app', repeat('2', 64), 'x', now(), ir.item_contratual_id, 'manual'
             FROM item_revisao ir WHERE ir.revisao_id = 'e0e0e0e0-0000-0000-0000-0000000000d2' AND ir.codigo_eap = '3.1'$$, :c_ev)]);
SET app.usuario_id = :orcamentista;
CALL pg_temp.espera_erro_com('quem não é da empresa nem da fiscalização registrar foto', 'Só a empresa contratada e a fiscalização', ARRAY[
  format($$INSERT INTO foto (contrato_id, origem, sha256, chave_arquivo, tirada_em) VALUES (%L, 'camera_app', repeat('2', 64), 'x', now())$$, :c_ev)]);
CALL pg_temp.espera_erro_com('foto sem usuário na sessão', 'foto tem autor', ARRAY[
  $$SELECT set_config('app.usuario_id', '', false)$$,
  format($$INSERT INTO foto (contrato_id, origem, sha256, chave_arquivo, tirada_em) VALUES (%L, 'camera_app', repeat('2', 64), 'x', now())$$, :c_ev)]);

SET app.usuario_id = :apontador;
INSERT INTO foto (id, contrato_id, origem, sha256, chave_arquivo, tirada_em)
VALUES ('e0e0e0e0-0000-0000-000f-0000000000a2', :c_ev, 'camera_app', repeat('2', 64), 'ficticio/instalacoes.jpg', '2027-02-10 09:00-03');
CALL pg_temp.espera_erro('a mesma foto duas vezes no contrato', ARRAY[
  format($$INSERT INTO foto (contrato_id, origem, sha256, chave_arquivo, tirada_em) VALUES (%L, 'camera_app', repeat('2', 64), 'y', now())$$, :c_ev)]);
CALL pg_temp.espera_erro_com('trocar o arquivo de uma foto registrada', 'não se altera', ARRAY[
  $$UPDATE foto SET sha256 = repeat('3', 64) WHERE id = 'e0e0e0e0-0000-0000-000f-0000000000a2'$$]);
CALL pg_temp.espera_erro_com('trocar a hora de uma foto registrada', 'não se altera', ARRAY[
  $$UPDATE foto SET tirada_em = now() WHERE id = 'e0e0e0e0-0000-0000-000f-0000000000a2'$$]);
CALL pg_temp.espera_erro_com('aplicação apagar foto', 'permission denied', ARRAY[$$DELETE FROM foto$$]);
RESET ROLE;
CALL pg_temp.espera_erro_com('nem o dono apaga foto de evidência', 'não se apaga', ARRAY[$$DELETE FROM foto$$]);
SET ROLE app_rw;
-- legenda e vínculo podem vir depois; o vínculo sugerido fica em nome de quem aceitou
SET app.usuario_id = :fiscal;
UPDATE foto SET legenda = 'Ponto de instalação elétrica, sala 2', evento_id = pg_temp.evento(5), vinculo_origem = 'sugestao_aceita'
 WHERE id = 'e0e0e0e0-0000-0000-000f-0000000000a2';
SELECT pg_temp.confere_texto('autor da foto continua sendo quem tirou',
  (SELECT u.nome FROM foto f JOIN usuario u ON u.id = f.autor WHERE f.id = 'e0e0e0e0-0000-0000-000f-0000000000a2'), 'Apontador da Alfa (fictício)');
SELECT pg_temp.confere_texto('vínculo sugerido em nome de quem aceitou',
  (SELECT u.nome FROM foto f JOIN usuario u ON u.id = f.vinculo_confirmado_por WHERE f.id = 'e0e0e0e0-0000-0000-000f-0000000000a2'), 'Fiscal técnico (fictício)');
SELECT pg_temp.confere_texto('foto tirada com vínculo fica confirmada por quem tirou',
  (SELECT u.nome FROM foto f JOIN usuario u ON u.id = f.vinculo_confirmado_por WHERE f.id = 'e0e0e0e0-0000-0000-000f-0000000000a1'), 'Fiscal técnico (fictício)');
SELECT pg_temp.confere_vazio('foto ligada à planilha sem confirmação de pessoa', $$
  SELECT id FROM foto WHERE num_nonnulls(item_contratual_id, frente_id, evento_id) > 0 AND vinculo_confirmado_por IS NULL$$);

RESET ROLE;
