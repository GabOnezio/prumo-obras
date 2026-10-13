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
    /// Leva um número inteiro com `escala` casas decimais para centavos.
    ///
    /// A conta é toda em inteiros, sem perda. `Arredondar` é o `round(numeric, 2)` do
    /// PostgreSQL (meio centavo vai para longe do zero) e `Truncar` é o `trunc(numeric, 2)`.
    fn para_centavos(self, valor: i128, escala: u32) -> Result<i128, ErroDominio> {
        if escala <= 2 {
            let fator = 10_i128.pow(2 - escala);
            return valor.checked_mul(fator).ok_or(ErroDominio::Estouro);
        }
        let divisor = 10_i128
            .checked_pow(escala - 2)
            .ok_or(ErroDominio::Estouro)?;
        let quociente = valor / divisor;
        let resto = valor % divisor;
        let sobe = match self {
            CriterioArredondamento::Truncar => false,
            CriterioArredondamento::Arredondar => {
                resto.unsigned_abs() * 2 >= divisor.unsigned_abs()
            }
        };
        Ok(if sobe {
            quociente + valor.signum()
        } else {
            quociente
        })
    }
}

/// `a × b ÷ 10^casas_a_mais`, em centavos, pelo critério do contrato.
///
/// O produto é feito com os inteiros dos dois números, e não com a multiplicação do tipo
/// decimal: quando o resultado exato não cabe em 28 dígitos, o tipo decimal arredonda as
/// últimas casas sem avisar, e o centavo poderia sair diferente do banco. Aqui o resultado é
/// o exato, ou é erro.
fn produto_em_centavos(
    a: Decimal,
    b: Decimal,
    casas_a_mais: u32,
    criterio: CriterioArredondamento,
) -> Result<Dinheiro, ErroDominio> {
    let produto = a
        .mantissa()
        .checked_mul(b.mantissa())
        .ok_or(ErroDominio::Estouro)?;
    let escala = a.scale() + b.scale() + casas_a_mais;
    let centavos = criterio.para_centavos(produto, escala)?;
    Decimal::try_from_i128_with_scale(centavos, 2)
        .map(Dinheiro)
        .map_err(|_| ErroDominio::Estouro)
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
/// É o mesmo cálculo de `fn_valor_item` do banco; `crates/paridade` confere os dois, centavo
/// a centavo, com o banco de pé.
pub fn valor_item(
    quantidade: Decimal,
    preco_unitario: Decimal,
    criterio: CriterioArredondamento,
) -> Result<Dinheiro, ErroDominio> {
    produto_em_centavos(quantidade, preco_unitario, 0, criterio)
}

/// `base × percentual ÷ 100`, com duas casas, pelo critério do contrato.
pub fn percentual(
    base: Dinheiro,
    percentual: Decimal,
    criterio: CriterioArredondamento,
) -> Result<Dinheiro, ErroDominio> {
    produto_em_centavos(base.0, percentual, 2, criterio)
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

    #[test]
    fn meio_centavo_exato_sobe_e_um_fio_abaixo_nao() {
        use CriterioArredondamento::{Arredondar, Truncar};
        // 1 × 0,005 = meio centavo exato
        assert_eq!(
            valor_item(d("1"), d("0.005"), Arredondar).unwrap(),
            Dinheiro::de_centavos(1)
        );
        assert_eq!(
            valor_item(d("1"), d("0.005"), Truncar).unwrap(),
            Dinheiro::ZERO
        );
        // 0,9999 × 0,005 = 0,00499950: abaixo de meio centavo
        assert_eq!(
            valor_item(d("0.9999"), d("0.005"), Arredondar).unwrap(),
            Dinheiro::ZERO
        );
        // negativo: meio centavo vai para longe do zero; truncar vai para o zero
        assert_eq!(
            valor_item(d("-1"), d("0.005"), Arredondar).unwrap(),
            Dinheiro::de_centavos(-1)
        );
        assert_eq!(
            valor_item(d("-1"), d("0.015"), Truncar).unwrap(),
            Dinheiro::de_centavos(-1)
        );
    }

    #[test]
    fn numeros_sem_casas_decimais_viram_centavos() {
        // escala 0 + escala 0: o resultado ganha as duas casas
        let v = valor_item(d("3"), d("7"), CriterioArredondamento::Arredondar).unwrap();
        assert_eq!(v, Dinheiro::de_centavos(2_100));
        assert_eq!(v.formatar(), "21,00");
        // escala 1 no total
        let v = valor_item(d("2.5"), d("3"), CriterioArredondamento::Truncar).unwrap();
        assert_eq!(v, Dinheiro::de_centavos(750));
    }

    #[test]
    fn no_limite_das_colunas_do_banco_a_conta_e_exata() {
        // 9999999999,9999 × 9,9999 = 99998999999,99900001 (exato, 8 casas)
        let (q, p) = (d("9999999999.9999"), d("9.9999"));
        assert_eq!(
            valor_item(q, p, CriterioArredondamento::Arredondar)
                .unwrap()
                .decimal(),
            d("99999000000.00")
        );
        assert_eq!(
            valor_item(q, p, CriterioArredondamento::Truncar)
                .unwrap()
                .decimal(),
            d("99998999999.99")
        );
        // O produto exato abaixo tem 30 dígitos e o tipo decimal guarda 28: a multiplicação dele
        // descartaria as duas últimas casas. A conta em inteiros não descarta nada.
        // 98765432109876,5432 × 87654321,1234 = 8657216902050480110381,93263088
        let (q, p) = (d("98765432109876.5432"), d("87654321.1234"));
        assert_eq!(
            valor_item(q, p, CriterioArredondamento::Truncar)
                .unwrap()
                .decimal(),
            d("8657216902050480110381.93")
        );
        assert_eq!(
            valor_item(q, p, CriterioArredondamento::Arredondar)
                .unwrap()
                .decimal(),
            d("8657216902050480110381.93")
        );
    }

    #[test]
    fn resultado_que_nao_cabe_em_28_digitos_e_erro() {
        // 99999999999999.9999² tem 36 dígitos; em centavos seriam 30
        let maximo = d("99999999999999.9999");
        assert_eq!(
            valor_item(maximo, maximo, CriterioArredondamento::Arredondar),
            Err(ErroDominio::Estouro)
        );
    }

    #[test]
    fn percentual_com_meio_centavo() {
        // 0,50 × 1% = 0,005
        let base = Dinheiro::de_centavos(50);
        assert_eq!(
            percentual(base, d("1"), CriterioArredondamento::Arredondar).unwrap(),
            Dinheiro::de_centavos(1)
        );
        assert_eq!(
            percentual(base, d("1"), CriterioArredondamento::Truncar).unwrap(),
            Dinheiro::ZERO
        );
        // 1.234,56 × 7,5% = 92,592
        assert_eq!(
            percentual(
                Dinheiro::de_centavos(123_456),
                d("7.5"),
                CriterioArredondamento::Arredondar
            )
            .unwrap(),
            Dinheiro::de_centavos(9_259)
        );
    }
}
