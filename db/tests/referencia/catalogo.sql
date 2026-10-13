-- Impressão do catálogo: uma linha por fato do schema public, em ordem.
-- O teste de porte roda este arquivo no schema de referência e na migração 0001 e exige
-- que as duas saídas sejam iguais, tirando o que a 0001 removeu de propósito.
-- O segundo campo é sempre o objeto dono do fato (tabela, visão, função ou tipo).
-- Objetos das extensões (ltree, btree_gist) ficam de fora.
SELECT linha FROM (
  SELECT format('coluna|%s|%s|%s|%s|%s|padrão: %s|gerada: %s', c.relname, a.attnum, a.attname,
                format_type(a.atttypid, a.atttypmod), CASE WHEN a.attnotnull THEN 'not null' ELSE 'null' END,
                coalesce(pg_get_expr(d.adbin, d.adrelid), ''), a.attgenerated) AS linha
    FROM pg_attribute a
    JOIN pg_class c     ON c.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
   WHERE n.nspname = 'public' AND c.relkind = 'r' AND a.attnum > 0 AND NOT a.attisdropped
  UNION ALL
  SELECT format('restrição|%s|%s|%s', c.relname, k.conname, pg_get_constraintdef(k.oid))
    FROM pg_constraint k
    JOIN pg_class c     ON c.oid = k.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public'
  UNION ALL
  SELECT format('índice|%s|%s', tablename, indexdef) FROM pg_indexes WHERE schemaname = 'public'
  UNION ALL
  SELECT format('função|%s|%s|%s', p.proname, pg_get_function_identity_arguments(p.oid),
                md5(pg_get_functiondef(p.oid)))
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.prokind IN ('f', 'p')
     AND NOT EXISTS (SELECT FROM pg_depend x WHERE x.objid = p.oid AND x.deptype = 'e')
  UNION ALL
  SELECT format('gatilho|%s|%s|%s', c.relname, t.tgname, pg_get_triggerdef(t.oid))
    FROM pg_trigger t
    JOIN pg_class c     ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND NOT t.tgisinternal
  UNION ALL
  SELECT format('visão|%s|%s|%s', c.relname, array_to_string(c.reloptions, ','), md5(pg_get_viewdef(c.oid)))
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind = 'v'
  UNION ALL
  SELECT format('tipo|%s|%s', t.typname, string_agg(e.enumlabel, ',' ORDER BY e.enumsortorder))
    FROM pg_type t
    JOIN pg_enum e      ON e.enumtypid = t.oid
    JOIN pg_namespace n ON n.oid = t.typnamespace
   WHERE n.nspname = 'public'
   GROUP BY t.typname
  UNION ALL
  SELECT format('rls|%s|ligada: %s|forçada: %s', c.relname, c.relrowsecurity, c.relforcerowsecurity)
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind = 'r'
  UNION ALL
  SELECT format('política|%s|%s|%s|%s|%s|usa: %s|confere: %s', tablename, policyname, permissive, cmd,
                roles::text, coalesce(qual, ''), coalesce(with_check, ''))
    FROM pg_policies WHERE schemaname = 'public'
) fatos
ORDER BY linha COLLATE "C";
