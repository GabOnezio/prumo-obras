//! Regras do Prumo. Este crate é puro: não lê relógio, arquivo, rede nem banco.
//! Tudo o que depende de data recebe a data como argumento.
//!
//! Estado: dinheiro, valor de evento, conferência da medição e previsão. As regras de
//! aditivo (art. 125 e 127) e as máquinas de estado ainda não estão aqui (ver
//! `docs/08-roadmap.md`, Fase 0). A paridade com o SQL do banco é conferida em
//! `crates/paridade`, com o banco de pé.

pub mod dinheiro;
pub mod evento;
pub mod medicao;
pub mod previsao;

pub use dinheiro::{formatar_decimal, percentual, valor_item, CriterioArredondamento, Dinheiro};
pub use evento::{Evento, ServicoNaFrente};
pub use medicao::{conferir_medicao, Conferencia, EventoDeclarado, SituacaoEvento};
pub use previsao::{
    desvio_trabalhavel, prever, prever_pagamento, Andamento, Calendario, Contagem, EventoPrevisto,
    EventoProgramado, FechamentoMedicao, MarcosPagamento, Metodo, Parametros, PrazosProcesso,
    Previsao,
};

/// Erros de regra e de cálculo do domínio.
#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum ErroDominio {
    #[error("o valor calculado não cabe no tipo decimal")]
    Estouro,
    #[error("avanço em andamento deve ficar entre 1% e 99%, veio {0}%")]
    AvancoInvalido(u8),
    #[error("o evento {evento} depende do evento {predecessora}, que não vem antes dele")]
    PredecessoraInvalida { evento: usize, predecessora: usize },
    #[error("o evento {0} tem término previsto antes do início previsto")]
    LinhaDeBaseInvalida(usize),
}
