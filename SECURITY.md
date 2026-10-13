# Política de segurança

## Versões suportadas

Correções de segurança e legais vão para o canal **LTS** e para a versão **current**. Prefeituras em produção devem usar o LTS.

## Como reportar uma vulnerabilidade

**Não abra issue pública.** Envie para o contato de segurança do projeto (preencher antes da primeira release: `seguranca@<dominio>`), com descrição, passos para reproduzir, impacto e versão. Resposta inicial em até 3 dias úteis; correção priorizada por gravidade. Divulgação coordenada após correção.

## Escopo especialmente sensível

- Isolamento entre municípios (RLS) e entre empresas dentro do mesmo município.
- Autorização por perfil e por designação; segregação de funções.
- Imutabilidade de registros aprovados e integridade da trilha de auditoria.
- Upload de arquivos e fotos (tipo, tamanho, malware, metadados).
- Injeção de prompt via texto de diário, medição ou arquivo importado (planilha, cronograma, projeto) para influenciar o módulo de IA (ver LP8).
- Leitura de arquivos do órgão (`.xlsx`, `.xls`, `.ods`, PDF): arquivo malformado, macro, fórmula, tamanho, bomba de descompactação.
- Qualquer caminho que deixe um evento ser aprovado sem Boletim de Execução emitido, ou que deixe a previsão influenciar aprovação, glosa ou pagamento.
- Atualizador do Tauri e assinatura de artefatos.

## Incidentes com dados pessoais

Em caso de incidente com dado pessoal, o operador (mantenedor) avisa o controlador (prefeitura) e seu encarregado imediatamente, para que a comunicação à ANPD e aos titulares siga a LGPD e a orientação jurídica do município.
