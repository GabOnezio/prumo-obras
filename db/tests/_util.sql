-- Utilitários das suítes de teste do banco. São temporários: somem ao fim da sessão.
\set ON_ERROR_STOP on
\pset footer off
SET client_min_messages = notice;

-- Executa comandos e exige que algum deles seja bloqueado.
-- Mesmo comportamento do utilitário de db/reference/seed_e_testes.sql.
CREATE OR REPLACE PROCEDURE pg_temp.espera_erro(p_desc text, p_cmds text[])
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

-- Exige que um número seja exatamente o esperado (ao centavo).
-- É função, e não procedimento, porque o PostgreSQL não aceita subconsulta em argumento de CALL.
CREATE OR REPLACE FUNCTION pg_temp.confere(p_desc text, p_obtido numeric, p_esperado numeric)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_obtido IS DISTINCT FROM p_esperado THEN
    RAISE EXCEPTION 'TESTE FALHOU: "%" deu %, esperado %', p_desc, p_obtido, p_esperado;
  END IF;
  RAISE NOTICE 'OK, confere | % = %', p_desc, p_esperado;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.confere_texto(p_desc text, p_obtido text, p_esperado text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_obtido IS DISTINCT FROM p_esperado THEN
    RAISE EXCEPTION 'TESTE FALHOU: "%" deu "%", esperado "%"', p_desc, p_obtido, p_esperado;
  END IF;
  RAISE NOTICE 'OK, confere | % = %', p_desc, p_esperado;
END $$;

-- Exige que uma consulta não devolva linha nenhuma; se devolver, mostra quais.
-- Serve para as regras do tipo "nenhuma tabela pode estar sem proteção".
CREATE OR REPLACE FUNCTION pg_temp.confere_vazio(p_desc text, p_consulta text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v text;
BEGIN
  EXECUTE format('SELECT string_agg(x::text, '', '' ORDER BY x::text) FROM (%s) q(x)', p_consulta) INTO v;
  IF v IS NOT NULL THEN
    RAISE EXCEPTION 'TESTE FALHOU: "%" encontrou: %', p_desc, v;
  END IF;
  RAISE NOTICE 'OK, confere | % = nenhum', p_desc;
END $$;
