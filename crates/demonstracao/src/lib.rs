//! Estado em memória e modelo de tela da **prévia** de desktop do Prumo.
//!
//! Não é o sistema: os dados são fictícios (`dados.rs`), não há banco, usuário,
//! designação, assinatura nem trilha de auditoria, e tudo volta ao início quando
//! o programa fecha. O que é de verdade são os cálculos e as regras, que vêm de
//! `prumo-dominio`: valor de evento, conferência da medição contra o Boletim de
//! Execução e previsão de término e de pagamento.

mod dados;

use chrono::{Datelike, NaiveDate};
use dados::*;
use prumo_dominio::{
    conferir_medicao, desvio_trabalhavel, formatar_decimal, percentual, prever, prever_pagamento,
    Andamento, Calendario, CriterioArredondamento, Dinheiro, ErroDominio, Evento, EventoDeclarado,
    EventoProgramado, FechamentoMedicao, Metodo, Parametros, ServicoNaFrente, SituacaoEvento,
};
use rust_decimal::Decimal;
use serde::Serialize;
use std::collections::{BTreeMap, BTreeSet};

#[derive(Debug, thiserror::Error)]
pub enum ErroDemo {
    #[error("O Boletim de Execução nº 8 já foi emitido e é imutável. Correção só por boletim retificador.")]
    BoletimJaEmitido,
    #[error("A Medição nº 3 já foi aprovada e é imutável.")]
    MedicaoJaAprovada,
    #[error("Situação desconhecida: {0}.")]
    SituacaoDesconhecida(String),
    #[error("Este evento não faz parte da Medição nº 3.")]
    EventoForaDaMedicao,
    #[error(
        "A medição não pode ser aprovada: {0} sem boletim que o marque concluído e sem glosa."
    )]
    MedicaoComPendencia(String),
    #[error("{0}")]
    Dominio(#[from] ErroDominio),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum SituacaoRascunho {
    EmAndamento,
    Concluido,
}

/// O que muda na prévia enquanto ela está aberta.
#[derive(Clone, Debug)]
pub struct Estado {
    /// Linha da Alvenaria no Boletim nº 8 (rascunho, ou como foi emitido).
    situacao: SituacaoRascunho,
    avanco: u8,
    boletim_8_emitido: bool,
    glosados: BTreeSet<usize>,
    medicao_aprovada: bool,
}

impl Default for Estado {
    fn default() -> Estado {
        Estado {
            situacao: SituacaoRascunho::EmAndamento,
            avanco: AVANCO_INICIAL_RASCUNHO,
            boletim_8_emitido: false,
            glosados: BTreeSet::new(),
            medicao_aprovada: false,
        }
    }
}

// ----------------------------------------------------------------- modelo de tela

#[derive(Clone, Debug, Serialize)]
pub struct Painel {
    pub contrato: ContratoVm,
    pub eventos: Vec<EventoVm>,
    pub total_da_planilha: String,
    pub boletim_vigente: BoletimVigenteVm,
    pub fisico_verificado: String,
    pub rascunho: RascunhoVm,
    pub medicao: MedicaoVm,
    pub previsao: PrevisaoVm,
}

#[derive(Clone, Debug, Serialize)]
pub struct ContratoVm {
    pub numero: String,
    pub obra: String,
    pub forma_de_medir: String,
    pub revisao: String,
    pub cronograma: String,
    pub termino_contratual: String,
}

#[derive(Clone, Debug, Serialize)]
pub struct SituacaoVm {
    /// `concluido`, `em_andamento` ou `nao_iniciado`.
    pub codigo: String,
    pub rotulo: String,
}

#[derive(Clone, Debug, Serialize)]
pub struct ServicoVm {
    pub item: String,
    pub descricao: String,
    pub quantidade: String,
    pub preco_unitario: String,
    pub valor: String,
}

#[derive(Clone, Debug, Serialize)]
pub struct EventoVm {
    pub id: usize,
    pub nome: String,
    pub linha_de_base: String,
    pub situacao: SituacaoVm,
    pub valor: String,
    pub servicos: Vec<ServicoVm>,
}

#[derive(Clone, Debug, Serialize)]
pub struct BoletimVigenteVm {
    pub numero: u32,
    pub vistoria_em: String,
}

#[derive(Clone, Debug, Serialize)]
pub struct LinhaRascunhoVm {
    pub evento_id: usize,
    pub nome: String,
    pub linha_de_base: String,
    pub situacao: SituacaoVm,
    pub editavel: bool,
}

#[derive(Clone, Debug, Serialize)]
pub struct RascunhoVm {
    pub numero: u32,
    pub periodo: String,
    pub vistoria_em: String,
    pub emitido: bool,
    /// `em_andamento` ou `concluido`: a linha editável (Alvenaria).
    pub situacao: String,
    pub avanco: u8,
    pub linhas: Vec<LinhaRascunhoVm>,
    pub concluidos: usize,
    pub em_andamento: usize,
    /// Consequência de emitir, para o cartão e para o diálogo de ação irreversível.
    pub efeito_da_emissao: String,
}

#[derive(Clone, Debug, Serialize)]
pub struct ItemMedicaoVm {
    pub evento_id: usize,
    pub nome: String,
    pub previsto: String,
    pub valor: String,
    pub situacao: SituacaoVm,
    pub boletim: String,
    pub glosado: bool,
    pub pendente: bool,
    /// Resultado da regra determinística para este evento.
    pub regra: String,
    pub servicos: Vec<ServicoVm>,
}

#[derive(Clone, Debug, Serialize)]
pub struct MedicaoVm {
    pub numero: u32,
    pub periodo: String,
    pub enviada_em: String,
    pub aprovada: bool,
    pub status: String,
    pub valor_bruto: String,
    pub valor_glosado: String,
    pub valor_conferido: String,
    pub conferidos: String,
    pub pode_aprovar: bool,
    pub itens: Vec<ItemMedicaoVm>,
    pub confirmacao_da_aprovacao: String,
}

#[derive(Clone, Debug, Serialize)]
pub struct LinhaPrevisaoVm {
    pub evento_id: usize,
    pub nome: String,
    pub linha_de_base: String,
    pub situacao: SituacaoVm,
    pub termino: String,
    pub desvio: String,
    pub metodo: String,
    pub pagamento: String,
    /// Falso para evento já pago: o pagamento não é previsão.
    pub pagamento_e_previsao: bool,
    pub valor: String,
}

#[derive(Clone, Debug, Serialize)]
pub struct MesVm {
    pub mes: String,
    pub eventos: String,
    pub bruto: String,
    pub retencoes: String,
    pub liquido: String,
}

#[derive(Clone, Debug, Serialize)]
pub struct ComoVm {
    pub rotulo: String,
    pub texto: String,
}

#[derive(Clone, Debug, Serialize)]
pub struct PrevisaoVm {
    pub calculada_em: String,
    pub boletim: u32,
    pub termino_contratual: String,
    pub termino_previsto: String,
    pub desvio: String,
    pub proximo_desembolso_valor: String,
    pub proximo_desembolso_data: String,
    pub linhas: Vec<LinhaPrevisaoVm>,
    pub desembolso: Vec<MesVm>,
    pub como_foi_calculado: Vec<ComoVm>,
}

// ------------------------------------------------------------------- formatação

fn data(d: NaiveDate) -> String {
    format!("{:02}/{:02}/{}", d.day(), d.month(), d.year())
}

fn periodo(inicio: NaiveDate, fim: NaiveDate) -> String {
    if inicio.year() == fim.year() {
        format!("{:02}/{:02} a {}", inicio.day(), inicio.month(), data(fim))
    } else {
        format!("{} a {}", data(inicio), data(fim))
    }
}

fn mes_ano(d: NaiveDate) -> String {
    const MESES: [&str; 12] = [
        "jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez",
    ];
    format!("{}/{}", MESES[d.month0() as usize], d.year())
}

fn rotulo_desvio(dias: i64) -> String {
    match dias {
        0 => "sem desvio".into(),
        1 => "+1 dia útil".into(),
        -1 => "-1 dia útil".into(),
        n if n > 0 => format!("+{n} dias úteis"),
        n => format!("{n} dias úteis"),
    }
}

fn plural(n: usize, um: &str, varios: &str) -> String {
    if n == 1 {
        format!("1 {um}")
    } else {
        format!("{n} {varios}")
    }
}

fn situacao_vm(andamento: Andamento) -> SituacaoVm {
    let (codigo, rotulo) = match andamento {
        Andamento::NaoIniciado => ("nao_iniciado", "Não iniciado".to_string()),
        Andamento::EmAndamento { avanco_pct, .. } => {
            ("em_andamento", format!("Em andamento · {avanco_pct}%"))
        }
        Andamento::Concluido { concluido_em, .. } => {
            ("concluido", format!("Concluído em {}", data(concluido_em)))
        }
    };
    SituacaoVm {
        codigo: codigo.into(),
        rotulo,
    }
}

fn situacao_no_boletim(andamento: Andamento) -> SituacaoEvento {
    match andamento {
        Andamento::NaoIniciado => SituacaoEvento::NaoIniciado,
        Andamento::EmAndamento { avanco_pct, .. } => SituacaoEvento::EmAndamento { avanco_pct },
        Andamento::Concluido { concluido_em, .. } => SituacaoEvento::Concluido { em: concluido_em },
    }
}

// ------------------------------------------------------------ dados → domínio

fn centesimos(valor: i64) -> Decimal {
    Decimal::new(valor, 2)
}

fn evento(i: usize) -> Evento {
    let d = &EVENTOS[i];
    Evento {
        agrupador: d.agrupador.into(),
        frente: d.frente.into(),
        servicos: d
            .servicos
            .iter()
            .map(|s| ServicoNaFrente {
                item: s.item.into(),
                descricao: s.descricao.into(),
                unidade: s.unidade.into(),
                quantidade: centesimos(s.quantidade),
                preco_unitario: centesimos(s.preco),
            })
            .collect(),
    }
}

fn servicos_vm(e: &Evento) -> Result<Vec<ServicoVm>, ErroDominio> {
    e.servicos
        .iter()
        .map(|s| {
            Ok(ServicoVm {
                item: s.item.clone(),
                descricao: format!("{} ({})", s.descricao, s.unidade),
                quantidade: formatar_decimal(s.quantidade, 2),
                preco_unitario: formatar_decimal(s.preco_unitario, 2),
                valor: s.valor(CRITERIO)?.formatar(),
            })
        })
        .collect()
}

fn calendario() -> Calendario {
    Calendario::new(SEM_EXPEDIENTE)
}

fn parametros() -> Parametros {
    Parametros {
        avanco_minimo_pct: AVANCO_MINIMO_PCT,
        eventos_minimos_para_ritmo: EVENTOS_MINIMOS_PARA_RITMO,
        fator_minimo: centesimos(FAIXA_DO_FATOR.0),
        fator_maximo: centesimos(FAIXA_DO_FATOR.1),
    }
}

/// O que o Boletim nº 7, emitido, registra de cada evento.
fn andamentos_do_boletim_7() -> [Andamento; 6] {
    [
        Andamento::Concluido {
            inicio_real: FUNDACOES_INICIO,
            concluido_em: FUNDACOES_FIM,
        },
        Andamento::Concluido {
            inicio_real: PILARES_INICIO,
            concluido_em: PILARES_FIM,
        },
        Andamento::EmAndamento {
            inicio_real: ALVENARIA_INICIO,
            avanco_pct: ALVENARIA_AVANCO_BOLETIM_7,
        },
        Andamento::NaoIniciado,
        Andamento::NaoIniciado,
        Andamento::NaoIniciado,
    ]
}

impl Estado {
    /// O Boletim nº 8 com a linha da Alvenaria como está no rascunho (ou como foi emitida).
    fn andamentos_do_boletim_8(&self) -> [Andamento; 6] {
        let mut a = andamentos_do_boletim_7();
        a[ALVENARIA] = match self.situacao {
            SituacaoRascunho::EmAndamento => Andamento::EmAndamento {
                inicio_real: ALVENARIA_INICIO,
                avanco_pct: self.avanco,
            },
            SituacaoRascunho::Concluido => Andamento::Concluido {
                inicio_real: ALVENARIA_INICIO,
                concluido_em: VISTORIA_BOLETIM_8,
            },
        };
        a
    }

    /// Número, data da vistoria e conteúdo do último boletim **emitido**.
    fn boletim_vigente(&self) -> (u32, NaiveDate, [Andamento; 6]) {
        if self.boletim_8_emitido {
            (8, VISTORIA_BOLETIM_8, self.andamentos_do_boletim_8())
        } else {
            (7, VISTORIA_BOLETIM_7, andamentos_do_boletim_7())
        }
    }

    fn declarados(
        &self,
        valores: &[Dinheiro],
        andamentos: &[Andamento; 6],
    ) -> Vec<EventoDeclarado> {
        DECLARADOS_MEDICAO_3
            .iter()
            .map(|&i| EventoDeclarado {
                valor: valores[i],
                situacao_no_boletim: Some(situacao_no_boletim(andamentos[i])),
                glosado: self.glosados.contains(&i),
            })
            .collect()
    }

    // ------------------------------------------------------------------ ações

    /// Altera a linha da Alvenaria no rascunho do Boletim nº 8.
    pub fn salvar_rascunho(&mut self, situacao: &str, avanco: u8) -> Result<(), ErroDemo> {
        if self.boletim_8_emitido {
            return Err(ErroDemo::BoletimJaEmitido);
        }
        match situacao {
            "em_andamento" => {
                SituacaoEvento::em_andamento(avanco)?;
                self.situacao = SituacaoRascunho::EmAndamento;
                self.avanco = avanco;
            }
            "concluido" => self.situacao = SituacaoRascunho::Concluido,
            outra => return Err(ErroDemo::SituacaoDesconhecida(outra.into())),
        }
        Ok(())
    }

    /// Emite o Boletim nº 8. Depois disso ele não muda mais.
    pub fn emitir_boletim(&mut self) -> Result<(), ErroDemo> {
        if self.boletim_8_emitido {
            return Err(ErroDemo::BoletimJaEmitido);
        }
        self.boletim_8_emitido = true;
        Ok(())
    }

    /// Glosa o evento inteiro na Medição nº 3.
    pub fn glosar(&mut self, evento: usize) -> Result<(), ErroDemo> {
        self.exigir_medicao_aberta(evento)?;
        self.glosados.insert(evento);
        Ok(())
    }

    pub fn desfazer_glosa(&mut self, evento: usize) -> Result<(), ErroDemo> {
        self.exigir_medicao_aberta(evento)?;
        self.glosados.remove(&evento);
        Ok(())
    }

    fn exigir_medicao_aberta(&self, evento: usize) -> Result<(), ErroDemo> {
        if self.medicao_aprovada {
            Err(ErroDemo::MedicaoJaAprovada)
        } else if !DECLARADOS_MEDICAO_3.contains(&evento) {
            Err(ErroDemo::EventoForaDaMedicao)
        } else {
            Ok(())
        }
    }

    /// Aprova a Medição nº 3. Só passa se todo evento declarado estiver concluído
    /// no último boletim emitido, ou glosado.
    pub fn aprovar_medicao(&mut self) -> Result<(), ErroDemo> {
        if self.medicao_aprovada {
            return Err(ErroDemo::MedicaoJaAprovada);
        }
        let valores = valores_dos_eventos()?;
        let (_, _, andamentos) = self.boletim_vigente();
        let conferencia = conferir_medicao(&self.declarados(&valores, &andamentos))?;
        if !conferencia.pode_aprovar() {
            let nomes: Vec<String> = conferencia
                .pendentes
                .iter()
                .map(|&p| evento(DECLARADOS_MEDICAO_3[p]).nome())
                .collect();
            return Err(ErroDemo::MedicaoComPendencia(nomes.join(", ")));
        }
        self.medicao_aprovada = true;
        Ok(())
    }

    // ------------------------------------------------------------------- tela

    /// Tudo o que as telas mostram, já calculado e formatado.
    pub fn painel(&self) -> Result<Painel, ErroDemo> {
        let cal = calendario();
        let eventos: Vec<Evento> = (0..EVENTOS.len()).map(evento).collect();
        let valores = valores_dos_eventos()?;
        let total = valores
            .iter()
            .try_fold(Dinheiro::ZERO, |soma, v| soma.somar(*v))?;
        let (numero_boletim, hoje, andamentos) = self.boletim_vigente();
        let linha_de_base =
            |i: usize| periodo(EVENTOS[i].inicio_previsto, EVENTOS[i].termino_previsto);

        // Previsão de término, sobre o último boletim emitido.
        let programados: Vec<EventoProgramado> = EVENTOS
            .iter()
            .zip(andamentos)
            .map(|(d, andamento)| EventoProgramado {
                inicio_previsto: d.inicio_previsto,
                termino_previsto: d.termino_previsto,
                predecessoras: d.predecessoras.to_vec(),
                andamento,
            })
            .collect();
        let previsao = prever(&programados, hoje, &cal, &parametros())?;

        // Físico verificado: valor dos eventos ponderado pelo avanço do boletim emitido.
        let mut executado = Decimal::ZERO;
        for (valor, andamento) in valores.iter().zip(andamentos) {
            let avanco = match andamento {
                Andamento::Concluido { .. } => 100,
                Andamento::EmAndamento { avanco_pct, .. } => u32::from(avanco_pct),
                Andamento::NaoIniciado => 0,
            };
            executado += valor.decimal() * Decimal::from(avanco);
        }
        let fisico = if total.eh_zero() {
            Decimal::ZERO
        } else {
            executado / total.decimal()
        };

        // Medição nº 3 conferida contra o boletim.
        let conferencia = conferir_medicao(&self.declarados(&valores, &andamentos))?;
        let mut itens = Vec::new();
        for (posicao, &i) in DECLARADOS_MEDICAO_3.iter().enumerate() {
            let glosado = self.glosados.contains(&i);
            let pendente = conferencia.pendentes.contains(&posicao);
            let regra = if glosado {
                "Glosado: o evento inteiro saiu desta medição e pode voltar em outra.".to_string()
            } else {
                match andamentos[i] {
                    Andamento::Concluido { concluido_em, .. } => format!(
                        "O Boletim de Execução nº {numero_boletim} marca este evento como concluído em {}. Pode ser aprovado.",
                        data(concluido_em)
                    ),
                    Andamento::EmAndamento { avanco_pct, .. } => format!(
                        "O Boletim de Execução nº {numero_boletim} marca este evento como em andamento, com {avanco_pct}%. Evento só é aprovado quando o boletim o marca concluído."
                    ),
                    Andamento::NaoIniciado => format!(
                        "O Boletim de Execução nº {numero_boletim} marca este evento como não iniciado. Evento só é aprovado quando o boletim o marca concluído."
                    ),
                }
            };
            itens.push(ItemMedicaoVm {
                evento_id: i,
                nome: eventos[i].nome(),
                previsto: mes_ano(EVENTOS[i].termino_previsto),
                valor: valores[i].formatar(),
                situacao: situacao_vm(andamentos[i]),
                boletim: format!("Boletim nº {numero_boletim}"),
                glosado,
                pendente,
                regra,
                servicos: servicos_vm(&eventos[i])?,
            });
        }
        let conferidos =
            DECLARADOS_MEDICAO_3.len() - conferencia.pendentes.len() - self.glosados.len();
        let medicao = MedicaoVm {
            numero: 3,
            periodo: periodo(PERIODO_MEDICAO_3.0, PERIODO_MEDICAO_3.1),
            enviada_em: data(MEDICAO_3_ENVIADA),
            aprovada: self.medicao_aprovada,
            status: if self.medicao_aprovada { "Aprovada" } else { "Em análise" }.into(),
            valor_bruto: conferencia.valor_bruto.formatar(),
            valor_glosado: conferencia.valor_glosado.formatar(),
            valor_conferido: conferencia.valor_conferido.formatar(),
            conferidos: format!("{conferidos} de {}", DECLARADOS_MEDICAO_3.len()),
            pode_aprovar: conferencia.pode_aprovar() && !self.medicao_aprovada,
            itens,
            confirmacao_da_aprovacao: format!(
                "Você está aprovando a Medição nº 3 no valor de R$ {}, com R$ {} glosados. Esta ação não pode ser desfeita.",
                conferencia.valor_conferido.formatar(),
                conferencia.valor_glosado.formatar()
            ),
        };

        // Do término de cada evento até o pagamento previsto.
        let depois_da_medicao_3 = PERIODO_MEDICAO_3
            .1
            .succ_opt()
            .unwrap_or(PERIODO_MEDICAO_3.1);
        let mut linhas = Vec::new();
        let mut meses: BTreeMap<(i32, u32), Mes> = BTreeMap::new();
        let mut proximo: Option<(NaiveDate, Dinheiro)> = None;
        for (i, previsto) in previsao.eventos.iter().enumerate() {
            let (pagamento, pagamento_e_previsao) = if i == FUNDACOES {
                ("pago na Medição nº 2".to_string(), false)
            } else {
                // Evento glosado na Medição nº 3 só entra em medição de período seguinte.
                let base = if self.glosados.contains(&i) {
                    previsto.termino.max(depois_da_medicao_3)
                } else {
                    previsto.termino
                };
                let marcos =
                    prever_pagamento(base, FechamentoMedicao::UltimoDiaDoMes, &PRAZOS, &cal);
                let retencao = percentual(valores[i], Decimal::from(RETENCAO_PCT), CRITERIO)?;
                let mes = meses
                    .entry((marcos.pagamento.year(), marcos.pagamento.month()))
                    .or_insert_with(|| Mes::em(marcos.pagamento));
                mes.eventos.push(eventos[i].nome());
                mes.bruto = mes.bruto.somar(valores[i])?;
                mes.retencoes = mes.retencoes.somar(retencao)?;
                proximo = Some(match proximo {
                    Some((quando, soma)) if quando == marcos.pagamento => {
                        (quando, soma.somar(valores[i])?)
                    }
                    Some(atual) if atual.0 < marcos.pagamento => atual,
                    _ => (marcos.pagamento, valores[i]),
                });
                (data(marcos.pagamento), true)
            };
            let concluido = matches!(andamentos[i], Andamento::Concluido { .. });
            linhas.push(LinhaPrevisaoVm {
                evento_id: i,
                nome: eventos[i].nome(),
                linha_de_base: linha_de_base(i),
                situacao: situacao_vm(andamentos[i]),
                termino: if concluido {
                    "já concluído".into()
                } else {
                    data(previsto.termino)
                },
                desvio: rotulo_desvio(previsto.desvio_dias),
                metodo: match previsto.metodo {
                    Metodo::Real => "data real do boletim",
                    Metodo::Ritmo => "ritmo verificado do evento",
                    Metodo::LinhaDeBaseAjustada => "linha de base × fator de ritmo",
                }
                .into(),
                pagamento,
                pagamento_e_previsao,
                valor: valores[i].formatar(),
            });
        }
        let desembolso = meses
            .into_values()
            .map(|m| MesVm {
                mes: mes_ano(m.quando),
                eventos: m.eventos.join(", "),
                bruto: m.bruto.formatar(),
                retencoes: m.retencoes.formatar(),
                liquido: (m.bruto - m.retencoes).formatar(),
            })
            .collect();

        // "Como foi calculado": as entradas, com a origem de cada uma.
        let mut como = vec![
            ComoVm {
                rotulo: "Cronograma".into(),
                texto: "versão 1, linha de base, fornecido pelo órgão.".into(),
            },
            ComoVm {
                rotulo: "Avanço verificado".into(),
                texto: format!(
                    "Boletim de Execução nº {numero_boletim}, vistoria em {}.",
                    data(hoje)
                ),
            },
        ];
        for (i, previsto) in previsao.eventos.iter().enumerate() {
            if let (
                Metodo::Ritmo,
                Andamento::EmAndamento {
                    inicio_real,
                    avanco_pct,
                },
            ) = (previsto.metodo, andamentos[i])
            {
                let decorridos = cal.contar(inicio_real, hoje) as usize;
                let restantes = cal.contar(cal.depois_de(hoje), previsto.termino) as usize;
                como.push(ComoVm {
                    rotulo: eventos[i].nome(),
                    texto: format!(
                        "{avanco_pct}% em {}. Nesse ritmo, {}.",
                        plural(decorridos, "dia útil", "dias úteis"),
                        if restantes == 1 {
                            "falta 1 dia útil".to_string()
                        } else {
                            format!("faltam {restantes} dias úteis")
                        }
                    ),
                });
            }
        }
        como.push(ComoVm {
            rotulo: "Fator de ritmo da obra".into(),
            texto: if previsao.ritmo_medido {
                format!(
                    "{} sobre {} (duração real ÷ prevista). Aplicado aos eventos não iniciados.",
                    formatar_decimal(previsao.fator_ritmo, 2),
                    plural(
                        previsao.eventos_concluidos,
                        "evento concluído",
                        "eventos concluídos"
                    )
                )
            } else {
                "ainda não há ritmo medido; vale a duração da linha de base.".into()
            },
        });
        como.push(ComoVm {
            rotulo: "Calendário da obra".into(),
            texto: format!(
                "segunda a sexta, menos {} dias sem expediente cadastrados.",
                SEM_EXPEDIENTE.len()
            ),
        });
        como.push(ComoVm {
            rotulo: "Fechamento da medição".into(),
            texto: "último dia do mês (contrato).".into(),
        });
        como.push(ComoVm {
            rotulo: "Prazos de processo".into(),
            texto: format!(
                "envio {} dias, análise {} dias, atesto e liquidação {} dias, pagamento {} dias. Dias corridos. Configuração do município e do contrato.",
                PRAZOS.envio_da_medicao, PRAZOS.analise_da_fiscalizacao, PRAZOS.atesto_e_liquidacao, PRAZOS.pagamento
            ),
        });
        como.push(ComoVm {
            rotulo: "Retenções".into(),
            texto: format!(
                "{RETENCAO_PCT}% sobre o valor bruto, pela alíquota cadastrada no contrato."
            ),
        });

        let (termino_previsto, desvio) = match previsao.termino {
            Some(t) => (
                data(t),
                rotulo_desvio(desvio_trabalhavel(&cal, TERMINO_CONTRATUAL, t)),
            ),
            None => ("sem dados".into(), "sem dados".into()),
        };
        let previsao_vm = PrevisaoVm {
            calculada_em: data(hoje),
            boletim: numero_boletim,
            termino_contratual: data(TERMINO_CONTRATUAL),
            termino_previsto,
            desvio,
            proximo_desembolso_valor: proximo.map_or("sem dados".into(), |(_, v)| v.formatar()),
            proximo_desembolso_data: proximo.map_or("sem dados".into(), |(quando, _)| data(quando)),
            linhas,
            desembolso,
            como_foi_calculado: como,
        };

        // Boletim nº 8: rascunho editável, ou como foi emitido.
        let no_rascunho = self.andamentos_do_boletim_8();
        let mut liberados = 0usize;
        let mut valor_liberado = Dinheiro::ZERO;
        for &i in &DECLARADOS_MEDICAO_3 {
            if matches!(no_rascunho[i], Andamento::Concluido { .. }) {
                liberados += 1;
                valor_liberado = valor_liberado.somar(valores[i])?;
            }
        }
        let rascunho = RascunhoVm {
            numero: 8,
            periodo: periodo(PERIODO_BOLETIM_8.0, PERIODO_BOLETIM_8.1),
            vistoria_em: data(VISTORIA_BOLETIM_8),
            emitido: self.boletim_8_emitido,
            situacao: match self.situacao {
                SituacaoRascunho::EmAndamento => "em_andamento",
                SituacaoRascunho::Concluido => "concluido",
            }
            .into(),
            avanco: self.avanco,
            linhas: (0..EVENTOS.len())
                .map(|i| LinhaRascunhoVm {
                    evento_id: i,
                    nome: eventos[i].nome(),
                    linha_de_base: linha_de_base(i),
                    situacao: situacao_vm(no_rascunho[i]),
                    editavel: i == ALVENARIA && !self.boletim_8_emitido,
                })
                .collect(),
            concluidos: no_rascunho.iter().filter(|a| matches!(a, Andamento::Concluido { .. })).count(),
            em_andamento: no_rascunho.iter().filter(|a| matches!(a, Andamento::EmAndamento { .. })).count(),
            efeito_da_emissao: format!(
                "libera a análise de {} (R$ {}) na Medição nº 3 e não pode ser alterado; correções exigem boletim retificador.",
                plural(liberados, "evento concluído", "eventos concluídos"),
                valor_liberado.formatar()
            ),
        };

        let mut eventos_vm = Vec::new();
        for (i, e) in eventos.iter().enumerate() {
            eventos_vm.push(EventoVm {
                id: i,
                nome: e.nome(),
                linha_de_base: linha_de_base(i),
                situacao: situacao_vm(andamentos[i]),
                valor: valores[i].formatar(),
                servicos: servicos_vm(e)?,
            });
        }

        Ok(Painel {
            contrato: ContratoVm {
                numero: CONTRATO.into(),
                obra: OBRA.into(),
                forma_de_medir: "medido por eventos".into(),
                revisao: "Revisão 0 vigente".into(),
                cronograma: "cronograma versão 1".into(),
                termino_contratual: data(TERMINO_CONTRATUAL),
            },
            eventos: eventos_vm,
            total_da_planilha: total.formatar(),
            boletim_vigente: BoletimVigenteVm {
                numero: numero_boletim,
                vistoria_em: data(hoje),
            },
            fisico_verificado: format!("{}%", formatar_decimal(fisico, 1)),
            rascunho,
            medicao,
            previsao: previsao_vm,
        })
    }
}

/// Desembolso previsto de um mês, enquanto é somado.
struct Mes {
    quando: NaiveDate,
    eventos: Vec<String>,
    bruto: Dinheiro,
    retencoes: Dinheiro,
}

impl Mes {
    fn em(quando: NaiveDate) -> Mes {
        Mes {
            quando,
            eventos: Vec::new(),
            bruto: Dinheiro::ZERO,
            retencoes: Dinheiro::ZERO,
        }
    }
}

/// Planilha da obra fictícia, já distribuída em eventos, e o critério do contrato.
///
/// O seed do banco (`db/seed/exemplo.sql`, contrato 045/2026) tem que trazer os mesmos
/// serviços, quantidades e preços. `crates/paridade` confere os dois, linha a linha.
pub fn planilha_por_eventos() -> (Vec<Evento>, CriterioArredondamento) {
    ((0..EVENTOS.len()).map(evento).collect(), CRITERIO)
}

fn valores_dos_eventos() -> Result<Vec<Dinheiro>, ErroDominio> {
    (0..EVENTOS.len())
        .map(|i| evento(i).valor(CRITERIO))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn linha<'a>(p: &'a Painel, nome: &str) -> &'a LinhaPrevisaoVm {
        p.previsao.linhas.iter().find(|l| l.nome == nome).unwrap()
    }

    #[test]
    fn planilha_e_valores_dos_eventos() {
        let p = Estado::default().painel().unwrap();
        assert_eq!(p.eventos.len(), 6);
        assert_eq!(p.eventos[PILARES].valor, "26.014,74");
        assert_eq!(p.eventos[ALVENARIA].valor, "16.641,60");
        assert_eq!(p.eventos[3].valor, "38.920,00");
        assert_eq!(p.total_da_planilha, "164.039,34");
    }

    #[test]
    fn estado_inicial_usa_o_boletim_7() {
        let p = Estado::default().painel().unwrap();
        assert_eq!(p.boletim_vigente.numero, 7);
        assert_eq!(p.fisico_verificado, "43,8%");
        assert_eq!(linha(&p, "Alvenaria × Térreo").termino, "22/12/2026");
        assert_eq!(linha(&p, "Alvenaria × Térreo").desvio, "+2 dias úteis");
        assert_eq!(linha(&p, "Alvenaria × Térreo").pagamento, "19/02/2027");
        assert_eq!(linha(&p, "Cobertura × Térreo").termino, "02/02/2027");
        assert_eq!(linha(&p, "Cobertura × Térreo").pagamento, "19/04/2027");
        assert_eq!(
            linha(&p, "Estrutura: pilares × Térreo").termino,
            "já concluído"
        );
        assert_eq!(
            linha(&p, "Fundações × Térreo").pagamento,
            "pago na Medição nº 2"
        );
        assert_eq!(p.previsao.termino_previsto, "13/05/2027");
        assert_eq!(p.previsao.desvio, "+9 dias úteis");
        assert_eq!(p.previsao.proximo_desembolso_valor, "42.656,34");
        assert_eq!(p.previsao.proximo_desembolso_data, "19/02/2027");
    }

    #[test]
    fn desembolso_de_fevereiro_soma_pilares_e_alvenaria() {
        let p = Estado::default().painel().unwrap();
        let fev = &p.previsao.desembolso[0];
        assert_eq!(fev.mes, "fev/2027");
        assert_eq!(fev.bruto, "42.656,34");
        assert_eq!(fev.retencoes, "4.692,20");
        assert_eq!(fev.liquido, "37.964,14");
        let meses: Vec<&str> = p
            .previsao
            .desembolso
            .iter()
            .map(|m| m.mes.as_str())
            .collect();
        assert_eq!(meses, ["fev/2027", "abr/2027", "mai/2027", "jul/2027"]);
    }

    #[test]
    fn medicao_nao_aprova_com_evento_em_andamento_no_boletim() {
        let mut e = Estado::default();
        let p = e.painel().unwrap();
        assert!(!p.medicao.pode_aprovar);
        assert_eq!(p.medicao.conferidos, "1 de 2");
        assert_eq!(p.medicao.valor_bruto, "42.656,34");
        assert!(p.medicao.itens[1].pendente);
        assert!(matches!(
            e.aprovar_medicao(),
            Err(ErroDemo::MedicaoComPendencia(_))
        ));
        assert!(!e.painel().unwrap().medicao.aprovada);
    }

    #[test]
    fn glosar_o_evento_libera_a_aprovacao_e_adia_o_pagamento_dele() {
        let mut e = Estado::default();
        e.glosar(ALVENARIA).unwrap();
        let p = e.painel().unwrap();
        assert!(p.medicao.pode_aprovar);
        assert_eq!(p.medicao.valor_glosado, "16.641,60");
        assert_eq!(p.medicao.valor_conferido, "26.014,74");
        // sai da medição de dezembro: entra na de janeiro e é pago um mês depois
        assert_eq!(linha(&p, "Alvenaria × Térreo").pagamento, "22/03/2027");
        e.aprovar_medicao().unwrap();
        assert!(e.painel().unwrap().medicao.aprovada);
        assert!(matches!(
            e.desfazer_glosa(ALVENARIA),
            Err(ErroDemo::MedicaoJaAprovada)
        ));
    }

    #[test]
    fn emitir_o_boletim_8_com_alvenaria_concluida_libera_a_medicao() {
        let mut e = Estado::default();
        e.salvar_rascunho("concluido", 0).unwrap();
        // rascunho não vale: a medição continua presa ao boletim 7
        assert!(!e.painel().unwrap().medicao.pode_aprovar);
        e.emitir_boletim().unwrap();
        let p = e.painel().unwrap();
        assert_eq!(p.boletim_vigente.numero, 8);
        assert!(p.medicao.pode_aprovar);
        assert_eq!(p.medicao.valor_conferido, "42.656,34");
        assert_eq!(linha(&p, "Alvenaria × Térreo").termino, "já concluído");
        e.aprovar_medicao().unwrap();
        assert_eq!(e.painel().unwrap().medicao.status, "Aprovada");
    }

    #[test]
    fn boletim_emitido_e_imutavel() {
        let mut e = Estado::default();
        e.emitir_boletim().unwrap();
        assert!(matches!(
            e.salvar_rascunho("concluido", 0),
            Err(ErroDemo::BoletimJaEmitido)
        ));
        assert!(matches!(
            e.emitir_boletim(),
            Err(ErroDemo::BoletimJaEmitido)
        ));
        assert!(e
            .painel()
            .unwrap()
            .rascunho
            .linhas
            .iter()
            .all(|l| !l.editavel));
    }

    #[test]
    fn avanco_menor_no_boletim_8_adia_o_pagamento_para_marco() {
        let mut e = Estado::default();
        e.salvar_rascunho("em_andamento", 71).unwrap();
        e.emitir_boletim().unwrap();
        let p = e.painel().unwrap();
        // 71% em 16 dias úteis: faltam 7; termina em 04/01/2027 e cai na medição de janeiro
        assert_eq!(linha(&p, "Alvenaria × Térreo").termino, "04/01/2027");
        assert_eq!(linha(&p, "Alvenaria × Térreo").pagamento, "22/03/2027");
    }

    #[test]
    fn rascunho_recusa_avanco_fora_da_faixa_e_situacao_desconhecida() {
        let mut e = Estado::default();
        assert!(e.salvar_rascunho("em_andamento", 0).is_err());
        assert!(e.salvar_rascunho("em_andamento", 100).is_err());
        assert!(matches!(
            e.salvar_rascunho("pago", 50),
            Err(ErroDemo::SituacaoDesconhecida(_))
        ));
        assert_eq!(e.painel().unwrap().rascunho.avanco, AVANCO_INICIAL_RASCUNHO);
    }

    #[test]
    fn so_evento_da_medicao_pode_ser_glosado() {
        let mut e = Estado::default();
        assert!(matches!(
            e.glosar(FUNDACOES),
            Err(ErroDemo::EventoForaDaMedicao)
        ));
    }

    #[test]
    fn o_painel_vira_json() {
        let p = Estado::default().painel().unwrap();
        let json = serde_json::to_value(&p).unwrap();
        assert_eq!(
            json["medicao"]["itens"][0]["nome"],
            "Estrutura: pilares × Térreo"
        );
    }
}
