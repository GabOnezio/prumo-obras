//! Conferência da medição por eventos contra o Boletim de Execução.
//! Ver `docs/10-execucao-eventos-previsao.md` §5 e §9 (invariantes 1 e 6).

use crate::dinheiro::Dinheiro;
use crate::ErroDominio;
use chrono::NaiveDate;

/// Situação de um evento em um Boletim de Execução **emitido**.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SituacaoEvento {
    NaoIniciado,
    EmAndamento { avanco_pct: u8 },
    Concluido { em: NaiveDate },
    ConcluidoComPendencia { em: NaiveDate },
    Paralisado,
}

impl SituacaoEvento {
    pub fn em_andamento(avanco_pct: u8) -> Result<SituacaoEvento, ErroDominio> {
        if (1..=99).contains(&avanco_pct) {
            Ok(SituacaoEvento::EmAndamento { avanco_pct })
        } else {
            Err(ErroDominio::AvancoInvalido(avanco_pct))
        }
    }

    /// Só `Concluido` libera o pagamento. `ConcluidoComPendencia` não libera
    /// (resposta provisória da questão 19 em `docs/QUESTOES-ABERTAS.md`).
    pub fn libera_pagamento(self) -> bool {
        matches!(self, SituacaoEvento::Concluido { .. })
    }
}

/// Um evento que a empresa declarou concluído na medição.
#[derive(Clone, Copy, Debug)]
pub struct EventoDeclarado {
    pub valor: Dinheiro,
    /// `None` quando nenhum boletim emitido cita o evento.
    pub situacao_no_boletim: Option<SituacaoEvento>,
    pub glosado: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Conferencia {
    pub valor_bruto: Dinheiro,
    pub valor_glosado: Dinheiro,
    /// Soma dos eventos não glosados que o boletim marca como concluídos.
    pub valor_conferido: Dinheiro,
    /// Posições dos eventos que impedem a aprovação: nem conferidos, nem glosados.
    pub pendentes: Vec<usize>,
}

impl Conferencia {
    pub fn pode_aprovar(&self) -> bool {
        self.pendentes.is_empty()
    }
}

/// Glosar tira o evento inteiro. Evento sem boletim que o marque concluído
/// fica pendente, e medição com pendência não é aprovada.
pub fn conferir_medicao(eventos: &[EventoDeclarado]) -> Result<Conferencia, ErroDominio> {
    let mut c = Conferencia {
        valor_bruto: Dinheiro::ZERO,
        valor_glosado: Dinheiro::ZERO,
        valor_conferido: Dinheiro::ZERO,
        pendentes: Vec::new(),
    };
    for (i, e) in eventos.iter().enumerate() {
        c.valor_bruto = c.valor_bruto.somar(e.valor)?;
        if e.glosado {
            c.valor_glosado = c.valor_glosado.somar(e.valor)?;
        } else if e
            .situacao_no_boletim
            .is_some_and(SituacaoEvento::libera_pagamento)
        {
            c.valor_conferido = c.valor_conferido.somar(e.valor)?;
        } else {
            c.pendentes.push(i);
        }
    }
    Ok(c)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dia(a: i32, m: u32, d: u32) -> NaiveDate {
        NaiveDate::from_ymd_opt(a, m, d).unwrap()
    }

    fn declarado(
        centavos: i64,
        situacao: Option<SituacaoEvento>,
        glosado: bool,
    ) -> EventoDeclarado {
        EventoDeclarado {
            valor: Dinheiro::de_centavos(centavos),
            situacao_no_boletim: situacao,
            glosado,
        }
    }

    #[test]
    fn evento_em_andamento_no_boletim_impede_a_aprovacao() {
        let c = conferir_medicao(&[
            declarado(
                2_601_474,
                Some(SituacaoEvento::Concluido {
                    em: dia(2026, 12, 11),
                }),
                false,
            ),
            declarado(
                1_664_160,
                Some(SituacaoEvento::EmAndamento { avanco_pct: 70 }),
                false,
            ),
        ])
        .unwrap();
        assert!(!c.pode_aprovar());
        assert_eq!(c.pendentes, vec![1]);
        assert_eq!(c.valor_bruto, Dinheiro::de_centavos(4_265_634));
        assert_eq!(c.valor_conferido, Dinheiro::de_centavos(2_601_474));
    }

    #[test]
    fn evento_sem_boletim_impede_a_aprovacao() {
        let c = conferir_medicao(&[declarado(1_664_160, None, false)]).unwrap();
        assert_eq!(c.pendentes, vec![0]);
    }

    #[test]
    fn concluido_com_pendencia_e_paralisado_nao_liberam() {
        for s in [
            SituacaoEvento::ConcluidoComPendencia {
                em: dia(2026, 12, 22),
            },
            SituacaoEvento::Paralisado,
            SituacaoEvento::NaoIniciado,
        ] {
            assert!(!conferir_medicao(&[declarado(100, Some(s), false)])
                .unwrap()
                .pode_aprovar());
        }
    }

    #[test]
    fn glosa_tira_o_evento_inteiro_e_libera_a_aprovacao() {
        let c = conferir_medicao(&[
            declarado(
                2_601_474,
                Some(SituacaoEvento::Concluido {
                    em: dia(2026, 12, 11),
                }),
                false,
            ),
            declarado(
                1_664_160,
                Some(SituacaoEvento::EmAndamento { avanco_pct: 70 }),
                true,
            ),
        ])
        .unwrap();
        assert!(c.pode_aprovar());
        assert_eq!(c.valor_glosado, Dinheiro::de_centavos(1_664_160));
        assert_eq!(c.valor_conferido, Dinheiro::de_centavos(2_601_474));
    }

    #[test]
    fn todos_concluidos_aprova_o_valor_bruto() {
        let concluido = Some(SituacaoEvento::Concluido {
            em: dia(2026, 12, 22),
        });
        let c = conferir_medicao(&[
            declarado(2_601_474, concluido, false),
            declarado(1_664_160, concluido, false),
        ])
        .unwrap();
        assert!(c.pode_aprovar());
        assert_eq!(c.valor_conferido, c.valor_bruto);
        assert!(c.valor_glosado.eh_zero());
    }

    #[test]
    fn avanco_em_andamento_fica_entre_1_e_99() {
        assert!(SituacaoEvento::em_andamento(70).is_ok());
        assert_eq!(
            SituacaoEvento::em_andamento(0),
            Err(ErroDominio::AvancoInvalido(0))
        );
        assert_eq!(
            SituacaoEvento::em_andamento(100),
            Err(ErroDominio::AvancoInvalido(100))
        );
    }
}
