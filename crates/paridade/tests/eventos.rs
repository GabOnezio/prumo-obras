//! Valor de evento: `Evento::valor` (Rust) × `fn_recalcular_eventos` (SQL).
//!
//! Dois testes. O primeiro confere que o seed fictício do banco tem a mesma planilha da
//! prévia de desktop e que os seis eventos valem o mesmo nos três lugares. O segundo monta
//! contratos sorteados, com serviços repartidos em várias frentes, e compara evento a evento.

mod comum;

use comum::{
    conectar, decimal, id, nome_no_banco, sql_das_pessoas, sql_de_enviar, Sorteio, EMPRESA_ALFA,
};
use prumo_dominio::{valor_item, CriterioArredondamento, Dinheiro, Evento, ServicoNaFrente};
use rust_decimal::Decimal;
use std::collections::BTreeMap;

#[test]
#[ignore = "precisa do banco: rode scripts/db-test.sh paridade"]
fn eventos_do_seed_sao_os_da_previa_e_valem_o_mesmo_no_rust_e_no_sql() {
    let mut banco = conectar();
    let (da_previa, criterio) = prumo_demonstracao::planilha_por_eventos();

    let contrato = banco
        .query_one(
            "SELECT c.criterio_arredondamento::text, c.valor_inicial::text, r.valor_total::text
               FROM contrato c
               JOIN revisao_orcamento r ON r.contrato_id = c.id AND r.status = 'vigente'
              WHERE c.numero = '045/2026'",
            &[],
        )
        .expect("o contrato 045/2026 do seed fictício não está no banco");
    assert_eq!(contrato.get::<_, &str>(0), nome_no_banco(criterio));

    // Cada serviço de cada evento, como está no banco, na ordem da planilha.
    let linhas = banco
        .query(
            "SELECT a.titulo, f.nome, e.valor::text, ir.codigo_eap, ir.descricao, ir.unidade,
                    q.quantidade::text, ir.preco_unitario::text
               FROM evento e
               JOIN agrupador_evento a  ON a.id = e.agrupador_id
               JOIN frente_obra f       ON f.id = e.frente_id
               JOIN revisao_orcamento r ON r.id = e.revisao_id AND r.status = 'vigente'
               JOIN contrato c          ON c.id = r.contrato_id
               JOIN item_revisao ir     ON ir.revisao_id = e.revisao_id AND ir.tipo = 'servico'
                                       AND ir.agrupador_evento_id = e.agrupador_id
               JOIN item_frente q       ON q.item_revisao_id = ir.id AND q.frente_id = e.frente_id
              WHERE c.numero = '045/2026'
              ORDER BY a.numero, f.ordem, ir.path",
            &[],
        )
        .expect("não leu os eventos do seed");

    let mut do_banco: Vec<(Evento, Decimal)> = Vec::new();
    for linha in &linhas {
        let (agrupador, frente): (&str, &str) = (linha.get(0), linha.get(1));
        let novo = do_banco
            .last()
            .is_none_or(|(e, _)| e.agrupador != agrupador || e.frente != frente);
        if novo {
            let evento = Evento {
                agrupador: agrupador.into(),
                frente: frente.into(),
                servicos: Vec::new(),
            };
            do_banco.push((evento, decimal(linha.get(2))));
        }
        let (evento, _) = do_banco.last_mut().expect("acabou de entrar");
        evento.servicos.push(ServicoNaFrente {
            item: linha.get::<_, &str>(3).into(),
            descricao: linha.get::<_, &str>(4).into(),
            unidade: linha.get::<_, &str>(5).into(),
            quantidade: decimal(linha.get(6)),
            preco_unitario: decimal(linha.get(7)),
        });
    }

    assert_eq!(do_banco.len(), da_previa.len(), "número de eventos");
    let mut total = Dinheiro::ZERO;
    for ((banco_ev, valor_no_sql), previa_ev) in do_banco.iter().zip(&da_previa) {
        let nome = previa_ev.nome();
        assert_eq!(banco_ev.nome(), nome);
        assert_eq!(
            banco_ev.servicos.len(),
            previa_ev.servicos.len(),
            "{nome}: serviços"
        );
        for (b, p) in banco_ev.servicos.iter().zip(&previa_ev.servicos) {
            assert_eq!(b.item, p.item, "{nome}");
            assert_eq!(b.descricao, p.descricao, "{nome}, item {}", p.item);
            assert_eq!(b.unidade, p.unidade, "{nome}, item {}", p.item);
            assert_eq!(b.quantidade, p.quantidade, "{nome}, item {}", p.item);
            assert_eq!(
                b.preco_unitario, p.preco_unitario,
                "{nome}, item {}",
                p.item
            );
        }
        let da_previa_valor = previa_ev.valor(criterio).expect("valor na prévia");
        let do_banco_no_rust = banco_ev.valor(criterio).expect("valor em Rust");
        assert_eq!(do_banco_no_rust, da_previa_valor, "{nome}");
        assert_eq!(
            do_banco_no_rust.decimal(),
            *valor_no_sql,
            "{nome}: Rust × SQL"
        );
        total = total.somar(do_banco_no_rust).expect("soma");
    }
    assert_eq!(total, Dinheiro::de_centavos(16_403_934));
    assert_eq!(
        total.decimal(),
        decimal(contrato.get(1)),
        "valor do contrato"
    );
    assert_eq!(
        total.decimal(),
        decimal(contrato.get(2)),
        "valor da planilha"
    );
    println!(
        "seed × prévia: {} eventos e {} serviços iguais, campo a campo; total {}",
        do_banco.len(),
        linhas.len(),
        total.formatar()
    );
}

/// Um serviço de um contrato sorteado: quantidade repartida nas frentes, em décimos de milésimo.
struct ServicoSorteado {
    agrupador: usize,
    preco: Decimal,
    /// Parte de cada frente (índice = frente). Zero = o serviço não passa por ela.
    partes: Vec<i64>,
}

impl ServicoSorteado {
    fn quantidade(&self) -> Decimal {
        Decimal::new(self.partes.iter().sum(), 4)
    }
}

fn sortear_servico(
    sorteio: &mut Sorteio,
    agrupadores: usize,
    frentes: usize,
    casas: u32,
) -> ServicoSorteado {
    let mut partes = vec![0_i64; frentes];
    let usadas = 1 + sorteio.ate(frentes as u64) as usize;
    for _ in 0..usadas {
        let frente = sorteio.ate(frentes as u64) as usize;
        // de 0,0001 a 500,0000 por sorteio; a mesma frente pode ser sorteada de novo e soma
        partes[frente] += 1 + sorteio.ate(5_000_000) as i64;
    }
    ServicoSorteado {
        agrupador: sorteio.ate(agrupadores as u64) as usize,
        // preço de 0,01 para cima, com as casas decimais que o contrato aceita
        preco: sorteio.decimal(2_000, casas) + Decimal::new(1, 2),
        partes,
    }
}

#[test]
#[ignore = "precisa do banco: rode scripts/db-test.sh paridade"]
fn eventos_de_contratos_sorteados_valem_o_mesmo_no_rust_e_no_sql() {
    const CONTRATOS: usize = 12;
    const SERVICOS: usize = 10;
    const FRENTES: usize = 4;
    const AGRUPADORES: usize = 3;

    let mut banco = conectar();
    let mut sorteio = Sorteio::novo(0x5052_554D_4F00_0002);
    let mut eventos_conferidos = 0;
    let mut com_diferenca_para_a_planilha = 0;

    for c in 0..CONTRATOS {
        let criterio = if c % 2 == 0 {
            CriterioArredondamento::Arredondar
        } else {
            CriterioArredondamento::Truncar
        };
        let casas = if c % 3 == 0 { 4 } else { 2 };
        let servicos: Vec<ServicoSorteado> = (0..SERVICOS)
            .map(|_| sortear_servico(&mut sorteio, AGRUPADORES, FRENTES, casas))
            .collect();

        // O que o Rust espera: valor da planilha e valor de cada evento.
        let mut planilha = Dinheiro::ZERO;
        let mut esperado: BTreeMap<(usize, usize), Evento> = BTreeMap::new();
        for (n, s) in servicos.iter().enumerate() {
            planilha = planilha
                .somar(valor_item(s.quantidade(), s.preco, criterio).expect("valor do item"))
                .expect("soma da planilha");
            for (frente, parte) in s.partes.iter().enumerate().filter(|(_, p)| **p > 0) {
                esperado
                    .entry((s.agrupador, frente))
                    .or_insert_with(|| Evento {
                        agrupador: format!("Agrupador {}", s.agrupador + 1),
                        frente: format!("Frente {}", frente + 1),
                        servicos: Vec::new(),
                    })
                    .servicos
                    .push(ServicoNaFrente {
                        item: format!("1.{}", n + 1),
                        descricao: String::new(),
                        unidade: "un".into(),
                        quantidade: Decimal::new(*parte, 4),
                        preco_unitario: s.preco,
                    });
            }
        }
        assert!(!planilha.eh_zero(), "contrato {c}: planilha zerada");

        // O mesmo contrato, gravado no banco como a aplicação gravaria.
        let (contrato, revisao, grupo) = (id(1, c, 0), id(2, c, 0), id(5, c, 0));
        let mut sql = format!(
            "INSERT INTO contrato (id, obra_id, orgao_id, numero, processo_licitatorio, objeto, regime_execucao,
                                   data_assinatura, data_base_orcamento, prazo_execucao_dias, vigencia_fim,
                                   valor_inicial, valor_orcamento_base, bdi_percentual, criterio_arredondamento,
                                   casas_decimais_preco, forma_acompanhamento, empresa_id)
             VALUES ('{contrato}', 'e0e0e0e0-0000-0000-0000-0000000000b1', 'e0e0e0e0-0000-0000-0000-0000000000a1',
                     'PARIDADE-{c:02}', 'Teste de paridade', 'Contrato sorteado', 'empreitada_preco_global',
                     '2026-09-14', '2026-05-01', 90, '2027-03-31', {valor}, {valor}, 0, '{criterio}', {casas}, 'eventos',
                     '{EMPRESA_ALFA}');
             INSERT INTO revisao_orcamento (id, contrato_id, numero, origem) VALUES ('{revisao}', '{contrato}', 0, 'importacao');
             INSERT INTO item_contratual (id, contrato_id) VALUES ('{item_grupo}', '{contrato}');
             INSERT INTO item_revisao (id, revisao_id, item_contratual_id, parent_id, ordem, codigo_eap, tipo, descricao)
             VALUES ('{grupo}', '{revisao}', '{item_grupo}', NULL, 1, '1', 'grupo', 'GRUPO');",
            valor = planilha.decimal(),
            criterio = nome_no_banco(criterio),
            item_grupo = id(4, c, 0),
        );
        for f in 0..FRENTES {
            sql += &format!(
                "INSERT INTO frente_obra (id, contrato_id, ordem, nome) VALUES ('{}', '{contrato}', {}, 'Frente {}');",
                id(6, c, f),
                f + 1,
                f + 1
            );
        }
        for a in 0..AGRUPADORES {
            sql += &format!(
                "INSERT INTO agrupador_evento (id, contrato_id, numero, titulo) VALUES ('{}', '{contrato}', {}, 'Agrupador {}');",
                id(7, c, a),
                a + 1,
                a + 1
            );
        }
        for (n, s) in servicos.iter().enumerate() {
            let (item, item_revisao) = (id(4, c, n + 1), id(5, c, n + 1));
            sql += &format!(
                "INSERT INTO item_contratual (id, contrato_id) VALUES ('{item}', '{contrato}');
                 INSERT INTO item_revisao (id, revisao_id, item_contratual_id, parent_id, ordem, codigo_eap, tipo, descricao,
                                           unidade, quantidade, preco_unitario, agrupador_evento_id)
                 VALUES ('{item_revisao}', '{revisao}', '{item}', '{grupo}', {ordem}, '1.{ordem}', 'servico', 'Serviço {ordem}',
                         'un', {quantidade}, {preco}, '{agrupador}');",
                ordem = n + 1,
                quantidade = s.quantidade(),
                preco = s.preco,
                agrupador = id(7, c, s.agrupador),
            );
            for (f, parte) in s.partes.iter().enumerate().filter(|(_, p)| **p > 0) {
                sql += &format!(
                    "INSERT INTO item_frente (item_revisao_id, frente_id, quantidade) VALUES ('{item_revisao}', '{}', {});",
                    id(6, c, f),
                    Decimal::new(*parte, 4)
                );
            }
        }
        // Ao ficar vigente o banco soma a planilha, compara com o valor do contrato (que veio
        // do Rust) e calcula os eventos. Depois uma medição marca todos os eventos.
        let medicao = id(8, c, 0);
        sql += &format!(
            "UPDATE revisao_orcamento SET status = 'vigente', data_vigencia = DATE '2026-09-14' WHERE id = '{revisao}';
             INSERT INTO medicao (id, contrato_id, numero, revisao_id, periodo_inicio, periodo_fim)
             VALUES ('{medicao}', '{contrato}', 1, '{revisao}', '2026-10-01', '2026-10-31');
             INSERT INTO medicao_evento (medicao_id, evento_id) SELECT '{medicao}'::uuid, id FROM evento WHERE revisao_id = '{revisao}';"
        );
        sql += &sql_das_pessoas(&contrato);
        sql += &sql_de_enviar(&medicao);
        banco
            .batch_execute(&sql)
            .unwrap_or_else(|e| panic!("contrato {c} não gravou: {e}"));

        let no_sql: BTreeMap<(usize, usize), Decimal> = banco
            .query(
                "SELECT a.numero::int, f.ordem::int, e.valor::text
                   FROM evento e
                   JOIN agrupador_evento a ON a.id = e.agrupador_id
                   JOIN frente_obra f      ON f.id = e.frente_id
                  WHERE e.revisao_id = $1::text::uuid",
                &[&revisao],
            )
            .expect("não leu os eventos")
            .iter()
            .map(|l| {
                let (a, f): (i32, i32) = (l.get(0), l.get(1));
                ((a as usize - 1, f as usize - 1), decimal(l.get(2)))
            })
            .collect();

        assert_eq!(
            no_sql.keys().collect::<Vec<_>>(),
            esperado.keys().collect::<Vec<_>>(),
            "contrato {c}: os eventos (agrupador, frente) não são os mesmos"
        );
        let mut soma_dos_eventos = Dinheiro::ZERO;
        for (chave, evento) in &esperado {
            let no_rust = evento.valor(criterio).expect("valor do evento");
            assert_eq!(
                no_rust.decimal(),
                no_sql[chave],
                "contrato {c} ({criterio:?}, {casas} casas), {}: Rust × SQL",
                evento.nome()
            );
            soma_dos_eventos = soma_dos_eventos.somar(no_rust).expect("soma");
            eventos_conferidos += 1;
        }

        let totais = banco
            .query_one(
                "SELECT r.valor_total::text, m.valor_bruto::text
                   FROM revisao_orcamento r JOIN medicao m ON m.revisao_id = r.id
                  WHERE r.id = $1::text::uuid",
                &[&revisao],
            )
            .expect("não leu os totais");
        assert_eq!(
            planilha.decimal(),
            decimal(totais.get(0)),
            "contrato {c}: valor da planilha"
        );
        assert_eq!(
            soma_dos_eventos.decimal(),
            decimal(totais.get(1)),
            "contrato {c}: medição com todos os eventos"
        );
        if soma_dos_eventos != planilha {
            com_diferenca_para_a_planilha += 1;
        }
    }
    println!(
        "contratos sorteados: {CONTRATOS} contratos, {eventos_conferidos} eventos iguais no Rust e no SQL; \
         em {com_diferenca_para_a_planilha} deles a soma dos eventos difere da planilha por arredondamento"
    );
}
