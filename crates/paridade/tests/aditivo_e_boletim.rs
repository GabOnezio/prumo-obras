//! Aditivo e boletim de medição por quantidade: Rust × SQL, num contrato do começo ao fim.
//!
//! Cada contrato sorteado passa por: planilha (Rev. 0), medição 1, aditivo 1 (acréscimo,
//! supressão e item novo), limites simulados, homologação com a Rev. 1 calculada em Rust,
//! medição 2 e aditivo 2 simulado. Em cada passo o que o banco calculou é comparado com o
//! que o Rust calculou: `fator_art127`, `fn_aditivo_item_guard`, `fn_limites_aditivos`,
//! `fn_medicao_item_guard`, `fn_boletim_medicao` e o total de cada revisão.

mod comum;

use comum::{
    conectar, decimal, id, nome_no_banco, sql_das_pessoas, sql_de_aprovar, sql_de_enviar, Sorteio,
    EMPRESA_ALFA,
};
use postgres::Client;
use prumo_dominio::{
    aplicar_aditivo, boletim_de_medicao, fator_art127, limites_dos_aditivos, medir_por_quantidade,
    percentual_executado, preco_de_item_novo, CriterioArredondamento, Dinheiro, Historico,
    ItemDoAditivo, ItemId, ItemPlanilha, Limites, Medido, Operacao, Planilha, RegraDeLimites,
    ServicoNovo, SituacaoDosLimites, TipoItem,
};
use rust_decimal::Decimal;
use std::collections::{BTreeMap, BTreeSet};

const OBRA: &str = "e0e0e0e0-0000-0000-0000-0000000000b2";
const ORGAO: &str = "e0e0e0e0-0000-0000-0000-0000000000a1";
/// O banco de referência avisa a partir de 90% do teto.
const ATENCAO: i64 = 90;

fn grupo(n: u128, pai: Option<u128>, ordem: u32, codigo: &str) -> ItemPlanilha {
    ItemPlanilha {
        id: ItemId(n),
        pai: pai.map(ItemId),
        ordem,
        codigo_eap: codigo.into(),
        descricao: format!("GRUPO {codigo}"),
        tipo: TipoItem::Grupo,
    }
}

/// Três grupos, um subgrupo e nove serviços com quantidade e preço sorteados.
fn sortear_planilha(
    sorteio: &mut Sorteio,
    criterio: CriterioArredondamento,
    casas: u32,
) -> Planilha {
    let mut itens = vec![
        grupo(1, None, 1, "1"),
        grupo(2, None, 2, "2"),
        grupo(0x21, Some(2), 1, "2.1"),
        grupo(3, None, 3, "3"),
    ];
    let servicos = [
        (0x101, 1, 1, "1.1"),
        (0x102, 1, 2, "1.2"),
        (0x103, 1, 3, "1.3"),
        (0x104, 0x21, 1, "2.1.1"),
        (0x105, 0x21, 2, "2.1.2"),
        (0x106, 2, 2, "2.2"),
        (0x107, 3, 1, "3.1"),
        (0x108, 3, 2, "3.2"),
        (0x109, 3, 3, "3.3"),
    ];
    for (n, pai, ordem, codigo) in servicos {
        itens.push(ItemPlanilha {
            id: ItemId(n),
            pai: Some(ItemId(pai)),
            ordem,
            codigo_eap: codigo.into(),
            descricao: format!("Serviço {codigo}"),
            tipo: TipoItem::Servico {
                unidade: "un".into(),
                quantidade: sorteio.decimal(500, 4) + Decimal::ONE,
                preco_unitario: sorteio.decimal(900, casas) + Decimal::new(1, 2),
            },
        });
    }
    Planilha::nova(0, criterio, casas, itens).expect("planilha sorteada")
}

fn servicos(planilha: &Planilha) -> Vec<(ItemId, Decimal, Decimal)> {
    planilha
        .itens()
        .filter_map(|(item, _)| match &item.tipo {
            TipoItem::Servico {
                quantidade,
                preco_unitario,
                ..
            } => Some((item.id, *quantidade, *preco_unitario)),
            TipoItem::Grupo => None,
        })
        .collect()
}

fn n(item: ItemId) -> usize {
    item.0 as usize
}

/// Comandos que gravam os itens de uma revisão, na ordem da árvore.
fn sql_dos_itens(planilha: &Planilha, c: usize, revisao: &str) -> String {
    let tipo_do_id = 0x50 + planilha.numero();
    let mut sql = String::new();
    for (item, _) in planilha.itens() {
        let pai = item.pai.map_or("NULL".to_string(), |p| {
            format!("'{}'", id(tipo_do_id, c, n(p)))
        });
        let (tipo, colunas) = match &item.tipo {
            TipoItem::Grupo => ("grupo", "NULL, NULL, NULL".to_string()),
            TipoItem::Servico {
                unidade,
                quantidade,
                preco_unitario,
            } => (
                "servico",
                format!("'{unidade}', {quantidade}, {preco_unitario}"),
            ),
        };
        sql += &format!(
            "INSERT INTO item_revisao (id, revisao_id, item_contratual_id, parent_id, ordem, codigo_eap, tipo, descricao,
                                       unidade, quantidade, preco_unitario)
             VALUES ('{}', '{revisao}', '{}', {pai}, {}, '{}', '{tipo}', '{}', {colunas});",
            id(tipo_do_id, c, n(item.id)),
            id(4, c, n(item.id)),
            item.ordem,
            item.codigo_eap,
            item.descricao,
        );
    }
    sql
}

/// Sorteia uma medição dentro do saldo, calcula em Rust, grava e compara linha a linha.
fn medir(
    banco: &mut Client,
    sorteio: &mut Sorteio,
    planilha: &Planilha,
    ja_medido: &BTreeMap<ItemId, Medido>,
    c: usize,
    numero: usize,
    revisao: &str,
) -> BTreeMap<ItemId, Medido> {
    let medicao = id(8, c, numero);
    let mut no_rust = BTreeMap::new();
    let mut sql = format!(
        "INSERT INTO medicao (id, contrato_id, numero, revisao_id, periodo_inicio, periodo_fim)
         VALUES ('{medicao}', '{}', {numero}, '{revisao}', '2026-{mes:02}-01', '2026-{mes:02}-28');",
        id(1, c, 0),
        mes = 9 + numero,
    );
    for (item, contratada, _) in servicos(planilha) {
        let antes = ja_medido.get(&item).copied().unwrap_or_default().quantidade;
        let saldo = contratada - antes;
        // dois em cada três serviços entram, com 0% a 100% do saldo
        if sorteio.ate(3) == 0 || saldo.is_zero() {
            continue;
        }
        let quantidade =
            (saldo * Decimal::from(sorteio.ate(101)) / Decimal::ONE_HUNDRED).round_dp(4);
        if quantidade.is_zero() {
            continue;
        }
        let medido =
            medir_por_quantidade(planilha, item, quantidade, antes).expect("medição em Rust");
        no_rust.insert(item, medido);
        sql += &format!(
            "INSERT INTO medicao_item (medicao_id, item_contratual_id, quantidade, valor) VALUES ('{medicao}', '{}', {quantidade}, 0);",
            id(4, c, n(item)),
        );
    }
    sql += &sql_de_enviar(&medicao);
    sql += &sql_de_aprovar(&medicao);
    banco
        .batch_execute(&sql)
        .unwrap_or_else(|e| panic!("contrato {c}, medição {numero}: {e}"));

    let linhas = banco
        .query(
            "SELECT ir.codigo_eap, mi.valor::text
               FROM medicao_item mi
               JOIN medicao m       ON m.id = mi.medicao_id
               JOIN item_revisao ir ON ir.revisao_id = m.revisao_id AND ir.item_contratual_id = mi.item_contratual_id
              WHERE mi.medicao_id = $1::text::uuid",
            &[&medicao],
        )
        .expect("linhas da medição");
    assert_eq!(
        linhas.len(),
        no_rust.len(),
        "contrato {c}, medição {numero}"
    );
    for linha in &linhas {
        let codigo: &str = linha.get(0);
        let item = planilha
            .itens()
            .find(|(i, _)| i.codigo_eap == codigo)
            .expect("item da medição")
            .0
            .id;
        assert_eq!(
            no_rust[&item].valor.decimal(),
            decimal(linha.get(1)),
            "contrato {c}, medição {numero}, item {codigo}"
        );
    }
    let bruto = banco
        .query_one(
            "SELECT valor_bruto::text FROM medicao WHERE id = $1::text::uuid",
            &[&medicao],
        )
        .expect("valor bruto");
    let total = no_rust.values().fold(Dinheiro::ZERO, |s, m| s + m.valor);
    assert_eq!(
        total.decimal(),
        decimal(bruto.get(0)),
        "contrato {c}, medição {numero}: valor bruto"
    );
    no_rust
}

/// Compara o boletim do banco com o do Rust, linha a linha e coluna a coluna.
fn comparar_boletim(
    banco: &mut Client,
    planilha: &Planilha,
    anterior: &BTreeMap<ItemId, Medido>,
    atual: &BTreeMap<ItemId, Medido>,
    c: usize,
    numero: usize,
) -> usize {
    let no_rust = boletim_de_medicao(planilha, anterior, atual).expect("boletim em Rust");
    let no_sql = banco
        .query(
            "SELECT codigo_eap, nivel, unidade, qtd_contratada::text, preco_unitario::text, valor_contratado::text,
                    qtd_anterior::text, qtd_atual::text, qtd_acumulada::text, qtd_saldo::text,
                    valor_anterior::text, valor_atual::text, valor_acumulado::text, valor_saldo::text,
                    perc_acumulado::text
               FROM fn_boletim_medicao($1::text::uuid)",
            &[&id(8, c, numero)],
        )
        .expect("fn_boletim_medicao");
    assert_eq!(
        no_sql.len(),
        no_rust.len(),
        "contrato {c}, boletim {numero}: linhas"
    );
    let opcional =
        |linha: &postgres::Row, coluna: usize| linha.get::<_, Option<&str>>(coluna).map(decimal);
    for (sql, rust) in no_sql.iter().zip(&no_rust) {
        let onde = format!("contrato {c}, boletim {numero}, item {}", rust.codigo_eap);
        assert_eq!(sql.get::<_, &str>(0), rust.codigo_eap, "{onde}: ordem");
        assert_eq!(sql.get::<_, i32>(1) as u32, rust.nivel, "{onde}: nível");
        let q = rust.quantidades.as_ref();
        assert_eq!(
            sql.get::<_, Option<&str>>(2),
            q.map(|q| q.unidade.as_str()),
            "{onde}: unidade"
        );
        assert_eq!(
            opcional(sql, 3),
            q.map(|q| q.contratada),
            "{onde}: contratada"
        );
        assert_eq!(
            opcional(sql, 4),
            q.map(|q| q.preco_unitario),
            "{onde}: preço"
        );
        assert_eq!(
            opcional(sql, 6),
            q.map(|q| q.anterior),
            "{onde}: quantidade anterior"
        );
        assert_eq!(
            opcional(sql, 7),
            q.map(|q| q.atual),
            "{onde}: quantidade atual"
        );
        assert_eq!(
            opcional(sql, 8),
            q.map(|q| q.acumulada),
            "{onde}: quantidade acumulada"
        );
        assert_eq!(
            opcional(sql, 9),
            q.map(|q| q.saldo),
            "{onde}: saldo de quantidade"
        );
        assert_eq!(
            decimal(sql.get(5)),
            rust.valor_contratado.decimal(),
            "{onde}: contratado"
        );
        assert_eq!(
            decimal(sql.get(10)),
            rust.valor_anterior.decimal(),
            "{onde}: valor anterior"
        );
        assert_eq!(
            decimal(sql.get(11)),
            rust.valor_atual.decimal(),
            "{onde}: valor atual"
        );
        assert_eq!(
            decimal(sql.get(12)),
            rust.valor_acumulado.decimal(),
            "{onde}: valor acumulado"
        );
        assert_eq!(
            decimal(sql.get(13)),
            rust.valor_saldo.decimal(),
            "{onde}: saldo"
        );
        assert_eq!(
            opcional(sql, 14),
            rust.percentual_acumulado,
            "{onde}: % acumulado"
        );
    }
    no_rust.len()
}

/// Grava as linhas de um aditivo em rascunho e compara preço e valor de cada uma.
fn gravar_e_comparar_aditivo(
    banco: &mut Client,
    base: &Planilha,
    itens: &[ItemDoAditivo],
    calculados: &[prumo_dominio::ItemCalculado],
    c: usize,
    numero: usize,
    revisao_base: &str,
) {
    let (aditivo, contrato) = (id(9, c, numero), id(1, c, 0));
    let mut sql = format!(
        "INSERT INTO aditivo (id, contrato_id, numero, tipo, fundamento_legal, justificativa, revisao_base_id)
         VALUES ('{aditivo}', '{contrato}', {numero}, 'valor', 'Teste de paridade', 'Teste de paridade', '{revisao_base}');"
    );
    for (linha, calculado) in itens.iter().zip(calculados) {
        let item = id(4, c, n(linha.item));
        match &linha.novo {
            None => {
                // preço e valor ficam por conta do gatilho do banco
                sql += &format!(
                    "INSERT INTO aditivo_item (aditivo_id, item_contratual_id, operacao, quantidade_delta, preco_unitario, valor_delta)
                     VALUES ('{aditivo}', '{item}', '{}', {}, 0, 0);",
                    linha.operacao.nome(),
                    linha.quantidade,
                );
            }
            Some(novo) => {
                // item novo: o preço é o que o Rust calculou com o fator; o banco calcula o valor
                sql += &format!(
                    "INSERT INTO item_contratual (id, contrato_id) VALUES ('{item}', '{contrato}');
                     INSERT INTO aditivo_item (aditivo_id, item_contratual_id, operacao, quantidade_delta, preco_unitario, valor_delta,
                                               parent_item_contratual_id, codigo_eap, descricao, unidade, preco_referencia)
                     VALUES ('{aditivo}', '{item}', 'inclusao', {}, {}, 0, '{}', '{}', '{}', '{}', {});",
                    linha.quantidade,
                    calculado.preco_unitario,
                    id(4, c, n(novo.grupo)),
                    novo.codigo_eap,
                    novo.descricao,
                    novo.unidade,
                    novo.preco_de_referencia,
                );
            }
        }
    }
    banco
        .batch_execute(&sql)
        .unwrap_or_else(|e| panic!("contrato {c}, aditivo {numero}: {e}"));

    let no_sql: BTreeMap<String, (Decimal, Decimal)> = banco
        .query(
            "SELECT item_contratual_id::text, preco_unitario::text, valor_delta::text
               FROM aditivo_item WHERE aditivo_id = $1::text::uuid",
            &[&aditivo],
        )
        .expect("itens do aditivo")
        .iter()
        .map(|l| {
            (
                l.get::<_, String>(0),
                (decimal(l.get(1)), decimal(l.get(2))),
            )
        })
        .collect();
    assert_eq!(no_sql.len(), calculados.len());
    for calculado in calculados {
        let rotulo = base
            .item(calculado.item)
            .map_or("item novo".to_string(), |i| i.codigo_eap.clone());
        let (preco, valor) = no_sql[&id(4, c, n(calculado.item))];
        assert_eq!(
            calculado.preco_unitario, preco,
            "contrato {c}, aditivo {numero}, {rotulo}: preço"
        );
        assert_eq!(
            calculado.valor.decimal(),
            valor,
            "contrato {c}, aditivo {numero}, {rotulo}: valor"
        );
    }
}

/// Compara `fn_limites_aditivos` com o Rust e devolve a situação.
fn comparar_limites(
    banco: &mut Client,
    no_rust: &Limites,
    c: usize,
    simulando: Option<usize>,
) -> SituacaoDosLimites {
    let simular = simulando.map(|numero| id(9, c, numero));
    let l = banco
        .query_one(
            "SELECT valor_inicial::text, acrescimos::text, supressoes::text, restabelecimentos::text,
                    perc_acrescimos::text, perc_supressoes::text, limite_acrescimo::text, limite_supressao::text,
                    situacao
               FROM fn_limites_aditivos($1::text::uuid, $2::text::uuid)",
            &[&id(1, c, 0), &simular],
        )
        .expect("fn_limites_aditivos");
    let onde = format!("contrato {c}, limites (simulando {simulando:?})");
    assert_eq!(
        decimal(l.get(0)),
        no_rust.valor_inicial.decimal(),
        "{onde}: valor inicial"
    );
    assert_eq!(
        decimal(l.get(1)),
        no_rust.acrescimos.decimal(),
        "{onde}: acréscimos"
    );
    assert_eq!(
        decimal(l.get(2)),
        no_rust.supressoes.decimal(),
        "{onde}: supressões"
    );
    assert_eq!(
        decimal(l.get(3)),
        no_rust.restabelecimentos.decimal(),
        "{onde}: restabelecimentos"
    );
    assert_eq!(
        decimal(l.get(4)),
        no_rust.percentual_de_acrescimos,
        "{onde}: % de acréscimos"
    );
    assert_eq!(
        decimal(l.get(5)),
        no_rust.percentual_de_supressoes,
        "{onde}: % de supressões"
    );
    assert_eq!(
        decimal(l.get(6)),
        no_rust.regra.limite_de_acrescimos,
        "{onde}: teto de acréscimos"
    );
    assert_eq!(
        decimal(l.get(7)),
        no_rust.regra.limite_de_supressoes,
        "{onde}: teto de supressões"
    );
    let no_sql = match l.get::<_, &str>(8) {
        "OK" => SituacaoDosLimites::Dentro,
        "ATENÇÃO: acima de 90% do limite" => SituacaoDosLimites::Atencao,
        "EXCEDE LIMITE LEGAL" => SituacaoDosLimites::Excede,
        outra => panic!("{onde}: situação desconhecida no banco: {outra}"),
    };
    assert_eq!(no_sql, no_rust.situacao, "{onde}: situação");
    no_sql
}

fn somar(a: &BTreeMap<ItemId, Medido>, b: &BTreeMap<ItemId, Medido>) -> BTreeMap<ItemId, Medido> {
    let mut soma = a.clone();
    for (item, m) in b {
        let linha = soma.entry(*item).or_default();
        linha.quantidade += m.quantidade;
        linha.valor = linha.valor + m.valor;
    }
    soma
}

fn quantidades(medido: &BTreeMap<ItemId, Medido>) -> BTreeMap<ItemId, Decimal> {
    medido
        .iter()
        .map(|(item, m)| (*item, m.quantidade))
        .collect()
}

fn valores(itens: &[prumo_dominio::ItemCalculado]) -> Vec<(Operacao, Dinheiro)> {
    itens.iter().map(|i| (i.operacao, i.valor)).collect()
}

#[test]
#[ignore = "precisa do banco: rode scripts/db-test.sh paridade"]
fn aditivo_e_boletim_dao_os_mesmos_numeros_no_rust_e_no_sql() {
    const CONTRATOS: usize = 12;
    let mut banco = conectar();
    let mut sorteio = Sorteio::novo(0x5052_554D_4F00_0003);
    let mut situacoes = BTreeSet::new();
    let (mut linhas_de_boletim, mut itens_de_aditivo, mut revisoes_diferentes) = (0, 0, 0);

    for c in 100..100 + CONTRATOS {
        let criterio = if c % 2 == 0 {
            CriterioArredondamento::Truncar
        } else {
            CriterioArredondamento::Arredondar
        };
        let casas = if c % 3 == 0 { 4 } else { 2 };
        let reforma = c % 4 == 0;
        let rev0 = sortear_planilha(&mut sorteio, criterio, casas);
        let valor_inicial = rev0.valor_total().expect("total da Rev. 0");
        // orçamento-base de 100% a 130% da proposta
        let orcamento_base = Dinheiro::de_centavos(
            (valor_inicial.decimal().mantissa() * (100 + sorteio.ate(31) as i128) / 100) as i64,
        );
        let fator = fator_art127(valor_inicial, orcamento_base).expect("fator");
        let regra = RegraDeLimites::do_art_125(reforma, Decimal::from(ATENCAO));

        // --- contrato e Rev. 0 ---
        let (contrato, revisao_0, revisao_1) = (id(1, c, 0), id(2, c, 0), id(2, c, 1));
        let mut sql = format!(
            "INSERT INTO contrato (id, obra_id, orgao_id, numero, processo_licitatorio, objeto, regime_execucao,
                                   data_assinatura, data_base_orcamento, prazo_execucao_dias, vigencia_fim,
                                   valor_inicial, valor_orcamento_base, bdi_percentual, reforma,
                                   criterio_arredondamento, casas_decimais_preco, forma_acompanhamento, empresa_id)
             VALUES ('{contrato}', '{OBRA}', '{ORGAO}', 'PARIDADE-BM-{c}', 'Teste de paridade', 'Contrato sorteado',
                     'empreitada_preco_unitario', '2026-09-14', '2026-05-01', 120, '2027-04-30',
                     {}, {}, 0, {reforma}, '{}', {casas}, 'bm', '{EMPRESA_ALFA}');
             INSERT INTO revisao_orcamento (id, contrato_id, numero, origem) VALUES ('{revisao_0}', '{contrato}', 0, 'importacao');",
            valor_inicial.decimal(),
            orcamento_base.decimal(),
            nome_no_banco(criterio),
        );
        for (item, _) in rev0.itens() {
            sql += &format!(
                "INSERT INTO item_contratual (id, contrato_id) VALUES ('{}', '{contrato}');",
                id(4, c, n(item.id))
            );
        }
        sql += &sql_dos_itens(&rev0, c, &revisao_0);
        sql += &format!("UPDATE revisao_orcamento SET status = 'vigente', data_vigencia = DATE '2026-09-14' WHERE id = '{revisao_0}';");
        sql += &sql_das_pessoas(&contrato);
        banco
            .batch_execute(&sql)
            .unwrap_or_else(|e| panic!("contrato {c} não gravou: {e}"));

        let do_banco = banco
            .query_one(
                "SELECT c.fator_art127::text, r.valor_total::text
                   FROM contrato c JOIN revisao_orcamento r ON r.contrato_id = c.id AND r.numero = 0
                  WHERE c.id = $1::text::uuid",
                &[&contrato],
            )
            .expect("fator e total");
        assert_eq!(
            fator,
            decimal(do_banco.get(0)),
            "contrato {c}: fator do art. 127"
        );
        assert_eq!(
            valor_inicial.decimal(),
            decimal(do_banco.get(1)),
            "contrato {c}: Rev. 0"
        );

        // --- medição 1 e o boletim dela ---
        let medicao_1 = medir(
            &mut banco,
            &mut sorteio,
            &rev0,
            &BTreeMap::new(),
            c,
            1,
            &revisao_0,
        );
        linhas_de_boletim +=
            comparar_boletim(&mut banco, &rev0, &BTreeMap::new(), &medicao_1, c, 1);

        // --- aditivo 1: acréscimo no primeiro serviço, supressão num serviço com saldo, item novo ---
        let lista = servicos(&rev0);
        let (acrescido, quantidade_do_acrescido, preco_do_acrescido) = lista[0];
        let mut itens_1 = vec![ItemDoAditivo {
            item: acrescido,
            operacao: Operacao::Acrescimo,
            quantidade: (quantidade_do_acrescido / Decimal::ONE_HUNDRED)
                .round_dp(4)
                .max(Decimal::new(1, 4)),
            novo: None,
        }];
        let mut suprimido: BTreeMap<ItemId, Decimal> = BTreeMap::new();
        let com_saldo = lista[1..].iter().find(|(item, contratada, _)| {
            let medido = medicao_1.get(item).copied().unwrap_or_default().quantidade;
            contratada - medido >= Decimal::ONE
        });
        if let Some((item, contratada, _)) = com_saldo {
            let medido = medicao_1.get(item).copied().unwrap_or_default().quantidade;
            let corte = ((contratada - medido) / Decimal::TWO)
                .round_dp(4)
                .min(contratada / Decimal::from(50));
            let corte = corte.round_dp(4).max(Decimal::new(1, 4));
            itens_1.push(ItemDoAditivo {
                item: *item,
                operacao: Operacao::Supressao,
                quantidade: -corte,
                novo: None,
            });
            suprimido.insert(*item, corte);
        }
        itens_1.push(ItemDoAditivo {
            item: ItemId(0x900),
            operacao: Operacao::Inclusao,
            quantidade: sorteio.decimal(20, 4) + Decimal::ONE,
            novo: Some(ServicoNovo {
                grupo: ItemId(2),
                codigo_eap: "2.3".into(),
                descricao: "Serviço novo".into(),
                unidade: "m".into(),
                preco_de_referencia: sorteio.decimal(50, 2) + Decimal::ONE,
            }),
        });
        let historico_1 = Historico {
            medido: quantidades(&medicao_1),
            suprimido: BTreeMap::new(),
        };
        let aditivo_1 =
            aplicar_aditivo(&rev0, fator, &itens_1, &historico_1).expect("aditivo 1 em Rust");
        gravar_e_comparar_aditivo(
            &mut banco,
            &rev0,
            &itens_1,
            &aditivo_1.itens,
            c,
            1,
            &revisao_0,
        );
        itens_de_aditivo += aditivo_1.itens.len();

        // limites simulando o aditivo 1, ainda em rascunho
        let limites_1 =
            limites_dos_aditivos(valor_inicial, valores(&aditivo_1.itens), regra).expect("limites");
        situacoes.insert(format!(
            "{:?}",
            comparar_limites(&mut banco, &limites_1, c, Some(1))
        ));

        // --- homologação: a Rev. 1 calculada em Rust é gravada e o banco tem que aceitar e somar igual ---
        let rev1 = &aditivo_1.planilha;
        let mut sql = format!(
            "INSERT INTO revisao_orcamento (id, contrato_id, numero, origem, aditivo_id)
             VALUES ('{revisao_1}', '{contrato}', 1, 'aditivo', '{}');",
            id(9, c, 1)
        );
        sql += &sql_dos_itens(rev1, c, &revisao_1);
        sql += &format!(
            "UPDATE revisao_orcamento SET status = 'substituida' WHERE id = '{revisao_0}';
             UPDATE revisao_orcamento SET status = 'vigente', data_vigencia = DATE '2026-11-28' WHERE id = '{revisao_1}';
             UPDATE aditivo SET status = 'homologado', revisao_resultante_id = '{revisao_1}',
                                data_assinatura = DATE '2026-11-28', homologado_em = now()
              WHERE id = '{}';",
            id(9, c, 1)
        );
        banco.batch_execute(&sql).unwrap_or_else(|e| {
            panic!("contrato {c}: o banco recusou a Rev. 1 calculada em Rust: {e}")
        });
        let total_1 = banco
            .query_one(
                "SELECT valor_total::text FROM revisao_orcamento WHERE id = $1::text::uuid",
                &[&revisao_1],
            )
            .expect("total da Rev. 1");
        let total_1_no_rust = rev1.valor_total().expect("total da Rev. 1 em Rust");
        assert_eq!(
            total_1_no_rust.decimal(),
            decimal(total_1.get(0)),
            "contrato {c}: Rev. 1"
        );
        // valor inicial + acréscimos − supressões: pode diferir da Rev. 1 por arredondamento
        let pela_soma = valor_inicial + limites_1.acrescimos - limites_1.supressoes;
        if pela_soma != total_1_no_rust {
            revisoes_diferentes += 1;
        }
        // depois de homologado, a conta sem simulação dá o mesmo
        comparar_limites(&mut banco, &limites_1, c, None);

        // --- medição 2, sobre a Rev. 1, e o boletim dela ---
        let medicao_2 = medir(&mut banco, &mut sorteio, rev1, &medicao_1, c, 2, &revisao_1);
        linhas_de_boletim += comparar_boletim(&mut banco, rev1, &medicao_1, &medicao_2, c, 2);

        // --- aditivo 2, só simulado: devolve metade do que foi suprimido e acrescenta até
        //     30%, 95% ou 150% do teto, conforme o contrato ---
        let fracao = [30, 95, 150][c % 3];
        let alvo = valor_inicial.decimal() * regra.limite_de_acrescimos * Decimal::from(fracao)
            / Decimal::from(10_000)
            - limites_1.acrescimos.decimal();
        let mut itens_2 = vec![ItemDoAditivo {
            item: acrescido,
            operacao: Operacao::Acrescimo,
            quantidade: (alvo / preco_do_acrescido)
                .round_dp(4)
                .max(Decimal::new(1, 4)),
            novo: None,
        }];
        if let Some((item, corte)) = suprimido.iter().next() {
            let devolve = (corte / Decimal::TWO).round_dp(4);
            if !devolve.is_zero() {
                itens_2.push(ItemDoAditivo {
                    item: *item,
                    operacao: Operacao::Restabelecimento,
                    quantidade: devolve,
                    novo: None,
                });
            }
        }
        let historico_2 = Historico {
            medido: quantidades(&somar(&medicao_1, &medicao_2)),
            suprimido,
        };
        let aditivo_2 =
            aplicar_aditivo(rev1, fator, &itens_2, &historico_2).expect("aditivo 2 em Rust");
        gravar_e_comparar_aditivo(
            &mut banco,
            rev1,
            &itens_2,
            &aditivo_2.itens,
            c,
            2,
            &revisao_1,
        );
        itens_de_aditivo += aditivo_2.itens.len();
        let todos = valores(&aditivo_1.itens)
            .into_iter()
            .chain(valores(&aditivo_2.itens));
        let limites_2 =
            limites_dos_aditivos(valor_inicial, todos, regra).expect("limites com o aditivo 2");
        situacoes.insert(format!(
            "{:?}",
            comparar_limites(&mut banco, &limites_2, c, Some(2))
        ));
    }

    // O teste só vale se passou pelas três situações.
    let esperadas: BTreeSet<String> = ["Atencao", "Dentro", "Excede"]
        .iter()
        .map(|s| s.to_string())
        .collect();
    assert_eq!(situacoes, esperadas, "situações de limite exercitadas");
    println!(
        "aditivo e boletim: {CONTRATOS} contratos; {linhas_de_boletim} linhas de boletim, {itens_de_aditivo} itens de aditivo, \
         fator, limites e totais das revisões iguais no Rust e no SQL; em {revisoes_diferentes} contratos a Rev. 1 difere de \
         valor inicial + acréscimos − supressões por arredondamento"
    );
}

/// A coluna gerada `fator_art127` usa `round(valor_inicial / valor_orcamento_base, 8)`.
/// Aqui a mesma expressão roda no banco para 10 mil pares de valores.
#[test]
#[ignore = "precisa do banco: rode scripts/db-test.sh paridade"]
fn fator_do_art_127_da_o_mesmo_no_rust_e_no_sql() {
    let mut banco = conectar();
    let mut sorteio = Sorteio::novo(0x5052_554D_4F00_0004);
    let mut pares: Vec<(i64, i64)> = vec![
        (5_855_128, 6_430_000),   // cenário de referência
        (16_403_934, 17_800_000), // seed fictício, contrato por eventos
        (13_659_563, 14_980_000), // seed fictício, contrato por quantidade
        (100, 300),
        (200, 300),
        (1, 3),
        // meio exato na nona casa: 0,000000005 e 0,000000015
        (1, 200_000_000),
        (3, 200_000_000),
        (5, 200_000_000),
        (5, 8), // 0,625: sem nada a arredondar
        (1, 99_999_999_999),
        (99_999_999_999, 1),
        (1, 1),
    ];
    for _ in 0..10_000 {
        // de R$ 0,01 a R$ 1 bilhão, nos dois valores
        pares.push((
            1 + sorteio.ate(100_000_000_000) as i64,
            1 + sorteio.ate(100_000_000_000) as i64,
        ));
    }
    let propostas: Vec<String> = pares
        .iter()
        .map(|(p, _)| Dinheiro::de_centavos(*p).decimal().to_string())
        .collect();
    let bases: Vec<String> = pares
        .iter()
        .map(|(_, b)| Dinheiro::de_centavos(*b).decimal().to_string())
        .collect();
    let linhas = banco
        .query(
            "SELECT round(p::numeric(18,2) / b::numeric(18,2), 8)::text
               FROM unnest($1::text[], $2::text[]) WITH ORDINALITY AS t(p, b, n)
              ORDER BY n",
            &[&propostas, &bases],
        )
        .expect("divisão no banco");
    assert_eq!(linhas.len(), pares.len());
    for ((proposta, base), linha) in pares.iter().zip(&linhas) {
        let no_rust = fator_art127(
            Dinheiro::de_centavos(*proposta),
            Dinheiro::de_centavos(*base),
        )
        .expect("fator");
        assert_eq!(
            no_rust,
            decimal(linha.get(0)),
            "{proposta} ÷ {base} centavos: Rust × SQL"
        );
    }
    println!(
        "fator do art. 127: {} pares iguais no Rust e no SQL",
        pares.len()
    );
}

/// Percentual executado e preço de item novo, com os casos que caem em meio exato: é neles
/// que um arredondamento diferente do `round` do PostgreSQL apareceria.
#[test]
#[ignore = "precisa do banco: rode scripts/db-test.sh paridade"]
fn percentual_e_preco_de_item_novo_dao_o_mesmo_no_rust_e_no_sql() {
    let mut banco = conectar();
    let mut sorteio = Sorteio::novo(0x5052_554D_4F00_0005);

    // --- percentual: 100 × parte ÷ todo, com duas casas ---
    // Meio exato: todo de 200,00 e parte com número ímpar de centavos dá ímpar × 0,005%.
    let mut pares: Vec<(i64, i64)> = (0..2_000)
        .map(|_| (sorteio.ate(10_000) as i64 * 2 + 1, 20_000))
        .collect();
    pares.push((0, 100));
    pares.push((1, 0)); // todo zero: sem percentual
    for _ in 0..8_000 {
        pares.push((
            sorteio.ate(100_000_000_000) as i64,
            1 + sorteio.ate(100_000_000_000) as i64,
        ));
    }
    let partes: Vec<String> = pares
        .iter()
        .map(|(p, _)| Dinheiro::de_centavos(*p).decimal().to_string())
        .collect();
    let todos: Vec<String> = pares
        .iter()
        .map(|(_, t)| Dinheiro::de_centavos(*t).decimal().to_string())
        .collect();
    let linhas = banco
        .query(
            "SELECT round(100 * p::numeric(18,2) / nullif(t::numeric(18,2), 0), 2)::text
               FROM unnest($1::text[], $2::text[]) WITH ORDINALITY AS x(p, t, n)
              ORDER BY n",
            &[&partes, &todos],
        )
        .expect("percentual no banco");
    for ((parte, todo), linha) in pares.iter().zip(&linhas) {
        let no_rust =
            percentual_executado(Dinheiro::de_centavos(*parte), Dinheiro::de_centavos(*todo))
                .expect("percentual");
        let no_sql = linha.get::<_, Option<&str>>(0).map(decimal);
        assert_eq!(no_rust, no_sql, "{parte} de {todo} centavos: Rust × SQL");
    }

    // --- preço de item novo: preço de referência × fator, nas casas do contrato ---
    // Meio exato: fator de 0,5 e preço de referência com última casa ímpar.
    let mut casos: Vec<(Decimal, Decimal, u32)> = Vec::new();
    for i in 0..3_000_u32 {
        let casas = 2 + i % 3;
        casos.push((
            Decimal::new(sorteio.ate(50_000) as i64 * 2 + 1, casas),
            Decimal::new(50_000_000, 8),
            casas,
        ));
    }
    for i in 0..7_000_u32 {
        casos.push((
            sorteio.decimal(100_000, 4),
            sorteio.decimal(2, 8),
            2 + i % 3,
        ));
    }
    let referencias: Vec<String> = casos.iter().map(|(r, _, _)| r.to_string()).collect();
    let fatores: Vec<String> = casos.iter().map(|(_, f, _)| f.to_string()).collect();
    let casas: Vec<i32> = casos.iter().map(|(_, _, c)| *c as i32).collect();
    let linhas = banco
        .query(
            "SELECT round(r::numeric * f::numeric, c)::text
               FROM unnest($1::text[], $2::text[], $3::int[]) WITH ORDINALITY AS x(r, f, c, n)
              ORDER BY n",
            &[&referencias, &fatores, &casas],
        )
        .expect("preço de item novo no banco");
    for ((referencia, fator, casas), linha) in casos.iter().zip(&linhas) {
        let no_rust = preco_de_item_novo(*referencia, *fator, *casas).expect("preço de item novo");
        assert_eq!(
            no_rust,
            decimal(linha.get(0)),
            "{referencia} × {fator} com {casas} casas: Rust × SQL"
        );
    }
    println!(
        "percentual e preço de item novo: {} percentuais (2.000 em meio exato) e {} preços (3.000 em meio exato) iguais no Rust e no SQL",
        pares.len(),
        casos.len()
    );
}
