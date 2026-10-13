-- =============================================================================
-- Prumo · seed de demonstração · TUDO FICTÍCIO
--
-- Município de Exemplo, com dois contratos:
--   045/2026  Ampliação da Escola Municipal      medido por EVENTOS      critério: arredondar
--   052/2026  Pavimentação da Rua das Acácias    medido por QUANTIDADE   critério: truncar
--
-- O contrato 045/2026 tem a mesma planilha da prévia de desktop (crates/demonstracao):
-- 6 eventos, total R$ 164.039,34. O teste de paridade confere linha a linha.
-- Nenhum nome, CNPJ, preço ou quantidade vem de obra, empresa ou pessoa real.
-- Os CNPJs têm dígito verificador inválido de propósito.
--
-- Roda como dono das tabelas, depois das migrações, numa transação só:
--   psql -1 -v ON_ERROR_STOP=1 -f db/seed/exemplo.sql
-- SQL puro, sem comando do psql, para poder ser carregado por outro programa.
-- Os valores (total de item, de evento e de revisão) não estão escritos aqui: o banco calcula.
-- Até a migração 0007 a medição por eventos se chama 'ple' no banco, nome herdado da referência.
-- =============================================================================

INSERT INTO tenant (id, razao_social, cnpj) VALUES
  ('e0e0e0e0-0000-0000-0000-000000000001', 'Município de Exemplo', '00000000000101');

SELECT set_config('app.tenant_id', 'e0e0e0e0-0000-0000-0000-000000000001', false),
       set_config('app.usuario', 'seed.exemplo', false);

INSERT INTO orgao (id, nome, cnpj, esfera, uf, municipio) VALUES
  ('e0e0e0e0-0000-0000-0000-0000000000a1', 'Secretaria Municipal de Obras de Exemplo', '00000000000102',
   'municipal', 'PR', 'Exemplo');

INSERT INTO obra (id, nome, municipio, uf) VALUES
  ('e0e0e0e0-0000-0000-0000-0000000000b1', 'Ampliação da Escola Municipal',   'Exemplo', 'PR'),
  ('e0e0e0e0-0000-0000-0000-0000000000b2', 'Pavimentação da Rua das Acácias', 'Exemplo', 'PR');

INSERT INTO contrato (id, obra_id, orgao_id, numero, processo_licitatorio, objeto, regime_execucao,
                      data_assinatura, data_base_orcamento, prazo_execucao_dias, vigencia_fim, data_inicio_obra,
                      valor_inicial, valor_orcamento_base, bdi_percentual, criterio_arredondamento,
                      forma_acompanhamento)
VALUES
  ('e0e0e0e0-0000-0000-0000-0000000000c1', 'e0e0e0e0-0000-0000-0000-0000000000b1',
   'e0e0e0e0-0000-0000-0000-0000000000a1', '045/2026', 'Concorrência Eletrônica nº 12/2026',
   'Ampliação da Escola Municipal', 'empreitada_preco_global',
   '2026-09-14', '2026-05-01', 215, '2027-07-30', '2026-09-28',
   164039.34, 178000.00, 24.50, 'arredondar', 'ple'),
  ('e0e0e0e0-0000-0000-0000-0000000000c2', 'e0e0e0e0-0000-0000-0000-0000000000b2',
   'e0e0e0e0-0000-0000-0000-0000000000a1', '052/2026', 'Concorrência Eletrônica nº 15/2026',
   'Pavimentação da Rua das Acácias', 'empreitada_preco_unitario',
   '2026-10-05', '2026-06-01', 120, '2027-04-30', '2026-10-13',
   136595.63, 149800.00, 22.00, 'truncar', 'bm');

-- Retenção ilustrativa, a mesma da prévia. Alíquota e base reais vêm do contrato de cada obra.
INSERT INTO contrato_retencao (contrato_id, tipo, aliquota, base_percentual) VALUES
  ('e0e0e0e0-0000-0000-0000-0000000000c1', 'INSS', 11, 100);

-- -----------------------------------------------------------------------------
-- Frente e agrupadores do contrato por eventos. Evento = agrupador × frente.
-- -----------------------------------------------------------------------------
INSERT INTO frente_obra (id, contrato_id, ordem, nome) VALUES
  ('e0e0e0e0-0000-0000-0000-0000000000f1', 'e0e0e0e0-0000-0000-0000-0000000000c1', 1, 'Térreo');

INSERT INTO agrupador_evento (id, contrato_id, numero, titulo)
SELECT md5('agrupador:c1:' || numero)::uuid, 'e0e0e0e0-0000-0000-0000-0000000000c1', numero, titulo
  FROM (VALUES (1, 'Fundações'), (2, 'Estrutura: pilares'), (3, 'Alvenaria'), (4, 'Cobertura'),
               (5, 'Instalações e revestimentos'), (6, 'Pintura e limpeza final')) AS a(numero, titulo);

-- -----------------------------------------------------------------------------
-- Planilhas (Rev. 0) dos dois contratos. Agrupador só existe no contrato por eventos.
-- -----------------------------------------------------------------------------
INSERT INTO revisao_orcamento (id, contrato_id, numero, origem) VALUES
  ('e0e0e0e0-0000-0000-0000-0000000000d1', 'e0e0e0e0-0000-0000-0000-0000000000c1', 0, 'importacao'),
  ('e0e0e0e0-0000-0000-0000-0000000000d2', 'e0e0e0e0-0000-0000-0000-0000000000c2', 0, 'importacao');

CREATE TEMP TABLE seed_planilha (
  contrato text, codigo text, descricao text, unidade text, quantidade numeric, preco numeric, agrupador int);

INSERT INTO seed_planilha VALUES
  ('c1', '1',   'FUNDAÇÕES',                            NULL,     NULL,    NULL, NULL),
  ('c1', '1.1', 'Escavação manual de vala',             'm³',    86.00,   68.45,    1),
  ('c1', '1.2', 'Armadura CA-50',                       'kg',   920.00,    9.84,    1),
  ('c1', '1.3', 'Concreto fck 25 MPa',                  'm³',    24.50,  785.40,    1),
  ('c1', '2',   'ESTRUTURA: PILARES',                   NULL,     NULL,    NULL, NULL),
  ('c1', '2.1', 'Fôrma de pilar',                       'm²',    96.00,   62.30,    2),
  ('c1', '2.2', 'Armadura CA-50',                       'kg',  1150.00,    9.84,    2),
  ('c1', '2.3', 'Concreto fck 25 MPa',                  'm³',    11.10,  785.40,    2),
  ('c1', '3',   'ALVENARIA',                            NULL,     NULL,    NULL, NULL),
  ('c1', '3.1', 'Alvenaria de vedação, bloco cerâmico', 'm²',   160.00,   89.15,    3),
  ('c1', '3.2', 'Chapisco em alvenaria',                'm²',   320.00,    7.43,    3),
  ('c1', '4',   'COBERTURA',                            NULL,     NULL,    NULL, NULL),
  ('c1', '4.1', 'Estrutura de madeira para telhado',    'm²',   280.00,   74.50,    4),
  ('c1', '4.2', 'Telhamento com telha cerâmica',        'm²',   280.00,   64.50,    4),
  ('c1', '5',   'INSTALAÇÕES E REVESTIMENTOS',          NULL,     NULL,    NULL, NULL),
  ('c1', '5.1', 'Ponto de instalação elétrica',         'un',    64.00,  142.80,    5),
  ('c1', '5.2', 'Ponto de instalação hidrossanitária',  'un',    38.00,  168.50,    5),
  ('c1', '5.3', 'Reboco',                               'm²',   320.00,   31.20,    5),
  ('c1', '5.4', 'Piso cerâmico',                        'm²',   210.00,   58.90,    5),
  ('c1', '6',   'PINTURA E LIMPEZA FINAL',              NULL,     NULL,    NULL, NULL),
  ('c1', '6.1', 'Pintura acrílica',                     'm²',   640.00,   14.85,    6),
  ('c1', '6.2', 'Limpeza final da obra',                'm²',   210.00,    4.20,    6),
  ('c2', '1',   'SERVIÇOS PRELIMINARES',                NULL,     NULL,    NULL, NULL),
  ('c2', '1.1', 'Placa de obra',                        'm²',     4.50,  412.37, NULL),
  ('c2', '1.2', 'Mobilização e desmobilização',         'un',     1.00, 3850.00, NULL),
  ('c2', '2',   'TERRAPLENAGEM',                        NULL,     NULL,    NULL, NULL),
  ('c2', '2.1', 'Regularização do subleito',            'm²',  1260.00,    2.87, NULL),
  ('c2', '2.2', 'Escavação e carga de material de 1ª categoria', 'm³', 378.50, 9.43, NULL),
  ('c2', '3',   'PAVIMENTAÇÃO',                         NULL,     NULL,    NULL, NULL),
  ('c2', '3.1', 'Base de brita graduada',               'm³',   189.25,  142.55, NULL),
  ('c2', '3.2', 'Imprimação',                           'm²',  1260.00,    6.18, NULL),
  ('c2', '3.3', 'Concreto asfáltico usinado a quente',  't',    151.20,  468.90, NULL),
  ('c2', '4',   'DRENAGEM E SINALIZAÇÃO',               NULL,     NULL,    NULL, NULL),
  ('c2', '4.1', 'Meio-fio de concreto',                 'm',    420.00,   38.75, NULL),
  ('c2', '4.2', 'Sinalização horizontal',               'm²',    63.35,   27.90, NULL);

-- Identidade de cada item, estável entre revisões. Os ids saem do código do item, para o
-- seed dar sempre os mesmos.
INSERT INTO item_contratual (id, contrato_id)
SELECT md5('item:' || contrato || ':' || codigo)::uuid,
       ('e0e0e0e0-0000-0000-0000-0000000000' || contrato)::uuid
  FROM seed_planilha;

-- Grupos primeiro, serviços depois: o serviço precisa do grupo já gravado.
INSERT INTO item_revisao (id, revisao_id, item_contratual_id, parent_id, ordem, codigo_eap, tipo, descricao)
SELECT md5('rev0:' || contrato || ':' || codigo)::uuid,
       ('e0e0e0e0-0000-0000-0000-0000000000d' || right(contrato, 1))::uuid,
       md5('item:' || contrato || ':' || codigo)::uuid, NULL, codigo::int, codigo, 'grupo', descricao
  FROM seed_planilha
 WHERE unidade IS NULL;

INSERT INTO item_revisao (id, revisao_id, item_contratual_id, parent_id, ordem, codigo_eap, tipo, descricao,
                          unidade, quantidade, preco_unitario, fonte, agrupador_evento_id)
SELECT md5('rev0:' || contrato || ':' || codigo)::uuid,
       ('e0e0e0e0-0000-0000-0000-0000000000d' || right(contrato, 1))::uuid,
       md5('item:' || contrato || ':' || codigo)::uuid,
       md5('rev0:' || contrato || ':' || split_part(codigo, '.', 1))::uuid,
       split_part(codigo, '.', 2)::int, codigo, 'servico', descricao, unidade, quantidade, preco, 'PROPRIA',
       CASE WHEN agrupador IS NOT NULL THEN md5('agrupador:' || contrato || ':' || agrupador)::uuid END
  FROM seed_planilha
 WHERE unidade IS NOT NULL;

-- Cada serviço do contrato por eventos cai inteiro na frente Térreo.
INSERT INTO item_frente (item_revisao_id, frente_id, quantidade)
SELECT md5('rev0:c1:' || codigo)::uuid, 'e0e0e0e0-0000-0000-0000-0000000000f1', quantidade
  FROM seed_planilha
 WHERE contrato = 'c1' AND unidade IS NOT NULL;

DROP TABLE seed_planilha;

-- Ao ficar vigente, o banco soma a planilha, confere com o valor do contrato e,
-- no contrato por eventos, calcula o valor de cada evento.
UPDATE revisao_orcamento SET status = 'vigente', data_vigencia = DATE '2026-09-14'
 WHERE id = 'e0e0e0e0-0000-0000-0000-0000000000d1';
UPDATE revisao_orcamento SET status = 'vigente', data_vigencia = DATE '2026-10-05'
 WHERE id = 'e0e0e0e0-0000-0000-0000-0000000000d2';

-- Mês previsto de conclusão de cada evento, contado do início da obra (setembro de 2026 = 1).
UPDATE evento e SET periodo_previsto = p.periodo
  FROM agrupador_evento a,
       (VALUES (1, 2), (2, 3), (3, 4), (4, 5), (5, 7), (6, 8)) AS p(numero, periodo)
 WHERE a.id = e.agrupador_id AND a.numero = p.numero
   AND e.revisao_id = 'e0e0e0e0-0000-0000-0000-0000000000d1';
