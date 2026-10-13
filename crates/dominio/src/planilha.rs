//! Planilha orçamentária de uma revisão: a árvore de grupos e serviços do contrato.
//!
//! As conferências daqui são as mesmas dos gatilhos `fn_item_revisao_guard` e das restrições
//! da tabela `item_revisao`. O banco continua conferindo, como última defesa.

use crate::dinheiro::{valor_item, CriterioArredondamento, Dinheiro};
use crate::ErroDominio;
use rust_decimal::Decimal;
use std::collections::{BTreeMap, BTreeSet};

/// Casas decimais que a coluna de quantidade guarda (`NUMERIC(18,4)`).
pub const CASAS_DA_QUANTIDADE: u32 = 4;

/// Identidade de um item, estável entre as revisões (`item_contratual.id` no banco).
/// Medição, aditivo, diário e foto apontam para ela.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct ItemId(pub u128);

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum TipoItem {
    Grupo,
    Servico {
        unidade: String,
        quantidade: Decimal,
        preco_unitario: Decimal,
    },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ItemPlanilha {
    pub id: ItemId,
    /// Grupo em que o item está. `None` para os itens do primeiro nível.
    pub pai: Option<ItemId>,
    /// Posição entre os irmãos, de 1 a 99.999.
    pub ordem: u32,
    /// Código como veio na planilha do órgão (ex.: `2.1.3`).
    pub codigo_eap: String,
    pub descricao: String,
    pub tipo: TipoItem,
}

impl ItemPlanilha {
    pub fn eh_servico(&self) -> bool {
        matches!(self.tipo, TipoItem::Servico { .. })
    }
}

/// Planilha conferida, com os itens na ordem da árvore.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Planilha {
    numero: u16,
    criterio: CriterioArredondamento,
    casas_do_preco: u32,
    /// Itens em ordem de árvore, cada um com o nível (1 = primeiro nível).
    itens: Vec<(ItemPlanilha, u32)>,
    posicao: BTreeMap<ItemId, usize>,
}

impl Planilha {
    /// Confere e monta a planilha. `numero` é o da revisão (0 = planilha do contrato).
    pub fn nova(
        numero: u16,
        criterio: CriterioArredondamento,
        casas_do_preco: u32,
        itens: Vec<ItemPlanilha>,
    ) -> Result<Planilha, ErroDominio> {
        if !(2..=4).contains(&casas_do_preco) {
            return Err(ErroDominio::CasasDoPrecoInvalidas(casas_do_preco));
        }
        let mut ids = BTreeSet::new();
        let mut codigos = BTreeSet::new();
        let mut grupos = BTreeSet::new();
        for item in &itens {
            if !ids.insert(item.id) || !codigos.insert(item.codigo_eap.as_str()) {
                return Err(ErroDominio::ItemRepetido(item.codigo_eap.clone()));
            }
            if !(1..=99_999).contains(&item.ordem) {
                return Err(ErroDominio::OrdemInvalida(item.codigo_eap.clone()));
            }
            match &item.tipo {
                TipoItem::Grupo => {
                    grupos.insert(item.id);
                }
                TipoItem::Servico {
                    quantidade,
                    preco_unitario,
                    ..
                } => {
                    conferir_servico(
                        &item.codigo_eap,
                        *quantidade,
                        *preco_unitario,
                        casas_do_preco,
                    )?;
                }
            }
        }

        // Filhos de cada grupo, por ordem. O pai tem que existir e ser grupo.
        let mut filhos: BTreeMap<Option<ItemId>, BTreeMap<u32, ItemPlanilha>> = BTreeMap::new();
        for item in itens {
            if item.pai.is_some_and(|pai| !grupos.contains(&pai)) {
                return Err(ErroDominio::PaiInvalido(item.codigo_eap));
            }
            let irmaos = filhos.entry(item.pai).or_default();
            if irmaos.contains_key(&item.ordem) {
                return Err(ErroDominio::OrdemInvalida(item.codigo_eap));
            }
            irmaos.insert(item.ordem, item);
        }

        // Percorre a árvore a partir do primeiro nível. O que sobrar está pendurado num ciclo.
        let mut em_ordem = Vec::with_capacity(ids.len());
        let mut pilha: Vec<(ItemPlanilha, u32)> = filhos
            .remove(&None)
            .unwrap_or_default()
            .into_values()
            .rev()
            .map(|item| (item, 1))
            .collect();
        while let Some((item, nivel)) = pilha.pop() {
            if let Some(dele) = filhos.remove(&Some(item.id)) {
                pilha.extend(dele.into_values().rev().map(|f| (f, nivel + 1)));
            }
            em_ordem.push((item, nivel));
        }
        if let Some(solto) = filhos.into_values().flat_map(BTreeMap::into_values).next() {
            return Err(ErroDominio::PaiInvalido(solto.codigo_eap));
        }

        let posicao = em_ordem
            .iter()
            .enumerate()
            .map(|(i, (item, _))| (item.id, i))
            .collect();
        Ok(Planilha {
            numero,
            criterio,
            casas_do_preco,
            itens: em_ordem,
            posicao,
        })
    }

    pub fn numero(&self) -> u16 {
        self.numero
    }

    pub fn criterio(&self) -> CriterioArredondamento {
        self.criterio
    }

    pub fn casas_do_preco(&self) -> u32 {
        self.casas_do_preco
    }

    /// Itens na ordem da árvore, cada um com o nível (1 = primeiro nível).
    pub fn itens(&self) -> impl Iterator<Item = (&ItemPlanilha, u32)> {
        self.itens.iter().map(|(item, nivel)| (item, *nivel))
    }

    pub fn item(&self, id: ItemId) -> Option<&ItemPlanilha> {
        self.posicao.get(&id).map(|&i| &self.itens[i].0)
    }

    /// Posições, na ordem da árvore, do item e de tudo o que está abaixo dele.
    pub(crate) fn ramo(&self, id: ItemId) -> std::ops::Range<usize> {
        let Some(&inicio) = self.posicao.get(&id) else {
            return 0..0;
        };
        let nivel = self.itens[inicio].1;
        let fim = self.itens[inicio + 1..]
            .iter()
            .position(|(_, n)| *n <= nivel)
            .map_or(self.itens.len(), |p| inicio + 1 + p);
        inicio..fim
    }

    pub(crate) fn na_posicao(&self, posicao: usize) -> &ItemPlanilha {
        &self.itens[posicao].0
    }

    /// Valor de um serviço: quantidade × preço, pelo critério do contrato. `None` para grupo
    /// e para item que não está na planilha.
    pub fn valor_do_servico(&self, id: ItemId) -> Result<Option<Dinheiro>, ErroDominio> {
        match self.item(id).map(|item| &item.tipo) {
            Some(TipoItem::Servico {
                quantidade,
                preco_unitario,
                ..
            }) => valor_item(*quantidade, *preco_unitario, self.criterio).map(Some),
            _ => Ok(None),
        }
    }

    /// Soma dos serviços. É o valor da revisão (`revisao_orcamento.valor_total`).
    pub fn valor_total(&self) -> Result<Dinheiro, ErroDominio> {
        self.itens
            .iter()
            .try_fold(Dinheiro::ZERO, |soma, (item, _)| {
                match self.valor_do_servico(item.id)? {
                    Some(valor) => soma.somar(valor),
                    None => Ok(soma),
                }
            })
    }
}

/// Quantidade e preço de um serviço dentro do que o banco guarda sem arredondar.
pub(crate) fn conferir_servico(
    codigo: &str,
    quantidade: Decimal,
    preco_unitario: Decimal,
    casas_do_preco: u32,
) -> Result<(), ErroDominio> {
    if quantidade.is_sign_negative() && !quantidade.is_zero() {
        return Err(ErroDominio::QuantidadeInvalida(codigo.into()));
    }
    if quantidade.normalize().scale() > CASAS_DA_QUANTIDADE {
        return Err(ErroDominio::QuantidadeInvalida(codigo.into()));
    }
    if preco_unitario.is_sign_negative() && !preco_unitario.is_zero() {
        return Err(ErroDominio::PrecoInvalido(codigo.into()));
    }
    if preco_unitario.normalize().scale() > casas_do_preco {
        return Err(ErroDominio::PrecoInvalido(codigo.into()));
    }
    Ok(())
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use CriterioArredondamento::{Arredondar, Truncar};

    pub(crate) fn d(texto: &str) -> Decimal {
        texto.parse().unwrap()
    }

    pub(crate) fn grupo(id: u128, pai: Option<u128>, ordem: u32, codigo: &str) -> ItemPlanilha {
        ItemPlanilha {
            id: ItemId(id),
            pai: pai.map(ItemId),
            ordem,
            codigo_eap: codigo.into(),
            descricao: format!("GRUPO {codigo}"),
            tipo: TipoItem::Grupo,
        }
    }

    pub(crate) fn servico(
        id: u128,
        pai: u128,
        ordem: u32,
        codigo: &str,
        unidade: &str,
        quantidade: &str,
        preco: &str,
    ) -> ItemPlanilha {
        ItemPlanilha {
            id: ItemId(id),
            pai: Some(ItemId(pai)),
            ordem,
            codigo_eap: codigo.into(),
            descricao: format!("Serviço {codigo}"),
            tipo: TipoItem::Servico {
                unidade: unidade.into(),
                quantidade: d(quantidade),
                preco_unitario: d(preco),
            },
        }
    }

    /// Planilha do cenário de `db/reference/seed_e_testes.sql` (contrato com critério de
    /// truncar). Os ids repetem os finais dos ids do seed.
    pub(crate) fn planilha_de_referencia() -> Planilha {
        Planilha::nova(
            0,
            Truncar,
            2,
            vec![
                // fora de ordem de propósito: quem ordena é a planilha
                servico(0x32, 0x3, 2, "3.2", "m²", "640.00", "7.43"),
                grupo(0x1, None, 1, "1"),
                servico(0x11, 0x1, 1, "1.1", "m²", "6.00", "450.00"),
                servico(0x12, 0x1, 2, "1.2", "m²", "180.00", "12.35"),
                grupo(0x2, None, 2, "2"),
                grupo(0x21, Some(0x2), 1, "2.1"),
                servico(0x211, 0x21, 1, "2.1.1", "m³", "42.50", "68.93"),
                servico(0x212, 0x21, 2, "2.1.2", "m³", "18.20", "785.40"),
                servico(0x22, 0x2, 2, "2.2", "m²", "64.00", "48.77"),
                grupo(0x3, None, 3, "3"),
                servico(0x31, 0x3, 1, "3.1", "m²", "320.00", "89.15"),
            ],
        )
        .unwrap()
    }

    #[test]
    fn planilha_de_referencia_soma_58_551_28() {
        let p = planilha_de_referencia();
        assert_eq!(p.valor_total().unwrap(), Dinheiro::de_centavos(5_855_128));
        // escavação: 42,50 × 68,93 = 2.929,525, truncado
        assert_eq!(
            p.valor_do_servico(ItemId(0x211)).unwrap(),
            Some(Dinheiro::de_centavos(292_952))
        );
        assert_eq!(p.valor_do_servico(ItemId(0x2)).unwrap(), None);
    }

    #[test]
    fn itens_saem_na_ordem_da_arvore_com_o_nivel() {
        let p = planilha_de_referencia();
        let ordem: Vec<(&str, u32)> = p
            .itens()
            .map(|(item, nivel)| (item.codigo_eap.as_str(), nivel))
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
                ("3", 1),
                ("3.1", 2),
                ("3.2", 2),
            ]
        );
    }

    #[test]
    fn ramo_pega_o_item_e_o_que_esta_abaixo() {
        let p = planilha_de_referencia();
        let codigos = |id: u128| -> Vec<&str> {
            p.ramo(ItemId(id))
                .map(|i| p.na_posicao(i).codigo_eap.as_str())
                .collect()
        };
        assert_eq!(codigos(0x2), vec!["2", "2.1", "2.1.1", "2.1.2", "2.2"]);
        assert_eq!(codigos(0x21), vec!["2.1", "2.1.1", "2.1.2"]);
        assert_eq!(codigos(0x32), vec!["3.2"]);
        assert!(codigos(0x999).is_empty());
    }

    #[test]
    fn o_mesmo_item_arredondado_soma_um_centavo_a_mais() {
        let mut itens: Vec<ItemPlanilha> = planilha_de_referencia()
            .itens()
            .map(|(item, _)| item.clone())
            .collect();
        itens.reverse();
        let p = Planilha::nova(0, Arredondar, 2, itens).unwrap();
        assert_eq!(p.valor_total().unwrap(), Dinheiro::de_centavos(5_855_129));
    }

    fn erro_de(itens: Vec<ItemPlanilha>) -> ErroDominio {
        Planilha::nova(0, Arredondar, 2, itens).unwrap_err()
    }

    #[test]
    fn servico_so_fica_abaixo_de_grupo() {
        let e = erro_de(vec![
            grupo(1, None, 1, "1"),
            servico(2, 1, 1, "1.1", "m", "1", "1"),
            servico(3, 2, 1, "1.1.1", "m", "1", "1"),
        ]);
        assert_eq!(e, ErroDominio::PaiInvalido("1.1.1".into()));
    }

    #[test]
    fn pai_que_nao_existe_e_erro() {
        let e = erro_de(vec![servico(2, 9, 1, "1.1", "m", "1", "1")]);
        assert_eq!(e, ErroDominio::PaiInvalido("1.1".into()));
    }

    #[test]
    fn grupos_em_ciclo_sao_erro() {
        let e = erro_de(vec![grupo(1, Some(2), 1, "A"), grupo(2, Some(1), 1, "B")]);
        assert!(matches!(e, ErroDominio::PaiInvalido(_)));
    }

    #[test]
    fn codigo_id_e_ordem_nao_se_repetem() {
        let mesmo_codigo = erro_de(vec![grupo(1, None, 1, "1"), grupo(2, None, 2, "1")]);
        assert_eq!(mesmo_codigo, ErroDominio::ItemRepetido("1".into()));
        let mesmo_id = erro_de(vec![grupo(1, None, 1, "1"), grupo(1, None, 2, "2")]);
        assert_eq!(mesmo_id, ErroDominio::ItemRepetido("2".into()));
        let mesma_ordem = erro_de(vec![grupo(1, None, 1, "1"), grupo(2, None, 1, "2")]);
        assert_eq!(mesma_ordem, ErroDominio::OrdemInvalida("2".into()));
        let ordem_zero = erro_de(vec![grupo(1, None, 0, "1")]);
        assert_eq!(ordem_zero, ErroDominio::OrdemInvalida("1".into()));
    }

    #[test]
    fn preco_com_mais_casas_que_o_contrato_e_erro() {
        // "Preço unitário com 3 casas num contrato de 2", do seed de referência
        let e = erro_de(vec![
            grupo(1, None, 1, "1"),
            servico(2, 1, 1, "1.2", "m²", "180.00", "12.355"),
        ]);
        assert_eq!(e, ErroDominio::PrecoInvalido("1.2".into()));
        // zeros à direita não contam como casa
        let ok = Planilha::nova(
            0,
            Arredondar,
            2,
            vec![
                grupo(1, None, 1, "1"),
                servico(2, 1, 1, "1.2", "m²", "180.00", "12.3500"),
            ],
        );
        assert!(ok.is_ok());
    }

    #[test]
    fn quantidade_negativa_ou_com_mais_de_quatro_casas_e_erro() {
        let negativa = erro_de(vec![
            grupo(1, None, 1, "1"),
            servico(2, 1, 1, "1.1", "m", "-1", "1"),
        ]);
        assert_eq!(negativa, ErroDominio::QuantidadeInvalida("1.1".into()));
        // o banco guarda 4 casas e arredondaria a quinta sem avisar
        let cinco_casas = erro_de(vec![
            grupo(1, None, 1, "1"),
            servico(2, 1, 1, "1.1", "m", "1.00001", "1"),
        ]);
        assert_eq!(cinco_casas, ErroDominio::QuantidadeInvalida("1.1".into()));
        let preco_negativo = erro_de(vec![
            grupo(1, None, 1, "1"),
            servico(2, 1, 1, "1.1", "m", "1", "-0.01"),
        ]);
        assert_eq!(preco_negativo, ErroDominio::PrecoInvalido("1.1".into()));
    }

    #[test]
    fn casas_do_preco_fora_de_2_a_4_e_erro() {
        for casas in [0, 1, 5] {
            assert_eq!(
                Planilha::nova(0, Arredondar, casas, vec![]).unwrap_err(),
                ErroDominio::CasasDoPrecoInvalidas(casas)
            );
        }
    }
}
