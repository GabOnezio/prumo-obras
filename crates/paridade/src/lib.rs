//! Paridade entre as regras em Rust e o SQL do banco: mesma entrada, mesmo centavo.
//!
//! Este crate não tem código de produção. Os testes ficam em `tests/` e todos são
//! `#[ignore]`: precisam de um PostgreSQL com as migrações e o seed fictício. Quem sobe
//! esse banco e roda os testes é `scripts/db-test.sh paridade`, que informa o endereço em
//! `PRUMO_PARIDADE_URL`. Assim `cargo test` sem banco não passa a impressão de ter
//! conferido alguma coisa.
//!
//! O `prumo-dominio` continua puro, sem banco: é este crate que conversa com os dois lados.
//! Os números vão e voltam do banco como texto, para não passar por ponto flutuante.
