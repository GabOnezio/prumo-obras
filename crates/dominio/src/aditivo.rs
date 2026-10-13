//! Aditivo de valor: preço de item novo, limites de acréscimo e supressão, e a planilha
//! que resulta do aditivo (Rev. N+1).
//!
//! As contas reproduzem o schema de referência (`fator_art127`, `fn_aditivo_item_guard`,
//! `fn_limites_aditivos`) e `crates/paridade` confere os dois lados com o banco de pé.
//!
//! `TODO(jurídico)`: os pontos abaixo vêm do schema de referência e de
//! `docs/07-conformidade.md`. Nenhum foi conferido no texto oficial da Lei 14.133/2021.
//! Estão marcados onde aparecem no código:
//!   1. limite de 25% para acréscimos e para supressões, e de 50% para acréscimos em reforma
//!      de edifício ou de equipamento (art. 125);
//!   2. base do limite: o valor inicial do contrato, aqui sem reajuste (a lei fala em valor
//!      inicial atualizado; o reajuste ainda não existe no sistema);
//!   3. acréscimos e supressões somados em separado, sem compensar um com o outro;
//!   4. restabelecimento de quantidade suprimida fora da conta de acréscimos
//!      (o schema cita o Acórdão 66/2021 do Plenário do TCU);
//!   5. preço de item novo pela relação entre a proposta e o orçamento-base (art. 127).

use crate::conta::{dividir_arredondando, potencia_de_dez, vezes};
use crate::dinheiro::{valor_item, Dinheiro};
use crate::planilha::{conferir_servico, ItemId, ItemPlanilha, Planilha, TipoItem};
use crate::ErroDominio;
use rust_decimal::Decimal;
use std::collections::{BTreeMap, BTreeSet};

/// Casas decimais do fator, as mesmas da coluna `contrato.fator_art127`.
pub const CASAS_DO_FATOR: u32 = 8;

/// Relação entre o valor da proposta e o orçamento-base da licitação, com 8 casas.
/// `TODO(jurídico)` 5: art. 127.
pub fn fator_art127(
    valor_da_proposta: Dinheiro,
    orcamento_base: Dinheiro,
) -> Result<Decimal, ErroDominio> {
    let proposta = valor_da_proposta.decimal().mantissa();
    let base = orcamento_base.decimal().mantissa();
    if proposta <= 0 || base <= 0 {
        return Err(ErroDominio::ValorDoContratoInvalido);
    }
    let fator = dividir_arredondando(vezes(proposta, potencia_de_dez(CASAS_DO_FATOR)?)?, base)?;
    Decimal::try_from_i128_with_scale(fator, CASAS_DO_FATOR).map_err(|_| ErroDominio::Estouro)
}

/// Preço unitário de um item que não existe na planilha: preço de referência × fator,
/// nas casas decimais que o contrato aceita. `TODO(jurídico)` 5: art. 127.
///
/// Arredonda (meio para longe do zero) mesmo em contrato que trunca valores: é o que o
/// cenário de referência faz. O critério do contrato vale para quantidade × preço.
pub fn preco_de_item_novo(
    preco_de_referencia: Decimal,
    fator: Decimal,
    casas_do_preco: u32,
) -> Result<Decimal, ErroDominio> {
    let produto = vezes(preco_de_referencia.mantissa(), fator.mantissa())?;
    let escala = preco_de_referencia.scale() + fator.scale();
    let preco = if escala <= casas_do_preco {
        vezes(produto, potencia_de_dez(casas_do_preco - escala)?)?
    } else {
        dividir_arredondando(produto, potencia_de_dez(escala - casas_do_preco)?)?
    };
    Decimal::try_from_i128_with_scale(preco, casas_do_preco).map_err(|_| ErroDominio::Estouro)
}

/// O que o aditivo faz com um item (`operacao_aditivo` no banco).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Operacao {
    /// Aumenta a quantidade de um serviço que já existe, pelo preço da planilha.
    Acrescimo,
    /// Diminui a quantidade de um serviço que já existe.
    Supressao,
    /// Cria um serviço que não existia.
    Inclusao,
    /// Devolve quantidade suprimida antes, no mesmo item e preço.
    Restabelecimento,
}

impl Operacao {
    pub fn nome(self) -> &'static str {
        match self {
            Operacao::Acrescimo => "acrescimo",
            Operacao::Supressao => "supressao",
            Operacao::Inclusao => "inclusao",
            Operacao::Restabelecimento => "restabelecimento",
        }
    }
}

/// Dados de um serviço novo. Só para [`Operacao::Inclusao`].
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ServicoNovo {
    /// Grupo da planilha em que o serviço entra; ele vai para o fim do grupo.
    pub grupo: ItemId,
    pub codigo_eap: String,
    pub descricao: String,
    pub unidade: String,
    /// Preço de referência na data do aditivo, antes do fator.
    pub preco_de_referencia: Decimal,
}

/// Uma linha do aditivo, como a pessoa informa.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ItemDoAditivo {
    pub item: ItemId,
    pub operacao: Operacao,
    /// Negativa na supressão, positiva nas outras.
    pub quantidade: Decimal,
    pub novo: Option<ServicoNovo>,
}

/// Uma linha do aditivo com o preço e o valor que o sistema calculou.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ItemCalculado {
    pub item: ItemId,
    pub operacao: Operacao,
    pub quantidade: Decimal,
    pub preco_unitario: Decimal,
    /// Quantidade × preço, pelo critério do contrato. Negativo na supressão.
    pub valor: Dinheiro,
}

/// O que o contrato já tem e que limita o aditivo.
#[derive(Clone, Debug, Default)]
pub struct Historico {
    /// Quantidade já medida de cada item, em medições não canceladas.
    pub medido: BTreeMap<ItemId, Decimal>,
    /// Quantidade de cada item suprimida em aditivos homologados e ainda não restabelecida.
    pub suprimido: BTreeMap<ItemId, Decimal>,
}

/// Resultado de aplicar um aditivo a uma planilha.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AditivoAplicado {
    pub itens: Vec<ItemCalculado>,
    /// A planilha seguinte (Rev. N+1).
    pub planilha: Planilha,
}

/// Confere as linhas do aditivo contra a planilha base, calcula preço e valor de cada uma
/// e monta a planilha seguinte.
///
/// Regras, as mesmas de `fn_aditivo_item_guard`:
/// - um item aparece uma vez só no aditivo;
/// - acréscimo, supressão e restabelecimento só em serviço da planilha base, pelo preço dela;
/// - supressão não deixa a quantidade abaixo do que já foi medido;
/// - inclusão cria item que não existe, abaixo de um grupo, com preço de referência × fator.
///
/// E duas que o banco de referência não tem:
/// - restabelecimento não passa da quantidade suprimida antes e ainda não devolvida. Sem
///   isso, um acréscimo chamado de restabelecimento ficaria fora do limite legal;
/// - código de item novo não repete código da planilha.
pub fn aplicar_aditivo(
    base: &Planilha,
    fator: Decimal,
    itens: &[ItemDoAditivo],
    historico: &Historico,
) -> Result<AditivoAplicado, ErroDominio> {
    let mut vistos = BTreeSet::new();
    let mut calculados = Vec::with_capacity(itens.len());
    let mut deltas: BTreeMap<ItemId, Decimal> = BTreeMap::new();
    let mut novos: Vec<ItemPlanilha> = Vec::new();

    for linha in itens {
        let rotulo = || rotulo_do_item(base, linha);
        if !vistos.insert(linha.item) {
            return Err(ErroDominio::ItemRepetido(rotulo()));
        }
        let sinal_certo = match linha.operacao {
            Operacao::Supressao => linha.quantidade.is_sign_negative(),
            _ => linha.quantidade.is_sign_positive(),
        };
        if linha.quantidade.is_zero() || !sinal_certo {
            return Err(ErroDominio::QuantidadeDoAditivoInvalida(rotulo()));
        }

        let preco_unitario = match linha.operacao {
            Operacao::Inclusao => {
                let novo = linha
                    .novo
                    .as_ref()
                    .ok_or_else(|| ErroDominio::InclusaoIncompleta(rotulo()))?;
                if base.item(linha.item).is_some() {
                    return Err(ErroDominio::InclusaoDeItemExistente(rotulo()));
                }
                let grupo_valido = base
                    .item(novo.grupo)
                    .is_some_and(|grupo| !grupo.eh_servico());
                if !grupo_valido {
                    return Err(ErroDominio::PaiInvalido(rotulo()));
                }
                if novo.codigo_eap.is_empty() || novo.unidade.is_empty() {
                    return Err(ErroDominio::InclusaoIncompleta(rotulo()));
                }
                let preco =
                    preco_de_item_novo(novo.preco_de_referencia, fator, base.casas_do_preco())?;
                conferir_servico(
                    &novo.codigo_eap,
                    linha.quantidade,
                    preco,
                    base.casas_do_preco(),
                )?;
                novos.push(ItemPlanilha {
                    id: linha.item,
                    pai: Some(novo.grupo),
                    ordem: 0, // definida ao montar a planilha
                    codigo_eap: novo.codigo_eap.clone(),
                    descricao: novo.descricao.clone(),
                    tipo: TipoItem::Servico {
                        unidade: novo.unidade.clone(),
                        quantidade: linha.quantidade,
                        preco_unitario: preco,
                    },
                });
                preco
            }
            _ => {
                let Some(TipoItem::Servico {
                    quantidade: contratada,
                    preco_unitario,
                    ..
                }) = base.item(linha.item).map(|item| &item.tipo)
                else {
                    return Err(ErroDominio::ItemForaDaPlanilha(rotulo()));
                };
                let medido = historico
                    .medido
                    .get(&linha.item)
                    .copied()
                    .unwrap_or_default();
                if contratada + linha.quantidade < medido {
                    return Err(ErroDominio::SupressaoAbaixoDoMedido {
                        item: rotulo(),
                        medido,
                    });
                }
                if linha.operacao == Operacao::Restabelecimento {
                    let suprimido = historico
                        .suprimido
                        .get(&linha.item)
                        .copied()
                        .unwrap_or_default();
                    if linha.quantidade > suprimido {
                        return Err(ErroDominio::RestabelecimentoSemSupressao {
                            item: rotulo(),
                            suprimido,
                        });
                    }
                }
                deltas.insert(linha.item, linha.quantidade);
                *preco_unitario
            }
        };

        calculados.push(ItemCalculado {
            item: linha.item,
            operacao: linha.operacao,
            quantidade: linha.quantidade,
            preco_unitario,
            valor: valor_item(linha.quantidade, preco_unitario, base.criterio())?,
        });
    }

    // Planilha seguinte: os itens da base com a quantidade ajustada e os novos no fim do grupo.
    let mut seguinte: Vec<ItemPlanilha> = Vec::new();
    let mut ultima_ordem: BTreeMap<Option<ItemId>, u32> = BTreeMap::new();
    for (item, _) in base.itens() {
        let mut copia = item.clone();
        if let (TipoItem::Servico { quantidade, .. }, Some(delta)) =
            (&mut copia.tipo, deltas.get(&item.id))
        {
            *quantidade += delta;
        }
        let ordem = ultima_ordem.entry(copia.pai).or_default();
        *ordem = (*ordem).max(copia.ordem);
        seguinte.push(copia);
    }
    novos.sort_by(|a, b| a.codigo_eap.cmp(&b.codigo_eap));
    for mut novo in novos {
        let ordem = ultima_ordem.entry(novo.pai).or_default();
        *ordem += 1;
        novo.ordem = *ordem;
        seguinte.push(novo);
    }
    let numero = base.numero().checked_add(1).ok_or(ErroDominio::Estouro)?;
    let planilha = Planilha::nova(numero, base.criterio(), base.casas_do_preco(), seguinte)?;

    Ok(AditivoAplicado {
        itens: calculados,
        planilha,
    })
}

fn rotulo_do_item(base: &Planilha, linha: &ItemDoAditivo) -> String {
    match (base.item(linha.item), &linha.novo) {
        (Some(item), _) => item.codigo_eap.clone(),
        (None, Some(novo)) => novo.codigo_eap.clone(),
        (None, None) => format!("{:x}", linha.item.0),
    }
}

/// Percentuais que limitam os aditivos de um contrato.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RegraDeLimites {
    /// Teto dos acréscimos, em % do valor inicial.
    pub limite_de_acrescimos: Decimal,
    /// Teto das supressões, em % do valor inicial.
    pub limite_de_supressoes: Decimal,
    /// A partir de quantos % do teto a situação vira "atenção". Não é da lei: é aviso de
    /// tela, e vem da configuração.
    pub atencao_a_partir_de: Decimal,
}

impl RegraDeLimites {
    /// `TODO(jurídico)` 1: 25% para acréscimos e para supressões; 50% para acréscimos quando
    /// o contrato é de reforma de edifício ou de equipamento (art. 125).
    pub fn do_art_125(reforma: bool, atencao_a_partir_de: Decimal) -> RegraDeLimites {
        RegraDeLimites {
            limite_de_acrescimos: Decimal::from(if reforma { 50 } else { 25 }),
            limite_de_supressoes: Decimal::from(25),
            atencao_a_partir_de,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SituacaoDosLimites {
    Dentro,
    /// Passou do percentual de atenção, mas ainda cabe no teto.
    Atencao,
    /// Passou do teto de acréscimos ou do de supressões.
    Excede,
}

/// Posição dos aditivos de um contrato frente aos limites.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Limites {
    pub valor_inicial: Dinheiro,
    /// Acréscimos e inclusões.
    pub acrescimos: Dinheiro,
    /// Supressões, em valor positivo.
    pub supressoes: Dinheiro,
    /// Fica fora da conta de acréscimos. `TODO(jurídico)` 4.
    pub restabelecimentos: Dinheiro,
    /// Com duas casas, para mostrar. A situação é decidida com a conta exata, não com este.
    pub percentual_de_acrescimos: Decimal,
    pub percentual_de_supressoes: Decimal,
    pub regra: RegraDeLimites,
    pub situacao: SituacaoDosLimites,
}

/// Soma os itens de aditivo que contam (os homologados e, numa simulação, os do aditivo em
/// rascunho) e compara com os limites.
///
/// `TODO(jurídico)` 2 e 3: a base é o valor inicial sem reajuste, e acréscimos e supressões
/// são somados em separado, sem compensação.
pub fn limites_dos_aditivos(
    valor_inicial: Dinheiro,
    itens: impl IntoIterator<Item = (Operacao, Dinheiro)>,
    regra: RegraDeLimites,
) -> Result<Limites, ErroDominio> {
    let inicial = valor_inicial.decimal().mantissa();
    if inicial <= 0 {
        return Err(ErroDominio::ValorDoContratoInvalido);
    }
    let (mut acrescimos, mut supressoes, mut restabelecimentos) =
        (Dinheiro::ZERO, Dinheiro::ZERO, Dinheiro::ZERO);
    for (operacao, valor) in itens {
        match operacao {
            Operacao::Acrescimo | Operacao::Inclusao => acrescimos = acrescimos.somar(valor)?,
            Operacao::Supressao => supressoes = supressoes.somar(Dinheiro::ZERO - valor)?,
            Operacao::Restabelecimento => restabelecimentos = restabelecimentos.somar(valor)?,
        }
    }

    let atencao_de_acrescimos =
        regra.limite_de_acrescimos * regra.atencao_a_partir_de / Decimal::ONE_HUNDRED;
    let atencao_de_supressoes =
        regra.limite_de_supressoes * regra.atencao_a_partir_de / Decimal::ONE_HUNDRED;
    let situacao = if passa_de(acrescimos, inicial, regra.limite_de_acrescimos)?
        || passa_de(supressoes, inicial, regra.limite_de_supressoes)?
    {
        SituacaoDosLimites::Excede
    } else if passa_de(acrescimos, inicial, atencao_de_acrescimos)?
        || passa_de(supressoes, inicial, atencao_de_supressoes)?
    {
        SituacaoDosLimites::Atencao
    } else {
        SituacaoDosLimites::Dentro
    };

    Ok(Limites {
        valor_inicial,
        acrescimos,
        supressoes,
        restabelecimentos,
        percentual_de_acrescimos: percentual_de(acrescimos, inicial)?,
        percentual_de_supressoes: percentual_de(supressoes, inicial)?,
        regra,
        situacao,
    })
}

/// `100 × valor ÷ inicial`, com duas casas.
fn percentual_de(valor: Dinheiro, inicial: i128) -> Result<Decimal, ErroDominio> {
    let centesimos = dividir_arredondando(vezes(valor.decimal().mantissa(), 10_000)?, inicial)?;
    Decimal::try_from_i128_with_scale(centesimos, 2).map_err(|_| ErroDominio::Estouro)
}

/// `100 × valor ÷ inicial > teto`, sem dividir: `100 × valor > teto × inicial`.
fn passa_de(valor: Dinheiro, inicial: i128, teto: Decimal) -> Result<bool, ErroDominio> {
    let esquerda = vezes(
        vezes(valor.decimal().mantissa(), 100)?,
        potencia_de_dez(teto.scale())?,
    )?;
    let direita = vezes(teto.mantissa(), inicial)?;
    Ok(esquerda > direita)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::planilha::tests::{d, grupo, planilha_de_referencia, servico};
    use crate::CriterioArredondamento;

    // Cenário de `db/reference/seed_e_testes.sql`: contrato de R$ 58.551,28, orçamento-base
    // de R$ 64.300,00. Os números esperados são os de `docs/plano-fase-0.md` §4.

    fn fator() -> Decimal {
        fator_art127(
            Dinheiro::de_centavos(5_855_128),
            Dinheiro::de_centavos(6_430_000),
        )
        .unwrap()
    }

    fn linha(item: u128, operacao: Operacao, quantidade: &str) -> ItemDoAditivo {
        ItemDoAditivo {
            item: ItemId(item),
            operacao,
            quantidade: d(quantidade),
            novo: None,
        }
    }

    fn dreno() -> ItemDoAditivo {
        ItemDoAditivo {
            item: ItemId(0x23),
            operacao: Operacao::Inclusao,
            quantidade: d("40.00"),
            novo: Some(ServicoNovo {
                grupo: ItemId(0x2),
                codigo_eap: "2.3".into(),
                descricao: "Dreno com brita nº 2 e manta geotêxtil".into(),
                unidade: "m".into(),
                preco_de_referencia: d("52.00"),
            }),
        }
    }

    /// Aditivo 1 do cenário: +4,00 m³ de concreto, −200,00 m² de chapisco, dreno novo.
    fn aditivo_1() -> Vec<ItemDoAditivo> {
        vec![
            linha(0x212, Operacao::Acrescimo, "4.00"),
            linha(0x32, Operacao::Supressao, "-200.00"),
            dreno(),
        ]
    }

    /// Quantidades medidas até a medição 2 do cenário.
    fn medido_ate_a_medicao_2() -> Historico {
        Historico {
            medido: [
                (ItemId(0x11), d("6.00")),
                (ItemId(0x12), d("180.00")),
                (ItemId(0x211), d("42.50")),
                (ItemId(0x212), d("10.00")),
                (ItemId(0x22), d("64.00")),
            ]
            .into(),
            suprimido: BTreeMap::new(),
        }
    }

    fn regra() -> RegraDeLimites {
        RegraDeLimites::do_art_125(false, d("90"))
    }

    #[test]
    fn fator_do_cenario_de_referencia() {
        // 58.551,28 ÷ 64.300,00 = 0,910595334...
        assert_eq!(fator(), d("0.91059533"));
    }

    #[test]
    fn fator_arredonda_na_oitava_casa() {
        // 2 ÷ 3 = 0,666666666...
        let f = fator_art127(Dinheiro::de_centavos(200), Dinheiro::de_centavos(300)).unwrap();
        assert_eq!(f, d("0.66666667"));
        // 1 ÷ 3 = 0,333333333...
        let f = fator_art127(Dinheiro::de_centavos(100), Dinheiro::de_centavos(300)).unwrap();
        assert_eq!(f, d("0.33333333"));
        // proposta acima do orçamento-base: fator maior que 1
        let f = fator_art127(Dinheiro::de_centavos(110), Dinheiro::de_centavos(100)).unwrap();
        assert_eq!(f, d("1.10000000"));
    }

    #[test]
    fn fator_exige_valores_positivos() {
        for (proposta, base) in [(0, 100), (100, 0), (-100, 100), (100, -100)] {
            assert_eq!(
                fator_art127(Dinheiro::de_centavos(proposta), Dinheiro::de_centavos(base)),
                Err(ErroDominio::ValorDoContratoInvalido)
            );
        }
    }

    #[test]
    fn preco_do_dreno_e_47_35() {
        // 52,00 × 0,91059533 = 47,3509571...
        assert_eq!(
            preco_de_item_novo(d("52.00"), fator(), 2).unwrap(),
            d("47.35")
        );
        // o mesmo preço num contrato de 4 casas
        assert_eq!(
            preco_de_item_novo(d("52.00"), fator(), 4).unwrap(),
            d("47.3510")
        );
    }

    #[test]
    fn preco_de_item_novo_arredonda_meio_para_cima() {
        // 0,25 × 0,5 = 0,125
        assert_eq!(
            preco_de_item_novo(d("0.25"), d("0.5"), 2).unwrap(),
            d("0.13")
        );
        // 0,24 × 0,5 = 0,12
        assert_eq!(
            preco_de_item_novo(d("0.24"), d("0.5"), 2).unwrap(),
            d("0.12")
        );
        // sem casas a cortar
        assert_eq!(preco_de_item_novo(d("7"), d("2"), 2).unwrap(), d("14.00"));
    }

    #[test]
    fn itens_do_aditivo_1() {
        let aplicado = aplicar_aditivo(
            &planilha_de_referencia(),
            fator(),
            &aditivo_1(),
            &medido_ate_a_medicao_2(),
        )
        .unwrap();
        let valores: Vec<(Operacao, Decimal, Dinheiro)> = aplicado
            .itens
            .iter()
            .map(|i| (i.operacao, i.preco_unitario, i.valor))
            .collect();
        assert_eq!(
            valores,
            vec![
                // 4,00 × 785,40
                (
                    Operacao::Acrescimo,
                    d("785.40"),
                    Dinheiro::de_centavos(314_160)
                ),
                // −200,00 × 7,43
                (
                    Operacao::Supressao,
                    d("7.43"),
                    Dinheiro::de_centavos(-148_600)
                ),
                // 40,00 × 47,35
                (
                    Operacao::Inclusao,
                    d("47.35"),
                    Dinheiro::de_centavos(189_400)
                ),
            ]
        );
    }

    #[test]
    fn revisao_1_soma_62_100_88() {
        let aplicado = aplicar_aditivo(
            &planilha_de_referencia(),
            fator(),
            &aditivo_1(),
            &medido_ate_a_medicao_2(),
        )
        .unwrap();
        let p = &aplicado.planilha;
        assert_eq!(p.numero(), 1);
        // 58.551,28 + 3.141,60 − 1.486,00 + 1.894,00
        assert_eq!(p.valor_total().unwrap(), Dinheiro::de_centavos(6_210_088));
        // concreto: 18,20 + 4,00 = 22,20 m³
        assert_eq!(
            p.valor_do_servico(ItemId(0x212)).unwrap(),
            Some(Dinheiro::de_centavos(1_743_588))
        );
        // chapisco: 640,00 − 200,00 = 440,00 m²
        assert_eq!(
            p.valor_do_servico(ItemId(0x32)).unwrap(),
            Some(Dinheiro::de_centavos(326_920))
        );
        // o dreno entra no fim do grupo 2, depois do 2.2
        let ordem: Vec<&str> = p.itens().map(|(i, _)| i.codigo_eap.as_str()).collect();
        assert_eq!(
            ordem,
            vec!["1", "1.1", "1.2", "2", "2.1", "2.1.1", "2.1.2", "2.2", "2.3", "3", "3.1", "3.2"]
        );
        assert_eq!(p.item(ItemId(0x23)).unwrap().ordem, 3);
        // a planilha base não muda
        assert_eq!(
            planilha_de_referencia().valor_total().unwrap(),
            Dinheiro::de_centavos(5_855_128)
        );
    }

    fn valores(aplicado: &AditivoAplicado) -> Vec<(Operacao, Dinheiro)> {
        aplicado
            .itens
            .iter()
            .map(|i| (i.operacao, i.valor))
            .collect()
    }

    #[test]
    fn limites_com_o_aditivo_1() {
        let aplicado = aplicar_aditivo(
            &planilha_de_referencia(),
            fator(),
            &aditivo_1(),
            &medido_ate_a_medicao_2(),
        )
        .unwrap();
        let l = limites_dos_aditivos(
            Dinheiro::de_centavos(5_855_128),
            valores(&aplicado),
            regra(),
        )
        .unwrap();
        // acréscimo de 3.141,60 mais inclusão de 1.894,00
        assert_eq!(l.acrescimos, Dinheiro::de_centavos(503_560));
        assert_eq!(l.supressoes, Dinheiro::de_centavos(148_600));
        assert_eq!(l.restabelecimentos, Dinheiro::ZERO);
        // 5.035,60 ÷ 58.551,28 = 8,6003...% · 1.486,00 ÷ 58.551,28 = 2,5379...%
        assert_eq!(l.percentual_de_acrescimos, d("8.60"));
        assert_eq!(l.percentual_de_supressoes, d("2.54"));
        assert_eq!(l.regra.limite_de_acrescimos, d("25"));
        assert_eq!(l.situacao, SituacaoDosLimites::Dentro);
    }

    #[test]
    fn aditivo_2_simulado_excede_o_limite() {
        // Sobre a Rev. 1: +120,00 m² de alvenaria a 89,15 = 10.698,00
        let rev1 = aplicar_aditivo(
            &planilha_de_referencia(),
            fator(),
            &aditivo_1(),
            &medido_ate_a_medicao_2(),
        )
        .unwrap();
        let aditivo_2 = aplicar_aditivo(
            &rev1.planilha,
            fator(),
            &[linha(0x31, Operacao::Acrescimo, "120.00")],
            &medido_ate_a_medicao_2(),
        )
        .unwrap();
        assert_eq!(aditivo_2.planilha.numero(), 2);
        let todos = valores(&rev1).into_iter().chain(valores(&aditivo_2));
        let l = limites_dos_aditivos(Dinheiro::de_centavos(5_855_128), todos, regra()).unwrap();
        // 5.035,60 + 10.698,00 = 15.733,60 → 26,8715...%
        assert_eq!(l.acrescimos, Dinheiro::de_centavos(1_573_360));
        assert_eq!(l.percentual_de_acrescimos, d("26.87"));
        assert_eq!(l.situacao, SituacaoDosLimites::Excede);
    }

    fn limites_com(acrescimos: i64, supressoes: i64, regra: RegraDeLimites) -> SituacaoDosLimites {
        limites_dos_aditivos(
            Dinheiro::de_centavos(100_0000),
            [
                (Operacao::Acrescimo, Dinheiro::de_centavos(acrescimos)),
                (Operacao::Supressao, Dinheiro::de_centavos(-supressoes)),
            ],
            regra,
        )
        .unwrap()
        .situacao
    }

    #[test]
    fn exatamente_no_teto_ainda_cabe() {
        // contrato de 10.000,00: 25% = 2.500,00; atenção a partir de 90% do teto = 2.250,00
        // (os valores abaixo estão em centavos: 225_000 = 2.250,00)
        assert_eq!(limites_com(225_000, 0, regra()), SituacaoDosLimites::Dentro);
        assert_eq!(
            limites_com(225_001, 0, regra()),
            SituacaoDosLimites::Atencao
        );
        assert_eq!(
            limites_com(250_000, 0, regra()),
            SituacaoDosLimites::Atencao
        );
        assert_eq!(limites_com(250_001, 0, regra()), SituacaoDosLimites::Excede);
        // o mesmo do lado das supressões
        assert_eq!(limites_com(0, 225_000, regra()), SituacaoDosLimites::Dentro);
        assert_eq!(
            limites_com(0, 225_001, regra()),
            SituacaoDosLimites::Atencao
        );
        assert_eq!(
            limites_com(0, 250_000, regra()),
            SituacaoDosLimites::Atencao
        );
        assert_eq!(limites_com(0, 250_001, regra()), SituacaoDosLimites::Excede);
    }

    #[test]
    fn acrescimo_e_supressao_nao_se_compensam() {
        // 20% de acréscimo e 20% de supressão: o valor do contrato não muda, e os dois cabem
        assert_eq!(
            limites_com(200_000, 200_000, regra()),
            SituacaoDosLimites::Dentro
        );
        // 30% de acréscimo não é "compensado" por 30% de supressão
        assert_eq!(
            limites_com(300_000, 300_000, regra()),
            SituacaoDosLimites::Excede
        );
    }

    #[test]
    fn reforma_dobra_so_o_teto_de_acrescimos() {
        let reforma = RegraDeLimites::do_art_125(true, d("90"));
        assert_eq!(reforma.limite_de_acrescimos, d("50"));
        assert_eq!(reforma.limite_de_supressoes, d("25"));
        assert_eq!(limites_com(450_000, 0, reforma), SituacaoDosLimites::Dentro);
        assert_eq!(
            limites_com(500_000, 0, reforma),
            SituacaoDosLimites::Atencao
        );
        assert_eq!(limites_com(500_001, 0, reforma), SituacaoDosLimites::Excede);
        assert_eq!(limites_com(0, 250_001, reforma), SituacaoDosLimites::Excede);
    }

    #[test]
    fn restabelecimento_fica_fora_da_conta_de_acrescimos() {
        let l = limites_dos_aditivos(
            Dinheiro::de_centavos(100_0000),
            [
                (Operacao::Acrescimo, Dinheiro::de_centavos(200_000)),
                (Operacao::Restabelecimento, Dinheiro::de_centavos(100_000)),
            ],
            regra(),
        )
        .unwrap();
        assert_eq!(l.acrescimos, Dinheiro::de_centavos(200_000));
        assert_eq!(l.restabelecimentos, Dinheiro::de_centavos(100_000));
        assert_eq!(l.situacao, SituacaoDosLimites::Dentro);
    }

    fn erro(itens: &[ItemDoAditivo], historico: &Historico) -> ErroDominio {
        aplicar_aditivo(&planilha_de_referencia(), fator(), itens, historico).unwrap_err()
    }

    #[test]
    fn supressao_nao_vai_abaixo_do_medido() {
        // "Suprimir abaixo do já medido (escavação toda medida)", do seed de referência
        let e = erro(
            &[linha(0x211, Operacao::Supressao, "-1")],
            &medido_ate_a_medicao_2(),
        );
        assert_eq!(
            e,
            ErroDominio::SupressaoAbaixoDoMedido {
                item: "2.1.1".into(),
                medido: d("42.50"),
            }
        );
        // concreto: 18,20 contratados, 10,00 medidos; dá para suprimir até 8,20
        let ok = aplicar_aditivo(
            &planilha_de_referencia(),
            fator(),
            &[linha(0x212, Operacao::Supressao, "-8.20")],
            &medido_ate_a_medicao_2(),
        );
        assert!(ok.is_ok());
        let e = erro(
            &[linha(0x212, Operacao::Supressao, "-8.21")],
            &medido_ate_a_medicao_2(),
        );
        assert!(matches!(e, ErroDominio::SupressaoAbaixoDoMedido { .. }));
    }

    #[test]
    fn restabelecimento_so_devolve_o_que_foi_suprimido() {
        let sem_supressao = erro(
            &[linha(0x32, Operacao::Restabelecimento, "50")],
            &Historico::default(),
        );
        assert_eq!(
            sem_supressao,
            ErroDominio::RestabelecimentoSemSupressao {
                item: "3.2".into(),
                suprimido: Decimal::ZERO,
            }
        );
        let com_200_suprimidos = Historico {
            suprimido: [(ItemId(0x32), d("200"))].into(),
            ..Historico::default()
        };
        let ok = aplicar_aditivo(
            &planilha_de_referencia(),
            fator(),
            &[linha(0x32, Operacao::Restabelecimento, "200")],
            &com_200_suprimidos,
        )
        .unwrap();
        assert_eq!(ok.itens[0].valor, Dinheiro::de_centavos(148_600));
        let a_mais = erro(
            &[linha(0x32, Operacao::Restabelecimento, "200.0001")],
            &com_200_suprimidos,
        );
        assert!(matches!(
            a_mais,
            ErroDominio::RestabelecimentoSemSupressao { .. }
        ));
    }

    #[test]
    fn sinal_da_quantidade_segue_a_operacao() {
        let h = Historico::default();
        for (operacao, quantidade) in [
            (Operacao::Acrescimo, "-1"),
            (Operacao::Acrescimo, "0"),
            (Operacao::Supressao, "1"),
            (Operacao::Supressao, "0"),
            (Operacao::Restabelecimento, "-1"),
        ] {
            assert_eq!(
                erro(&[linha(0x31, operacao, quantidade)], &h),
                ErroDominio::QuantidadeDoAditivoInvalida("3.1".into()),
                "{operacao:?} {quantidade}"
            );
        }
        let mut negativo = dreno();
        negativo.quantidade = d("-40");
        assert_eq!(
            erro(&[negativo], &h),
            ErroDominio::QuantidadeDoAditivoInvalida("2.3".into())
        );
    }

    #[test]
    fn um_item_aparece_uma_vez_so_no_aditivo() {
        let e = erro(
            &[
                linha(0x31, Operacao::Acrescimo, "1"),
                linha(0x31, Operacao::Supressao, "-1"),
            ],
            &Historico::default(),
        );
        assert_eq!(e, ErroDominio::ItemRepetido("3.1".into()));
    }

    #[test]
    fn acrescimo_so_em_servico_da_planilha() {
        let h = Historico::default();
        // grupo não tem quantidade
        assert_eq!(
            erro(&[linha(0x2, Operacao::Acrescimo, "1")], &h),
            ErroDominio::ItemForaDaPlanilha("2".into())
        );
        // item que não existe
        assert!(matches!(
            erro(&[linha(0x999, Operacao::Acrescimo, "1")], &h),
            ErroDominio::ItemForaDaPlanilha(_)
        ));
    }

    #[test]
    fn inclusao_cria_item_novo_abaixo_de_grupo() {
        let h = Historico::default();
        // sem os dados do serviço novo
        assert_eq!(
            erro(&[linha(0x23, Operacao::Inclusao, "40")], &h),
            ErroDominio::InclusaoIncompleta("23".into())
        );
        // item que já existe
        let mut existente = dreno();
        existente.item = ItemId(0x22);
        assert_eq!(
            erro(&[existente], &h),
            ErroDominio::InclusaoDeItemExistente("2.2".into())
        );
        // abaixo de um serviço, e não de um grupo
        let mut sob_servico = dreno();
        sob_servico.novo.as_mut().unwrap().grupo = ItemId(0x22);
        assert_eq!(
            erro(&[sob_servico], &h),
            ErroDominio::PaiInvalido("2.3".into())
        );
        // código que já existe na planilha
        let mut codigo_repetido = dreno();
        codigo_repetido.novo.as_mut().unwrap().codigo_eap = "2.2".into();
        assert_eq!(
            erro(&[codigo_repetido], &h),
            ErroDominio::ItemRepetido("2.2".into())
        );
        // sem unidade
        let mut sem_unidade = dreno();
        sem_unidade.novo.as_mut().unwrap().unidade = String::new();
        assert_eq!(
            erro(&[sem_unidade], &h),
            ErroDominio::InclusaoIncompleta("2.3".into())
        );
    }

    #[test]
    fn duas_inclusoes_no_mesmo_grupo_entram_na_ordem_do_codigo() {
        let mut segundo = dreno();
        segundo.item = ItemId(0x24);
        segundo.novo.as_mut().unwrap().codigo_eap = "2.4".into();
        // informados fora de ordem
        let aplicado = aplicar_aditivo(
            &planilha_de_referencia(),
            fator(),
            &[segundo, dreno()],
            &Historico::default(),
        )
        .unwrap();
        let p = &aplicado.planilha;
        assert_eq!(p.item(ItemId(0x23)).unwrap().ordem, 3);
        assert_eq!(p.item(ItemId(0x24)).unwrap().ordem, 4);
    }

    #[test]
    fn valor_da_revisao_pode_diferir_da_soma_dos_valores_do_aditivo() {
        // Contrato que trunca. Serviço de 1,50 a 0,33 = 0,495 → 0,49.
        // Acréscimo de 1,50 a 0,33 = 0,495 → 0,49. Somados: 0,98.
        // Na revisão seguinte o serviço tem 3,00 a 0,33 = 0,99: um centavo a mais.
        let base = Planilha::nova(
            0,
            CriterioArredondamento::Truncar,
            2,
            vec![
                grupo(1, None, 1, "1"),
                servico(2, 1, 1, "1.1", "m²", "1.50", "0.33"),
            ],
        )
        .unwrap();
        let aplicado = aplicar_aditivo(
            &base,
            d("1"),
            &[linha(2, Operacao::Acrescimo, "1.50")],
            &Historico::default(),
        )
        .unwrap();
        assert_eq!(base.valor_total().unwrap(), Dinheiro::de_centavos(49));
        assert_eq!(aplicado.itens[0].valor, Dinheiro::de_centavos(49));
        assert_eq!(
            aplicado.planilha.valor_total().unwrap(),
            Dinheiro::de_centavos(99)
        );
    }
}
