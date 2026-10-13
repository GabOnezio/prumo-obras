//! Regras do Prumo. Este crate é puro: não lê relógio, arquivo, rede nem banco.
//! Tudo o que depende de data recebe a data como argumento.
//!
//! O que há aqui: dinheiro, valor de evento, conferência da medição por eventos, previsão,
//! planilha orçamentária, aditivo (art. 125 e 127), boletim de medição por quantidade e as
//! máquinas de estado dos documentos (`fluxo`). A paridade com o SQL do banco é conferida
//! em `crates/paridade`, com o banco de pé.

pub mod aditivo;
pub mod boletim_medicao;
mod conta;
pub mod dinheiro;
pub mod evento;
pub mod fluxo;
pub mod medicao;
pub mod planilha;
pub mod previsao;

pub use aditivo::{
    aplicar_aditivo, fator_art127, limites_dos_aditivos, preco_de_item_novo, AditivoAplicado,
    Historico, ItemCalculado, ItemDoAditivo, Limites, Operacao, RegraDeLimites, ServicoNovo,
    SituacaoDosLimites,
};
pub use boletim_medicao::{
    boletim_de_medicao, medir_por_quantidade, LinhaDoBoletim, Medido, QuantidadesDoBoletim,
};
pub use dinheiro::{formatar_decimal, percentual, valor_item, CriterioArredondamento, Dinheiro};
pub use evento::{Evento, ServicoNaFrente};
pub use medicao::{conferir_medicao, Conferencia, EventoDeclarado, SituacaoEvento};
pub use planilha::{ItemId, ItemPlanilha, Planilha, TipoItem};
pub use previsao::{
    desvio_trabalhavel, prever, prever_pagamento, Andamento, Calendario, Contagem, EventoPrevisto,
    EventoProgramado, FechamentoMedicao, MarcosPagamento, Metodo, Parametros, PrazosProcesso,
    Previsao,
};

use rust_decimal::Decimal;

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
    #[error("divisão por zero")]
    DivisaoPorZero,
    #[error("o contrato aceita de 2 a 4 casas decimais no preço, veio {0}")]
    CasasDoPrecoInvalidas(u32),
    #[error("o item {0} aparece mais de uma vez")]
    ItemRepetido(String),
    #[error("o item {0} tem posição inválida ou repetida dentro do grupo")]
    OrdemInvalida(String),
    #[error("o item {0} não está abaixo de um grupo da planilha")]
    PaiInvalido(String),
    #[error("o item {0} tem quantidade negativa ou com mais de 4 casas decimais")]
    QuantidadeInvalida(String),
    #[error(
        "o item {0} tem preço unitário negativo ou com mais casas decimais que o contrato aceita"
    )]
    PrecoInvalido(String),
    #[error("o valor do contrato e o orçamento-base têm que ser maiores que zero")]
    ValorDoContratoInvalido,
    #[error("o item {0} não é serviço da planilha")]
    ItemForaDaPlanilha(String),
    #[error("o item {0} do aditivo tem quantidade zero ou com o sinal errado para a operação")]
    QuantidadeDoAditivoInvalida(String),
    #[error("a inclusão do item {0} está sem grupo, código, unidade ou preço de referência")]
    InclusaoIncompleta(String),
    #[error("o item {0} já existe na planilha: inclusão é só para item novo")]
    InclusaoDeItemExistente(String),
    #[error("a supressão deixaria o item {item} abaixo da quantidade já medida ({medido})")]
    SupressaoAbaixoDoMedido { item: String, medido: Decimal },
    #[error("o item {item} só tem {suprimido} suprimidos para restabelecer")]
    RestabelecimentoSemSupressao { item: String, suprimido: Decimal },
    #[error("o item {item} ficaria com {acumulado} medidos, acima dos {contratado} contratados")]
    MedicaoAcimaDoContratado {
        item: String,
        acumulado: Decimal,
        contratado: Decimal,
    },
    #[error("o item {item} ficaria com quantidade medida negativa ({acumulado})")]
    MedicaoAcumuladaNegativa { item: String, acumulado: Decimal },
}
