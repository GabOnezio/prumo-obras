//! Máquina de estado da medição: a tabela de transições em Rust (`fluxo::medicao`) × a do
//! banco (`fn_transicao_medicao`) e os nomes dos estados e das ações nos dois lados.

mod comum;

use comum::conectar;
use prumo_dominio::aditivo::SituacaoDosLimites;
use prumo_dominio::fluxo::aditivo::{
    self as fluxo_do_aditivo, AcaoAditivo, EstadoAditivo, RegrasDoAditivo, SituacaoDoAditivo,
};
use prumo_dominio::fluxo::diario::{self, AcaoDiario, EstadoDiario};
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

fn rotulos(banco: &mut postgres::Client, tipo: &str) -> Vec<String> {
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
}

#[test]
#[ignore = "precisa do banco: rode scripts/db-test.sh paridade"]
fn transicoes_do_diario_sao_as_mesmas_no_rust_e_no_sql() {
    let mut banco = conectar();
    let estados: Vec<String> = EstadoDiario::TODOS
        .iter()
        .map(|e| e.nome().to_string())
        .collect();
    let acoes: Vec<String> = AcaoDiario::TODAS
        .iter()
        .map(|a| a.codigo().to_string())
        .collect();
    assert_eq!(
        rotulos(&mut banco, "status_rdo"),
        estados,
        "estados do diário"
    );
    assert_eq!(rotulos(&mut banco, "acao_rdo"), acoes, "ações do diário");
    // As situações de evento do Boletim de Execução têm os mesmos nomes no domínio e no banco.
    assert_eq!(
        rotulos(&mut banco, "situacao_evento"),
        prumo_dominio::SituacaoEvento::NOMES,
        "situações de evento"
    );

    let (mut comparadas, mut permitidas) = (0, 0);
    for estado in EstadoDiario::TODOS {
        for acao in AcaoDiario::TODAS {
            let linha = banco
                .query_one(
                    "SELECT fn_transicao_rdo($1::text::status_rdo, $2::text::acao_rdo)::text",
                    &[&estado.nome(), &acao.codigo()],
                )
                .expect("fn_transicao_rdo");
            let no_sql: Option<&str> = linha.get(0);
            let esperado = Papel::TODOS.iter().find_map(|papel| {
                let pedido = Pedido {
                    quem: PessoaId(99),
                    papel: *papel,
                    motivo: Some("motivo"),
                };
                diario::transitar(estado, acao, &pedido, Some(PessoaId(1)))
                    .ok()
                    .map(|e| e.nome())
            });
            assert_eq!(no_sql, esperado, "{estado:?} + {acao:?}: SQL × Rust");
            comparadas += 1;
            if esperado.is_some() {
                permitidas += 1;
            }
        }
    }
    assert_eq!(permitidas, 4);
    println!(
        "fluxo do diário: {} estados e {} ações com os mesmos nomes; {comparadas} combinações iguais no Rust e no SQL, {permitidas} permitidas",
        estados.len(),
        acoes.len()
    );
}

#[test]
#[ignore = "precisa do banco: rode scripts/db-test.sh paridade"]
fn transicoes_do_aditivo_sao_as_mesmas_no_rust_e_no_sql() {
    let mut banco = conectar();
    let estados: Vec<String> = EstadoAditivo::TODOS
        .iter()
        .map(|e| e.nome().to_string())
        .collect();
    assert_eq!(
        rotulos(&mut banco, "status_aditivo"),
        estados,
        "estados do aditivo"
    );

    // Aditivo pronto para homologar, pedido por alguém que não o enviou.
    let pronto = SituacaoDoAditivo {
        enviado_por: Some(PessoaId(1)),
        limites: SituacaoDosLimites::Dentro,
        tem_parecer: true,
        termo_assinado: true,
    };
    let regras = RegrasDoAditivo {
        parecer_exigido: true,
    };
    let (mut comparadas, mut permitidas) = (0, 0);
    for de in EstadoAditivo::TODOS {
        for para in EstadoAditivo::TODOS {
            let no_rust = AcaoAditivo::TODAS.iter().any(|acao| {
                Papel::TODOS.iter().any(|papel| {
                    let pedido = Pedido {
                        quem: PessoaId(99),
                        papel: *papel,
                        motivo: Some("motivo"),
                    };
                    fluxo_do_aditivo::transitar(de, *acao, &pedido, &pronto, &regras) == Ok(para)
                })
            });
            let linha = banco
                .query_one(
                    "SELECT fn_transicao_aditivo($1::text::status_aditivo, $2::text::status_aditivo)",
                    &[&de.nome(), &para.nome()],
                )
                .expect("fn_transicao_aditivo");
            let no_sql: bool = linha.get(0);
            assert_eq!(no_sql, no_rust, "{de:?} → {para:?}: SQL × Rust");
            comparadas += 1;
            if no_rust {
                permitidas += 1;
            }
        }
    }
    assert_eq!(permitidas, 3);
    println!(
        "fluxo do aditivo: {} estados com os mesmos nomes; {comparadas} pares de estados iguais no Rust e no SQL, {permitidas} permitidos",
        estados.len()
    );
}
