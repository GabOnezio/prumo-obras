//! Estados do aditivo (`docs/01-modulos.md` §3.6; `status_aditivo` no banco).
//!
//! ```text
//! rascunho ─► enviado ─► homologado   (gera a planilha seguinte, Rev. N+1)
//!                  └───► rejeitado    (com motivo)
//! ```
//! Homologado e rejeitado são finais e imutáveis.

use super::{achar, ErroFluxo, Papel, Pedido, PessoaId, Transicao};
use crate::aditivo::SituacaoDosLimites;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EstadoAditivo {
    Rascunho,
    Enviado,
    Homologado,
    Rejeitado,
}

impl EstadoAditivo {
    pub const TODOS: [EstadoAditivo; 4] = [
        EstadoAditivo::Rascunho,
        EstadoAditivo::Enviado,
        EstadoAditivo::Homologado,
        EstadoAditivo::Rejeitado,
    ];

    /// Nome do estado no banco.
    pub fn nome(self) -> &'static str {
        match self {
            EstadoAditivo::Rascunho => "rascunho",
            EstadoAditivo::Enviado => "enviado",
            EstadoAditivo::Homologado => "homologado",
            EstadoAditivo::Rejeitado => "rejeitado",
        }
    }

    /// Os itens do aditivo só mudam em rascunho.
    pub fn conteudo_editavel(self) -> bool {
        self == EstadoAditivo::Rascunho
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AcaoAditivo {
    Enviar,
    Homologar,
    Rejeitar,
}

impl AcaoAditivo {
    pub const TODAS: [AcaoAditivo; 3] = [
        AcaoAditivo::Enviar,
        AcaoAditivo::Homologar,
        AcaoAditivo::Rejeitar,
    ];

    pub fn nome(self) -> &'static str {
        match self {
            AcaoAditivo::Enviar => "enviar o aditivo",
            AcaoAditivo::Homologar => "homologar o aditivo",
            AcaoAditivo::Rejeitar => "rejeitar o aditivo",
        }
    }
}

/// O que a homologação confere.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SituacaoDoAditivo {
    /// Quem montou e enviou o aditivo.
    pub enviado_por: Option<PessoaId>,
    /// Limites com este aditivo somado aos já homologados (`limites_dos_aditivos`).
    pub limites: SituacaoDosLimites,
    /// Há parecer do controle interno ou do jurídico anexado.
    pub tem_parecer: bool,
    /// O termo aditivo tem data de assinatura.
    pub termo_assinado: bool,
}

/// Exigências do município para o aditivo. Vêm de `config_municipio`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RegrasDoAditivo {
    pub parecer_exigido: bool,
}

const TABELA: [Transicao<EstadoAditivo, AcaoAditivo>; 3] = {
    use AcaoAditivo as A;
    use EstadoAditivo as E;
    [
        Transicao {
            de: E::Rascunho,
            acao: A::Enviar,
            para: E::Enviado,
            papel: Papel::Planejamento,
        },
        Transicao {
            de: E::Enviado,
            acao: A::Homologar,
            para: E::Homologado,
            papel: Papel::Gestor,
        },
        Transicao {
            de: E::Enviado,
            acao: A::Rejeitar,
            para: E::Rejeitado,
            papel: Papel::Gestor,
        },
    ]
};

/// Confere se a ação pode ser feita e devolve o novo estado.
///
/// Aditivo que passa do limite legal não é homologado. `TODO(jurídico)`: a lei pode admitir
/// exceções (supressão por acordo entre as partes, por exemplo); nenhuma está implementada,
/// e a questão 40 de `docs/QUESTOES-ABERTAS.md` pede a conferência.
pub fn transitar(
    estado: EstadoAditivo,
    acao: AcaoAditivo,
    pedido: &Pedido,
    situacao: &SituacaoDoAditivo,
    regras: &RegrasDoAditivo,
) -> Result<EstadoAditivo, ErroFluxo> {
    let invalida = ErroFluxo::TransicaoInvalida {
        documento: "aditivo",
        estado: estado.nome(),
        acao: acao.nome(),
    };
    let novo = achar(&TABELA, estado, acao, pedido, invalida, acao.nome())?;
    match acao {
        AcaoAditivo::Enviar => {}
        AcaoAditivo::Rejeitar => {
            if !pedido.tem_motivo() {
                return Err(ErroFluxo::MotivoObrigatorio { acao: acao.nome() });
            }
        }
        AcaoAditivo::Homologar => {
            if situacao.enviado_por == Some(pedido.quem) {
                return Err(ErroFluxo::AutorNaoAprova { acao: acao.nome() });
            }
            if situacao.limites == SituacaoDosLimites::Excede {
                return Err(ErroFluxo::AditivoAcimaDoLimite);
            }
            if regras.parecer_exigido && !situacao.tem_parecer {
                return Err(ErroFluxo::AditivoSemParecer);
            }
            if !situacao.termo_assinado {
                return Err(ErroFluxo::AditivoSemAssinatura);
            }
        }
    }
    Ok(novo)
}

#[cfg(test)]
mod tests {
    use super::*;
    use AcaoAditivo as A;
    use EstadoAditivo as E;

    const ORCAMENTISTA: PessoaId = PessoaId(1);
    const SECRETARIO: PessoaId = PessoaId(2);
    const COM_PARECER: RegrasDoAditivo = RegrasDoAditivo {
        parecer_exigido: true,
    };
    const SEM_PARECER: RegrasDoAditivo = RegrasDoAditivo {
        parecer_exigido: false,
    };

    fn pedido(quem: PessoaId, papel: Papel) -> Pedido<'static> {
        Pedido {
            quem,
            papel,
            motivo: Some("motivo do teste"),
        }
    }

    /// Aditivo pronto para homologar.
    fn pronto() -> SituacaoDoAditivo {
        SituacaoDoAditivo {
            enviado_por: Some(ORCAMENTISTA),
            limites: SituacaoDosLimites::Dentro,
            tem_parecer: true,
            termo_assinado: true,
        }
    }

    #[test]
    fn cada_combinacao_de_estado_acao_e_papel() {
        // Escritas aqui de novo, à mão: é contra esta lista que a tabela é conferida.
        let permitidas = [
            (E::Rascunho, A::Enviar, E::Enviado, Papel::Planejamento),
            (E::Enviado, A::Homologar, E::Homologado, Papel::Gestor),
            (E::Enviado, A::Rejeitar, E::Rejeitado, Papel::Gestor),
        ];
        let mut aceitas = 0;
        for estado in E::TODOS {
            for acao in A::TODAS {
                let prevista = permitidas
                    .iter()
                    .find(|(de, a, _, _)| *de == estado && *a == acao);
                for papel in Papel::TODOS {
                    let r = transitar(
                        estado,
                        acao,
                        &pedido(PessoaId(99), papel),
                        &pronto(),
                        &COM_PARECER,
                    );
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
        // 4 estados × 3 ações × 9 papéis = 108 combinações; só 3 passam
        assert_eq!(aceitas, 3);
    }

    #[test]
    fn homologado_e_rejeitado_sao_finais() {
        for estado in [E::Homologado, E::Rejeitado] {
            assert!(!estado.conteudo_editavel());
            for acao in A::TODAS {
                for papel in Papel::TODOS {
                    let r = transitar(
                        estado,
                        acao,
                        &pedido(PessoaId(99), papel),
                        &pronto(),
                        &COM_PARECER,
                    );
                    assert!(matches!(r, Err(ErroFluxo::TransicaoInvalida { .. })));
                }
            }
        }
    }

    #[test]
    fn quem_montou_o_aditivo_nao_homologa() {
        // a mesma pessoa tem também o papel de gestor
        let r = transitar(
            E::Enviado,
            A::Homologar,
            &pedido(ORCAMENTISTA, Papel::Gestor),
            &pronto(),
            &COM_PARECER,
        );
        assert_eq!(
            r,
            Err(ErroFluxo::AutorNaoAprova {
                acao: "homologar o aditivo"
            })
        );
    }

    #[test]
    fn aditivo_acima_do_limite_nao_e_homologado() {
        let acima = SituacaoDoAditivo {
            limites: SituacaoDosLimites::Excede,
            ..pronto()
        };
        let r = transitar(
            E::Enviado,
            A::Homologar,
            &pedido(SECRETARIO, Papel::Gestor),
            &acima,
            &COM_PARECER,
        );
        assert_eq!(r, Err(ErroFluxo::AditivoAcimaDoLimite));
        // perto do teto ainda passa: "atenção" é aviso, não bloqueio
        let perto = SituacaoDoAditivo {
            limites: SituacaoDosLimites::Atencao,
            ..pronto()
        };
        let r = transitar(
            E::Enviado,
            A::Homologar,
            &pedido(SECRETARIO, Papel::Gestor),
            &perto,
            &COM_PARECER,
        );
        assert_eq!(r, Ok(E::Homologado));
        // acima do limite, dá para rejeitar
        let r = transitar(
            E::Enviado,
            A::Rejeitar,
            &pedido(SECRETARIO, Papel::Gestor),
            &acima,
            &COM_PARECER,
        );
        assert_eq!(r, Ok(E::Rejeitado));
    }

    #[test]
    fn parecer_so_e_cobrado_onde_o_municipio_exige() {
        let sem = SituacaoDoAditivo {
            tem_parecer: false,
            ..pronto()
        };
        let secretario = pedido(SECRETARIO, Papel::Gestor);
        assert_eq!(
            transitar(E::Enviado, A::Homologar, &secretario, &sem, &COM_PARECER),
            Err(ErroFluxo::AditivoSemParecer)
        );
        assert_eq!(
            transitar(E::Enviado, A::Homologar, &secretario, &sem, &SEM_PARECER),
            Ok(E::Homologado)
        );
    }

    #[test]
    fn sem_termo_assinado_nao_homologa() {
        let sem = SituacaoDoAditivo {
            termo_assinado: false,
            ..pronto()
        };
        let r = transitar(
            E::Enviado,
            A::Homologar,
            &pedido(SECRETARIO, Papel::Gestor),
            &sem,
            &SEM_PARECER,
        );
        assert_eq!(r, Err(ErroFluxo::AditivoSemAssinatura));
    }

    #[test]
    fn rejeitar_exige_motivo() {
        let sem_motivo = Pedido {
            quem: SECRETARIO,
            papel: Papel::Gestor,
            motivo: Some("  "),
        };
        let r = transitar(
            E::Enviado,
            A::Rejeitar,
            &sem_motivo,
            &pronto(),
            &COM_PARECER,
        );
        assert_eq!(
            r,
            Err(ErroFluxo::MotivoObrigatorio {
                acao: "rejeitar o aditivo"
            })
        );
    }

    #[test]
    fn nomes_dos_estados_sao_os_do_banco() {
        // os mesmos rótulos do tipo status_aditivo da migração 0001
        let nomes: Vec<&str> = E::TODOS.iter().map(|e| e.nome()).collect();
        assert_eq!(
            nomes,
            vec!["rascunho", "enviado", "homologado", "rejeitado"]
        );
    }
}
