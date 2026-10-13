# ADR 0004 · Diário da empresa só no app de celular; plataformas do app de campo

- **Estado:** aceito, com pontos a validar (questões 25 a 29)
- **Data:** 13/10/2026
- **Decisor:** Gabriel Onezio Ferreira

## Contexto

A prévia de desktop trazia a tela "Diário no celular", da empresa contratada. O autor decidiu que essa interface não pertence ao executável de desktop: ela só existe no app de celular. Ele também listou onde o app de celular tem que chegar: Android (APK), Apple, HarmonyOS, KaiOS, GrapheneOS e LineageOS. Até aqui a documentação falava em "Android + PWA" e tratava o iOS como opcional (questão 10).

## Decisão

1. **O diário de obras da empresa é interface só de celular.** Lançar clima, efetivo, serviços, fotos e áudio e fechar o dia acontece no app de campo. O desktop não tem essa tela, nem a prévia.
2. **O fiscal continua com a visão dele no desktop** (módulo P07): validar, devolver e registrar instruções sobre o diário que a empresa fechou.
3. **Plataformas-alvo do app de campo:** Android, GrapheneOS, LineageOS, HarmonyOS, Apple (iPhone e iPad) e KaiOS. O que cada uma exige está em `03-arquitetura.md` §5.1.
4. **O app de campo não depende de serviços do Google.** GrapheneOS, LineageOS e HarmonyOS não trazem o Google Play Services; o que o app precisar (localização, notificação, mapa, atualização) usa o que o sistema oferece sem ele.

"Apple" foi lido aqui como iOS e iPadOS (iPhone e iPad), não macOS.

## O que a lista de plataformas implica

- **Um APK cobre quatro delas:** Android, GrapheneOS, LineageOS e HarmonyOS até a versão 4, que roda apps Android.
- **Apple é um segundo alvo do mesmo código** (Tauri 2 compila para iOS), mas o build exige macOS com Xcode e conta de desenvolvedor, e a distribuição passa pela Apple.
- **HarmonyOS NEXT (versão 5 em diante) não roda APK.** Exige um app próprio para a plataforma. Não há plano para isso ainda (questão 26).
- **KaiOS não roda APK nem Tauri.** É sistema de celular de teclas, com apps web, tela pequena e pouca memória. Atendê-lo significa um cliente web reduzido, feito à parte, e não está decidido o que ele consegue fazer (questão 28).

## Alternativas descartadas

| Alternativa | Por que não |
|---|---|
| Manter o diário da empresa também no desktop | O diário é feito na obra, com câmera e GPS do aparelho; a foto de evidência só vale se vier da câmera do app |
| Só Android, com PWA para o resto | O autor quer o app nas plataformas listadas, inclusive Apple |
| Usar serviços do Google onde existirem | Criaria dois comportamentos e deixaria três plataformas da lista sem função |

## Consequências

- A tela saiu da prévia de desktop (`apps/desktop/previa`). O desenho dela continua no canvas de telas, como referência para o app de celular.
- A questão 10 (iOS) está respondida: entra.
- `apps/mobile` ainda não existe. Nenhuma das plataformas tem código nem foi testada em aparelho.
- A regra da foto de evidência (câmera do app, hora, GPS com precisão, hash) vale em toda plataforma. Onde não for possível cumpri-la, a plataforma não gera evidência; isso pesa sobretudo no KaiOS.
- Distribuir fora da loja do Google passa a ser requisito, não exceção (questão 29).
- Fica em aberto se a empresa consulta os diários fechados pelo navegador (questão 25).
