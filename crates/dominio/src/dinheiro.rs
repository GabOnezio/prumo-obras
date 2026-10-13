//! Dinheiro e arredondamento. Valor nunca é `f32`/`f64`.

use crate::ErroDominio;
use rust_decimal::{Decimal, RoundingStrategy};
use std::ops::{Add, Sub};

/// Critério do contrato (`contrato.criterio_arredondamento` no schema de referência).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CriterioArredondamento {
    Arredondar,
    Truncar,
}

impl CriterioArredondamento {
    fn aplicar(self, valor: Decimal) -> Decimal {
        let estrategia = match self {
            // `round(numeric, 2)` do PostgreSQL: meio para longe do zero.
            CriterioArredondamento::Arredondar => RoundingStrategy::MidpointAwayFromZero,
            // `trunc(numeric, 2)`.
            CriterioArredondamento::Truncar => RoundingStrategy::ToZero,
        };
        valor.round_dp_with_strategy(2, estrategia)
    }
}

/// Valor em reais, com duas casas.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, PartialOrd, Ord)]
pub struct Dinheiro(Decimal);

impl Dinheiro {
    pub const ZERO: Dinheiro = Dinheiro(Decimal::ZERO);

    pub fn de_centavos(centavos: i64) -> Dinheiro {
        Dinheiro(Decimal::new(centavos, 2))
    }

    pub fn decimal(self) -> Decimal {
        self.0
    }

    pub fn eh_zero(self) -> bool {
        self.0.is_zero()
    }

    pub fn somar(self, outro: Dinheiro) -> Result<Dinheiro, ErroDominio> {
        self.0
            .checked_add(outro.0)
            .map(Dinheiro)
            .ok_or(ErroDominio::Estouro)
    }

    /// Formato brasileiro, sem o símbolo: `26.014,74`.
    pub fn formatar(self) -> String {
        formatar_decimal(self.0, 2)
    }
}

impl Add for Dinheiro {
    type Output = Dinheiro;
    /// Soma direta. Para valores vindos de fora do banco, prefira [`Dinheiro::somar`].
    fn add(self, outro: Dinheiro) -> Dinheiro {
        Dinheiro(self.0 + outro.0)
    }
}

impl Sub for Dinheiro {
    type Output = Dinheiro;
    fn sub(self, outro: Dinheiro) -> Dinheiro {
        Dinheiro(self.0 - outro.0)
    }
}

/// Quantidade × preço unitário, com duas casas, pelo critério do contrato.
/// É o mesmo cálculo de `fn_valor_item` do schema de referência.
pub fn valor_item(
    quantidade: Decimal,
    preco_unitario: Decimal,
    criterio: CriterioArredondamento,
) -> Result<Dinheiro, ErroDominio> {
    let bruto = quantidade
        .checked_mul(preco_unitario)
        .ok_or(ErroDominio::Estouro)?;
    Ok(Dinheiro(criterio.aplicar(bruto)))
}

/// `base × percentual ÷ 100`, com duas casas, pelo critério do contrato.
pub fn percentual(
    base: Dinheiro,
    percentual: Decimal,
    criterio: CriterioArredondamento,
) -> Result<Dinheiro, ErroDominio> {
    let bruto = base
        .0
        .checked_mul(percentual)
        .and_then(|v| v.checked_div(Decimal::ONE_HUNDRED))
        .ok_or(ErroDominio::Estouro)?;
    Ok(Dinheiro(criterio.aplicar(bruto)))
}

/// Número no formato brasileiro: ponto no milhar, vírgula decimal.
pub fn formatar_decimal(valor: Decimal, casas: u32) -> String {
    let arredondado = valor.round_dp_with_strategy(casas, RoundingStrategy::MidpointAwayFromZero);
    let texto = format!("{:.*}", casas as usize, arredondado.abs());
    let (inteiro, fracao) = match texto.split_once('.') {
        Some((i, f)) => (i, Some(f)),
        None => (texto.as_str(), None),
    };
    let mut saida = String::new();
    if arredondado.is_sign_negative() && !arredondado.is_zero() {
        saida.push('-');
    }
    for (i, digito) in inteiro.chars().enumerate() {
        if i > 0 && (inteiro.len() - i) % 3 == 0 {
            saida.push('.');
        }
        saida.push(digito);
    }
    if let Some(f) = fracao {
        saida.push(',');
        saida.push_str(f);
    }
    saida
}

#[cfg(test)]
mod tests {
    use super::*;

    fn d(texto: &str) -> Decimal {
        texto.parse().unwrap()
    }

    #[test]
    fn escavacao_do_seed_de_referencia_trunca_em_2929_52() {
        // seed_e_testes.sql: "escavação 42,50 × 68,93 = 2.929,525 → truncado em 2.929,52"
        let v = valor_item(d("42.50"), d("68.93"), CriterioArredondamento::Truncar).unwrap();
        assert_eq!(v, Dinheiro::de_centavos(292_952));
    }

    #[test]
    fn o_mesmo_item_arredondado_da_um_centavo_a_mais() {
        let v = valor_item(d("42.50"), d("68.93"), CriterioArredondamento::Arredondar).unwrap();
        assert_eq!(v, Dinheiro::de_centavos(292_953));
    }

    #[test]
    fn meio_centavo_negativo_arredonda_para_longe_do_zero() {
        // estorno: -42,50 × 68,93 = -2.929,525
        let v = valor_item(d("-42.50"), d("68.93"), CriterioArredondamento::Arredondar).unwrap();
        assert_eq!(v, Dinheiro::de_centavos(-292_953));
        let t = valor_item(d("-42.50"), d("68.93"), CriterioArredondamento::Truncar).unwrap();
        assert_eq!(t, Dinheiro::de_centavos(-292_952));
    }

    #[test]
    fn retencao_de_11_por_cento() {
        let base = Dinheiro::de_centavos(2_601_474);
        let r = percentual(base, d("11"), CriterioArredondamento::Arredondar).unwrap();
        assert_eq!(r, Dinheiro::de_centavos(286_162));
        assert_eq!(base - r, Dinheiro::de_centavos(2_315_312));
    }

    #[test]
    fn formato_brasileiro() {
        assert_eq!(Dinheiro::de_centavos(2_601_474).formatar(), "26.014,74");
        assert_eq!(Dinheiro::de_centavos(0).formatar(), "0,00");
        assert_eq!(Dinheiro::de_centavos(99).formatar(), "0,99");
        assert_eq!(
            Dinheiro::de_centavos(100_000_000).formatar(),
            "1.000.000,00"
        );
        assert_eq!(Dinheiro::de_centavos(-123_456).formatar(), "-1.234,56");
        assert_eq!(formatar_decimal(d("1150"), 2), "1.150,00");
        assert_eq!(formatar_decimal(d("1.1"), 2), "1,10");
        assert_eq!(formatar_decimal(d("43.84"), 1), "43,8");
    }

    #[test]
    fn multiplicacao_que_nao_cabe_vira_erro_e_nao_panico() {
        let enorme = Decimal::MAX;
        assert_eq!(
            valor_item(enorme, enorme, CriterioArredondamento::Arredondar),
            Err(ErroDominio::Estouro)
        );
    }
}
