-- Documentos do órgão e cronograma com versões (migração 0007; invariantes 8 e 9 de docs/10 §9).
-- Roda sobre o seed, como app_rw, no município de Exemplo. Quem age é o orçamentista.
SET ROLE app_rw;
SET app.tenant_id = 'e0e0e0e0-0000-0000-0000-000000000001';
SET app.usuario = 'teste.cronograma';
SET app.usuario_id = 'e0e0e0e0-0000-0000-0001-000000000008';

\set c_ev   '''e0e0e0e0-0000-0000-0000-0000000000c1'''
\set c_bm   '''e0e0e0e0-0000-0000-0000-0000000000c2'''
\set rev_ev '''e0e0e0e0-0000-0000-0000-0000000000d1'''
\set rev_bm '''e0e0e0e0-0000-0000-0000-0000000000d2'''
\set base_ev '''e0e0e0e0-0000-0000-0000-0000000000a1'''
\set base_bm '''e0e0e0e0-0000-0000-0000-0000000000a2'''
\set v1_ev  '''e0e0e0e0-0000-0000-0009-0000000000a1'''
\set v1_bm  '''e0e0e0e0-0000-0000-0009-0000000000a2'''
\set hash   '''bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'''

CREATE FUNCTION pg_temp.evento(p_agrupador int) RETURNS uuid LANGUAGE sql AS $$
  SELECT e.id FROM evento e JOIN agrupador_evento a ON a.id = e.agrupador_id
   WHERE e.revisao_id = 'e0e0e0e0-0000-0000-0000-0000000000d1' AND a.numero = p_agrupador
$$;
CREATE FUNCTION pg_temp.grupo(p_codigo text) RETURNS uuid LANGUAGE sql AS $$
  SELECT item_contratual_id FROM item_revisao WHERE revisao_id = 'e0e0e0e0-0000-0000-0000-0000000000d2' AND codigo_eap = p_codigo
$$;

\echo
\echo '== Seed: a linha de base dos dois contratos está vigente =='
SELECT pg_temp.confere('eventos com datas na linha de base', (SELECT count(*) FROM cronograma_evento WHERE cronograma_versao_id = :base_ev), 6);
SELECT pg_temp.confere('dependências entre eventos', (SELECT count(*) FROM cronograma_predecessora WHERE cronograma_versao_id = :base_ev), 5);
SELECT pg_temp.confere('parcelas do contrato por quantidade somam 100% por grupo',
  (SELECT count(*) FROM (SELECT item_contratual_id FROM cronograma_parcela WHERE cronograma_versao_id = :base_bm
                          GROUP BY 1 HAVING sum(percentual) = 100) g), 4);
SELECT pg_temp.confere_texto('término previsto da obra na linha de base',
  (SELECT max(termino_previsto)::text FROM cronograma_evento WHERE cronograma_versao_id = :base_ev), '2027-04-30');
SELECT pg_temp.confere('dias sem expediente no calendário', (SELECT count(*) FROM calendario_obra WHERE NOT trabalhavel), 7);

\echo
\echo '== Linha de base é imutável =='
CALL pg_temp.espera_erro_com('mudar uma data da linha de base', 'datas e parcelas não mudam', ARRAY[
  format($$UPDATE cronograma_evento SET termino_previsto = termino_previsto + 30 WHERE cronograma_versao_id = %L$$, :base_ev)]);
CALL pg_temp.espera_erro_com('tirar um evento da linha de base', 'datas e parcelas não mudam', ARRAY[
  format($$DELETE FROM cronograma_evento WHERE cronograma_versao_id = %L$$, :base_ev)]);
CALL pg_temp.espera_erro_com('acrescentar dependência à linha de base', 'datas e parcelas não mudam', ARRAY[
  format($$INSERT INTO cronograma_predecessora (cronograma_versao_id, evento_id, predecessora_evento_id)
           VALUES (%L, pg_temp.evento(6), pg_temp.evento(1))$$, :base_ev)]);
CALL pg_temp.espera_erro_com('mudar parcela da linha de base por quantidade', 'datas e parcelas não mudam', ARRAY[
  format($$UPDATE cronograma_parcela SET percentual = 50 WHERE cronograma_versao_id = %L$$, :base_bm)]);
CALL pg_temp.espera_erro_com('alterar o registro da versão vigente', 'vigente não se altera', ARRAY[
  format($$UPDATE cronograma_versao SET motivo = 'ajuste' WHERE id = %L$$, :base_ev)]);
CALL pg_temp.espera_erro_com('voltar a versão vigente para rascunho', 'vigente não se altera', ARRAY[
  format($$UPDATE cronograma_versao SET status = 'rascunho' WHERE id = %L$$, :base_ev)]);
CALL pg_temp.espera_erro_com('marcar a vigente como substituída à mão', 'vigente não se altera', ARRAY[
  format($$UPDATE cronograma_versao SET status = 'substituida' WHERE id = %L$$, :base_ev)]);
CALL pg_temp.espera_erro_com('apagar a linha de base', 'não se apaga', ARRAY[
  format($$DELETE FROM cronograma_versao WHERE id = %L$$, :base_ev)]);

\echo
\echo '== Reprogramar é criar versão nova, com motivo e autor =='
CALL pg_temp.espera_erro('reprogramação sem motivo', ARRAY[
  format($$INSERT INTO cronograma_versao (contrato_id, revisao_id, numero, tipo) VALUES (%L, %L, 1, 'reprogramacao')$$, :c_ev, :rev_ev)]);
CALL pg_temp.espera_erro('segunda linha de base', ARRAY[
  format($$INSERT INTO cronograma_versao (contrato_id, revisao_id, numero, tipo) VALUES (%L, %L, 1, 'linha_de_base')$$, :c_ev, :rev_ev)]);
CALL pg_temp.espera_erro_com('pular o número da versão', 'tem que ser a seguinte', ARRAY[
  format($$INSERT INTO cronograma_versao (contrato_id, revisao_id, numero, tipo, motivo) VALUES (%L, %L, 5, 'reprogramacao', 'x')$$, :c_ev, :rev_ev)]);
CALL pg_temp.espera_erro_com('versão que já nasce vigente', 'nasce em rascunho', ARRAY[
  format($$INSERT INTO cronograma_versao (contrato_id, revisao_id, numero, tipo, motivo, status) VALUES (%L, %L, 1, 'reprogramacao', 'x', 'vigente')$$, :c_ev, :rev_ev)]);
CALL pg_temp.espera_erro_com('cronograma sem autor (sessão sem usuário)', 'cronograma tem autor', ARRAY[
  $$SELECT set_config('app.usuario_id', '', false)$$,
  format($$INSERT INTO cronograma_versao (contrato_id, revisao_id, numero, tipo, motivo) VALUES (%L, %L, 1, 'reprogramacao', 'x')$$, :c_ev, :rev_ev)]);
INSERT INTO cronograma_versao (id, contrato_id, revisao_id, numero, tipo, motivo)
VALUES (:v1_ev, :c_ev, :rev_ev, 1, 'reprogramacao', 'Paralisação por chuva de 03 a 09/11/2026');
SELECT pg_temp.confere_texto('a versão ficou em nome de quem está na sessão',
  (SELECT u.nome FROM cronograma_versao v JOIN usuario u ON u.id = v.autor WHERE v.id = :v1_ev), 'Orçamentista (fictício)');

-- Reprogramação com cinco dos seis eventos, sete dias depois da linha de base.
INSERT INTO cronograma_evento (cronograma_versao_id, evento_id, inicio_previsto, termino_previsto)
SELECT :v1_ev, evento_id, inicio_previsto + 7, termino_previsto + 7 FROM cronograma_evento
 WHERE cronograma_versao_id = :base_ev AND evento_id <> pg_temp.evento(6);
CALL pg_temp.espera_erro_com('publicar cronograma que não cobre todos os eventos', 'Pintura e limpeza final × Térreo" não tem datas', ARRAY[
  format($$UPDATE cronograma_versao SET status = 'vigente' WHERE id = %L$$, :v1_ev)]);
CALL pg_temp.espera_erro('evento com término antes do início', ARRAY[
  format($$INSERT INTO cronograma_evento (cronograma_versao_id, evento_id, inicio_previsto, termino_previsto)
           VALUES (%L, pg_temp.evento(6), '2027-05-07', '2027-03-29')$$, :v1_ev)]);
CALL pg_temp.espera_erro('o mesmo evento duas vezes na versão', ARRAY[
  format($$INSERT INTO cronograma_evento (cronograma_versao_id, evento_id, inicio_previsto, termino_previsto)
           VALUES (%L, pg_temp.evento(1), '2026-10-05', '2026-11-02')$$, :v1_ev)]);
CALL pg_temp.espera_erro('evento que depende de si mesmo', ARRAY[
  format($$INSERT INTO cronograma_predecessora (cronograma_versao_id, evento_id, predecessora_evento_id)
           VALUES (%L, pg_temp.evento(2), pg_temp.evento(2))$$, :v1_ev)]);
INSERT INTO cronograma_evento (cronograma_versao_id, evento_id, inicio_previsto, termino_previsto)
VALUES (:v1_ev, pg_temp.evento(6), '2027-03-29', '2027-05-07');
CALL pg_temp.espera_erro_com('ir de rascunho direto para substituída', 'não vai direto para substituído', ARRAY[
  format($$UPDATE cronograma_versao SET status = 'substituida' WHERE id = %L$$, :v1_ev)]);
UPDATE cronograma_versao SET status = 'vigente' WHERE id = :v1_ev;

SELECT pg_temp.confere_texto('a reprogramação está vigente', (SELECT status FROM cronograma_versao WHERE id = :v1_ev), 'vigente');
SELECT pg_temp.confere_texto('a linha de base passou a substituída sozinha', (SELECT status FROM cronograma_versao WHERE id = :base_ev), 'substituida');
SELECT pg_temp.confere('uma versão vigente por contrato',
  (SELECT count(*) FROM cronograma_versao WHERE contrato_id = :c_ev AND status = 'vigente'), 1);
SELECT pg_temp.confere_texto('a linha de base continua com o término original',
  (SELECT max(termino_previsto)::text FROM cronograma_evento WHERE cronograma_versao_id = :base_ev), '2027-04-30');
SELECT pg_temp.confere_texto('a reprogramação termina sete dias depois',
  (SELECT max(termino_previsto)::text FROM cronograma_evento WHERE cronograma_versao_id = :v1_ev), '2027-05-07');
CALL pg_temp.espera_erro_com('mexer na linha de base depois de substituída', 'datas e parcelas não mudam', ARRAY[
  format($$UPDATE cronograma_evento SET termino_previsto = '2027-12-31' WHERE cronograma_versao_id = %L$$, :base_ev)]);
CALL pg_temp.espera_erro_com('reativar a linha de base', 'já foi substituído', ARRAY[
  format($$UPDATE cronograma_versao SET status = 'vigente' WHERE id = %L$$, :base_ev)]);
CALL pg_temp.espera_erro_com('mudar data da reprogramação vigente', 'datas e parcelas não mudam', ARRAY[
  format($$UPDATE cronograma_evento SET termino_previsto = '2027-12-31' WHERE cronograma_versao_id = %L$$, :v1_ev)]);

-- Rascunho abandonado pode ser apagado, com as linhas dele.
INSERT INTO cronograma_versao (id, contrato_id, revisao_id, numero, tipo, motivo)
VALUES ('e0e0e0e0-0000-0000-0009-0000000000a9', :c_ev, :rev_ev, 2, 'reprogramacao', 'Ensaio');
INSERT INTO cronograma_evento (cronograma_versao_id, evento_id, inicio_previsto, termino_previsto)
VALUES ('e0e0e0e0-0000-0000-0009-0000000000a9', pg_temp.evento(1), '2026-10-05', '2026-11-02');
DELETE FROM cronograma_versao WHERE id = 'e0e0e0e0-0000-0000-0009-0000000000a9';
SELECT pg_temp.confere('linhas do rascunho apagado', (SELECT count(*) FROM cronograma_evento WHERE cronograma_versao_id = 'e0e0e0e0-0000-0000-0009-0000000000a9'), 0);

\echo
\echo '== Cronograma por quantidade: cada grupo soma 100% e nenhum fica de fora =='
INSERT INTO cronograma_versao (id, contrato_id, revisao_id, numero, tipo, motivo)
VALUES (:v1_bm, :c_bm, :rev_bm, 1, 'reprogramacao', 'Atraso na liberação da usina de asfalto');
INSERT INTO cronograma_parcela (cronograma_versao_id, revisao_id, item_contratual_id, periodo, percentual) VALUES
  (:v1_bm, :rev_bm, pg_temp.grupo('1'), 1, 100),
  (:v1_bm, :rev_bm, pg_temp.grupo('2'), 1, 50), (:v1_bm, :rev_bm, pg_temp.grupo('2'), 2, 50),
  (:v1_bm, :rev_bm, pg_temp.grupo('3'), 3, 50), (:v1_bm, :rev_bm, pg_temp.grupo('3'), 4, 40);
CALL pg_temp.espera_erro_com('grupo que soma 90%', 'grupo 3 não somam 100%', ARRAY[
  format($$UPDATE cronograma_versao SET status = 'vigente' WHERE id = %L$$, :v1_bm)]);
INSERT INTO cronograma_parcela (cronograma_versao_id, revisao_id, item_contratual_id, periodo, percentual)
VALUES (:v1_bm, :rev_bm, pg_temp.grupo('3'), 5, 10);
CALL pg_temp.espera_erro_com('grupo sem parcela nenhuma', 'grupo 4 não somam 100%', ARRAY[
  format($$UPDATE cronograma_versao SET status = 'vigente' WHERE id = %L$$, :v1_bm)]);
CALL pg_temp.espera_erro('parcela acima de 100%', ARRAY[
  format($$INSERT INTO cronograma_parcela (cronograma_versao_id, revisao_id, item_contratual_id, periodo, percentual)
           VALUES (%L, %L, pg_temp.grupo('4'), 5, 100.01)$$, :v1_bm, :rev_bm)]);
CALL pg_temp.espera_erro_com('parcela de outra planilha', 'mesma planilha do cronograma', ARRAY[
  format($$INSERT INTO cronograma_parcela (cronograma_versao_id, revisao_id, item_contratual_id, periodo, percentual)
           VALUES (%L, %L, pg_temp.grupo('4'), 5, 100)$$, :v1_bm, :rev_ev)]);
INSERT INTO cronograma_parcela (cronograma_versao_id, revisao_id, item_contratual_id, periodo, percentual)
VALUES (:v1_bm, :rev_bm, pg_temp.grupo('4'), 5, 100), (:v1_bm, :rev_bm, pg_temp.grupo('3.1'), 5, 100);
CALL pg_temp.espera_erro_com('parcela de serviço, e não de grupo do primeiro nível', 'não é grupo do primeiro nível', ARRAY[
  format($$UPDATE cronograma_versao SET status = 'vigente' WHERE id = %L$$, :v1_bm)]);
DELETE FROM cronograma_parcela WHERE cronograma_versao_id = :v1_bm AND item_contratual_id = pg_temp.grupo('3.1');
UPDATE cronograma_versao SET status = 'vigente' WHERE id = :v1_bm;
SELECT pg_temp.confere_texto('reprogramação por quantidade vigente', (SELECT status FROM cronograma_versao WHERE id = :v1_bm), 'vigente');

\echo
\echo '== Documento do órgão é prova: registrado uma vez, não muda =='
INSERT INTO documento_orgao (id, contrato_id, tipo, nome, arquivo_sha256, chave_arquivo, recebido_em)
VALUES ('e0e0e0e0-0000-0000-0009-0000000000d1', :c_ev, 'projeto', 'Projeto arquitetônico', :hash, 'ficticio/projeto.pdf', '2026-09-14');
CALL pg_temp.espera_erro('o mesmo arquivo duas vezes no contrato', ARRAY[
  format($$INSERT INTO documento_orgao (contrato_id, tipo, nome, arquivo_sha256, chave_arquivo, recebido_em)
           VALUES (%L, 'projeto', 'De novo', %L, 'x', '2026-09-14')$$, :c_ev, :hash)]);
CALL pg_temp.espera_erro('hash que não é SHA-256', ARRAY[
  format($$INSERT INTO documento_orgao (contrato_id, tipo, nome, arquivo_sha256, chave_arquivo, recebido_em)
           VALUES (%L, 'projeto', 'x', 'abc', 'x', '2026-09-14')$$, :c_ev)]);
CALL pg_temp.espera_erro_com('aplicação alterar documento do órgão', 'permission denied', ARRAY[$$UPDATE documento_orgao SET nome = 'outro'$$]);
RESET ROLE;
CALL pg_temp.espera_erro_com('nem o dono altera documento do órgão', 'Documento do órgão não se altera', ARRAY[$$UPDATE documento_orgao SET nome = 'outro'$$]);
SET ROLE app_rw;

INSERT INTO prancha (id, documento_id, numero, titulo, disciplina) VALUES
  ('e0e0e0e0-0000-0000-0009-0000000000f1', 'e0e0e0e0-0000-0000-0009-0000000000d1', 'ARQ-01', 'Planta baixa do térreo', 'arquitetura');
INSERT INTO prancha_vinculo (prancha_id, alvo, alvo_id, origem)
VALUES ('e0e0e0e0-0000-0000-0009-0000000000f1', 'frente', 'e0e0e0e0-0000-0000-0000-0000000000f1', 'sugestao_aceita');
SELECT pg_temp.confere_texto('vínculo sugerido fica em nome de quem aceitou',
  (SELECT u.nome FROM prancha_vinculo v JOIN usuario u ON u.id = v.confirmado_por), 'Orçamentista (fictício)');
CALL pg_temp.espera_erro_com('vincular prancha a grupo de outro contrato', 'não é grupo_eap deste contrato', ARRAY[
  $$INSERT INTO prancha_vinculo (prancha_id, alvo, alvo_id, origem)
    VALUES ('e0e0e0e0-0000-0000-0009-0000000000f1', 'grupo_eap', pg_temp.grupo('3'), 'manual')$$]);
CALL pg_temp.espera_erro_com('vincular prancha a serviço (só grupo, frente ou agrupador)', 'não é grupo_eap deste contrato', ARRAY[
  format($$INSERT INTO prancha_vinculo (prancha_id, alvo, alvo_id, origem)
           SELECT 'e0e0e0e0-0000-0000-0009-0000000000f1', 'grupo_eap', item_contratual_id, 'manual'
             FROM item_revisao WHERE revisao_id = %L AND codigo_eap = '3.1'$$, :rev_ev)]);
CALL pg_temp.espera_erro_com('vínculo sem pessoa na sessão', 'pessoa identificada', ARRAY[
  $$SELECT set_config('app.usuario_id', '', false)$$,
  $$INSERT INTO prancha_vinculo (prancha_id, alvo, alvo_id, origem)
    SELECT 'e0e0e0e0-0000-0000-0009-0000000000f1', 'agrupador', id, 'sugestao_aceita' FROM agrupador_evento LIMIT 1$$]);
CALL pg_temp.espera_erro('dois registros de calendário para o mesmo dia', ARRAY[
  format($$INSERT INTO calendario_obra (contrato_id, data, trabalhavel, motivo) VALUES (%L, '2026-12-25', true, 'x')$$, :c_ev)]);

RESET ROLE;
