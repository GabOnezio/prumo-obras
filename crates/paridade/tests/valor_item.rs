//! `valor_item` (Rust) × `fn_valor_item` (SQL): quantidade × preço, ao centavo, nos dois
//! critérios de arredondamento.

mod comum;

use comum::{conectar, decimal, nome_no_banco, Sorteio};
use prumo_dominio::{valor_item, CriterioArredondamento};
use rust_decimal::Decimal;

const CRITERIOS: [CriterioArredondamento; 2] = [
    CriterioArredondamento::Arredondar,
    CriterioArredondamento::Truncar,
];

/// Casos escolhidos à mão: os que costumam dar diferença de um centavo.
fn grade_fixa() -> Vec<(Decimal, Decimal)> {
    [
        ("42.50", "68.93"), // escavação do seed de referência: 2.929,525
        ("4.50", "412.37"), // placa de obra do seed fictício: 1.855,665
        ("1", "0.005"),     // meio centavo exato
        ("1", "0.015"),
        ("1", "0.025"),
        ("1", "0.004"),
        ("1", "0.006"),
        ("0.5", "0.01"),
        ("0.9999", "0.005"), // um fio abaixo de meio centavo
        ("1.0001", "0.005"), // um fio acima
        ("-42.50", "68.93"), // estorno: quantidade negativa
        ("-1", "0.005"),
        ("-1", "0.015"),
        ("-0.9999", "0.005"),
        ("0", "123.45"),
        ("123.4567", "0"),
        ("0.0001", "0.0001"),
        ("3", "0.33"),
        ("1.50", "0.33"),
        ("1", "1"),
        ("1000000", "0.01"),
        ("0.0001", "99999.9999"),
        ("9999999999.9999", "9.9999"),
        ("999999999.9999", "999999.9999"),
        ("98765432.1098", "8765.4321"),
    ]
    .iter()
    .map(|(q, p)| (decimal(q), decimal(p)))
    .collect()
}

/// 10 mil pares com semente fixa. Um em cada cinco cai de propósito em meio centavo exato
/// (quantidade inteira ímpar × preço com três casas terminando em 5); um em cada dez tem
/// quantidade negativa.
fn pares_sorteados() -> Vec<(Decimal, Decimal)> {
    let mut sorteio = Sorteio::novo(0x5052_554D_4F00_0001);
    (0..10_000)
        .map(|i| {
            if i % 5 == 0 {
                let quantidade = Decimal::from(sorteio.ate(5_000) * 2 + 1);
                let preco = Decimal::new((sorteio.ate(100_000) * 10 + 5) as i64, 3);
                return (quantidade, preco);
            }
            let casas_q = sorteio.ate(5) as u32;
            let casas_p = sorteio.ate(5) as u32;
            let mut quantidade = sorteio.decimal(1_000_000, casas_q);
            if i % 10 == 3 {
                quantidade = -quantidade;
            }
            (quantidade, sorteio.decimal(100_000, casas_p))
        })
        .collect()
}

#[test]
#[ignore = "precisa do banco: rode scripts/db-test.sh paridade"]
fn valor_de_item_da_o_mesmo_centavo_no_rust_e_no_sql() {
    let mut banco = conectar();
    let mut casos = grade_fixa();
    let fixos = casos.len();
    casos.extend(pares_sorteados());
    let quantidades: Vec<String> = casos.iter().map(|(q, _)| q.to_string()).collect();
    let precos: Vec<String> = casos.iter().map(|(_, p)| p.to_string()).collect();

    let mut conferidos = 0;
    let mut em_meio_centavo = 0;
    for criterio in CRITERIOS {
        let linhas = banco
            .query(
                "SELECT fn_valor_item(q::numeric, p::numeric, $3::text::criterio_arredondamento)::text
                   FROM unnest($1::text[], $2::text[]) WITH ORDINALITY AS t(q, p, n)
                  ORDER BY n",
                &[&quantidades, &precos, &nome_no_banco(criterio)],
            )
            .expect("fn_valor_item falhou no banco");
        assert_eq!(linhas.len(), casos.len());
        for ((quantidade, preco), linha) in casos.iter().zip(&linhas) {
            let no_sql = decimal(linha.get::<_, &str>(0));
            let no_rust = valor_item(*quantidade, *preco, criterio)
                .unwrap_or_else(|e| panic!("{quantidade} × {preco}: {e}"))
                .decimal();
            assert_eq!(
                no_rust, no_sql,
                "{quantidade} × {preco} ({criterio:?}): Rust deu {no_rust}, SQL deu {no_sql}"
            );
            conferidos += 1;
        }
    }
    for (quantidade, preco) in &casos {
        // meio centavo exato: os dois critérios dão resultados diferentes e o produto,
        // em milésimos, termina em 5
        let milesimos = quantidade * preco * Decimal::from(1000);
        if milesimos.fract().is_zero() && (milesimos.abs() % Decimal::from(10)) == Decimal::from(5)
        {
            em_meio_centavo += 1;
        }
    }
    assert!(
        em_meio_centavo >= 2_000,
        "esperava ao menos 2.000 casos em meio centavo exato, vieram {em_meio_centavo}"
    );
    println!(
        "valor de item: {conferidos} comparações iguais ({fixos} casos fixos e 10.000 sorteados, \
         nos 2 critérios); {em_meio_centavo} casos caem em meio centavo exato"
    );
}
