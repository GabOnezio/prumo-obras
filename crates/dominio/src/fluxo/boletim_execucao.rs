//! Estados do Boletim de Execução, o documento do fiscal (`docs/01-modulos.md` §3.3).
//!
//! ```text
//! rascunho ─► emitido   (assinado e imutável)
//! ```
//! Boletim emitido não volta nem muda. Correção é outro boletim, retificador, que aponta
//! para o primeiro; o emitido continua emitido.

use super::{achar, ErroFluxo, Papel, Pedido, Transicao};
use crate::medicao::SituacaoEvento;
use chrono::NaiveDate;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EstadoBoletim {
    Rascunho,
    Emitido,
}

impl EstadoBoletim {
    pub const TODOS: [EstadoBoletim; 2] = [EstadoBoletim::Rascunho, EstadoBoletim::Emitido];

    /// Nome do estado no banco.
    pub fn nome(self) -> &'static str {
        match self {
            EstadoBoletim::Rascunho => "rascunho",
            EstadoBoletim::Emitido => "emitido",
        }
    }

    pub fn conteudo_editavel(self) -> bool {
        self == EstadoBoletim::Rascunho
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AcaoBoletim {
    Emitir,
}

impl AcaoBoletim {
    pub const TODAS: [AcaoBoletim; 1] = [AcaoBoletim::Emitir];

    pub fn nome(self) -> &'static str {
        match self {
            AcaoBoletim::Emitir => "emitir o boletim",
        }
    }
}

/// Uma linha do boletim em rascunho: a situação de um evento e quantas evidências tem.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct LinhaDoBoletimDeExecucao {
    pub situacao: SituacaoEvento,
    /// Fotos, vistorias e diários ligados à linha.
    pub evidencias: u32,
}

/// Exigências do município para o boletim. Vêm de `config_municipio`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RegrasDoBoletim {
    /// Quantas evidências uma linha precisa para marcar "concluído".
    pub evidencias_para_concluido: u32,
}

const TABELA: [Transicao<EstadoBoletim, AcaoBoletim>; 1] = [Transicao {
    de: EstadoBoletim::Rascunho,
    acao: AcaoBoletim::Emitir,
    para: EstadoBoletim::Emitido,
    papel: Papel::Fiscal,
}];

/// Confere se o boletim pode ser emitido e devolve o novo estado.
///
/// Para emitir: ao menos uma linha; evento marcado como concluído (com ou sem pendência)
/// tem a evidência mínima do município e foi verificado até o fim do período do boletim.
pub fn transitar(
    estado: EstadoBoletim,
    acao: AcaoBoletim,
    pedido: &Pedido,
    linhas: &[LinhaDoBoletimDeExecucao],
    fim_do_periodo: NaiveDate,
    regras: &RegrasDoBoletim,
) -> Result<EstadoBoletim, ErroFluxo> {
    let invalida = ErroFluxo::TransicaoInvalida {
        documento: "Boletim de Execução",
        estado: estado.nome(),
        acao: acao.nome(),
    };
    let novo = achar(&TABELA, estado, acao, pedido, invalida, acao.nome())?;
    if linhas.is_empty() {
        return Err(ErroFluxo::BoletimVazio);
    }
    for (i, linha) in linhas.iter().enumerate() {
        let verificado_em = match linha.situacao {
            SituacaoEvento::Concluido { em } | SituacaoEvento::ConcluidoComPendencia { em } => em,
            _ => continue,
        };
        if linha.evidencias < regras.evidencias_para_concluido {
            return Err(ErroFluxo::BoletimSemEvidencia { linha: i + 1 });
        }
        if verificado_em > fim_do_periodo {
            return Err(ErroFluxo::BoletimComDataForaDoPeriodo { linha: i + 1 });
        }
    }
    Ok(novo)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::fluxo::PessoaId;
    use AcaoBoletim as A;
    use EstadoBoletim as E;

    const FISCAL: PessoaId = PessoaId(2);
    const UMA_EVIDENCIA: RegrasDoBoletim = RegrasDoBoletim {
        evidencias_para_concluido: 1,
    };

    fn dia(a: i32, m: u32, d: u32) -> NaiveDate {
        NaiveDate::from_ymd_opt(a, m, d).unwrap()
    }

    fn fim() -> NaiveDate {
        dia(2026, 12, 31)
    }

    fn pedido(papel: Papel) -> Pedido<'static> {
        Pedido {
            quem: FISCAL,
            papel,
            motivo: None,
        }
    }

    fn linha(situacao: SituacaoEvento, evidencias: u32) -> LinhaDoBoletimDeExecucao {
        LinhaDoBoletimDeExecucao {
            situacao,
            evidencias,
        }
    }

    fn concluido(em: NaiveDate) -> SituacaoEvento {
        SituacaoEvento::Concluido { em }
    }

    fn linhas_validas() -> Vec<LinhaDoBoletimDeExecucao> {
        vec![
            linha(concluido(dia(2026, 12, 11)), 2),
            linha(SituacaoEvento::em_andamento(70).unwrap(), 0),
            linha(SituacaoEvento::NaoIniciado, 0),
        ]
    }

    #[test]
    fn cada_combinacao_de_estado_acao_e_papel() {
        let mut aceitas = 0;
        for estado in E::TODOS {
            for acao in A::TODAS {
                for papel in Papel::TODOS {
                    let r = transitar(
                        estado,
                        acao,
                        &pedido(papel),
                        &linhas_validas(),
                        fim(),
                        &UMA_EVIDENCIA,
                    );
                    match (estado, papel) {
                        (E::Rascunho, Papel::Fiscal) => {
                            assert_eq!(r, Ok(E::Emitido));
                            aceitas += 1;
                        }
                        (E::Rascunho, _) => assert!(
                            matches!(r, Err(ErroFluxo::PapelNaoPode { .. })),
                            "{papel:?}: {r:?}"
                        ),
                        (E::Emitido, _) => assert!(
                            matches!(r, Err(ErroFluxo::TransicaoInvalida { .. })),
                            "{papel:?}: {r:?}"
                        ),
                    }
                }
            }
        }
        // 2 estados × 1 ação × 9 papéis = 18 combinações; só 1 passa
        assert_eq!(aceitas, 1);
    }

    #[test]
    fn boletim_emitido_e_imutavel() {
        assert!(!E::Emitido.conteudo_editavel());
        assert!(E::Rascunho.conteudo_editavel());
        let r = transitar(
            E::Emitido,
            A::Emitir,
            &pedido(Papel::Fiscal),
            &linhas_validas(),
            fim(),
            &UMA_EVIDENCIA,
        );
        assert_eq!(
            r,
            Err(ErroFluxo::TransicaoInvalida {
                documento: "Boletim de Execução",
                estado: "emitido",
                acao: "emitir o boletim",
            })
        );
    }

    #[test]
    fn a_empresa_nao_emite_o_boletim_do_fiscal() {
        let r = transitar(
            E::Rascunho,
            A::Emitir,
            &pedido(Papel::Contratada),
            &linhas_validas(),
            fim(),
            &UMA_EVIDENCIA,
        );
        assert!(matches!(r, Err(ErroFluxo::PapelNaoPode { .. })));
    }

    #[test]
    fn boletim_sem_linha_nao_e_emitido() {
        let r = transitar(
            E::Rascunho,
            A::Emitir,
            &pedido(Papel::Fiscal),
            &[],
            fim(),
            &UMA_EVIDENCIA,
        );
        assert_eq!(r, Err(ErroFluxo::BoletimVazio));
    }

    #[test]
    fn concluido_sem_a_evidencia_minima_nao_passa() {
        let linhas = vec![
            linha(SituacaoEvento::em_andamento(50).unwrap(), 0),
            linha(concluido(dia(2026, 12, 11)), 1),
        ];
        let duas = RegrasDoBoletim {
            evidencias_para_concluido: 2,
        };
        let r = transitar(
            E::Rascunho,
            A::Emitir,
            &pedido(Papel::Fiscal),
            &linhas,
            fim(),
            &duas,
        );
        assert_eq!(r, Err(ErroFluxo::BoletimSemEvidencia { linha: 2 }));
        // com uma evidência exigida, passa
        let r = transitar(
            E::Rascunho,
            A::Emitir,
            &pedido(Papel::Fiscal),
            &linhas,
            fim(),
            &UMA_EVIDENCIA,
        );
        assert_eq!(r, Ok(E::Emitido));
        // concluído com pendência também precisa de evidência
        let com_pendencia = vec![linha(
            SituacaoEvento::ConcluidoComPendencia {
                em: dia(2026, 12, 20),
            },
            0,
        )];
        let r = transitar(
            E::Rascunho,
            A::Emitir,
            &pedido(Papel::Fiscal),
            &com_pendencia,
            fim(),
            &UMA_EVIDENCIA,
        );
        assert_eq!(r, Err(ErroFluxo::BoletimSemEvidencia { linha: 1 }));
    }

    #[test]
    fn em_andamento_e_nao_iniciado_nao_pedem_evidencia() {
        let linhas = vec![
            linha(SituacaoEvento::em_andamento(10).unwrap(), 0),
            linha(SituacaoEvento::NaoIniciado, 0),
            linha(SituacaoEvento::Paralisado, 0),
        ];
        let cinco = RegrasDoBoletim {
            evidencias_para_concluido: 5,
        };
        let r = transitar(
            E::Rascunho,
            A::Emitir,
            &pedido(Papel::Fiscal),
            &linhas,
            fim(),
            &cinco,
        );
        assert_eq!(r, Ok(E::Emitido));
    }

    #[test]
    fn conclusao_verificada_depois_do_periodo_nao_passa() {
        let linhas = vec![linha(concluido(dia(2027, 1, 2)), 3)];
        let r = transitar(
            E::Rascunho,
            A::Emitir,
            &pedido(Papel::Fiscal),
            &linhas,
            fim(),
            &UMA_EVIDENCIA,
        );
        assert_eq!(r, Err(ErroFluxo::BoletimComDataForaDoPeriodo { linha: 1 }));
        // no último dia do período, passa
        let linhas = vec![linha(concluido(fim()), 3)];
        let r = transitar(
            E::Rascunho,
            A::Emitir,
            &pedido(Papel::Fiscal),
            &linhas,
            fim(),
            &UMA_EVIDENCIA,
        );
        assert_eq!(r, Ok(E::Emitido));
    }
}
