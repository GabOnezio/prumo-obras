//! Previsão de término e de pagamento. Cálculo determinístico: mesma entrada,
//! mesma saída. Método inicial de `docs/10-execucao-eventos-previsao.md` §6,
//! ainda a validar com dados de obra real (questão 21).
//!
//! Nenhum prazo é constante aqui: calendário, limiares e prazos de processo
//! chegam como argumento.

use crate::ErroDominio;
use chrono::{Datelike, Days, NaiveDate, Weekday};
use rust_decimal::prelude::ToPrimitive;
use rust_decimal::Decimal;
use std::collections::BTreeSet;

/// Calendário da obra: segunda a sexta, menos os dias cadastrados como sem expediente.
#[derive(Clone, Debug, Default)]
pub struct Calendario {
    sem_expediente: BTreeSet<NaiveDate>,
}

impl Calendario {
    pub fn new(sem_expediente: impl IntoIterator<Item = NaiveDate>) -> Calendario {
        Calendario {
            sem_expediente: sem_expediente.into_iter().collect(),
        }
    }

    pub fn trabalhavel(&self, dia: NaiveDate) -> bool {
        !matches!(dia.weekday(), Weekday::Sat | Weekday::Sun) && !self.sem_expediente.contains(&dia)
    }

    /// Primeiro dia trabalhável em `dia` ou depois dele.
    pub fn no_dia_ou_depois(&self, dia: NaiveDate) -> NaiveDate {
        let mut d = dia;
        while !self.trabalhavel(d) {
            match d.succ_opt() {
                Some(proximo) => d = proximo,
                None => break,
            }
        }
        d
    }

    /// Primeiro dia trabalhável depois de `dia`.
    pub fn depois_de(&self, dia: NaiveDate) -> NaiveDate {
        match dia.succ_opt() {
            Some(proximo) => self.no_dia_ou_depois(proximo),
            None => dia,
        }
    }

    /// O `n`-ésimo dia trabalhável depois de `dia`. Com `n = 0`, devolve `dia`.
    pub fn avancar(&self, dia: NaiveDate, n: u32) -> NaiveDate {
        (0..n).fold(dia, |d, _| self.depois_de(d))
    }

    /// Dias trabalháveis em `[inicio, fim]`. Zero se `fim` vem antes de `inicio`.
    pub fn contar(&self, inicio: NaiveDate, fim: NaiveDate) -> u32 {
        inicio
            .iter_days()
            .take_while(|d| *d <= fim)
            .filter(|d| self.trabalhavel(*d))
            .count() as u32
    }
}

/// Dias trabalháveis entre a data prevista e a data nova: positivo se atrasou.
pub fn desvio_trabalhavel(cal: &Calendario, prevista: NaiveDate, nova: NaiveDate) -> i64 {
    if nova > prevista {
        prevista
            .succ_opt()
            .map_or(0, |d| i64::from(cal.contar(d, nova)))
    } else if nova < prevista {
        nova.succ_opt()
            .map_or(0, |d| -i64::from(cal.contar(d, prevista)))
    } else {
        0
    }
}

/// O que o último Boletim de Execução emitido diz do evento.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Andamento {
    NaoIniciado,
    EmAndamento {
        inicio_real: NaiveDate,
        avanco_pct: u8,
    },
    Concluido {
        inicio_real: NaiveDate,
        concluido_em: NaiveDate,
    },
}

#[derive(Clone, Debug)]
pub struct EventoProgramado {
    pub inicio_previsto: NaiveDate,
    pub termino_previsto: NaiveDate,
    /// Posições, na mesma lista, dos eventos que precisam terminar antes. Só posições anteriores.
    pub predecessoras: Vec<usize>,
    pub andamento: Andamento,
}

/// Limiares da previsão. Vêm de `config_municipio`.
#[derive(Clone, Debug)]
pub struct Parametros {
    /// Abaixo deste avanço o ritmo do próprio evento não é usado.
    pub avanco_minimo_pct: u8,
    /// Com menos eventos concluídos que isto, o fator de ritmo é 1.
    pub eventos_minimos_para_ritmo: usize,
    pub fator_minimo: Decimal,
    pub fator_maximo: Decimal,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Metodo {
    /// Data real, do boletim.
    Real,
    /// Ritmo verificado do próprio evento.
    Ritmo,
    /// Duração da linha de base × fator de ritmo da obra.
    LinhaDeBaseAjustada,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct EventoPrevisto {
    pub inicio: NaiveDate,
    pub termino: NaiveDate,
    pub metodo: Metodo,
    /// Dias trabalháveis depois (positivo) ou antes (negativo) do término da linha de base.
    pub desvio_dias: i64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Previsao {
    /// Σ duração real ÷ Σ duração prevista dos eventos concluídos, dentro da faixa.
    pub fator_ritmo: Decimal,
    /// Falso quando há menos eventos concluídos que o mínimo: o fator é 1 por falta de dado.
    pub ritmo_medido: bool,
    pub eventos_concluidos: usize,
    pub eventos: Vec<EventoPrevisto>,
    /// O maior término entre os eventos. `None` se a lista é vazia.
    pub termino: Option<NaiveDate>,
}

fn teto(valor: Decimal) -> u32 {
    valor.ceil().to_u32().unwrap_or(u32::MAX)
}

fn fator_de_ritmo(
    eventos: &[EventoProgramado],
    cal: &Calendario,
    p: &Parametros,
) -> (Decimal, bool, usize) {
    let (mut real, mut previsto, mut concluidos) = (0u32, 0u32, 0usize);
    for e in eventos {
        if let Andamento::Concluido {
            inicio_real,
            concluido_em,
        } = e.andamento
        {
            real += cal.contar(inicio_real, concluido_em);
            previsto += cal.contar(e.inicio_previsto, e.termino_previsto);
            concluidos += 1;
        }
    }
    if concluidos < p.eventos_minimos_para_ritmo || previsto == 0 {
        return (Decimal::ONE, false, concluidos);
    }
    let fator = Decimal::from(real) / Decimal::from(previsto);
    (
        fator.clamp(p.fator_minimo, p.fator_maximo),
        true,
        concluidos,
    )
}

/// Término previsto de cada evento e da obra, na data `hoje` (a da verificação do boletim).
pub fn prever(
    eventos: &[EventoProgramado],
    hoje: NaiveDate,
    cal: &Calendario,
    p: &Parametros,
) -> Result<Previsao, ErroDominio> {
    let (fator, ritmo_medido, eventos_concluidos) = fator_de_ritmo(eventos, cal, p);
    let mut previstos: Vec<EventoPrevisto> = Vec::with_capacity(eventos.len());

    for (i, e) in eventos.iter().enumerate() {
        if e.termino_previsto < e.inicio_previsto {
            return Err(ErroDominio::LinhaDeBaseInvalida(i));
        }
        if let Some(&pred) = e.predecessoras.iter().find(|&&pred| pred >= i) {
            return Err(ErroDominio::PredecessoraInvalida {
                evento: i,
                predecessora: pred,
            });
        }
        // Duração da linha de base esticada (ou encolhida) pelo ritmo da obra; no mínimo um dia.
        let duracao_ajustada =
            teto(Decimal::from(cal.contar(e.inicio_previsto, e.termino_previsto)) * fator).max(1);

        let (inicio, termino, metodo) = match e.andamento {
            Andamento::Concluido {
                inicio_real,
                concluido_em,
            } => (inicio_real, concluido_em, Metodo::Real),
            Andamento::EmAndamento {
                inicio_real,
                avanco_pct,
            } if avanco_pct >= p.avanco_minimo_pct && avanco_pct < 100 && inicio_real <= hoje => {
                // ritmo = avanço ÷ dias decorridos; dias restantes = (100 − avanço) ÷ ritmo
                let decorridos = cal.contar(inicio_real, hoje).max(1);
                let restantes = teto(
                    Decimal::from(100 - u32::from(avanco_pct)) * Decimal::from(decorridos)
                        / Decimal::from(avanco_pct),
                );
                (inicio_real, cal.avancar(hoje, restantes), Metodo::Ritmo)
            }
            Andamento::EmAndamento { inicio_real, .. } => {
                let inicio = cal.no_dia_ou_depois(inicio_real);
                let termino = cal
                    .avancar(inicio, duracao_ajustada - 1)
                    .max(cal.depois_de(hoje));
                (inicio_real, termino, Metodo::LinhaDeBaseAjustada)
            }
            Andamento::NaoIniciado => {
                // Não começa antes do previsto, nem antes de as predecessoras terminarem, nem antes de amanhã.
                let apos_predecessoras = e
                    .predecessoras
                    .iter()
                    .map(|&pred| cal.depois_de(previstos[pred].termino));
                let inicio = apos_predecessoras
                    .chain([e.inicio_previsto, cal.depois_de(hoje)])
                    .max()
                    .map_or(e.inicio_previsto, |d| cal.no_dia_ou_depois(d));
                (
                    inicio,
                    cal.avancar(inicio, duracao_ajustada - 1),
                    Metodo::LinhaDeBaseAjustada,
                )
            }
        };
        previstos.push(EventoPrevisto {
            inicio,
            termino,
            metodo,
            desvio_dias: desvio_trabalhavel(cal, e.termino_previsto, termino),
        });
    }

    let termino = previstos.iter().map(|e| e.termino).max();
    Ok(Previsao {
        fator_ritmo: fator,
        ritmo_medido,
        eventos_concluidos,
        eventos: previstos,
        termino,
    })
}

/// Como os prazos de processo são contados. Vem do contrato ou de `config_municipio`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Contagem {
    Corridos,
    Uteis,
}

/// Prazos, em dias, de cada etapa entre o fechamento da medição e o pagamento.
#[derive(Clone, Copy, Debug)]
pub struct PrazosProcesso {
    pub envio_da_medicao: u32,
    pub analise_da_fiscalizacao: u32,
    pub atesto_e_liquidacao: u32,
    pub pagamento: u32,
    pub contagem: Contagem,
}

/// Regra de fechamento do período de medição do contrato.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FechamentoMedicao {
    UltimoDiaDoMes,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct MarcosPagamento {
    pub fechamento: NaiveDate,
    pub envio: NaiveDate,
    pub analise: NaiveDate,
    pub liquidacao: NaiveDate,
    pub pagamento: NaiveDate,
}

fn ultimo_dia_do_mes(dia: NaiveDate) -> NaiveDate {
    let (ano, mes) = if dia.month() == 12 {
        (dia.year() + 1, 1)
    } else {
        (dia.year(), dia.month() + 1)
    };
    NaiveDate::from_ymd_opt(ano, mes, 1)
        .and_then(|primeiro| primeiro.pred_opt())
        .unwrap_or(dia)
}

/// Do término (real ou previsto) de um evento até a data prevista do pagamento.
pub fn prever_pagamento(
    termino: NaiveDate,
    fechamento: FechamentoMedicao,
    prazos: &PrazosProcesso,
    cal: &Calendario,
) -> MarcosPagamento {
    let somar = |dia: NaiveDate, n: u32| match prazos.contagem {
        Contagem::Corridos => dia.checked_add_days(Days::new(u64::from(n))).unwrap_or(dia),
        Contagem::Uteis => cal.avancar(dia, n),
    };
    let fechamento = match fechamento {
        FechamentoMedicao::UltimoDiaDoMes => ultimo_dia_do_mes(termino),
    };
    let envio = somar(fechamento, prazos.envio_da_medicao);
    let analise = somar(envio, prazos.analise_da_fiscalizacao);
    let liquidacao = somar(analise, prazos.atesto_e_liquidacao);
    let pagamento = somar(liquidacao, prazos.pagamento);
    MarcosPagamento {
        fechamento,
        envio,
        analise,
        liquidacao,
        pagamento,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dia(a: i32, m: u32, d: u32) -> NaiveDate {
        NaiveDate::from_ymd_opt(a, m, d).unwrap()
    }

    /// Feriados nacionais do período do exemplo.
    fn calendario() -> Calendario {
        Calendario::new([
            dia(2026, 10, 12),
            dia(2026, 11, 2),
            dia(2026, 11, 20),
            dia(2026, 12, 25),
            dia(2027, 1, 1),
            dia(2027, 3, 26),
            dia(2027, 4, 21),
        ])
    }

    fn parametros() -> Parametros {
        Parametros {
            avanco_minimo_pct: 10,
            eventos_minimos_para_ritmo: 2,
            fator_minimo: "0.5".parse().unwrap(),
            fator_maximo: "3".parse().unwrap(),
        }
    }

    const PRAZOS: PrazosProcesso = PrazosProcesso {
        envio_da_medicao: 5,
        analise_da_fiscalizacao: 10,
        atesto_e_liquidacao: 5,
        pagamento: 30,
        contagem: Contagem::Corridos,
    };

    /// Obra de exemplo no Boletim nº 7 (15/12/2026): fundações e pilares concluídos,
    /// alvenaria com `avanco` por cento, cobertura não iniciada.
    fn obra(avanco_alvenaria: u8) -> Vec<EventoProgramado> {
        vec![
            EventoProgramado {
                inicio_previsto: dia(2026, 9, 28),
                termino_previsto: dia(2026, 10, 26),
                predecessoras: vec![],
                andamento: Andamento::Concluido {
                    inicio_real: dia(2026, 9, 28),
                    concluido_em: dia(2026, 10, 28),
                },
            },
            EventoProgramado {
                inicio_previsto: dia(2026, 10, 30),
                termino_previsto: dia(2026, 11, 30),
                predecessoras: vec![0],
                andamento: Andamento::Concluido {
                    inicio_real: dia(2026, 11, 11),
                    concluido_em: dia(2026, 12, 11),
                },
            },
            EventoProgramado {
                inicio_previsto: dia(2026, 12, 1),
                termino_previsto: dia(2026, 12, 18),
                predecessoras: vec![1],
                andamento: Andamento::EmAndamento {
                    inicio_real: dia(2026, 12, 1),
                    avanco_pct: avanco_alvenaria,
                },
            },
            EventoProgramado {
                inicio_previsto: dia(2027, 1, 5),
                termino_previsto: dia(2027, 1, 29),
                predecessoras: vec![2],
                andamento: Andamento::NaoIniciado,
            },
        ]
    }

    #[test]
    fn calendario_pula_fim_de_semana_e_feriado() {
        let cal = calendario();
        assert!(!cal.trabalhavel(dia(2026, 12, 12))); // sábado
        assert!(!cal.trabalhavel(dia(2026, 12, 25))); // feriado
        assert_eq!(cal.contar(dia(2026, 12, 1), dia(2026, 12, 15)), 11);
        assert_eq!(cal.contar(dia(2026, 12, 15), dia(2026, 12, 1)), 0);
        assert_eq!(cal.avancar(dia(2026, 12, 15), 5), dia(2026, 12, 22));
        assert_eq!(cal.avancar(dia(2026, 12, 24), 1), dia(2026, 12, 28)); // pula o Natal e o fim de semana
        assert_eq!(cal.avancar(dia(2026, 12, 15), 0), dia(2026, 12, 15));
        assert_eq!(cal.depois_de(dia(2026, 12, 31)), dia(2027, 1, 4)); // 01/01 é feriado, depois fim de semana
    }

    #[test]
    fn desvio_conta_dias_trabalhaveis_para_os_dois_lados() {
        let cal = calendario();
        assert_eq!(
            desvio_trabalhavel(&cal, dia(2026, 11, 30), dia(2026, 12, 11)),
            9
        );
        assert_eq!(
            desvio_trabalhavel(&cal, dia(2026, 12, 11), dia(2026, 11, 30)),
            -9
        );
        assert_eq!(
            desvio_trabalhavel(&cal, dia(2026, 12, 18), dia(2026, 12, 18)),
            0
        );
    }

    #[test]
    fn fator_de_ritmo_e_duracao_real_sobre_prevista() {
        // fundações: 22 dias contra 20; pilares: 22 contra 20; fator 44 ÷ 40 = 1,10
        let p = prever(&obra(70), dia(2026, 12, 15), &calendario(), &parametros()).unwrap();
        assert_eq!(p.fator_ritmo, "1.1".parse().unwrap());
        assert!(p.ritmo_medido);
        assert_eq!(p.eventos_concluidos, 2);
    }

    #[test]
    fn alvenaria_com_70_por_cento_em_11_dias_termina_em_22_12() {
        // docs/10 §6.2: ritmo de 6,4% ao dia; faltam 30%, logo 5 dias trabalháveis
        let p = prever(&obra(70), dia(2026, 12, 15), &calendario(), &parametros()).unwrap();
        let alvenaria = p.eventos[2];
        assert_eq!(alvenaria.termino, dia(2026, 12, 22));
        assert_eq!(alvenaria.metodo, Metodo::Ritmo);
        assert_eq!(alvenaria.desvio_dias, 2);
    }

    #[test]
    fn evento_concluido_usa_a_data_real() {
        let p = prever(&obra(70), dia(2026, 12, 15), &calendario(), &parametros()).unwrap();
        assert_eq!(p.eventos[1].termino, dia(2026, 12, 11));
        assert_eq!(p.eventos[1].metodo, Metodo::Real);
        assert_eq!(p.eventos[1].desvio_dias, 9);
    }

    #[test]
    fn cobertura_nao_iniciada_estica_pelo_fator_e_respeita_a_folga() {
        // 19 dias de linha de base × 1,10 = 20,9, logo 21 dias. A alvenaria termina em 22/12,
        // antes do início previsto (05/01), então o início não muda.
        let p = prever(&obra(70), dia(2026, 12, 15), &calendario(), &parametros()).unwrap();
        let cobertura = p.eventos[3];
        assert_eq!(cobertura.inicio, dia(2027, 1, 5));
        assert_eq!(cobertura.termino, dia(2027, 2, 2));
        assert_eq!(cobertura.metodo, Metodo::LinhaDeBaseAjustada);
        assert_eq!(cobertura.desvio_dias, 2);
        assert_eq!(p.termino, Some(dia(2027, 2, 2)));
    }

    #[test]
    fn atraso_da_predecessora_empurra_o_evento_seguinte() {
        // 25% em 11 dias: faltam 33 dias trabalháveis; a alvenaria só termina em 02/02/2027
        let p = prever(&obra(25), dia(2026, 12, 15), &calendario(), &parametros()).unwrap();
        assert_eq!(p.eventos[2].termino, dia(2027, 2, 2));
        assert_eq!(p.eventos[3].inicio, dia(2027, 2, 3));
        assert!(p.eventos[3].termino > dia(2027, 2, 2));
    }

    #[test]
    fn avanco_abaixo_do_minimo_nao_usa_o_ritmo_do_evento() {
        let p = prever(&obra(5), dia(2026, 12, 15), &calendario(), &parametros()).unwrap();
        assert_eq!(p.eventos[2].metodo, Metodo::LinhaDeBaseAjustada);
        // 14 dias de linha de base × 1,10 = 15,4, logo 16 dias a partir de 01/12
        assert_eq!(p.eventos[2].termino, dia(2026, 12, 22));
    }

    #[test]
    fn sem_eventos_concluidos_suficientes_o_fator_e_1() {
        let mut eventos = obra(70);
        eventos[0].andamento = Andamento::NaoIniciado; // sobra um concluído; o mínimo é 2
        eventos[1].predecessoras.clear();
        let p = prever(&eventos, dia(2026, 12, 15), &calendario(), &parametros()).unwrap();
        assert_eq!(p.fator_ritmo, Decimal::ONE);
        assert!(!p.ritmo_medido);
    }

    #[test]
    fn fator_fica_dentro_da_faixa_configurada() {
        let mut p = parametros();
        p.fator_maximo = "1.05".parse().unwrap();
        let r = prever(&obra(70), dia(2026, 12, 15), &calendario(), &p).unwrap();
        assert_eq!(r.fator_ritmo, "1.05".parse().unwrap());
    }

    #[test]
    fn mesma_entrada_mesma_saida() {
        let a = prever(&obra(70), dia(2026, 12, 15), &calendario(), &parametros()).unwrap();
        let b = prever(&obra(70), dia(2026, 12, 15), &calendario(), &parametros()).unwrap();
        assert_eq!(a, b);
    }

    #[test]
    fn predecessora_que_vem_depois_e_erro() {
        let mut eventos = obra(70);
        eventos[0].predecessoras = vec![2];
        assert_eq!(
            prever(&eventos, dia(2026, 12, 15), &calendario(), &parametros()),
            Err(ErroDominio::PredecessoraInvalida {
                evento: 0,
                predecessora: 2
            })
        );
    }

    #[test]
    fn linha_de_base_invertida_e_erro() {
        let mut eventos = obra(70);
        eventos[3].termino_previsto = dia(2027, 1, 4);
        assert_eq!(
            prever(&eventos, dia(2026, 12, 15), &calendario(), &parametros()),
            Err(ErroDominio::LinhaDeBaseInvalida(3))
        );
    }

    #[test]
    fn pagamento_do_evento_que_termina_em_dezembro_cai_em_19_02() {
        // 22/12 → fecha 31/12 → +5 = 05/01 → +10 = 15/01 → +5 = 20/01 → +30 = 19/02/2027
        let m = prever_pagamento(
            dia(2026, 12, 22),
            FechamentoMedicao::UltimoDiaDoMes,
            &PRAZOS,
            &calendario(),
        );
        assert_eq!(m.fechamento, dia(2026, 12, 31));
        assert_eq!(m.envio, dia(2027, 1, 5));
        assert_eq!(m.analise, dia(2027, 1, 15));
        assert_eq!(m.liquidacao, dia(2027, 1, 20));
        assert_eq!(m.pagamento, dia(2027, 2, 19));
    }

    #[test]
    fn exemplo_do_documento_14_11_paga_em_19_01() {
        // docs/10 §6.3
        let m = prever_pagamento(
            dia(2026, 11, 14),
            FechamentoMedicao::UltimoDiaDoMes,
            &PRAZOS,
            &calendario(),
        );
        assert_eq!(m.fechamento, dia(2026, 11, 30));
        assert_eq!(m.pagamento, dia(2027, 1, 19));
    }

    #[test]
    fn os_prazos_vem_da_configuracao() {
        // trocar a configuração muda o resultado: prova que não há prazo embutido no código
        let cal = calendario();
        let termino = dia(2026, 12, 22);
        let padrao = prever_pagamento(termino, FechamentoMedicao::UltimoDiaDoMes, &PRAZOS, &cal);
        let rapido = PrazosProcesso {
            pagamento: 10,
            ..PRAZOS
        };
        let uteis = PrazosProcesso {
            contagem: Contagem::Uteis,
            ..PRAZOS
        };
        assert_eq!(
            prever_pagamento(termino, FechamentoMedicao::UltimoDiaDoMes, &rapido, &cal).pagamento,
            dia(2027, 1, 30)
        );
        let em_dias_uteis =
            prever_pagamento(termino, FechamentoMedicao::UltimoDiaDoMes, &uteis, &cal).pagamento;
        assert!(em_dias_uteis > padrao.pagamento);
    }

    #[test]
    fn termino_no_ultimo_dia_do_mes_ainda_entra_no_mes() {
        let m = prever_pagamento(
            dia(2027, 2, 28),
            FechamentoMedicao::UltimoDiaDoMes,
            &PRAZOS,
            &calendario(),
        );
        assert_eq!(m.fechamento, dia(2027, 2, 28));
    }
}
