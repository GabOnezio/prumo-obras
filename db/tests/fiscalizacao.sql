-- Fiscalização (migração 0003). Roda sobre o seed, como app_rw, no município de Exemplo.
-- O teste troca o usuário da sessão para agir como cada pessoa do seed.
SET ROLE app_rw;
SET app.tenant_id = 'e0e0e0e0-0000-0000-0000-000000000001';
SET app.usuario = 'teste.fiscalizacao';

\set c_ev '''e0e0e0e0-0000-0000-0000-0000000000c1'''
\set c_bm '''e0e0e0e0-0000-0000-0000-0000000000c2'''
\set fiscal   '''e0e0e0e0-0000-0000-0001-000000000001'''
\set gestor   '''e0e0e0e0-0000-0000-0001-000000000003'''
\set comissao '''e0e0e0e0-0000-0000-0001-000000000004'''
\set preposto '''e0e0e0e0-0000-0000-0001-000000000005'''
\set preposto_beta '''e0e0e0e0-0000-0000-0001-000000000007'''
\set hash '''aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'''

\echo
\echo '== Sem usuário na sessão ninguém pratica ato =='
CALL pg_temp.espera_erro_com('abrir ocorrência sem usuário na sessão', 'não diz quem está agindo', ARRAY[
  format($$INSERT INTO ocorrencia (contrato_id, tipo, descricao) VALUES (%L, 'qualidade', 'Trinca no reboco')$$, :c_ev)]);

\echo
\echo '== Ordem de serviço: sequência e efeito no contrato =='
SET app.usuario_id = :gestor;
CALL pg_temp.espera_erro_com('paralisar obra que não começou', 'não cabe depois de', ARRAY[
  format($$INSERT INTO ordem_servico (contrato_id, tipo, data, motivo) VALUES (%L, 'paralisacao', '2026-10-01', 'Chuva')$$, :c_ev)]);
INSERT INTO ordem_servico (contrato_id, tipo, data) VALUES (:c_ev, 'inicio', '2026-09-28');
SELECT pg_temp.confere_texto('início: contrato em execução', (SELECT status::text FROM contrato WHERE id = :c_ev), 'em_execucao');
SELECT pg_temp.confere_texto('a ordem ficou em nome de quem está na sessão',
  (SELECT u.nome FROM ordem_servico o JOIN usuario u ON u.id = o.emitida_por WHERE o.tipo = 'inicio'), 'Gestor do contrato (fictício)');
CALL pg_temp.espera_erro_com('segunda ordem de início', 'não cabe depois de', ARRAY[
  format($$INSERT INTO ordem_servico (contrato_id, tipo, data) VALUES (%L, 'inicio', '2026-10-01')$$, :c_ev)]);
CALL pg_temp.espera_erro_com('retomar obra que não está paralisada', 'não cabe depois de', ARRAY[
  format($$INSERT INTO ordem_servico (contrato_id, tipo, data, motivo) VALUES (%L, 'retomada', '2026-10-05', 'x')$$, :c_ev)]);
CALL pg_temp.espera_erro_com('paralisar sem motivo', 'ordem_servico_check', ARRAY[
  format($$INSERT INTO ordem_servico (contrato_id, tipo, data) VALUES (%L, 'paralisacao', '2026-11-03')$$, :c_ev)]);
CALL pg_temp.espera_erro_com('ordem com data anterior à última', 'data anterior', ARRAY[
  format($$INSERT INTO ordem_servico (contrato_id, tipo, data, motivo) VALUES (%L, 'paralisacao', '2026-09-01', 'x')$$, :c_ev)]);
INSERT INTO ordem_servico (contrato_id, tipo, data, motivo) VALUES (:c_ev, 'paralisacao', '2026-11-03', 'Chuva forte por cinco dias');
SELECT pg_temp.confere_texto('paralisação: contrato paralisado', (SELECT status::text FROM contrato WHERE id = :c_ev), 'paralisado');
INSERT INTO ordem_servico (contrato_id, tipo, data, motivo) VALUES (:c_ev, 'retomada', '2026-11-09', 'Terreno seco');
SELECT pg_temp.confere_texto('retomada: contrato em execução', (SELECT status::text FROM contrato WHERE id = :c_ev), 'em_execucao');
CALL pg_temp.espera_erro_com('alterar ordem de serviço emitida', 'Ordem de serviço não se altera', ARRAY[
  $$UPDATE ordem_servico SET data = '2026-09-01' WHERE tipo = 'inicio'$$]);
CALL pg_temp.espera_erro_com('apagar ordem de serviço', 'Ordem de serviço não se altera', ARRAY[$$DELETE FROM ordem_servico$$]);

\echo
\echo '== Ocorrência e notificação: só fiscal designado; o emitido não muda =='
SET app.usuario_id = :preposto;
CALL pg_temp.espera_erro_com('empresa abrir ocorrência', 'designação vigente', ARRAY[
  format($$INSERT INTO ocorrencia (contrato_id, tipo, descricao) VALUES (%L, 'qualidade', 'x')$$, :c_ev)]);
SET app.usuario_id = :gestor;
CALL pg_temp.espera_erro_com('gestor do contrato abrir ocorrência no lugar do fiscal', 'designação vigente', ARRAY[
  format($$INSERT INTO ocorrencia (contrato_id, tipo, descricao) VALUES (%L, 'qualidade', 'x')$$, :c_ev)]);
SET app.usuario_id = :fiscal;
INSERT INTO ocorrencia (id, contrato_id, tipo, descricao) VALUES
  ('e0e0e0e0-0000-0000-0002-000000000001', :c_ev, 'qualidade', 'Trinca no reboco da sala 3');
-- Mesmo informando outro autor, fica quem está na sessão.
INSERT INTO ocorrencia (id, contrato_id, tipo, descricao, aberta_por) VALUES
  ('e0e0e0e0-0000-0000-0002-000000000002', :c_ev, 'prazo', 'Frente parada sem justificativa', :gestor);
SELECT pg_temp.confere('ocorrências em nome do fiscal da sessão', (SELECT count(*) FROM ocorrencia WHERE aberta_por = :fiscal), 2);
CALL pg_temp.espera_erro_com('reescrever a descrição da ocorrência', 'não se altera', ARRAY[
  $$UPDATE ocorrencia SET descricao = 'Outra coisa'$$]);
CALL pg_temp.espera_erro_com('apagar ocorrência', 'não se apaga', ARRAY[$$DELETE FROM ocorrencia$$]);
UPDATE ocorrencia SET status = 'em_tratamento' WHERE id = 'e0e0e0e0-0000-0000-0002-000000000001';
CALL pg_temp.espera_erro_com('voltar a situação da ocorrência', 'não volta para', ARRAY[
  $$UPDATE ocorrencia SET status = 'aberta' WHERE id = 'e0e0e0e0-0000-0000-0002-000000000001'$$]);
CALL pg_temp.espera_erro_com('encerrar sem a data de encerramento', 'ocorrencia_check', ARRAY[
  $$UPDATE ocorrencia SET status = 'encerrada' WHERE id = 'e0e0e0e0-0000-0000-0002-000000000001'$$]);
SET app.usuario_id = :preposto;
CALL pg_temp.espera_erro_com('empresa mudar a situação da ocorrência', 'Só fiscal', ARRAY[
  $$UPDATE ocorrencia SET status = 'resolvida' WHERE id = 'e0e0e0e0-0000-0000-0002-000000000001'$$]);

SET app.usuario_id = :fiscal;
CALL pg_temp.espera_erro('notificação sem prazo de resposta (não há prazo padrão)', ARRAY[
  format($$INSERT INTO notificacao (contrato_id, numero, texto) VALUES (%L, 1, 'Corrigir o reboco')$$, :c_ev)]);
INSERT INTO notificacao (id, contrato_id, ocorrencia_id, numero, texto, prazo_resposta_dias) VALUES
  ('e0e0e0e0-0000-0000-0003-000000000001', :c_ev, 'e0e0e0e0-0000-0000-0002-000000000001', 1, 'Corrigir o reboco da sala 3', 5);
CALL pg_temp.espera_erro_com('alterar o texto da notificação emitida', 'não se altera', ARRAY[
  $$UPDATE notificacao SET texto = 'Outro texto'$$]);
CALL pg_temp.espera_erro_com('alterar o prazo da notificação emitida', 'não se altera', ARRAY[
  $$UPDATE notificacao SET prazo_resposta_dias = 30$$]);
CALL pg_temp.espera_erro_com('fiscal responder a própria notificação', 'Só a empresa contratada responde', ARRAY[
  $$UPDATE notificacao SET resposta = 'Feito'$$]);
SET app.usuario_id = :preposto_beta;
CALL pg_temp.espera_erro_com('empresa de outro contrato responder', 'Só a empresa contratada responde', ARRAY[
  $$UPDATE notificacao SET resposta = 'Feito'$$]);
SET app.usuario_id = :preposto;
CALL pg_temp.espera_erro_com('resposta em branco', 'Resposta em branco', ARRAY[$$UPDATE notificacao SET resposta = '  '$$]);
UPDATE notificacao SET resposta = 'Reboco refeito em 12/11/2026';
SELECT pg_temp.confere_texto('a resposta ficou em nome do preposto',
  (SELECT u.nome FROM notificacao n JOIN usuario u ON u.id = n.respondida_por), 'Preposto da Alfa (fictício)');
CALL pg_temp.espera_erro_com('responder de novo', 'a resposta é dada uma vez', ARRAY[
  $$UPDATE notificacao SET resposta = 'Mudei de ideia'$$]);
CALL pg_temp.espera_erro_com('apagar notificação', 'não se apaga', ARRAY[$$DELETE FROM notificacao$$]);

\echo
\echo '== Vistoria: do fiscal que fez, até concluir =='
SET app.usuario_id = :preposto;
CALL pg_temp.espera_erro_com('empresa registrar vistoria', 'designação vigente', ARRAY[
  format($$INSERT INTO vistoria (contrato_id, data) VALUES (%L, '2026-12-15')$$, :c_ev)]);
SET app.usuario_id = :fiscal;
INSERT INTO vistoria (id, contrato_id, data, observacao) VALUES
  ('e0e0e0e0-0000-0000-0004-000000000001', :c_ev, '2026-12-15', 'Alvenaria do térreo em 70%');
UPDATE vistoria SET observacao = 'Alvenaria do térreo em 70%, sem pendência' WHERE id = 'e0e0e0e0-0000-0000-0004-000000000001';
SET app.usuario_id = 'e0e0e0e0-0000-0000-0001-000000000002';
CALL pg_temp.espera_erro_com('outro fiscal alterar a vistoria', 'Só quem fez a vistoria', ARRAY[
  $$UPDATE vistoria SET observacao = 'x' WHERE id = 'e0e0e0e0-0000-0000-0004-000000000001'$$]);
SET app.usuario_id = :fiscal;
UPDATE vistoria SET concluida_em = now() WHERE id = 'e0e0e0e0-0000-0000-0004-000000000001';
CALL pg_temp.espera_erro_com('alterar vistoria concluída', 'Vistoria concluída não se altera', ARRAY[
  $$UPDATE vistoria SET observacao = 'x' WHERE id = 'e0e0e0e0-0000-0000-0004-000000000001'$$]);
CALL pg_temp.espera_erro_com('apagar vistoria concluída', 'Vistoria concluída não se altera', ARRAY[$$DELETE FROM vistoria WHERE id = 'e0e0e0e0-0000-0000-0004-000000000001'$$]);

\echo
\echo '== Recebimento: provisório do fiscal, definitivo da comissão de recebimento =='
SET app.usuario_id = :fiscal;
CALL pg_temp.espera_erro_com('definitivo sem o provisório (e sem ser da comissão)', 'comissão de recebimento', ARRAY[
  format($$INSERT INTO recebimento (contrato_id, tipo, data, termo_arquivo_sha256) VALUES (%L, 'definitivo', '2027-05-20', %L)$$, :c_ev, :hash)]);
SET app.usuario_id = :preposto;
CALL pg_temp.espera_erro_com('empresa registrar o recebimento provisório', 'fiscal com designação vigente', ARRAY[
  format($$INSERT INTO recebimento (contrato_id, tipo, data, termo_arquivo_sha256) VALUES (%L, 'provisorio', '2027-05-05', %L)$$, :c_ev, :hash)]);
SET app.usuario_id = :fiscal;
INSERT INTO recebimento (contrato_id, tipo, data, termo_arquivo_sha256, pendencias) VALUES
  (:c_ev, 'provisorio', '2027-05-05', :hash, 'Limpeza do pátio');
CALL pg_temp.espera_erro_com('fiscal registrar o definitivo', 'comissão de recebimento', ARRAY[
  format($$INSERT INTO recebimento (contrato_id, tipo, data, termo_arquivo_sha256) VALUES (%L, 'definitivo', '2027-05-20', %L)$$, :c_ev, :hash)]);
-- O seed não tem comissão de recebimento: a designação é criada aqui, pelo dono, e usada em seguida.
RESET ROLE;
INSERT INTO designacao (tenant_id, servidor_id, contrato_id, funcao, inicio, portaria_id)
SELECT 'e0e0e0e0-0000-0000-0000-000000000001', s.id, :c_ev, 'comissao_recebimento', DATE '2026-09-15', p.id
  FROM servidor s, portaria p WHERE s.usuario_id = :comissao;
SET ROLE app_rw;
SET app.usuario_id = :comissao;
CALL pg_temp.espera_erro_com('definitivo com data anterior ao provisório', 'só depois do provisório', ARRAY[
  format($$INSERT INTO recebimento (contrato_id, tipo, data, termo_arquivo_sha256) VALUES (%L, 'definitivo', '2027-05-01', %L)$$, :c_ev, :hash)]);
CALL pg_temp.espera_erro_com('definitivo em contrato sem provisório', 'comissão de recebimento', ARRAY[
  format($$INSERT INTO recebimento (contrato_id, tipo, data, termo_arquivo_sha256) VALUES (%L, 'definitivo', '2027-05-20', %L)$$, :c_bm, :hash)]);
INSERT INTO recebimento (id, contrato_id, tipo, data, termo_arquivo_sha256) VALUES
  ('e0e0e0e0-0000-0000-0005-000000000002', :c_ev, 'definitivo', '2027-05-20', :hash);
CALL pg_temp.espera_erro('segundo recebimento definitivo', ARRAY[
  format($$INSERT INTO recebimento (contrato_id, tipo, data, termo_arquivo_sha256) VALUES (%L, 'definitivo', '2027-06-01', %L)$$, :c_ev, :hash)]);
CALL pg_temp.espera_erro_com('alterar termo de recebimento', 'Termo de recebimento não se altera', ARRAY[
  $$UPDATE recebimento SET pendencias = NULL$$]);

\echo
\echo '== Garantia da obra =='
CALL pg_temp.espera_erro_com('garantia de menos de 5 anos', 'garantia_obra_prazo_anos_check', ARRAY[
  $$INSERT INTO garantia_obra (recebimento_id, prazo_anos, inicio, vence_em)
    VALUES ('e0e0e0e0-0000-0000-0005-000000000002', 4, '2027-05-20', '2031-05-20')$$]);
CALL pg_temp.espera_erro_com('vencimento que não bate com o prazo', 'garantia_obra_check', ARRAY[
  $$INSERT INTO garantia_obra (recebimento_id, prazo_anos, inicio, vence_em)
    VALUES ('e0e0e0e0-0000-0000-0005-000000000002', 5, '2027-05-20', '2033-05-20')$$]);
CALL pg_temp.espera_erro_com('garantia contada do recebimento provisório', 'data do recebimento definitivo', ARRAY[
  $$INSERT INTO garantia_obra (recebimento_id, prazo_anos, inicio, vence_em)
    SELECT id, 5, data, (data + interval '5 years')::date FROM recebimento WHERE tipo = 'provisorio'$$]);
INSERT INTO garantia_obra (recebimento_id, prazo_anos, inicio, vence_em)
VALUES ('e0e0e0e0-0000-0000-0005-000000000002', 5, '2027-05-20', '2032-05-20');
CALL pg_temp.espera_erro_com('alterar a garantia da obra', 'Garantia da obra não se altera', ARRAY[
  $$UPDATE garantia_obra SET prazo_anos = 10, vence_em = '2037-05-20'$$]);

RESET ROLE;
