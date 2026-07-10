# menubar-hide

## O que é
App macOS pra ocultar ícones da menu bar quando ela lota: um separador expande/recolhe os ícones escondidos, com opção de mostrar num painel abaixo da menu bar (resolve o notch).

## Tipo
Interno

## Escopo
- App novo em SwiftUI, macOS 14+ (subiu de 13 por causa do ScreenCaptureKit do painel)
- Esconder/mostrar ícones da menu bar com um clique no chevron
- Painel abaixo da menu bar com os ícones escondidos (modo alternável no clique-direito)
- Atalho de teclado ⌃⌥H pra alternar; iniciar com o sistema

## Contexto
- Referência de técnica lateral: https://github.com/dwarvesf/hidden (Hidden Bar, MIT). Só referência de estudo, o código aqui é novo
- Referência de técnica do painel: https://github.com/jordanbaird/Ice (Ice Bar, GPL-3.0). Só estudo de técnica, NUNCA copiar código (licença incompatível)
- Truque lateral: NSStatusItem separador com length 10000 empurra os ícones à esquerda dele pra fora da tela. Nunca usar isVisible (perde a posição do autosave)
- Truque do painel: CGWindowList acha os itens fora da tela, ScreenCaptureKit captura as imagens, NSPanel mostra abaixo da menu bar, clique é encaminhado via CGEvent (expande temporário + re-colapsa)
- Permissões do painel: Gravação de Tela (capturar) e Acessibilidade (encaminhar clique). Gravação de Tela exige relançar o app após conceder
- Autostart via SMAppService.mainApp (padrão do yourlaunch com .mainApp no lugar de .daemon)
- Projeto via XcodeGen (project.yml fonte de verdade, .xcodeproj gitignored, rodar `xcodegen` após mudar)
- Repo: https://github.com/junior-rj/menubar-hide (privado)
- Seguir a skill ios-swift-guidelines
- Sem prazo definido

## Arquivos importantes
- project.yml — definição do projeto (rodar xcodegen após mudar)
- MenubarHide/StatusBarController.swift — chevron + separador, toggle, menu, launch at login, integração do painel
- MenubarHide/HotkeyManager.swift — hotkey global ⌃⌥H via Carbon
- MenubarHide/MenuBarItemScanner.swift — descoberta dos itens escondidos via CGWindowList
- MenubarHide/ItemCapturer.swift — captura via ScreenCaptureKit
- MenubarHide/HiddenItemsPanel.swift — NSPanel + SwiftUI com os ícones
- MenubarHide/ClickForwarder.swift — clique sintético via CGEvent

## Regras específicas
- Ordem de criação dos NSStatusItem só vale no primeiro launch; se as posições bagunçarem no dev: `defaults delete com.sparrow.menubarhide`
- Option-clique no chevron sempre alterna lateral (necessário pra reorganizar ícones com cmd-drag mesmo no modo painel)
- Build: `xcodegen && xcodebuild -project MenubarHide.xcodeproj -scheme MenubarHide -configuration Debug build`
