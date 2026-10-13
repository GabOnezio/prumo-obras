# ADR 0009 · Máquinas de estado como tabela no domínio, com segregação de funções

- **Estado:** aceito para a estrutura; **provisório** nos pontos da questão 39
- **Data:** 13/10/2026
- **Decisor:** Gabriel Onezio Ferreira (estrutura pedida na Fase 0; os pontos provisórios aguardam resposta)

## Contexto

Medição, diário, aditivo e Boletim de Execução passam de mão em mão: a empresa declara, o fiscal confere, alguém atesta. O que cada um pode fazer, e em que momento, é a regra mais sensível do sistema: é ela que impede a empresa de aprovar a própria medição e quem administra o sistema de mexer em pagamento.

No schema de referência essa regra quase não existe. A medição tem três estados e qualquer um muda o estado; o campo "aprovada por" é um texto livre.

## Decisão

1. **Cada documento tem uma máquina de estado em `crates/dominio::fluxo`**, pura, sem banco. A máquina é uma tabela: estado de partida, ação, estado de chegada e o papel que pode pedir. O que não está na tabela não acontece.
2. **Toda ação passa por uma função `transitar`**, que confere, nesta ordem: se a ação cabe no estado; se o papel pode; a segregação de funções; as condições próprias da ação. A função não altera nada: devolve o novo estado ou o motivo da recusa.
3. **Segregação de funções é condição da transição**, não aviso de tela:
   - quem enviou a medição não aprova como fiscal nem atesta;
   - quem aprovou como fiscal não atesta;
   - quem fechou o diário não valida;
   - quem montou o aditivo não homologa.
   A conferência é por pessoa, não por papel: vale mesmo que a mesma pessoa tenha os dois papéis.
4. **Papel é resolvido antes, pela aplicação.** Fiscal, gestor do contrato e comissão só existem com **designação vigente** naquele contrato. Quem consulta a designação é a aplicação, que tem banco; a máquina recebe o papel já resolvido.
5. **O que a lei remete ao município entra por parâmetro**, sem valor padrão no código: se há comissão de medição, se o aditivo exige parecer, quantas evidências uma linha do boletim precisa para "concluído".
6. **Administração de TI, auditor externo e controle interno não agem em documento nenhum.** Leem; o jurídico anexa parecer, que é condição da homologação e não ação da máquina.
7. **Estado final não tem saída.** Medição paga ou cancelada, diário validado ou devolvido, aditivo homologado ou rejeitado, boletim emitido. Correção é documento novo que aponta para o anterior.

## As tabelas

**Medição**

| De | Ação | Para | Quem | Condição |
|---|---|---|---|---|
| rascunho, devolvida | enviar | enviada | contratada | |
| rascunho, devolvida | cancelar | cancelada | contratada | |
| enviada | iniciar a análise | em_analise | fiscal | |
| em_analise | devolver | devolvida | fiscal | motivo |
| em_analise | aprovar como fiscal | aprovada_fiscal | fiscal | não é quem enviou; nenhum evento pendente |
| aprovada_fiscal | atestar | atestada | comissão de medição, se o município exigir; senão o gestor do contrato | não é quem enviou nem quem aprovou |
| atestada | registrar a liquidação | liquidada | gestor do contrato | |
| liquidada | registrar o pagamento | paga | gestor do contrato | |

**Diário:** rascunho → fechado (contratada) → em_validacao (fiscal) → validado (fiscal, que não é quem fechou) ou devolvido (fiscal, com motivo).

**Aditivo:** rascunho → enviado (planejamento) → homologado (gestor, que não é quem enviou; dentro do limite legal; com parecer, se exigido; com termo assinado) ou rejeitado (gestor, com motivo).

**Boletim de Execução:** rascunho → emitido (fiscal; ao menos uma linha; "concluído" com a evidência mínima e verificado até o fim do período).

## O que é provisório (questão 39)

`docs/01-modulos.md` desenha os estados, mas não diz quem faz algumas ações. Estas linhas são proposta minha:

- quem atesta quando não há comissão: **gestor do contrato**;
- quem registra liquidação e pagamento: **gestor do contrato** (os dois fatos acontecem na contabilidade; aqui só ficam anotados);
- quem cancela uma medição: **a contratada**, e só antes da análise;
- quem atesta tem que ser pessoa diferente de quem aprovou como fiscal;
- aditivo acima do limite legal **não é homologado**. A lei pode ter exceções; nenhuma está implementada (questão 40).

Mudar qualquer uma é trocar uma linha da tabela e o teste correspondente.

## Como se prova

Para cada máquina, um teste percorre **todas** as combinações de estado, ação e papel (648 na medição, 180 no diário, 108 no aditivo, 18 no boletim) e compara com uma lista de transições escrita à mão no próprio teste. Passam 10, 4, 3 e 1. Há teste para cada regra de segregação e para cada condição.

## O que ainda não existe

- **O banco não conhece estes estados.** A `0001` tem os três estados de medição da referência e deixa qualquer um mudar. Os estados novos e os gatilhos entram nas migrações `0004` (medição), `0005` (diário) e `0008` (boletim), com teste que compara as transições aceitas pelo banco com as desta tabela.
- **Ninguém chama `transitar` ainda.** A aplicação e a API são da Fase 1. Lá, cada comando chama a máquina antes de gravar, e o banco confere de novo.
- **Designação vigente** não é conferida aqui, por desenho. A tabela de designação é da migração `0002`.

## Alternativas descartadas

| Alternativa | Por que não |
|---|---|
| Regra só nos gatilhos do banco | A tela precisa saber o que pode antes de tentar; e a regra ficaria fora dos testes rápidos |
| Um `match` por ação, sem tabela | Não dá para listar o que é permitido nem conferir contra a documentação |
| Permissão por papel, sem olhar a pessoa | Quem tem dois papéis aprovaria o próprio documento |
| Biblioteca de máquina de estado | Mais uma dependência para quatro tabelas pequenas |
