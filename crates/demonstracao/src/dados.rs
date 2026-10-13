//! Obra de exemplo. Tudo aqui é **fictício**: município de Exemplo, Contrato 045/2026.
//! Em produção estes valores vêm do banco e de `config_municipio`; nenhum deles
//! é regra do sistema.

use chrono::NaiveDate;
use prumo_dominio::{Contagem, CriterioArredondamento, PrazosProcesso};

/// Data literal conferida na compilação quando usada em `const`.
pub(crate) const fn dia(ano: i32, mes: u32, dia: u32) -> NaiveDate {
    match NaiveDate::from_ymd_opt(ano, mes, dia) {
        Some(d) => d,
        None => panic!("data inválida nos dados de demonstração"),
    }
}

pub(crate) struct Servico {
    pub item: &'static str,
    pub descricao: &'static str,
    pub unidade: &'static str,
    /// Quantidade na frente, em centésimos.
    pub quantidade: i64,
    /// Preço unitário, em centavos.
    pub preco: i64,
}

pub(crate) struct DadosEvento {
    pub agrupador: &'static str,
    pub frente: &'static str,
    pub servicos: &'static [Servico],
    pub inicio_previsto: NaiveDate,
    pub termino_previsto: NaiveDate,
    pub predecessoras: &'static [usize],
}

const fn servico(
    item: &'static str,
    descricao: &'static str,
    unidade: &'static str,
    quantidade: i64,
    preco: i64,
) -> Servico {
    Servico {
        item,
        descricao,
        unidade,
        quantidade,
        preco,
    }
}

pub(crate) const FUNDACOES: usize = 0;
pub(crate) const PILARES: usize = 1;
pub(crate) const ALVENARIA: usize = 2;

/// Planilha do órgão já distribuída em eventos (agrupador × frente), com a linha de base do cronograma.
pub(crate) const EVENTOS: [DadosEvento; 6] = [
    DadosEvento {
        agrupador: "Fundações",
        frente: "Térreo",
        servicos: &[
            servico("1.1", "Escavação manual de vala", "m³", 8_600, 6_845),
            servico("1.2", "Armadura CA-50", "kg", 92_000, 984),
            servico("1.3", "Concreto fck 25 MPa", "m³", 2_450, 78_540),
        ],
        inicio_previsto: dia(2026, 9, 28),
        termino_previsto: dia(2026, 10, 26),
        predecessoras: &[],
    },
    DadosEvento {
        agrupador: "Estrutura: pilares",
        frente: "Térreo",
        servicos: &[
            servico("2.1", "Fôrma de pilar", "m²", 9_600, 6_230),
            servico("2.2", "Armadura CA-50", "kg", 115_000, 984),
            servico("2.3", "Concreto fck 25 MPa", "m³", 1_110, 78_540),
        ],
        inicio_previsto: dia(2026, 10, 30),
        termino_previsto: dia(2026, 11, 30),
        predecessoras: &[FUNDACOES],
    },
    DadosEvento {
        agrupador: "Alvenaria",
        frente: "Térreo",
        servicos: &[
            servico(
                "3.1",
                "Alvenaria de vedação, bloco cerâmico",
                "m²",
                16_000,
                8_915,
            ),
            servico("3.2", "Chapisco em alvenaria", "m²", 32_000, 743),
        ],
        inicio_previsto: dia(2026, 12, 1),
        termino_previsto: dia(2026, 12, 18),
        predecessoras: &[PILARES],
    },
    DadosEvento {
        agrupador: "Cobertura",
        frente: "Térreo",
        servicos: &[
            servico(
                "4.1",
                "Estrutura de madeira para telhado",
                "m²",
                28_000,
                7_450,
            ),
            servico("4.2", "Telhamento com telha cerâmica", "m²", 28_000, 6_450),
        ],
        inicio_previsto: dia(2027, 1, 5),
        termino_previsto: dia(2027, 1, 29),
        predecessoras: &[ALVENARIA],
    },
    DadosEvento {
        agrupador: "Instalações e revestimentos",
        frente: "Térreo",
        servicos: &[
            servico("5.1", "Ponto de instalação elétrica", "un", 6_400, 14_280),
            servico(
                "5.2",
                "Ponto de instalação hidrossanitária",
                "un",
                3_800,
                16_850,
            ),
            servico("5.3", "Reboco", "m²", 32_000, 3_120),
            servico("5.4", "Piso cerâmico", "m²", 21_000, 5_890),
        ],
        inicio_previsto: dia(2027, 2, 1),
        termino_previsto: dia(2027, 3, 19),
        predecessoras: &[3],
    },
    DadosEvento {
        agrupador: "Pintura e limpeza final",
        frente: "Térreo",
        servicos: &[
            servico("6.1", "Pintura acrílica", "m²", 64_000, 1_485),
            servico("6.2", "Limpeza final da obra", "m²", 21_000, 420),
        ],
        inicio_previsto: dia(2027, 3, 22),
        termino_previsto: dia(2027, 4, 30),
        predecessoras: &[4],
    },
];

pub(crate) const CONTRATO: &str = "045/2026";
pub(crate) const OBRA: &str = "Ampliação da Escola Municipal";
pub(crate) const CRITERIO: CriterioArredondamento = CriterioArredondamento::Arredondar;
pub(crate) const TERMINO_CONTRATUAL: NaiveDate = dia(2027, 4, 30);

/// Dias sem expediente cadastrados no calendário da obra.
pub(crate) const SEM_EXPEDIENTE: [NaiveDate; 7] = [
    dia(2026, 10, 12),
    dia(2026, 11, 2),
    dia(2026, 11, 20),
    dia(2026, 12, 25),
    dia(2027, 1, 1),
    dia(2027, 3, 26),
    dia(2027, 4, 21),
];

// O que os boletins já emitidos registram.
pub(crate) const FUNDACOES_INICIO: NaiveDate = dia(2026, 9, 28);
pub(crate) const FUNDACOES_FIM: NaiveDate = dia(2026, 10, 28);
pub(crate) const PILARES_INICIO: NaiveDate = dia(2026, 11, 11);
pub(crate) const PILARES_FIM: NaiveDate = dia(2026, 12, 11);
pub(crate) const ALVENARIA_INICIO: NaiveDate = dia(2026, 12, 1);
pub(crate) const ALVENARIA_AVANCO_BOLETIM_7: u8 = 70;

pub(crate) const VISTORIA_BOLETIM_7: NaiveDate = dia(2026, 12, 15);
pub(crate) const VISTORIA_BOLETIM_8: NaiveDate = dia(2026, 12, 22);
pub(crate) const PERIODO_BOLETIM_8: (NaiveDate, NaiveDate) = (dia(2026, 12, 16), dia(2026, 12, 31));
pub(crate) const AVANCO_INICIAL_RASCUNHO: u8 = 90;

/// Medição nº 3: o que a empresa declarou concluído no período.
pub(crate) const PERIODO_MEDICAO_3: (NaiveDate, NaiveDate) = (dia(2026, 12, 1), dia(2026, 12, 31));
pub(crate) const MEDICAO_3_ENVIADA: NaiveDate = dia(2027, 1, 5);
pub(crate) const DECLARADOS_MEDICAO_3: [usize; 2] = [PILARES, ALVENARIA];

/// Configuração fictícia do município e do contrato.
pub(crate) const PRAZOS: PrazosProcesso = PrazosProcesso {
    envio_da_medicao: 5,
    analise_da_fiscalizacao: 10,
    atesto_e_liquidacao: 5,
    pagamento: 30,
    contagem: Contagem::Corridos,
};
pub(crate) const RETENCAO_PCT: u32 = 11;
pub(crate) const AVANCO_MINIMO_PCT: u8 = 10;
pub(crate) const EVENTOS_MINIMOS_PARA_RITMO: usize = 2;
/// Faixa do fator de ritmo, em centésimos: de 0,50 a 3,00.
pub(crate) const FAIXA_DO_FATOR: (i64, i64) = (50, 300);
