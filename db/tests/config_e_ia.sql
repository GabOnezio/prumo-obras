-- Configuração do município, registro de IA, publicação e denúncia (migração 0006).
-- Roda sobre o seed, como app_rw, no município de Exemplo.
SET ROLE app_rw;
SET app.tenant_id = 'e0e0e0e0-0000-0000-0000-000000000001';
SET app.usuario = 'teste.config';

\set c_bm '''e0e0e0e0-0000-0000-0000-0000000000c2'''
\set m1   '''e0e0e0e0-0000-0000-0000-0000000000e1'''
\set fiscal    '''e0e0e0e0-0000-0000-0001-000000000001'''
\set gestor    '''e0e0e0e0-0000-0000-0001-000000000003'''
\set comissao  '''e0e0e0e0-0000-0000-0001-000000000004'''
\set preposto  '''e0e0e0e0-0000-0000-0001-000000000007'''
\set hash '''aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'''

\echo
\echo '== Nenhuma configuração tem valor padrão no banco =='
SELECT pg_temp.confere_vazio('coluna de config_municipio com valor padrão', $$
  SELECT column_name FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'config_municipio'
     AND column_default IS NOT NULL AND column_name <> 'atualizado_em'$$);
SELECT pg_temp.confere_vazio('coluna de config_municipio que não aceita ficar em branco', $$
  SELECT column_name FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'config_municipio'
     AND is_nullable = 'NO' AND column_name NOT IN ('tenant_id', 'atualizado_em')$$);
SELECT pg_temp.confere('o seed configurou o município de Exemplo', (SELECT count(*) FROM config_municipio), 1);
CALL pg_temp.espera_erro_com('aplicação apagar a configuração', 'permission denied', ARRAY[$$DELETE FROM config_municipio$$]);
RESET ROLE;
CALL pg_temp.espera_erro_com('nem o dono apaga a configuração', 'não se apaga', ARRAY[$$DELETE FROM config_municipio$$]);
SET ROLE app_rw;
CALL pg_temp.espera_erro('limiar de previsão fora de 1 a 99', ARRAY[$$UPDATE config_municipio SET previsao_avanco_minimo_pct = 100$$]);
CALL pg_temp.espera_erro('faixa do fator invertida', ARRAY[$$UPDATE config_municipio SET previsao_fator_minimo = 5$$]);

\echo
\echo '== Quem atesta a medição vem da configuração: trocar a configuração troca o resultado =='
-- Medição 1 do contrato por quantidade, levada até "aprovada pelo fiscal".
INSERT INTO medicao (id, contrato_id, numero, revisao_id, periodo_inicio, periodo_fim)
SELECT :m1, :c_bm, 1, id, '2026-11-01', '2026-11-30' FROM revisao_orcamento WHERE contrato_id = :c_bm AND status = 'vigente';
INSERT INTO medicao_item (medicao_id, item_contratual_id, quantidade, valor)
SELECT :m1, ir.item_contratual_id, 1.00, 0 FROM item_revisao ir JOIN revisao_orcamento r ON r.id = ir.revisao_id
 WHERE r.contrato_id = :c_bm AND ir.codigo_eap = '1.2';
SET app.usuario_id = :preposto;
INSERT INTO medicao_etapa (medicao_id, acao) VALUES (:m1, 'enviar');
SET app.usuario_id = :fiscal;
INSERT INTO medicao_etapa (medicao_id, acao) VALUES (:m1, 'iniciar_analise');
INSERT INTO medicao_etapa (medicao_id, acao) VALUES (:m1, 'aprovar_fiscal');

-- 1. Sem a resposta configurada, o banco não escolhe por conta própria.
UPDATE config_municipio SET comissao_medicao_exigida = NULL;
CALL pg_temp.espera_erro_com('atestar sem a configuração da comissão', 'Configuração do município ausente', ARRAY[
  format($$SELECT set_config('app.usuario_id', %L, false)$$, :gestor),
  format($$INSERT INTO medicao_etapa (medicao_id, acao) VALUES (%L, 'atestar')$$, :m1)]);
-- 2. Com comissão exigida, o gestor do contrato não atesta.
UPDATE config_municipio SET comissao_medicao_exigida = true;
CALL pg_temp.espera_erro_com('gestor do contrato atestar onde a comissão é exigida', 'não tem, neste contrato, a função', ARRAY[
  format($$SELECT set_config('app.usuario_id', %L, false)$$, :gestor),
  format($$INSERT INTO medicao_etapa (medicao_id, acao) VALUES (%L, 'atestar')$$, :m1)]);
-- 3. Sem comissão exigida, quem não atesta é a comissão.
UPDATE config_municipio SET comissao_medicao_exigida = false;
CALL pg_temp.espera_erro_com('comissão atestar onde ela não é exigida', 'não tem, neste contrato, a função', ARRAY[
  format($$SELECT set_config('app.usuario_id', %L, false)$$, :comissao),
  format($$INSERT INTO medicao_etapa (medicao_id, acao) VALUES (%L, 'atestar')$$, :m1)]);
-- 4. De volta com comissão exigida, ela atesta.
UPDATE config_municipio SET comissao_medicao_exigida = true;
SET app.usuario_id = :comissao;
INSERT INTO medicao_etapa (medicao_id, acao) VALUES (:m1, 'atestar');
SELECT pg_temp.confere_texto('medição atestada pela comissão', (SELECT status::text FROM medicao WHERE id = :m1), 'atestada');
SELECT pg_temp.confere('a trilha de auditoria guardou as trocas de configuração',
  (SELECT count(*) FROM auditoria WHERE tabela = 'config_municipio' AND acao = 'U' AND usuario = 'teste.config'), 4);

\echo
\echo '== Registro de IA: a proposta não muda, e quem decide é pessoa =='
SET app.usuario_id = :fiscal;
CALL pg_temp.espera_erro_com('proposta que já nasce aceita', 'nasce sem desfecho', ARRAY[
  format($$INSERT INTO ia_decisao (funcao, classe, modelo, versao_modelo, versao_prompt, entrada_sha256, proposta, confianca, desfecho, decidida_em)
           VALUES ('IA-03', 'choice', 'modelo-local', '1', '1', %L, '{}', 'alta', 'aceita', now())$$, :hash)]);
CALL pg_temp.espera_erro('função de IA fora do padrão IA-NN', ARRAY[
  format($$INSERT INTO ia_decisao (funcao, classe, modelo, versao_modelo, versao_prompt, entrada_sha256, proposta, confianca)
           VALUES ('aprovar-medicao', 'choice', 'm', '1', '1', %L, '{}', 'alta')$$, :hash)]);
INSERT INTO ia_decisao (id, funcao, classe, modelo, versao_modelo, versao_prompt, entrada_sha256, proposta, confianca) VALUES
  ('e0e0e0e0-0000-0000-0007-000000000001', 'IA-03', 'choice', 'modelo-local-ficticio', '0.1', 'p1', :hash, '{"legenda": "Alvenaria do térreo"}', 'media'),
  ('e0e0e0e0-0000-0000-0007-000000000002', 'IA-21', 'choice', 'modelo-local-ficticio', '0.1', 'p1', :hash, '{"agrupador": 3}', 'baixa');
CALL pg_temp.espera_erro_com('reescrever a proposta registrada', 'não se altera', ARRAY[
  $$UPDATE ia_decisao SET proposta = '{"legenda": "Outra"}', desfecho = 'aceita' WHERE funcao = 'IA-03'$$]);
CALL pg_temp.espera_erro_com('trocar o modelo registrado', 'não se altera', ARRAY[
  $$UPDATE ia_decisao SET modelo = 'outro', desfecho = 'aceita' WHERE funcao = 'IA-03'$$]);
CALL pg_temp.espera_erro_com('apagar registro de IA', 'permission denied', ARRAY[$$DELETE FROM ia_decisao$$]);
RESET ROLE;
CALL pg_temp.espera_erro_com('nem o dono apaga registro de IA', 'não se apaga', ARRAY[$$DELETE FROM ia_decisao$$]);
SET ROLE app_rw;
-- aceitar fica em nome de quem está na sessão, mesmo que se informe outra pessoa
UPDATE ia_decisao SET desfecho = 'aceita', decidida_por = :gestor WHERE funcao = 'IA-03';
SELECT pg_temp.confere_texto('quem aceitou foi quem estava na sessão',
  (SELECT u.nome FROM ia_decisao d JOIN usuario u ON u.id = d.decidida_por WHERE d.funcao = 'IA-03'), 'Fiscal técnico (fictício)');
CALL pg_temp.espera_erro_com('mudar o desfecho depois de registrado', 'já foi registrado e não muda', ARRAY[
  $$UPDATE ia_decisao SET desfecho = 'rejeitada' WHERE funcao = 'IA-03'$$]);
RESET app.usuario_id;
CALL pg_temp.espera_erro_com('aceitar proposta sem pessoa na sessão', 'por uma pessoa identificada', ARRAY[
  $$UPDATE ia_decisao SET desfecho = 'aceita' WHERE funcao = 'IA-21'$$]);
-- descarte pelo sistema não tem pessoa
UPDATE ia_decisao SET desfecho = 'descartada' WHERE funcao = 'IA-21';
SELECT pg_temp.confere('descarte do sistema fica sem pessoa',
  (SELECT count(*) FROM ia_decisao WHERE funcao = 'IA-21' AND desfecho = 'descartada' AND decidida_por IS NULL), 1);

\echo
\echo '== Publicação e denúncia =='
SET app.usuario_id = :gestor;
INSERT INTO publicacao (id, alvo, contrato_id, documento, payload) VALUES
  ('e0e0e0e0-0000-0000-0008-000000000001', 'pncp', :c_bm, 'contrato', '{"numero": "052/2026"}');
CALL pg_temp.espera_erro_com('alterar o que foi mandado publicar', 'não se altera', ARRAY[
  $$UPDATE publicacao SET payload = '{"numero": "outro"}'$$]);
CALL pg_temp.espera_erro('confirmar publicação sem protocolo', ARRAY[$$UPDATE publicacao SET status = 'confirmada'$$]);
UPDATE publicacao SET status = 'enviada';
UPDATE publicacao SET status = 'confirmada', protocolo = 'PNCP-FICTICIO-0001';
CALL pg_temp.espera_erro_com('mexer em publicação confirmada', 'confirmada não muda', ARRAY[
  $$UPDATE publicacao SET status = 'falhou'$$]);
CALL pg_temp.espera_erro_com('apagar publicação', 'permission denied', ARRAY[$$DELETE FROM publicacao$$]);
RESET app.usuario_id;
INSERT INTO denuncia (canal, texto) VALUES ('portal', 'Obra parada há duas semanas');
CALL pg_temp.espera_erro_com('alterar o texto da denúncia', 'não se altera', ARRAY[$$UPDATE denuncia SET texto = 'x'$$]);
UPDATE denuncia SET status = 'em_analise';
SELECT pg_temp.confere_vazio('coluna que identifique quem denunciou', $$
  SELECT column_name FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'denuncia'
     AND column_name ~ '(nome|cpf|email|telefone|contato|denunciante)'$$);

RESET ROLE;
