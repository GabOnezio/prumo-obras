-- Pessoas e designação (migração 0002). Roda sobre o seed, como app_rw, no município de Exemplo.
SET ROLE app_rw;
SET app.tenant_id = 'e0e0e0e0-0000-0000-0000-000000000001';
SET app.usuario = 'teste.pessoas';

\set c_ev  '''e0e0e0e0-0000-0000-0000-0000000000c1'''
\set c_bm  '''e0e0e0e0-0000-0000-0000-0000000000c2'''
\set fiscal      '''e0e0e0e0-0000-0000-0001-000000000001'''
\set substituto  '''e0e0e0e0-0000-0000-0001-000000000002'''
\set gestor      '''e0e0e0e0-0000-0000-0001-000000000003'''
\set preposto    '''e0e0e0e0-0000-0000-0001-000000000005'''
\set orcamentista '''e0e0e0e0-0000-0000-0001-000000000008'''

\echo
\echo '== Quem é quem no contrato, em cada data =='
SELECT pg_temp.confere_texto('fiscal técnico é fiscal do contrato depois da portaria',
  fn_fiscal_do_contrato(:fiscal, :c_ev, DATE '2026-10-01')::text, 'true');
SELECT pg_temp.confere_texto('fiscal técnico ainda não era fiscal na véspera da portaria',
  fn_fiscal_do_contrato(:fiscal, :c_ev, DATE '2026-09-14')::text, 'false');
SELECT pg_temp.confere_texto('fiscal substituto conta como fiscal do contrato',
  fn_fiscal_do_contrato(:substituto, :c_ev, DATE '2026-10-01')::text, 'true');
SELECT pg_temp.confere_texto('gestor do contrato não é fiscal',
  fn_fiscal_do_contrato(:gestor, :c_ev, DATE '2026-10-01')::text, 'false');
SELECT pg_temp.confere_texto('gestor do contrato tem a função de gestor',
  fn_designado(:gestor, :c_ev, ARRAY['gestor_contrato']::funcao_designacao[], DATE '2026-10-01')::text, 'true');
SELECT pg_temp.confere_texto('servidor sem designação não é fiscal',
  fn_fiscal_do_contrato(:orcamentista, :c_ev, DATE '2026-10-01')::text, 'false');
SELECT pg_temp.confere_texto('preposto age pela contratada do contrato dele',
  fn_da_contratada(:preposto, :c_ev, DATE '2026-10-01')::text, 'true');
SELECT pg_temp.confere_texto('preposto não age pela contratada de outro contrato',
  fn_da_contratada(:preposto, :c_bm, DATE '2026-10-01')::text, 'false');
SELECT pg_temp.confere_texto('preposto não é fiscal',
  fn_fiscal_do_contrato(:preposto, :c_ev, DATE '2026-10-01')::text, 'false');
SELECT pg_temp.confere_texto('sessão sem usuário: ninguém', coalesce(app_usuario()::text, 'ninguém'), 'ninguém');

\echo
\echo '== Designação é histórico: encerra, não apaga nem reescreve =='
CALL pg_temp.espera_erro_com('apagar designação', 'Designação não é apagada', ARRAY[
  $$DELETE FROM designacao WHERE funcao = 'fiscal_substituto'$$]);
CALL pg_temp.espera_erro_com('trocar a função de uma designação', 'só muda para receber a data de fim', ARRAY[
  $$UPDATE designacao SET funcao = 'gestor_contrato' WHERE funcao = 'fiscal_substituto'$$]);
CALL pg_temp.espera_erro_com('trocar o início de uma designação', 'só muda para receber a data de fim', ARRAY[
  $$UPDATE designacao SET inicio = DATE '2026-01-01' WHERE funcao = 'fiscal_substituto'$$]);
CALL pg_temp.espera_erro_com('designação com fim antes do início', 'designacao_check', ARRAY[
  $$UPDATE designacao SET fim = DATE '2026-09-01' WHERE funcao = 'fiscal_substituto'$$]);
CALL pg_temp.espera_erro_com('a mesma função duas vezes no mesmo período', 'designacao_servidor_id_contrato_id_funcao_daterange_excl', ARRAY[
  $$INSERT INTO designacao (servidor_id, contrato_id, funcao, inicio, portaria_id)
    SELECT servidor_id, contrato_id, funcao, DATE '2026-12-01', portaria_id FROM designacao
     WHERE funcao = 'fiscal_tecnico' LIMIT 1$$]);
CALL pg_temp.espera_erro('designação sem portaria', ARRAY[
  $$INSERT INTO designacao (servidor_id, contrato_id, funcao, inicio)
    SELECT servidor_id, contrato_id, 'comissao_recebimento', DATE '2026-12-01' FROM designacao LIMIT 1$$]);

-- Encerrar é permitido, uma vez. Depois do fim, a pessoa deixa de ter a função.
UPDATE designacao SET fim = DATE '2026-11-30' WHERE funcao = 'fiscal_substituto' AND contrato_id = :c_ev;
SELECT pg_temp.confere_texto('substituto ainda é fiscal no último dia',
  fn_fiscal_do_contrato(:substituto, :c_ev, DATE '2026-11-30')::text, 'true');
SELECT pg_temp.confere_texto('substituto deixa de ser fiscal no dia seguinte',
  fn_fiscal_do_contrato(:substituto, :c_ev, DATE '2026-12-01')::text, 'false');
SELECT pg_temp.confere_texto('no outro contrato o substituto continua',
  fn_fiscal_do_contrato(:substituto, :c_bm, DATE '2026-12-01')::text, 'true');
CALL pg_temp.espera_erro_com('reabrir designação encerrada', 'só muda para receber a data de fim', ARRAY[
  format($$UPDATE designacao SET fim = NULL WHERE funcao = 'fiscal_substituto' AND contrato_id = %L$$, :c_ev)]);
-- Nova designação para o mesmo servidor, depois do fim da anterior, é outra linha.
INSERT INTO designacao (servidor_id, contrato_id, funcao, inicio, portaria_id)
SELECT servidor_id, contrato_id, funcao, DATE '2027-01-10', portaria_id FROM designacao
 WHERE funcao = 'fiscal_substituto' AND contrato_id = :c_ev;
SELECT pg_temp.confere_texto('substituto volta a ser fiscal com a nova designação',
  fn_fiscal_do_contrato(:substituto, :c_ev, DATE '2027-01-10')::text, 'true');
SELECT pg_temp.confere_texto('e não era no intervalo entre as duas',
  fn_fiscal_do_contrato(:substituto, :c_ev, DATE '2026-12-20')::text, 'false');

-- Usuário desativado perde todas as funções, sem mexer nas designações.
UPDATE usuario SET ativo = false WHERE id = :gestor;
SELECT pg_temp.confere_texto('usuário desativado não tem função',
  fn_designado(:gestor, :c_ev, ARRAY['gestor_contrato']::funcao_designacao[], DATE '2026-10-01')::text, 'false');
UPDATE usuario SET ativo = true WHERE id = :gestor;

\echo
\echo '== A mesma pessoa não está dos dois lados do contrato =='
CALL pg_temp.espera_erro_com('pessoa da empresa designada como fiscal do mesmo contrato', 'já age pela empresa', ARRAY[
  format($$WITH s AS (INSERT INTO servidor (usuario_id, matricula, cargo) VALUES (%L, 'EX-9999', 'Cargo') RETURNING id)
           INSERT INTO designacao (servidor_id, contrato_id, funcao, inicio, portaria_id)
           SELECT s.id, %L, 'fiscal_tecnico', DATE '2026-12-01', p.id FROM s, portaria p$$, :preposto, :c_ev)]);
CALL pg_temp.espera_erro_com('fiscal cadastrado como pessoa da empresa no mesmo contrato', 'já tem designação da prefeitura', ARRAY[
  format($$INSERT INTO usuario_externo (usuario_id, empresa_id, contrato_id, papel, inicio)
           SELECT %L, empresa_id, id, 'apontador', DATE '2026-12-01' FROM contrato WHERE id = %L$$, :fiscal, :c_ev)]);
CALL pg_temp.espera_erro_com('pessoa de uma empresa em contrato de outra', 'não é a contratada deste contrato', ARRAY[
  format($$INSERT INTO usuario_externo (usuario_id, empresa_id, contrato_id, papel, inicio)
           SELECT %L, 'e0e0e0e0-0000-0000-0000-0000000000e1', %L, 'apontador', DATE '2026-12-01'$$, :orcamentista, :c_bm)]);
CALL pg_temp.espera_erro('papel de pessoa da empresa fora da lista', ARRAY[
  $$UPDATE usuario_externo SET papel = 'dono'$$]);

\echo
\echo '== Trilha =='
SELECT pg_temp.confere('auditoria registrou o encerramento da designação',
  (SELECT count(*) FROM auditoria WHERE tabela = 'designacao' AND acao = 'U' AND usuario = 'teste.pessoas'), 1);

RESET ROLE;
