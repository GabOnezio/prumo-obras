//! Apoio comum aos testes de paridade: conexão e números de teste que se repetem.
#![allow(dead_code)]

use postgres::{Client, NoTls};
use prumo_dominio::CriterioArredondamento;
use rust_decimal::Decimal;

/// Município de Exemplo, do seed fictício.
pub const TENANT_EXEMPLO: &str = "e0e0e0e0-0000-0000-0000-000000000001";

/// Conecta no banco preparado por `scripts/db-test.sh paridade`, como a aplicação conecta:
/// papel `app_rw`, com o município e o usuário na sessão.
pub fn conectar() -> Client {
    let url = std::env::var("PRUMO_PARIDADE_URL")
        .expect("defina PRUMO_PARIDADE_URL ou rode scripts/db-test.sh paridade");
    let mut banco = Client::connect(&url, NoTls).expect("não conectou no banco de teste");
    banco
        .batch_execute(&format!(
            "SET ROLE app_rw; SET app.tenant_id = '{TENANT_EXEMPLO}'; SET app.usuario = 'teste.paridade';"
        ))
        .expect("não assumiu o papel da aplicação");
    banco
}

/// Nome do critério no tipo `criterio_arredondamento` do banco.
pub fn nome_no_banco(criterio: CriterioArredondamento) -> &'static str {
    match criterio {
        CriterioArredondamento::Arredondar => "arredondar",
        CriterioArredondamento::Truncar => "truncar",
    }
}

pub fn decimal(texto: &str) -> Decimal {
    texto
        .parse()
        .unwrap_or_else(|_| panic!("número inválido vindo do banco ou do teste: {texto:?}"))
}

/// Pessoas e cadastros do seed fictício que os testes usam para agir nos contratos sorteados.
pub const EMPRESA_ALFA: &str = "e0e0e0e0-0000-0000-0000-0000000000e1";
pub const PREPOSTO: &str = "e0e0e0e0-0000-0000-0001-000000000005";
pub const FISCAL: &str = "e0e0e0e0-0000-0000-0001-000000000001";
pub const PORTARIA: &str = "e0e0e0e0-0000-0000-0000-0000000000a9";

/// Põe o preposto e o fiscal do seed num contrato de teste, que tem que ser da empresa Alfa.
pub fn sql_das_pessoas(contrato: &str) -> String {
    format!(
        "INSERT INTO usuario_externo (usuario_id, empresa_id, contrato_id, papel, inicio)
         VALUES ('{PREPOSTO}', '{EMPRESA_ALFA}', '{contrato}', 'preposto', '2026-09-14');
         INSERT INTO designacao (servidor_id, contrato_id, funcao, inicio, portaria_id)
         SELECT s.id, '{contrato}', 'fiscal_tecnico', DATE '2026-09-15', '{PORTARIA}'
           FROM servidor s WHERE s.usuario_id = '{FISCAL}';"
    )
}

/// A empresa envia a medição.
pub fn sql_de_enviar(medicao: &str) -> String {
    format!(
        "SET app.usuario_id = '{PREPOSTO}';
         INSERT INTO medicao_etapa (medicao_id, acao) VALUES ('{medicao}', 'enviar');"
    )
}

/// O fiscal analisa e aprova a medição já enviada.
pub fn sql_de_aprovar(medicao: &str) -> String {
    format!(
        "SET app.usuario_id = '{FISCAL}';
         INSERT INTO medicao_etapa (medicao_id, acao) VALUES ('{medicao}', 'iniciar_analise');
         INSERT INTO medicao_etapa (medicao_id, acao) VALUES ('{medicao}', 'aprovar_fiscal');"
    )
}

/// Id de teste, legível e sem repetir: tipo do registro, contrato e número.
pub fn id(tipo: u16, contrato: usize, n: usize) -> String {
    format!("f0f0f0f0-{tipo:04x}-0000-{contrato:04x}-{n:012x}")
}

/// Gerador de números de teste com semente fixa (SplitMix64): a mesma sequência em toda
/// execução e em toda máquina. Não serve para nada além de teste.
pub struct Sorteio(u64);

impl Sorteio {
    pub fn novo(semente: u64) -> Sorteio {
        Sorteio(semente)
    }

    pub fn proximo(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }

    /// Inteiro em `0..limite`.
    pub fn ate(&mut self, limite: u64) -> u64 {
        self.proximo() % limite
    }

    /// Decimal em `0..teto_inteiro`, com `casas` casas decimais.
    pub fn decimal(&mut self, teto_inteiro: u64, casas: u32) -> Decimal {
        let unidades = 10_u64.pow(casas);
        let sorteado = self.ate(teto_inteiro * unidades);
        Decimal::new(sorteado as i64, casas)
    }
}
