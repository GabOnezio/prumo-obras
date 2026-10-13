//! Estados do diário de obras (`docs/01-modulos.md` §3.2).
//!
//! ```text
//! rascunho ─► fechado ─► em_validacao ─► validado
//!                              └───────► devolvido (com motivo)
//! ```
//! Dia fechado nunca é sobrescrito. Diário devolvido não volta a rascunho: a empresa retifica
//! com um registro novo, que aponta para o devolvido. Por isso `devolvido` não tem saída.

use super::{achar, ErroFluxo, Papel, Pedido, PessoaId, Transicao};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EstadoDiario {
    Rascunho,
    Fechado,
    EmValidacao,
    Validado,
    Devolvido,
}

impl EstadoDiario {
    pub const TODOS: [EstadoDiario; 5] = [
        EstadoDiario::Rascunho,
        EstadoDiario::Fechado,
        EstadoDiario::EmValidacao,
        EstadoDiario::Validado,
        EstadoDiario::Devolvido,
    ];

    /// Nome do estado no banco.
    pub fn nome(self) -> &'static str {
        match self {
            EstadoDiario::Rascunho => "rascunho",
            EstadoDiario::Fechado => "fechado",
            EstadoDiario::EmValidacao => "em_validacao",
            EstadoDiario::Validado => "validado",
            EstadoDiario::Devolvido => "devolvido",
        }
    }

    /// O texto, o efetivo, os serviços e as fotos só mudam em rascunho.
    pub fn conteudo_editavel(self) -> bool {
        self == EstadoDiario::Rascunho
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AcaoDiario {
    Fechar,
    IniciarValidacao,
    Validar,
    Devolver,
}

impl AcaoDiario {
    pub const TODAS: [AcaoDiario; 4] = [
        AcaoDiario::Fechar,
        AcaoDiario::IniciarValidacao,
        AcaoDiario::Validar,
        AcaoDiario::Devolver,
    ];

    pub fn nome(self) -> &'static str {
        match self {
            AcaoDiario::Fechar => "fechar o diário",
            AcaoDiario::IniciarValidacao => "iniciar a validação",
            AcaoDiario::Validar => "validar o diário",
            AcaoDiario::Devolver => "devolver o diário",
        }
    }
}

const TABELA: [Transicao<EstadoDiario, AcaoDiario>; 4] = {
    use AcaoDiario as A;
    use EstadoDiario as E;
    [
        Transicao {
            de: E::Rascunho,
            acao: A::Fechar,
            para: E::Fechado,
            papel: Papel::Contratada,
        },
        Transicao {
            de: E::Fechado,
            acao: A::IniciarValidacao,
            para: E::EmValidacao,
            papel: Papel::Fiscal,
        },
        Transicao {
            de: E::EmValidacao,
            acao: A::Validar,
            para: E::Validado,
            papel: Papel::Fiscal,
        },
        Transicao {
            de: E::EmValidacao,
            acao: A::Devolver,
            para: E::Devolvido,
            papel: Papel::Fiscal,
        },
    ]
};

/// Confere se a ação pode ser feita e devolve o novo estado. `fechado_por` é quem fechou o
/// diário pela empresa.
pub fn transitar(
    estado: EstadoDiario,
    acao: AcaoDiario,
    pedido: &Pedido,
    fechado_por: Option<PessoaId>,
) -> Result<EstadoDiario, ErroFluxo> {
    let invalida = ErroFluxo::TransicaoInvalida {
        documento: "diário",
        estado: estado.nome(),
        acao: acao.nome(),
    };
    let novo = achar(&TABELA, estado, acao, pedido, invalida, acao.nome())?;
    match acao {
        AcaoDiario::Validar if fechado_por == Some(pedido.quem) => {
            Err(ErroFluxo::AutorNaoAprova { acao: acao.nome() })
        }
        AcaoDiario::Devolver if !pedido.tem_motivo() => {
            Err(ErroFluxo::MotivoObrigatorio { acao: acao.nome() })
        }
        _ => Ok(novo),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use AcaoDiario as A;
    use EstadoDiario as E;

    const APONTADOR: PessoaId = PessoaId(1);
    const FISCAL: PessoaId = PessoaId(2);

    fn pedido(quem: PessoaId, papel: Papel) -> Pedido<'static> {
        Pedido {
            quem,
            papel,
            motivo: Some("motivo do teste"),
        }
    }

    #[test]
    fn cada_combinacao_de_estado_acao_e_papel() {
        // Escritas aqui de novo, à mão: é contra esta lista que a tabela é conferida.
        let permitidas = [
            (E::Rascunho, A::Fechar, E::Fechado, Papel::Contratada),
            (
                E::Fechado,
                A::IniciarValidacao,
                E::EmValidacao,
                Papel::Fiscal,
            ),
            (E::EmValidacao, A::Validar, E::Validado, Papel::Fiscal),
            (E::EmValidacao, A::Devolver, E::Devolvido, Papel::Fiscal),
        ];
        let mut aceitas = 0;
        for estado in E::TODOS {
            for acao in A::TODAS {
                let prevista = permitidas
                    .iter()
                    .find(|(de, a, _, _)| *de == estado && *a == acao);
                for papel in Papel::TODOS {
                    let r = transitar(estado, acao, &pedido(PessoaId(99), papel), Some(APONTADOR));
                    match prevista {
                        Some((_, _, para, quem)) if *quem == papel => {
                            assert_eq!(r, Ok(*para), "{estado:?} {acao:?} {papel:?}");
                            aceitas += 1;
                        }
                        Some(_) => assert!(
                            matches!(r, Err(ErroFluxo::PapelNaoPode { .. })),
                            "{estado:?} {acao:?} {papel:?}: {r:?}"
                        ),
                        None => assert!(
                            matches!(r, Err(ErroFluxo::TransicaoInvalida { .. })),
                            "{estado:?} {acao:?} {papel:?}: {r:?}"
                        ),
                    }
                }
            }
        }
        // 5 estados × 4 ações × 9 papéis = 180 combinações; só 4 passam
        assert_eq!(aceitas, 4);
    }

    #[test]
    fn diario_fechado_validado_ou_devolvido_nao_volta_a_rascunho() {
        for estado in [E::Fechado, E::EmValidacao, E::Validado, E::Devolvido] {
            assert!(!estado.conteudo_editavel());
            for acao in A::TODAS {
                for papel in Papel::TODOS {
                    let r = transitar(estado, acao, &pedido(PessoaId(99), papel), Some(APONTADOR));
                    assert_ne!(r, Ok(E::Rascunho), "{estado:?} {acao:?} {papel:?}");
                }
            }
        }
        // validado e devolvido são finais: a correção é um registro novo
        for estado in [E::Validado, E::Devolvido] {
            for acao in A::TODAS {
                let r = transitar(
                    estado,
                    acao,
                    &pedido(FISCAL, Papel::Fiscal),
                    Some(APONTADOR),
                );
                assert!(matches!(r, Err(ErroFluxo::TransicaoInvalida { .. })));
            }
        }
    }

    #[test]
    fn o_fiscal_nao_escreve_o_diario_da_empresa() {
        let r = transitar(E::Rascunho, A::Fechar, &pedido(FISCAL, Papel::Fiscal), None);
        assert!(matches!(r, Err(ErroFluxo::PapelNaoPode { .. })));
    }

    #[test]
    fn quem_fechou_nao_valida() {
        // a mesma pessoa aparece como fiscal
        let r = transitar(
            E::EmValidacao,
            A::Validar,
            &pedido(APONTADOR, Papel::Fiscal),
            Some(APONTADOR),
        );
        assert_eq!(
            r,
            Err(ErroFluxo::AutorNaoAprova {
                acao: "validar o diário"
            })
        );
        let r = transitar(
            E::EmValidacao,
            A::Validar,
            &pedido(FISCAL, Papel::Fiscal),
            Some(APONTADOR),
        );
        assert_eq!(r, Ok(E::Validado));
    }

    #[test]
    fn devolver_exige_motivo() {
        let sem_motivo = Pedido {
            quem: FISCAL,
            papel: Papel::Fiscal,
            motivo: None,
        };
        let r = transitar(E::EmValidacao, A::Devolver, &sem_motivo, Some(APONTADOR));
        assert_eq!(
            r,
            Err(ErroFluxo::MotivoObrigatorio {
                acao: "devolver o diário"
            })
        );
    }

    #[test]
    fn nomes_dos_estados_sao_unicos() {
        let mut nomes: Vec<&str> = E::TODOS.iter().map(|e| e.nome()).collect();
        nomes.sort_unstable();
        nomes.dedup();
        assert_eq!(nomes.len(), E::TODOS.len());
    }
}
