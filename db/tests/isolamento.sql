-- Dois municípios fictícios no mesmo banco não se enxergam nem se alteram.
-- Tudo o que a aplicação faria é feito aqui como app_rw, o papel que ela usa.
\set a '''aaaaaaaa-0000-0000-0000-00000000000a'''
\set b '''bbbbbbbb-0000-0000-0000-00000000000b'''

-- Quem cadastra município é a instalação, não a aplicação. CNPJs com dígito inválido, de propósito.
INSERT INTO tenant (id, razao_social, cnpj) VALUES
  (:a, 'Município de Exemplo',       '00000000000001'),
  (:b, 'Município de Outro Exemplo', '00000000000002');

-- Mesmos cadastros nos dois: órgão, obra, contrato, planilha de um serviço e uma medição.
CREATE PROCEDURE pg_temp.cria_obra(p_tenant uuid, p_nome text) LANGUAGE plpgsql AS $$
DECLARE v_orgao uuid; v_obra uuid; v_ctr uuid; v_rev uuid; v_ic_grupo uuid; v_ic_serv uuid; v_grupo uuid; v_med uuid;
BEGIN
  PERFORM set_config('app.tenant_id', p_tenant::text, false);
  INSERT INTO orgao (nome, cnpj, esfera, uf, municipio)
    VALUES ('Secretaria de Obras', '00000000000003', 'municipal', 'PR', p_nome) RETURNING id INTO v_orgao;
  INSERT INTO obra (nome, municipio, uf) VALUES ('Reforma da praça', p_nome, 'PR') RETURNING id INTO v_obra;
  INSERT INTO contrato (obra_id, orgao_id, numero, processo_licitatorio, objeto, regime_execucao, data_assinatura,
                        data_base_orcamento, prazo_execucao_dias, vigencia_fim, valor_inicial, valor_orcamento_base,
                        bdi_percentual)
    VALUES (v_obra, v_orgao, '001/2026', 'Concorrência nº 01/2026', 'Reforma da praça', 'empreitada_preco_unitario',
            '2026-01-05', '2025-10-01', 90, '2026-06-30', 1000.00, 1100.00, 25)
    RETURNING id INTO v_ctr;
  INSERT INTO revisao_orcamento (contrato_id, numero, origem) VALUES (v_ctr, 0, 'importacao') RETURNING id INTO v_rev;
  INSERT INTO item_contratual (contrato_id) VALUES (v_ctr) RETURNING id INTO v_ic_grupo;
  INSERT INTO item_contratual (contrato_id) VALUES (v_ctr) RETURNING id INTO v_ic_serv;
  INSERT INTO item_revisao (revisao_id, item_contratual_id, parent_id, ordem, codigo_eap, tipo, descricao)
    VALUES (v_rev, v_ic_grupo, NULL, 1, '1', 'grupo', 'PISO') RETURNING id INTO v_grupo;
  INSERT INTO item_revisao (revisao_id, item_contratual_id, parent_id, ordem, codigo_eap, tipo, descricao,
                            unidade, quantidade, preco_unitario)
    VALUES (v_rev, v_ic_serv, v_grupo, 1, '1.1', 'servico', 'Piso intertravado', 'm²', 10, 100.00);
  UPDATE revisao_orcamento SET status = 'vigente', data_vigencia = DATE '2026-01-05' WHERE id = v_rev;
  INSERT INTO medicao (contrato_id, numero, revisao_id, periodo_inicio, periodo_fim)
    VALUES (v_ctr, 1, v_rev, '2026-02-01', '2026-02-28') RETURNING id INTO v_med;
  INSERT INTO medicao_item (medicao_id, item_contratual_id, quantidade, valor) VALUES (v_med, v_ic_serv, 4, 0);
  INSERT INTO outbox (agregado, agregado_id, evento, payload) VALUES ('medicao', v_med, 'MedicaoAberta', '{}');
END $$;

-- Tabelas em que o papel corrente enxerga linha de outro município (tenant nulo é base pública).
CREATE FUNCTION pg_temp.tabelas_com_linha_alheia(p_tenant uuid) RETURNS SETOF text LANGUAGE plpgsql AS $$
DECLARE t text; n bigint;
BEGIN
  FOR t IN SELECT table_name FROM information_schema.columns
            WHERE table_schema = 'public' AND column_name = 'tenant_id'
              AND table_name IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') LOOP
    EXECUTE format('SELECT count(*) FROM %I WHERE tenant_id IS NOT NULL AND tenant_id IS DISTINCT FROM $1', t)
      INTO n USING p_tenant;
    IF n > 0 THEN RETURN NEXT t || ' (' || n || ')'; END IF;
  END LOOP;
END $$;

-- Total de linhas que o papel corrente enxerga, somando todas as tabelas com tenant_id.
CREATE FUNCTION pg_temp.linhas_visiveis() RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE t text; n bigint; total bigint := 0;
BEGIN
  FOR t IN SELECT table_name FROM information_schema.columns
            WHERE table_schema = 'public' AND column_name = 'tenant_id'
              AND table_name IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') LOOP
    EXECUTE format('SELECT count(*) FROM %I', t) INTO n;
    total := total + n;
  END LOOP;
  RETURN total;
END $$;

SET ROLE app_rw;
SET app.usuario = 'teste.isolamento';
CALL pg_temp.cria_obra(:a, 'Exemplo');
CALL pg_temp.cria_obra(:b, 'Outro Exemplo');
RESET ROLE;

-- Ids do município B, lidos como dono, para tentar alcançá-los a partir do A.
SELECT id AS obra_b     FROM obra     WHERE tenant_id = :b \gset
SELECT id AS contrato_b FROM contrato WHERE tenant_id = :b \gset
SELECT id AS medicao_b  FROM medicao  WHERE tenant_id = :b \gset
SELECT pg_temp.confere('o dono das tabelas enxerga os contratos dos dois municípios',
  (SELECT count(DISTINCT tenant_id) FROM contrato WHERE tenant_id IN (:a, :b)), 2);

SET ROLE app_rw;

\echo
\echo '== Município A só enxerga o que é dele =='
SET app.tenant_id = :a;
SELECT pg_temp.confere_vazio('A: tabela com linha de outro município',
  format('SELECT * FROM pg_temp.tabelas_com_linha_alheia(%L)', :a));
SELECT pg_temp.confere('A: órgãos', (SELECT count(*) FROM orgao), 1);
SELECT pg_temp.confere('A: obras', (SELECT count(*) FROM obra), 1);
SELECT pg_temp.confere('A: contratos', (SELECT count(*) FROM contrato), 1);
SELECT pg_temp.confere('A: revisões', (SELECT count(*) FROM revisao_orcamento), 1);
SELECT pg_temp.confere('A: itens da planilha', (SELECT count(*) FROM item_revisao), 2);
SELECT pg_temp.confere('A: medições', (SELECT count(*) FROM medicao), 1);
SELECT pg_temp.confere('A: valor medido, 4 × 100,00', (SELECT sum(valor) FROM medicao_item), 400.00);
SELECT pg_temp.confere('A: linhas na visão de situação do contrato', (SELECT count(*) FROM vw_contrato_situacao), 1);
SELECT pg_temp.confere_texto('A: a trilha de auditoria registrou o que a aplicação gravou',
  (SELECT string_agg(DISTINCT usuario, ',') FROM auditoria), 'teste.isolamento');
SELECT pg_temp.confere('A: avisos na fila de saída', (SELECT count(*) FROM outbox), 1);
SELECT pg_temp.confere('A: boletim da medição do município B', (SELECT count(*) FROM fn_boletim_medicao(:'medicao_b')), 0);
SELECT pg_temp.confere('A: limites de aditivo do contrato do município B',
  (SELECT count(*) FROM fn_limites_aditivos(:'contrato_b')), 0);
SELECT pg_temp.confere('A: município B no cadastro pelo id', (SELECT count(*) FROM obra WHERE id = :'obra_b'), 0);

\echo
\echo '== Município A não grava nem altera o que é do B =='
CALL pg_temp.espera_erro('A gravar linha com o tenant do B', ARRAY[
  format($$INSERT INTO obra (tenant_id, nome, municipio, uf) VALUES (%L, 'Intrusa', 'X', 'PR')$$, :b)]);
CALL pg_temp.espera_erro('A transferir uma linha sua para o B', ARRAY[
  format($$UPDATE obra SET tenant_id = %L$$, :b)]);
-- Alterar e apagar o que não se enxerga não dá erro: simplesmente não atinge linha nenhuma.
WITH x AS (UPDATE obra SET nome = 'Invadida' WHERE id = :'obra_b' RETURNING 1)
SELECT pg_temp.confere('A: linhas do B alteradas', (SELECT count(*) FROM x), 0);
WITH x AS (DELETE FROM medicao_item WHERE medicao_id = :'medicao_b' RETURNING 1)
SELECT pg_temp.confere('A: linhas do B apagadas', (SELECT count(*) FROM x), 0);

\echo
\echo '== Município B continua inteiro e também só enxerga o que é dele =='
SET app.tenant_id = :b;
SELECT pg_temp.confere_vazio('B: tabela com linha de outro município',
  format('SELECT * FROM pg_temp.tabelas_com_linha_alheia(%L)', :b));
SELECT pg_temp.confere('B: contratos', (SELECT count(*) FROM contrato), 1);
SELECT pg_temp.confere_texto('B: nome da obra, que o A tentou alterar', (SELECT nome FROM obra), 'Reforma da praça');
SELECT pg_temp.confere('B: valor medido, que o A tentou apagar', (SELECT sum(valor) FROM medicao_item), 400.00);

\echo
\echo '== Sessão sem município não enxerga nem grava nada =='
RESET app.tenant_id;
SELECT pg_temp.confere('sem tenant: linhas visíveis em todas as tabelas', pg_temp.linhas_visiveis(), 0);
SELECT pg_temp.confere('sem tenant: linhas na visão de situação do contrato', (SELECT count(*) FROM vw_contrato_situacao), 0);
CALL pg_temp.espera_erro('gravar sem tenant na sessão', ARRAY[
  $$INSERT INTO obra (nome, municipio, uf) VALUES ('Sem dono', 'X', 'PR')$$]);
CALL pg_temp.espera_erro('ler com tenant inválido na sessão', ARRAY[
  $$SET app.tenant_id = 'isto não é um id'$$, $$SELECT count(*) FROM contrato$$]);

\echo
\echo '== O que a aplicação não pode fazer, em município nenhum =='
SET app.tenant_id = :a;
CALL pg_temp.espera_erro('alterar a trilha de auditoria', ARRAY[$$UPDATE auditoria SET usuario = 'outro'$$]);
CALL pg_temp.espera_erro('apagar a trilha de auditoria', ARRAY[$$DELETE FROM auditoria$$]);
CALL pg_temp.espera_erro('esvaziar uma tabela', ARRAY[$$TRUNCATE medicao_glosa$$]);
CALL pg_temp.espera_erro('cadastrar município', ARRAY[
  $$INSERT INTO tenant (razao_social, cnpj) VALUES ('Município Intruso', '00000000000009')$$]);
CALL pg_temp.espera_erro('alterar o cadastro de um município', ARRAY[$$UPDATE tenant SET razao_social = 'Outro nome'$$]);
CALL pg_temp.espera_erro('desligar a RLS de uma tabela', ARRAY[$$ALTER TABLE contrato DISABLE ROW LEVEL SECURITY$$]);
CALL pg_temp.espera_erro('ler com row_security desligado', ARRAY[
  $$SET row_security = off$$, $$SELECT count(*) FROM contrato$$]);
CALL pg_temp.espera_erro('criar tabela', ARRAY[$$CREATE TABLE intrusa (id int)$$]);
CALL pg_temp.espera_erro('desligar um gatilho de regra', ARRAY[$$ALTER TABLE medicao DISABLE TRIGGER trg_medicao_guard$$]);
CALL pg_temp.espera_erro('trocar uma função de regra', ARRAY[
  $$CREATE OR REPLACE FUNCTION fn_medicao_guard() RETURNS trigger LANGUAGE plpgsql AS 'BEGIN RETURN NEW; END'$$]);
CALL pg_temp.espera_erro('ler o registro de migrações', ARRAY[$$SELECT count(*) FROM migracao_aplicada$$]);

RESET ROLE;
