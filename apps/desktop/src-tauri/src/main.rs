//! Prumo para desktop. Por enquanto é a prévia: a janela mostra as telas e os
//! comandos abaixo só repassam para `prumo-demonstracao`, que guarda o estado
//! em memória e chama as regras de `prumo-dominio`.

// Sem janela de console no Windows.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use prumo_demonstracao::{ErroDemo, Estado, Painel};
use std::sync::Mutex;
use tauri::State;

struct Previa(Mutex<Estado>);

/// Aplica a ação e devolve as telas recalculadas. Erro vira mensagem para a interface.
fn executar(
    previa: &State<Previa>,
    acao: impl FnOnce(&mut Estado) -> Result<(), ErroDemo>,
) -> Result<Painel, String> {
    let mut estado = previa
        .0
        .lock()
        .map_err(|_| "O estado da prévia ficou inconsistente. Feche e abra o Prumo.".to_string())?;
    acao(&mut estado).map_err(|e| e.to_string())?;
    estado.painel().map_err(|e| e.to_string())
}

#[tauri::command]
fn painel(previa: State<Previa>) -> Result<Painel, String> {
    executar(&previa, |_| Ok(()))
}

#[tauri::command]
fn salvar_rascunho(previa: State<Previa>, situacao: String, avanco: u8) -> Result<Painel, String> {
    executar(&previa, |e| e.salvar_rascunho(&situacao, avanco))
}

#[tauri::command]
fn emitir_boletim(previa: State<Previa>) -> Result<Painel, String> {
    executar(&previa, Estado::emitir_boletim)
}

#[tauri::command]
fn glosar_evento(previa: State<Previa>, evento: usize) -> Result<Painel, String> {
    executar(&previa, |e| e.glosar(evento))
}

#[tauri::command]
fn desfazer_glosa(previa: State<Previa>, evento: usize) -> Result<Painel, String> {
    executar(&previa, |e| e.desfazer_glosa(evento))
}

#[tauri::command]
fn aprovar_medicao(previa: State<Previa>) -> Result<Painel, String> {
    executar(&previa, Estado::aprovar_medicao)
}

#[tauri::command]
fn reiniciar(previa: State<Previa>) -> Result<Painel, String> {
    executar(&previa, |e| {
        *e = Estado::default();
        Ok(())
    })
}

fn main() {
    let resultado = tauri::Builder::default()
        .manage(Previa(Mutex::new(Estado::default())))
        .invoke_handler(tauri::generate_handler![
            painel,
            salvar_rascunho,
            emitir_boletim,
            glosar_evento,
            desfazer_glosa,
            aprovar_medicao,
            reiniciar
        ])
        .run(tauri::generate_context!());
    if let Err(erro) = resultado {
        eprintln!("não foi possível iniciar o Prumo: {erro}");
        std::process::exit(1);
    }
}
