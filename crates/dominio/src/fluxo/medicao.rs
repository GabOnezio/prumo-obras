//! Estados da medição, por eventos ou por quantidade (`docs/01-modulos.md` §3.4).
//!
//! ```text
//! rascunho ─► enviada ─► em_analise ─► devolvida (a empresa corrige e envia de novo)
//!                             └──────► aprovada_fiscal ─► atestada ─► liquidada ─► paga
//! ```
//! A comissão de medição só entra se o município exigir: aí é ela que atesta. Isso vem da
//! configuração do município, sem valor padrão no código.

use super::{achar, ErroFluxo, Papel, Pedido, PessoaId, Transicao};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EstadoMedicao {
    Rascunho,
    Enviada,
    EmAnalise,
    Devolvida,
    AprovadaFiscal,
    Atestada,
    Liquidada,
    Paga,
    Cancelada,
}

impl EstadoMedicao {
    pub const TODOS: [EstadoMedicao; 9] = [
        EstadoMedicao::Rascunho,
        EstadoMedicao::Enviada,
        EstadoMedicao::EmAnalise,
        EstadoMedicao::Devolvida,
        EstadoMedicao::AprovadaFiscal,
        EstadoMedicao::Atestada,
        EstadoMedicao::Liquidada,
        EstadoMedicao::Paga,
        EstadoMedicao::Cancelada,
    ];

    /// Nome do estado no banco.
    pub fn nome(self) -> &'static str {
        match self {
            EstadoMedicao::Rascunho => "rascunho",
            EstadoMedicao::Enviada => "enviada",
            EstadoMedicao::EmAnalise => "em_analise",
            EstadoMedicao::Devolvida => "devolvida",
            EstadoMedicao::AprovadaFiscal => "aprovada_fiscal",
            EstadoMedicao::Atestada => "atestada",
            EstadoMedicao::Liquidada => "liquidada",
            EstadoMedicao::Paga => "paga",
            EstadoMedicao::Cancelada => "cancelada",
        }
    }

    /// A empresa só altera o conteúdo da medição nestes estados.
    pub fn conteudo_editavel(self) -> bool {
        matches!(self, EstadoMedicao::Rascunho | EstadoMedicao::Devolvida)
    }

    /// Daqui em diante a medição conta como aprovada e nada nela muda.
    pub fn aprovada(self) -> bool {
        matches!(
            self,
            EstadoMedicao::AprovadaFiscal
                | EstadoMedicao::Atestada
                | EstadoMedicao::Liquidada
                | EstadoMedicao::Paga
        )
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AcaoMedicao {
    Enviar,
    Cancelar,
    IniciarAnalise,
    Devolver,
    AprovarComoFiscal,
    Atestar,
    RegistrarLiquidacao,
    RegistrarPagamento,
}

impl AcaoMedicao {
    pub const TODAS: [AcaoMedicao; 8] = [
        AcaoMedicao::Enviar,
        AcaoMedicao::Cancelar,
        AcaoMedicao::IniciarAnalise,
        AcaoMedicao::Devolver,
        AcaoMedicao::AprovarComoFiscal,
        AcaoMedicao::Atestar,
        AcaoMedicao::RegistrarLiquidacao,
        AcaoMedicao::RegistrarPagamento,
    ];

    pub fn nome(self) -> &'static str {
        match self {
            AcaoMedicao::Enviar => "enviar a medição",
            AcaoMedicao::Cancelar => "cancelar a medição",
            AcaoMedicao::IniciarAnalise => "iniciar a análise",
            AcaoMedicao::Devolver => "devolver a medição",
            AcaoMedicao::AprovarComoFiscal => "aprovar como fiscal",
            AcaoMedicao::Atestar => "atestar a medição",
            AcaoMedicao::RegistrarLiquidacao => "registrar a liquidação",
            AcaoMedicao::RegistrarPagamento => "registrar o pagamento",
        }
    }
}

/// Exigências do município para a medição. Vêm de `config_municipio`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RegrasDaMedicao {
    /// Com comissão de medição, é ela que atesta; sem, é o gestor do contrato.
    pub comissao_exigida: bool,
}

/// Quem já agiu nesta medição e o resultado da conferência.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct SituacaoDaMedicao {
    /// Quem enviou (o autor da medição).
    pub enviada_por: Option<PessoaId>,
    /// Quem aprovou como fiscal.
    pub aprovada_por: Option<PessoaId>,
    /// Eventos nem conferidos contra o Boletim de Execução nem glosados
    /// (`Conferencia::pendentes` em `medicao.rs`). Na medição por quantidade é zero.
    pub pendencias: usize,
}

fn tabela(regras: &RegrasDaMedicao) -> [Transicao<EstadoMedicao, AcaoMedicao>; 10] {
    use AcaoMedicao as A;
    use EstadoMedicao as E;
    let quem_atesta = if regras.comissao_exigida {
        Papel::ComissaoDeMedicao
    } else {
        Papel::GestorDoContrato
    };
    let t = |de, acao, para, papel| Transicao {
        de,
        acao,
        para,
        papel,
    };
    [
        t(E::Rascunho, A::Enviar, E::Enviada, Papel::Contratada),
        t(E::Devolvida, A::Enviar, E::Enviada, Papel::Contratada),
        t(E::Rascunho, A::Cancelar, E::Cancelada, Papel::Contratada),
        t(E::Devolvida, A::Cancelar, E::Cancelada, Papel::Contratada),
        t(E::Enviada, A::IniciarAnalise, E::EmAnalise, Papel::Fiscal),
        t(E::EmAnalise, A::Devolver, E::Devolvida, Papel::Fiscal),
        t(
            E::EmAnalise,
            A::AprovarComoFiscal,
            E::AprovadaFiscal,
            Papel::Fiscal,
        ),
        t(E::AprovadaFiscal, A::Atestar, E::Atestada, quem_atesta),
        // Liquidação e pagamento acontecem na contabilidade; aqui só se registra (questão 39).
        t(
            E::Atestada,
            A::RegistrarLiquidacao,
            E::Liquidada,
            Papel::GestorDoContrato,
        ),
        t(
            E::Liquidada,
            A::RegistrarPagamento,
            E::Paga,
            Papel::GestorDoContrato,
        ),
    ]
}

/// Confere se a ação pode ser feita e devolve o novo estado. Não altera nada.
pub fn transitar(
    estado: EstadoMedicao,
    acao: AcaoMedicao,
    pedido: &Pedido,
    situacao: &SituacaoDaMedicao,
    regras: &RegrasDaMedicao,
) -> Result<EstadoMedicao, ErroFluxo> {
    let invalida = ErroFluxo::TransicaoInvalida {
        documento: "medição",
        estado: estado.nome(),
        acao: acao.nome(),
    };
    let novo = achar(&tabela(regras), estado, acao, pedido, invalida, acao.nome())?;

    match acao {
        AcaoMedicao::Devolver if !pedido.tem_motivo() => {
            return Err(ErroFluxo::MotivoObrigatorio { acao: acao.nome() });
        }
        AcaoMedicao::AprovarComoFiscal | AcaoMedicao::Atestar => {
            if situacao.enviada_por == Some(pedido.quem) {
                return Err(ErroFluxo::AutorNaoAprova { acao: acao.nome() });
            }
            if acao == AcaoMedicao::AprovarComoFiscal && situacao.pendencias > 0 {
                return Err(ErroFluxo::MedicaoComPendencia);
            }
            if acao == AcaoMedicao::Atestar && situacao.aprovada_por == Some(pedido.quem) {
                return Err(ErroFluxo::MesmaPessoaEmDuasEtapas { acao: acao.nome() });
            }
        }
        _ => {}
    }
    Ok(novo)
}

#[cfg(test)]
mod tests {
    use super::*;
    use AcaoMedicao as A;
    use EstadoMedicao as E;

    const EMPRESA: PessoaId = PessoaId(1);
    const FISCAL: PessoaId = PessoaId(2);
    const GESTOR_DO_CONTRATO: PessoaId = PessoaId(3);
    const MEMBRO_DA_COMISSAO: PessoaId = PessoaId(4);

    const SEM_COMISSAO: RegrasDaMedicao = RegrasDaMedicao {
        comissao_exigida: false,
    };
    const COM_COMISSAO: RegrasDaMedicao = RegrasDaMedicao {
        comissao_exigida: true,
    };

    fn pedido(quem: PessoaId, papel: Papel) -> Pedido<'static> {
        Pedido {
            quem,
            papel,
            motivo: Some("motivo do teste"),
        }
    }

    /// Medição enviada pela empresa e aprovada pelo fiscal, sem pendência.
    fn em_andamento() -> SituacaoDaMedicao {
        SituacaoDaMedicao {
            enviada_por: Some(EMPRESA),
            aprovada_por: Some(FISCAL),
            pendencias: 0,
        }
    }

    /// As transições permitidas, escritas aqui de novo, à mão: é contra esta lista que a
    /// tabela do código é conferida.
    fn permitidas(regras: &RegrasDaMedicao) -> Vec<(E, A, E, Papel)> {
        let quem_atesta = if regras.comissao_exigida {
            Papel::ComissaoDeMedicao
        } else {
            Papel::GestorDoContrato
        };
        vec![
            (E::Rascunho, A::Enviar, E::Enviada, Papel::Contratada),
            (E::Devolvida, A::Enviar, E::Enviada, Papel::Contratada),
            (E::Rascunho, A::Cancelar, E::Cancelada, Papel::Contratada),
            (E::Devolvida, A::Cancelar, E::Cancelada, Papel::Contratada),
            (E::Enviada, A::IniciarAnalise, E::EmAnalise, Papel::Fiscal),
            (E::EmAnalise, A::Devolver, E::Devolvida, Papel::Fiscal),
            (
                E::EmAnalise,
                A::AprovarComoFiscal,
                E::AprovadaFiscal,
                Papel::Fiscal,
            ),
            (E::AprovadaFiscal, A::Atestar, E::Atestada, quem_atesta),
            (
                E::Atestada,
                A::RegistrarLiquidacao,
                E::Liquidada,
                Papel::GestorDoContrato,
            ),
            (
                E::Liquidada,
                A::RegistrarPagamento,
                E::Paga,
                Papel::GestorDoContrato,
            ),
        ]
    }

    /// Pessoa que não enviou nem aprovou, para a segregação não interferir.
    fn outra_pessoa() -> PessoaId {
        PessoaId(99)
    }

    #[test]
    fn cada_combinacao_de_estado_acao_e_papel() {
        for regras in [SEM_COMISSAO, COM_COMISSAO] {
            let lista = permitidas(&regras);
            let mut aceitas = 0;
            for estado in E::TODOS {
                for acao in A::TODAS {
                    let prevista = lista
                        .iter()
                        .find(|(de, a, _, _)| *de == estado && *a == acao);
                    for papel in Papel::TODOS {
                        let resultado = transitar(
                            estado,
                            acao,
                            &pedido(outra_pessoa(), papel),
                            &em_andamento(),
                            &regras,
                        );
                        match prevista {
                            Some((_, _, para, quem)) if *quem == papel => {
                                assert_eq!(resultado, Ok(*para), "{estado:?} {acao:?} {papel:?}");
                                aceitas += 1;
                            }
                            Some(_) => assert!(
                                matches!(resultado, Err(ErroFluxo::PapelNaoPode { .. })),
                                "{estado:?} {acao:?} {papel:?}: {resultado:?}"
                            ),
                            None => assert!(
                                matches!(resultado, Err(ErroFluxo::TransicaoInvalida { .. })),
                                "{estado:?} {acao:?} {papel:?}: {resultado:?}"
                            ),
                        }
                    }
                }
            }
            // 9 estados × 8 ações × 9 papéis = 648 combinações; só 10 passam
            assert_eq!(aceitas, 10);
        }
    }

    #[test]
    fn estados_finais_nao_tem_saida() {
        for estado in [E::Paga, E::Cancelada] {
            for acao in A::TODAS {
                for papel in Papel::TODOS {
                    let r = transitar(
                        estado,
                        acao,
                        &pedido(outra_pessoa(), papel),
                        &em_andamento(),
                        &SEM_COMISSAO,
                    );
                    assert!(r.is_err(), "{estado:?} {acao:?} {papel:?}");
                }
            }
        }
    }

    #[test]
    fn quem_administra_o_sistema_nao_age_em_medicao() {
        for regras in [SEM_COMISSAO, COM_COMISSAO] {
            for estado in E::TODOS {
                for acao in A::TODAS {
                    for papel in [
                        Papel::AdminTi,
                        Papel::AuditorExterno,
                        Papel::ControleInternoJuridico,
                    ] {
                        let r = transitar(
                            estado,
                            acao,
                            &pedido(outra_pessoa(), papel),
                            &em_andamento(),
                            &regras,
                        );
                        assert!(r.is_err(), "{estado:?} {acao:?} {papel:?}");
                    }
                }
            }
        }
    }

    #[test]
    fn quem_enviou_nao_aprova_nem_atesta() {
        // a mesma pessoa tem também o papel de fiscal no contrato
        let r = transitar(
            E::EmAnalise,
            A::AprovarComoFiscal,
            &pedido(EMPRESA, Papel::Fiscal),
            &em_andamento(),
            &SEM_COMISSAO,
        );
        assert_eq!(
            r,
            Err(ErroFluxo::AutorNaoAprova {
                acao: "aprovar como fiscal"
            })
        );
        let r = transitar(
            E::AprovadaFiscal,
            A::Atestar,
            &pedido(EMPRESA, Papel::GestorDoContrato),
            &em_andamento(),
            &SEM_COMISSAO,
        );
        assert!(matches!(r, Err(ErroFluxo::AutorNaoAprova { .. })));
    }

    #[test]
    fn quem_aprovou_como_fiscal_nao_atesta() {
        // o fiscal também é gestor do contrato
        let r = transitar(
            E::AprovadaFiscal,
            A::Atestar,
            &pedido(FISCAL, Papel::GestorDoContrato),
            &em_andamento(),
            &SEM_COMISSAO,
        );
        assert_eq!(
            r,
            Err(ErroFluxo::MesmaPessoaEmDuasEtapas {
                acao: "atestar a medição"
            })
        );
        // outra pessoa atesta
        let r = transitar(
            E::AprovadaFiscal,
            A::Atestar,
            &pedido(GESTOR_DO_CONTRATO, Papel::GestorDoContrato),
            &em_andamento(),
            &SEM_COMISSAO,
        );
        assert_eq!(r, Ok(E::Atestada));
    }

    #[test]
    fn com_comissao_exigida_so_ela_atesta() {
        let do_gestor = transitar(
            E::AprovadaFiscal,
            A::Atestar,
            &pedido(GESTOR_DO_CONTRATO, Papel::GestorDoContrato),
            &em_andamento(),
            &COM_COMISSAO,
        );
        assert!(matches!(do_gestor, Err(ErroFluxo::PapelNaoPode { .. })));
        let da_comissao = transitar(
            E::AprovadaFiscal,
            A::Atestar,
            &pedido(MEMBRO_DA_COMISSAO, Papel::ComissaoDeMedicao),
            &em_andamento(),
            &COM_COMISSAO,
        );
        assert_eq!(da_comissao, Ok(E::Atestada));
        // sem a exigência, a comissão não atesta
        let sem_exigencia = transitar(
            E::AprovadaFiscal,
            A::Atestar,
            &pedido(MEMBRO_DA_COMISSAO, Papel::ComissaoDeMedicao),
            &em_andamento(),
            &SEM_COMISSAO,
        );
        assert!(matches!(sem_exigencia, Err(ErroFluxo::PapelNaoPode { .. })));
    }

    #[test]
    fn evento_pendente_impede_a_aprovacao_do_fiscal() {
        let com_pendencia = SituacaoDaMedicao {
            pendencias: 1,
            ..em_andamento()
        };
        let r = transitar(
            E::EmAnalise,
            A::AprovarComoFiscal,
            &pedido(FISCAL, Papel::Fiscal),
            &com_pendencia,
            &SEM_COMISSAO,
        );
        assert_eq!(r, Err(ErroFluxo::MedicaoComPendencia));
        // devolver continua possível
        let r = transitar(
            E::EmAnalise,
            A::Devolver,
            &pedido(FISCAL, Papel::Fiscal),
            &com_pendencia,
            &SEM_COMISSAO,
        );
        assert_eq!(r, Ok(E::Devolvida));
    }

    #[test]
    fn devolver_exige_motivo() {
        for motivo in [None, Some(""), Some("   ")] {
            let r = transitar(
                E::EmAnalise,
                A::Devolver,
                &Pedido {
                    quem: FISCAL,
                    papel: Papel::Fiscal,
                    motivo,
                },
                &em_andamento(),
                &SEM_COMISSAO,
            );
            assert_eq!(
                r,
                Err(ErroFluxo::MotivoObrigatorio {
                    acao: "devolver a medição"
                })
            );
        }
    }

    #[test]
    fn caminho_completo_sem_comissao() {
        let mut situacao = SituacaoDaMedicao::default();
        let mut estado = E::Rascunho;
        let passos = [
            (A::Enviar, EMPRESA, Papel::Contratada, E::Enviada),
            (A::IniciarAnalise, FISCAL, Papel::Fiscal, E::EmAnalise),
            (A::Devolver, FISCAL, Papel::Fiscal, E::Devolvida),
            (A::Enviar, EMPRESA, Papel::Contratada, E::Enviada),
            (A::IniciarAnalise, FISCAL, Papel::Fiscal, E::EmAnalise),
            (
                A::AprovarComoFiscal,
                FISCAL,
                Papel::Fiscal,
                E::AprovadaFiscal,
            ),
            (
                A::Atestar,
                GESTOR_DO_CONTRATO,
                Papel::GestorDoContrato,
                E::Atestada,
            ),
            (
                A::RegistrarLiquidacao,
                GESTOR_DO_CONTRATO,
                Papel::GestorDoContrato,
                E::Liquidada,
            ),
            (
                A::RegistrarPagamento,
                GESTOR_DO_CONTRATO,
                Papel::GestorDoContrato,
                E::Paga,
            ),
        ];
        for (acao, quem, papel, esperado) in passos {
            estado =
                transitar(estado, acao, &pedido(quem, papel), &situacao, &SEM_COMISSAO).unwrap();
            assert_eq!(estado, esperado);
            match acao {
                A::Enviar => situacao.enviada_por = Some(quem),
                A::AprovarComoFiscal => situacao.aprovada_por = Some(quem),
                _ => {}
            }
        }
    }

    #[test]
    fn o_que_cada_estado_permite() {
        let editaveis: Vec<E> = E::TODOS
            .into_iter()
            .filter(|e| e.conteudo_editavel())
            .collect();
        assert_eq!(editaveis, vec![E::Rascunho, E::Devolvida]);
        let aprovadas: Vec<E> = E::TODOS.into_iter().filter(|e| e.aprovada()).collect();
        assert_eq!(
            aprovadas,
            vec![E::AprovadaFiscal, E::Atestada, E::Liquidada, E::Paga]
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
