//! Contas em inteiros, sem perda, para o que tem que bater com o `NUMERIC` do banco.

use crate::ErroDominio;

/// `numerador ÷ denominador`, arredondado para o inteiro mais próximo. Meio vai para longe
/// do zero, como o `round` do PostgreSQL.
pub(crate) fn dividir_arredondando(
    numerador: i128,
    denominador: i128,
) -> Result<i128, ErroDominio> {
    if denominador == 0 {
        return Err(ErroDominio::DivisaoPorZero);
    }
    let quociente = numerador / denominador;
    let resto = numerador % denominador;
    let dobro_do_resto = resto
        .unsigned_abs()
        .checked_mul(2)
        .ok_or(ErroDominio::Estouro)?;
    if dobro_do_resto < denominador.unsigned_abs() {
        return Ok(quociente);
    }
    let sinal = if (numerador < 0) == (denominador < 0) {
        1
    } else {
        -1
    };
    Ok(quociente + sinal)
}

pub(crate) fn potencia_de_dez(casas: u32) -> Result<i128, ErroDominio> {
    10_i128.checked_pow(casas).ok_or(ErroDominio::Estouro)
}

/// `a × b`, com erro no lugar de estouro.
pub(crate) fn vezes(a: i128, b: i128) -> Result<i128, ErroDominio> {
    a.checked_mul(b).ok_or(ErroDominio::Estouro)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn meio_vai_para_longe_do_zero() {
        assert_eq!(dividir_arredondando(5, 10).unwrap(), 1); // 0,5
        assert_eq!(dividir_arredondando(-5, 10).unwrap(), -1);
        assert_eq!(dividir_arredondando(5, -10).unwrap(), -1);
        assert_eq!(dividir_arredondando(-5, -10).unwrap(), 1);
        assert_eq!(dividir_arredondando(15, 10).unwrap(), 2); // 1,5
        assert_eq!(dividir_arredondando(25, 10).unwrap(), 3); // 2,5: não é "meio para o par"
    }

    #[test]
    fn abaixo_de_meio_fica() {
        assert_eq!(dividir_arredondando(49, 100).unwrap(), 0);
        assert_eq!(dividir_arredondando(-49, 100).unwrap(), 0);
        assert_eq!(dividir_arredondando(149, 100).unwrap(), 1);
        assert_eq!(dividir_arredondando(0, 7).unwrap(), 0);
        assert_eq!(dividir_arredondando(21, 7).unwrap(), 3);
    }

    #[test]
    fn divisao_por_zero_e_erro() {
        assert_eq!(dividir_arredondando(1, 0), Err(ErroDominio::DivisaoPorZero));
    }
}
