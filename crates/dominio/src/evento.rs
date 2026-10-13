//! Evento = agrupador × frente de obra. Ver `docs/10-execucao-eventos-previsao.md` §1 e §4.

use crate::dinheiro::{valor_item, CriterioArredondamento, Dinheiro};
use crate::ErroDominio;
use rust_decimal::Decimal;

/// Quanto de um serviço da planilha cai em uma frente.
#[derive(Clone, Debug)]
pub struct ServicoNaFrente {
    /// Código do item na planilha do órgão (ex.: `3.1`).
    pub item: String,
    pub descricao: String,
    pub unidade: String,
    pub quantidade: Decimal,
    pub preco_unitario: Decimal,
}

impl ServicoNaFrente {
    pub fn valor(&self, criterio: CriterioArredondamento) -> Result<Dinheiro, ErroDominio> {
        valor_item(self.quantidade, self.preco_unitario, criterio)
    }
}

#[derive(Clone, Debug)]
pub struct Evento {
    pub agrupador: String,
    pub frente: String,
    pub servicos: Vec<ServicoNaFrente>,
}

impl Evento {
    pub fn nome(&self) -> String {
        format!("{} × {}", self.agrupador, self.frente)
    }

    /// `Σ arredonda(quantidade na frente × preço unitário)`, serviço a serviço.
    /// Arredonda cada serviço antes de somar, como `fn_recalcular_eventos` no banco;
    /// `crates/paridade` confere os dois. Por arredondar em cada frente, a soma dos
    /// eventos pode diferir do valor da planilha por centavos (ADR 0008, questão 36).
    pub fn valor(&self, criterio: CriterioArredondamento) -> Result<Dinheiro, ErroDominio> {
        self.servicos
            .iter()
            .try_fold(Dinheiro::ZERO, |soma, s| soma.somar(s.valor(criterio)?))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn servico(item: &str, quantidade: &str, preco: &str) -> ServicoNaFrente {
        ServicoNaFrente {
            item: item.into(),
            descricao: String::new(),
            unidade: String::new(),
            quantidade: quantidade.parse().unwrap(),
            preco_unitario: preco.parse().unwrap(),
        }
    }

    fn evento(servicos: Vec<ServicoNaFrente>) -> Evento {
        Evento {
            agrupador: "Agrupador".into(),
            frente: "Frente".into(),
            servicos,
        }
    }

    #[test]
    fn pilares_do_terreo_valem_26_014_74() {
        // docs/10 §1: fôrma, armadura e concreto dos pilares do Térreo
        let e = evento(vec![
            servico("2.1", "96.00", "62.30"),
            servico("2.2", "1150.00", "9.84"),
            servico("2.3", "11.10", "785.40"),
        ]);
        assert_eq!(
            e.valor(CriterioArredondamento::Arredondar).unwrap(),
            Dinheiro::de_centavos(2_601_474)
        );
    }

    #[test]
    fn alvenaria_do_terreo_vale_16_641_60() {
        let e = evento(vec![
            servico("3.1", "160.00", "89.15"),
            servico("3.2", "320.00", "7.43"),
        ]);
        assert_eq!(
            e.valor(CriterioArredondamento::Arredondar).unwrap(),
            Dinheiro::de_centavos(1_664_160)
        );
    }

    #[test]
    fn arredonda_cada_servico_antes_de_somar() {
        // dois serviços de 0,005: somados antes dariam 0,01; arredondados antes, 0,02
        let e = evento(vec![servico("a", "1", "0.005"), servico("b", "1", "0.005")]);
        assert_eq!(
            e.valor(CriterioArredondamento::Arredondar).unwrap(),
            Dinheiro::de_centavos(2)
        );
        assert_eq!(
            e.valor(CriterioArredondamento::Truncar).unwrap(),
            Dinheiro::ZERO
        );
    }

    #[test]
    fn nome_e_agrupador_vezes_frente() {
        let e = Evento {
            agrupador: "Alvenaria".into(),
            frente: "Térreo".into(),
            servicos: vec![],
        };
        assert_eq!(e.nome(), "Alvenaria × Térreo");
    }
}
