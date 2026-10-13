//! Imprime o modelo de tela em JSON, para conferir a interface sem abrir o app.
//!
//! `cargo run -p prumo-demonstracao --example painel -- [inicial|boletim-emitido|aprovada]`

use prumo_demonstracao::{ErroDemo, Estado};

fn main() -> Result<(), ErroDemo> {
    let mut estado = Estado::default();
    match std::env::args().nth(1).as_deref() {
        Some("boletim-emitido") => {
            estado.salvar_rascunho("concluido", 0)?;
            estado.emitir_boletim()?;
        }
        Some("aprovada") => {
            estado.salvar_rascunho("concluido", 0)?;
            estado.emitir_boletim()?;
            estado.aprovar_medicao()?;
        }
        _ => {}
    }
    match serde_json::to_string_pretty(&estado.painel()?) {
        Ok(json) => println!("{json}"),
        Err(e) => eprintln!("não foi possível gerar o JSON: {e}"),
    }
    Ok(())
}
