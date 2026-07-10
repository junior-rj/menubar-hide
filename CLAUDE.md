# menubar-hide

## O que é
App macOS pra ocultar ícones da menu bar quando ela lota: um separador expande/recolhe os ícones escondidos.

## Tipo
Interno

## Escopo
- App novo em SwiftUI, macOS 13+
- Esconder/mostrar ícones da menu bar com um clique no separador
- Atalho de teclado pra alternar; iniciar com o sistema

## Contexto
- Referência de técnica: https://github.com/dwarvesf/hidden (Hidden Bar, MIT, v1.10 2026-03). Só referência de estudo, o código aqui é novo
- Truque central do Hidden Bar: um NSStatusItem separador cujo comprimento expande pra empurrar os ícones pra fora da tela
- Autostart via SMAppService (padrão já usado no yourlaunch)
- Projeto via XcodeGen (project.yml como fonte de verdade, padrão do updates_devices)
- Seguir a skill ios-swift-guidelines
- Sem prazo definido

## Arquivos importantes
- (será preenchido conforme o projeto avança)

## Regras específicas
- (será preenchido conforme o projeto avança)
