//! Máquina de estado da medição: a tabela de transições em Rust (`fluxo::medicao`) × a do
//! banco (`fn_transicao_medicao`) e os nomes dos estados e das ações nos dois lados.

mod comum;

use comum::conectar;
use prumo_dominio::fluxo::medicao::{
    transitar, AcaoMedicao, EstadoMedicao, RegrasDaMedicao, SituacaoDaMedicao,
};
use prumo_dominio::fluxo::{Papel, Pedido, PessoaId};

/// Estado de chegada em Rust, para algum papel. Usa uma pessoa que não enviou nem aprovou e
/// uma medição sem pendência, para só a tabela decidir.
fn no_rust(estado: EstadoMedicao, acao: AcaoMedicao) -> Option<&'static str> {
    let situacao = SituacaoDaMedicao {
        enviada_por: Some(PessoaId(1)),
        aprovada_por: Some(PessoaId(2)),
        pendencias: 0,
    };
    for comissao_exigida in [false, true] {
        for papel in Papel::TODOS {
            let pedido = Pedido {
                quem: PessoaId(99),
                papel,
                motivo: Some("motivo"),
            };
            if let Ok(novo) = transitar(
                estado,
                acao,
                &pedido,
                &situacao,
                &RegrasDaMedicao { comissao_exigida },
            ) {
                return Some(novo.nome());
            }
        }
    }
    None
}

#[test]
#[ignore = "precisa do banco: rode scripts/db-test.sh paridade"]
fn transicoes_da_medicao_sao_as_mesmas_no_rust_e_no_sql() {
    let mut banco = conectar();

    // Os mesmos estados e as mesmas ações, com os mesmos nomes e na mesma ordem.
    let rotulos = |banco: &mut postgres::Client, tipo: &str| -> Vec<String> {
        banco
            .query(
                "SELECT e.enumlabel FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
                  WHERE t.typname = $1 ORDER BY e.enumsortorder",
                &[&tipo],
            )
            .expect("rótulos do tipo")
            .iter()
            .map(|l| l.get(0))
            .collect()
    };
    let estados: Vec<String> = EstadoMedicao::TODOS
        .iter()
        .map(|e| e.nome().to_string())
        .collect();
    let acoes: Vec<String> = AcaoMedicao::TODAS
        .iter()
        .map(|a| a.codigo().to_string())
        .collect();
    assert_eq!(
        rotulos(&mut banco, "status_medicao"),
        estados,
        "estados da medição"
    );
    assert_eq!(
        rotulos(&mut banco, "acao_medicao"),
        acoes,
        "ações da medição"
    );

    let (mut comparadas, mut permitidas) = (0, 0);
    for estado in EstadoMedicao::TODOS {
        for acao in AcaoMedicao::TODAS {
            let linha = banco
                .query_one(
                    "SELECT fn_transicao_medicao($1::text::status_medicao, $2::text::acao_medicao)::text",
                    &[&estado.nome(), &acao.codigo()],
                )
                .expect("fn_transicao_medicao");
            let no_sql: Option<&str> = linha.get(0);
            let esperado = no_rust(estado, acao);
            assert_eq!(no_sql, esperado, "{estado:?} + {acao:?}: SQL × Rust");
            comparadas += 1;
            if esperado.is_some() {
                permitidas += 1;
            }
        }
    }
    assert_eq!(permitidas, 10);
    println!(
        "fluxo da medição: {} estados e {} ações com os mesmos nomes; {comparadas} combinações iguais no Rust e no SQL, {permitidas} permitidas",
        estados.len(),
        acoes.len()
    );
}
