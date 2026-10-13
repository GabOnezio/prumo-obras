//! Máquinas de estado dos documentos do contrato: medição, diário de obras, aditivo e
//! Boletim de Execução.
//!
//! Cada máquina é uma tabela de transições: estado de partida, ação, estado de chegada e o
//! papel que pode pedir. O que não está na tabela não acontece. Além da tabela, cada
//! transição confere a segregação de funções (quem fez o documento não o aprova) e as
//! condições próprias da ação.
//!
//! O que fica fora daqui, porque depende de banco: saber se a pessoa tem aquele papel neste
//! contrato. A aplicação resolve o [`Papel`] a partir do perfil do usuário e, para fiscal,
//! gestor do contrato e comissão, da **designação vigente**; só então chama a transição.
//!
//! As tabelas seguem `docs/01-modulos.md` §3. Onde aquele documento não diz quem age, a
//! linha é proposta e está na questão 39 de `docs/QUESTOES-ABERTAS.md`.

pub mod aditivo;
pub mod boletim_execucao;
pub mod diario;
pub mod medicao;

/// Quem pede a ação (id do usuário).
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct PessoaId(pub u128);

/// Papel com que a pessoa age neste contrato.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Papel {
    /// Preposto ou responsável técnico da empresa contratada.
    Contratada,
    /// Fiscal com designação vigente no contrato.
    Fiscal,
    /// Gestor do contrato, com designação vigente.
    GestorDoContrato,
    /// Membro da comissão de medição, com designação vigente.
    ComissaoDeMedicao,
    /// Engenharia de planejamento e orçamento da prefeitura.
    Planejamento,
    /// Autoridade que autoriza aditivo: prefeito, secretário, diretor de obras.
    Gestor,
    /// Controle interno e procuradoria: leem e dão parecer.
    ControleInternoJuridico,
    /// Informática da prefeitura: administra usuários e o sistema, não dado de negócio.
    AdminTi,
    /// Tribunal de contas e controladoria: só leitura.
    AuditorExterno,
}

impl Papel {
    pub const TODOS: [Papel; 9] = [
        Papel::Contratada,
        Papel::Fiscal,
        Papel::GestorDoContrato,
        Papel::ComissaoDeMedicao,
        Papel::Planejamento,
        Papel::Gestor,
        Papel::ControleInternoJuridico,
        Papel::AdminTi,
        Papel::AuditorExterno,
    ];

    pub fn nome(self) -> &'static str {
        match self {
            Papel::Contratada => "contratada",
            Papel::Fiscal => "fiscal",
            Papel::GestorDoContrato => "gestor do contrato",
            Papel::ComissaoDeMedicao => "comissão de medição",
            Papel::Planejamento => "planejamento",
            Papel::Gestor => "gestor",
            Papel::ControleInternoJuridico => "controle interno e jurídico",
            Papel::AdminTi => "administração de TI",
            Papel::AuditorExterno => "auditor externo",
        }
    }
}

/// Quem pede, com que papel e, quando a ação exige, por quê.
#[derive(Clone, Copy, Debug)]
pub struct Pedido<'a> {
    pub quem: PessoaId,
    pub papel: Papel,
    pub motivo: Option<&'a str>,
}

impl Pedido<'_> {
    fn tem_motivo(&self) -> bool {
        self.motivo.is_some_and(|m| !m.trim().is_empty())
    }
}

/// Por que uma ação foi recusada.
#[derive(Clone, Debug, PartialEq, Eq, thiserror::Error)]
pub enum ErroFluxo {
    #[error("{documento} em \"{estado}\" não aceita a ação \"{acao}\"")]
    TransicaoInvalida {
        documento: &'static str,
        estado: &'static str,
        acao: &'static str,
    },
    #[error("o papel \"{papel}\" não pode \"{acao}\"")]
    PapelNaoPode {
        acao: &'static str,
        papel: &'static str,
    },
    #[error("quem fez o documento não pode \"{acao}\": a aprovação é de outra pessoa")]
    AutorNaoAprova { acao: &'static str },
    #[error("\"{acao}\" tem que ser feita por pessoa diferente da que aprovou a etapa anterior")]
    MesmaPessoaEmDuasEtapas { acao: &'static str },
    #[error("\"{acao}\" exige o motivo por escrito")]
    MotivoObrigatorio { acao: &'static str },
    #[error("a medição tem evento sem boletim que o marque concluído e sem glosa")]
    MedicaoComPendencia,
    #[error("o aditivo passa do limite legal de acréscimos ou de supressões")]
    AditivoAcimaDoLimite,
    #[error("o aditivo está sem o parecer do controle interno ou do jurídico")]
    AditivoSemParecer,
    #[error("o aditivo está sem a data de assinatura do termo")]
    AditivoSemAssinatura,
    #[error("o boletim não tem nenhuma linha")]
    BoletimVazio,
    #[error("a linha {linha} do boletim tem menos evidências que o mínimo para \"concluído\"")]
    BoletimSemEvidencia { linha: usize },
    #[error("a linha {linha} do boletim foi verificada depois do fim do período")]
    BoletimComDataForaDoPeriodo { linha: usize },
}

/// Uma linha da tabela de transições de uma máquina.
#[derive(Clone, Copy, Debug)]
pub(crate) struct Transicao<E, A> {
    pub de: E,
    pub acao: A,
    pub para: E,
    pub papel: Papel,
}

/// Acha a transição na tabela e confere o papel. Primeiro o estado, depois o papel: assim a
/// mensagem diz que a ação não cabe naquele estado antes de falar de permissão.
pub(crate) fn achar<E: Copy + PartialEq, A: Copy + PartialEq>(
    tabela: &[Transicao<E, A>],
    estado: E,
    acao: A,
    pedido: &Pedido,
    invalida: ErroFluxo,
    nome_da_acao: &'static str,
) -> Result<E, ErroFluxo> {
    let mut alguma = false;
    for t in tabela.iter().filter(|t| t.de == estado && t.acao == acao) {
        alguma = true;
        if t.papel == pedido.papel {
            return Ok(t.para);
        }
    }
    if alguma {
        Err(ErroFluxo::PapelNaoPode {
            acao: nome_da_acao,
            papel: pedido.papel.nome(),
        })
    } else {
        Err(invalida)
    }
}
