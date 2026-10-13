//! Boletim de medição por quantidade: contratado, anterior, atual, acumulado e saldo de cada
//! serviço, com subtotal por grupo.
//!
//! É a segunda forma de medir; a prioritária é por eventos (`medicao.rs`). As contas são as
//! de `fn_medicao_item_guard` e `fn_boletim_medicao` do banco, e `crates/paridade` confere
//! os dois lados.

use crate::conta::{dividir_arredondando, vezes};
use crate::dinheiro::{valor_item, Dinheiro};
use crate::planilha::{ItemId, Planilha, TipoItem};
use crate::ErroDominio;
use rust_decimal::Decimal;
use std::collections::BTreeMap;

/// Quanto de um serviço foi medido, em quantidade e em valor.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Medido {
    pub quantidade: Decimal,
    pub valor: Dinheiro,
}

/// Calcula uma linha de medição por quantidade: quantidade × preço da planilha da medição,
/// pelo critério do contrato.
///
/// `ja_medido` é a quantidade do item em outras medições não canceladas. O acumulado não
/// passa do contratado nem fica negativo; quantidade negativa é estorno.
pub fn medir_por_quantidade(
    planilha: &Planilha,
    item: ItemId,
    quantidade: Decimal,
    ja_medido: Decimal,
) -> Result<Medido, ErroDominio> {
    let Some(servico) = planilha.item(item) else {
        return Err(ErroDominio::ItemForaDaPlanilha(format!("{:x}", item.0)));
    };
    let TipoItem::Servico {
        quantidade: contratada,
        preco_unitario,
        ..
    } = &servico.tipo
    else {
        return Err(ErroDominio::ItemForaDaPlanilha(servico.codigo_eap.clone()));
    };
    let acumulado = ja_medido + quantidade;
    if acumulado > *contratada {
        return Err(ErroDominio::MedicaoAcimaDoContratado {
            item: servico.codigo_eap.clone(),
            acumulado,
            contratado: *contratada,
        });
    }
    if acumulado.is_sign_negative() && !acumulado.is_zero() {
        return Err(ErroDominio::MedicaoAcumuladaNegativa {
            item: servico.codigo_eap.clone(),
            acumulado,
        });
    }
    Ok(Medido {
        quantidade,
        valor: valor_item(quantidade, *preco_unitario, planilha.criterio())?,
    })
}

/// Colunas de quantidade de uma linha de serviço.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct QuantidadesDoBoletim {
    pub unidade: String,
    pub preco_unitario: Decimal,
    pub contratada: Decimal,
    pub anterior: Decimal,
    pub atual: Decimal,
    pub acumulada: Decimal,
    pub saldo: Decimal,
}

/// Uma linha do boletim: um serviço, ou um grupo com a soma do que está abaixo dele.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LinhaDoBoletim {
    pub item: ItemId,
    pub codigo_eap: String,
    pub descricao: String,
    /// 1 = primeiro nível da planilha.
    pub nivel: u32,
    /// Só nas linhas de serviço.
    pub quantidades: Option<QuantidadesDoBoletim>,
    pub valor_contratado: Dinheiro,
    pub valor_anterior: Dinheiro,
    pub valor_atual: Dinheiro,
    pub valor_acumulado: Dinheiro,
    pub valor_saldo: Dinheiro,
    /// Acumulado ÷ contratado, em %, com duas casas. `None` quando o contratado é zero.
    pub percentual_acumulado: Option<Decimal>,
}

/// Monta o boletim de uma medição sobre a planilha em que ela foi aberta.
///
/// `anterior` soma, por item, as medições anteriores não canceladas; `atual` é a medição do
/// boletim. Os valores entram como foram calculados em cada medição: o boletim soma, não
/// recalcula. As linhas saem na ordem da planilha.
pub fn boletim_de_medicao(
    planilha: &Planilha,
    anterior: &BTreeMap<ItemId, Medido>,
    atual: &BTreeMap<ItemId, Medido>,
) -> Result<Vec<LinhaDoBoletim>, ErroDominio> {
    for id in anterior.keys().chain(atual.keys()) {
        if !planilha.item(*id).is_some_and(|item| item.eh_servico()) {
            let rotulo = planilha
                .item(*id)
                .map_or_else(|| format!("{:x}", id.0), |item| item.codigo_eap.clone());
            return Err(ErroDominio::ItemForaDaPlanilha(rotulo));
        }
    }

    let mut linhas = Vec::new();
    for (item, nivel) in planilha.itens() {
        // Soma o item e tudo o que está abaixo dele. Num serviço, o ramo é ele mesmo.
        let (mut contratado, mut anterior_v, mut atual_v) =
            (Dinheiro::ZERO, Dinheiro::ZERO, Dinheiro::ZERO);
        for posicao in planilha.ramo(item.id) {
            let folha = planilha.na_posicao(posicao);
            let Some(valor) = planilha.valor_do_servico(folha.id)? else {
                continue;
            };
            contratado = contratado.somar(valor)?;
            anterior_v =
                anterior_v.somar(anterior.get(&folha.id).copied().unwrap_or_default().valor)?;
            atual_v = atual_v.somar(atual.get(&folha.id).copied().unwrap_or_default().valor)?;
        }
        let acumulado = anterior_v.somar(atual_v)?;

        let quantidades = match &item.tipo {
            TipoItem::Grupo => None,
            TipoItem::Servico {
                unidade,
                quantidade,
                preco_unitario,
            } => {
                let antes = anterior
                    .get(&item.id)
                    .copied()
                    .unwrap_or_default()
                    .quantidade;
                let agora = atual.get(&item.id).copied().unwrap_or_default().quantidade;
                Some(QuantidadesDoBoletim {
                    unidade: unidade.clone(),
                    preco_unitario: *preco_unitario,
                    contratada: *quantidade,
                    anterior: antes,
                    atual: agora,
                    acumulada: antes + agora,
                    saldo: quantidade - (antes + agora),
                })
            }
        };

        linhas.push(LinhaDoBoletim {
            item: item.id,
            codigo_eap: item.codigo_eap.clone(),
            descricao: item.descricao.clone(),
            nivel,
            quantidades,
            valor_contratado: contratado,
            valor_anterior: anterior_v,
            valor_atual: atual_v,
            valor_acumulado: acumulado,
            valor_saldo: contratado - acumulado,
            percentual_acumulado: percentual(acumulado, contratado)?,
        });
    }
    Ok(linhas)
}

/// `100 × parte ÷ todo`, com duas casas; `None` quando o todo é zero.
pub fn percentual(parte: Dinheiro, todo: Dinheiro) -> Result<Option<Decimal>, ErroDominio> {
    let todo = todo.decimal().mantissa();
    if todo == 0 {
        return Ok(None);
    }
    let centesimos = dividir_arredondando(vezes(parte.decimal().mantissa(), 10_000)?, todo)?;
    Decimal::try_from_i128_with_scale(centesimos, 2)
        .map(Some)
        .map_err(|_| ErroDominio::Estouro)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::aditivo::{
        aplicar_aditivo, fator_art127, Historico, ItemDoAditivo, Operacao, ServicoNovo,
    };
    use crate::planilha::tests::{d, planilha_de_referencia};

    // Cenário de `db/reference/seed_e_testes.sql`. Os números esperados são os de
    // `docs/plano-fase-0.md` §4, conferidos também contra o SQL de referência.

    fn medir(planilha: &Planilha, lancamentos: &[(u128, &str)]) -> BTreeMap<ItemId, Medido> {
        lancamentos
            .iter()
            .map(|(id, quantidade)| {
                let m = medir_por_quantidade(planilha, ItemId(*id), d(quantidade), Decimal::ZERO)
                    .unwrap();
                (ItemId(*id), m)
            })
            .collect()
    }

    fn total(medicao: &BTreeMap<ItemId, Medido>) -> Dinheiro {
        medicao
            .values()
            .fold(Dinheiro::ZERO, |soma, m| soma + m.valor)
    }

    fn somar(
        a: &BTreeMap<ItemId, Medido>,
        b: &BTreeMap<ItemId, Medido>,
    ) -> BTreeMap<ItemId, Medido> {
        let mut soma = a.clone();
        for (id, m) in b {
            let linha = soma.entry(*id).or_default();
            linha.quantidade += m.quantidade;
            linha.valor = linha.valor + m.valor;
        }
        soma
    }

    /// Rev. 1 do cenário: Rev. 0 mais o aditivo 1.
    fn revisao_1() -> Planilha {
        let fator = fator_art127(
            Dinheiro::de_centavos(5_855_128),
            Dinheiro::de_centavos(6_430_000),
        )
        .unwrap();
        let linha = |item: u128, operacao, quantidade: &str| ItemDoAditivo {
            item: ItemId(item),
            operacao,
            quantidade: d(quantidade),
            novo: None,
        };
        let dreno = ItemDoAditivo {
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
        };
        aplicar_aditivo(
            &planilha_de_referencia(),
            fator,
            &[
                linha(0x212, Operacao::Acrescimo, "4.00"),
                linha(0x32, Operacao::Supressao, "-200.00"),
                dreno,
            ],
            &Historico::default(),
        )
        .unwrap()
        .planilha
    }

    fn medicao_1() -> BTreeMap<ItemId, Medido> {
        medir(
            &planilha_de_referencia(),
            &[(0x11, "6.00"), (0x12, "180.00"), (0x211, "30.00")],
        )
    }

    fn medicao_2() -> BTreeMap<ItemId, Medido> {
        medir(
            &planilha_de_referencia(),
            &[(0x211, "12.50"), (0x212, "10.00"), (0x22, "64.00")],
        )
    }

    fn medicao_3() -> BTreeMap<ItemId, Medido> {
        medir(
            &revisao_1(),
            &[
                (0x212, "12.20"),
                (0x23, "40.00"),
                (0x31, "100.00"),
                (0x32, "300.00"),
            ],
        )
    }

    #[test]
    fn medicoes_1_e_2_do_cenario() {
        // 6,00 × 450,00 + 180,00 × 12,35 + 30,00 × 68,93
        assert_eq!(total(&medicao_1()), Dinheiro::de_centavos(699_090));
        // 12,50 × 68,93 = 861,625 → 861,62 (trunca) + 10,00 × 785,40 + 64,00 × 48,77
        assert_eq!(total(&medicao_2()), Dinheiro::de_centavos(1_183_690));
    }

    #[test]
    fn boletim_numero_3_do_cenario() {
        let m3 = medicao_3();
        // concreto 12,20 × 785,40 · dreno 40,00 × 47,35 · alvenaria 100,00 × 89,15 · chapisco 300,00 × 7,43
        assert_eq!(m3[&ItemId(0x212)].valor, Dinheiro::de_centavos(958_188));
        assert_eq!(m3[&ItemId(0x23)].valor, Dinheiro::de_centavos(189_400));
        assert_eq!(m3[&ItemId(0x31)].valor, Dinheiro::de_centavos(891_500));
        assert_eq!(m3[&ItemId(0x32)].valor, Dinheiro::de_centavos(222_900));
        assert_eq!(total(&m3), Dinheiro::de_centavos(2_261_988));

        let anterior = somar(&medicao_1(), &medicao_2());
        let boletim = boletim_de_medicao(&revisao_1(), &anterior, &m3).unwrap();
        let linha = |codigo: &str| boletim.iter().find(|l| l.codigo_eap == codigo).unwrap();

        // ordem e níveis da planilha, com o dreno no fim do grupo 2
        let ordem: Vec<(&str, u32)> = boletim
            .iter()
            .map(|l| (l.codigo_eap.as_str(), l.nivel))
            .collect();
        assert_eq!(
            ordem,
            vec![
                ("1", 1),
                ("1.1", 2),
                ("1.2", 2),
                ("2", 1),
                ("2.1", 2),
                ("2.1.1", 3),
                ("2.1.2", 3),
                ("2.2", 2),
                ("2.3", 2),
                ("3", 1),
                ("3.1", 2),
                ("3.2", 2),
            ]
        );

        // concreto: 22,20 contratados, 10,00 antes, 12,20 agora, saldo zero
        let concreto = linha("2.1.2");
        let q = concreto.quantidades.as_ref().unwrap();
        assert_eq!(
            (q.contratada, q.anterior, q.atual, q.acumulada, q.saldo),
            (d("22.20"), d("10.00"), d("12.20"), d("22.20"), d("0.00"))
        );
        assert_eq!(concreto.valor_contratado, Dinheiro::de_centavos(1_743_588));
        assert_eq!(concreto.valor_anterior, Dinheiro::de_centavos(785_400));
        assert_eq!(concreto.valor_atual, Dinheiro::de_centavos(958_188));
        assert_eq!(concreto.valor_saldo, Dinheiro::ZERO);
        assert_eq!(concreto.percentual_acumulado, Some(d("100.00")));

        // chapisco: 440,00 depois da supressão, 300,00 agora
        let chapisco = linha("3.2");
        let q = chapisco.quantidades.as_ref().unwrap();
        assert_eq!(
            (q.contratada, q.atual, q.saldo),
            (d("440.00"), d("300.00"), d("140.00"))
        );
        // 2.229,00 de 3.269,20 = 68,18%
        assert_eq!(chapisco.percentual_acumulado, Some(d("68.18")));

        // grupo 2 (infraestrutura): soma de 2.1.1, 2.1.2, 2.2 e 2.3
        let grupo_2 = linha("2");
        assert!(grupo_2.quantidades.is_none());
        // 2.929,52 + 17.435,88 + 3.121,28 + 1.894,00
        assert_eq!(grupo_2.valor_contratado, Dinheiro::de_centavos(2_538_068));
        // antes: escavação 2.067,90 + 861,62, concreto 7.854,00, impermeabilização 3.121,28
        assert_eq!(grupo_2.valor_anterior, Dinheiro::de_centavos(1_390_480));
        // agora: concreto 9.581,88 + dreno 1.894,00
        assert_eq!(grupo_2.valor_atual, Dinheiro::de_centavos(1_147_588));
        assert_eq!(grupo_2.valor_saldo, Dinheiro::ZERO);

        // subgrupo 2.1 (fundações): escavação e concreto
        let fundacoes = linha("2.1");
        assert_eq!(fundacoes.valor_contratado, Dinheiro::de_centavos(2_036_540));
        assert_eq!(fundacoes.percentual_acumulado, Some(d("100.00")));

        // contrato inteiro: soma dos grupos do primeiro nível
        let primeiro_nivel = || boletim.iter().filter(|l| l.nivel == 1);
        let soma = |campo: fn(&LinhaDoBoletim) -> Dinheiro| {
            primeiro_nivel().fold(Dinheiro::ZERO, |s, l| s + campo(l))
        };
        assert_eq!(
            soma(|l| l.valor_contratado),
            Dinheiro::de_centavos(6_210_088)
        );
        assert_eq!(soma(|l| l.valor_atual), Dinheiro::de_centavos(2_261_988));
        // medido depois da medição 3: 6.990,90 + 11.836,90 + 22.619,88
        assert_eq!(
            soma(|l| l.valor_acumulado),
            Dinheiro::de_centavos(4_144_768)
        );
        assert_eq!(soma(|l| l.valor_saldo), Dinheiro::de_centavos(2_065_320));
        // 41.447,68 ÷ 62.100,88 = 66,7425...%
        assert_eq!(
            percentual(soma(|l| l.valor_acumulado), soma(|l| l.valor_contratado)).unwrap(),
            Some(d("66.74"))
        );
    }

    #[test]
    fn nao_mede_acima_do_contratado() {
        let p = planilha_de_referencia();
        // "Medir acima do contratado (escavação 42,60 > 42,50)", do seed de referência
        let e = medir_por_quantidade(&p, ItemId(0x211), d("12.60"), d("30.00")).unwrap_err();
        assert_eq!(
            e,
            ErroDominio::MedicaoAcimaDoContratado {
                item: "2.1.1".into(),
                acumulado: d("42.60"),
                contratado: d("42.50"),
            }
        );
        // exatamente o saldo cabe
        assert!(medir_por_quantidade(&p, ItemId(0x211), d("12.50"), d("30.00")).is_ok());
    }

    #[test]
    fn estorno_nao_deixa_o_acumulado_negativo() {
        let p = planilha_de_referencia();
        // estorna 10 dos 30 já medidos
        let m = medir_por_quantidade(&p, ItemId(0x211), d("-10.00"), d("30.00")).unwrap();
        // −10,00 × 68,93
        assert_eq!(m.valor, Dinheiro::de_centavos(-68_930));
        let e = medir_por_quantidade(&p, ItemId(0x211), d("-30.01"), d("30.00")).unwrap_err();
        assert!(matches!(e, ErroDominio::MedicaoAcumuladaNegativa { .. }));
        // estornar tudo zera
        assert!(medir_por_quantidade(&p, ItemId(0x211), d("-30.00"), d("30.00")).is_ok());
    }

    #[test]
    fn so_mede_servico_da_planilha() {
        let p = planilha_de_referencia();
        assert_eq!(
            medir_por_quantidade(&p, ItemId(0x2), d("1"), Decimal::ZERO),
            Err(ErroDominio::ItemForaDaPlanilha("2".into()))
        );
        assert!(matches!(
            medir_por_quantidade(&p, ItemId(0x999), d("1"), Decimal::ZERO),
            Err(ErroDominio::ItemForaDaPlanilha(_))
        ));
        // o dreno só existe na Rev. 1
        assert!(medir_por_quantidade(&p, ItemId(0x23), d("1"), Decimal::ZERO).is_err());
        let fora = [(ItemId(0x23), Medido::default())].into();
        assert!(boletim_de_medicao(&p, &BTreeMap::new(), &fora).is_err());
    }

    #[test]
    fn boletim_sem_medicao_tem_tudo_no_saldo() {
        let p = planilha_de_referencia();
        let boletim = boletim_de_medicao(&p, &BTreeMap::new(), &BTreeMap::new()).unwrap();
        assert_eq!(boletim.len(), 11);
        for linha in &boletim {
            assert_eq!(linha.valor_acumulado, Dinheiro::ZERO);
            assert_eq!(linha.valor_saldo, linha.valor_contratado);
            assert_eq!(linha.percentual_acumulado, Some(d("0.00")));
        }
    }

    #[test]
    fn percentual_de_contratado_zero_nao_existe() {
        assert_eq!(percentual(Dinheiro::ZERO, Dinheiro::ZERO).unwrap(), None);
        // 1 ÷ 3 = 33,333...% · 2 ÷ 3 = 66,666...%
        let (um, dois, tres) = (
            Dinheiro::de_centavos(100),
            Dinheiro::de_centavos(200),
            Dinheiro::de_centavos(300),
        );
        assert_eq!(percentual(um, tres).unwrap(), Some(d("33.33")));
        assert_eq!(percentual(dois, tres).unwrap(), Some(d("66.67")));
    }
}
