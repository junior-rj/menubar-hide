# menubar-hide

## O que é
App macOS pra ocultar ícones da menu bar quando ela lota: um separador expande/recolhe os ícones escondidos, com opção de mostrar num painel abaixo da menu bar (resolve o notch).

## Escopo
- App novo em SwiftUI, macOS 14+ (subiu de 13 por causa do ScreenCaptureKit do painel)
- Esconder/mostrar ícones da menu bar com um clique no botão + / − (separador é #)
- Painel abaixo da menu bar com os ícones escondidos (modo alternável no clique-direito)
- Atalho de teclado ⌃⌥H pra alternar; iniciar com o sistema
- Arranjo dos ícones persistente: memoriza a posição de TODOS os ícones e reescreve no launch
- Espaçamento da menu bar ajustável pelo menu (NSStatusItemSpacing/NSStatusItemSelectionPadding)

## Contexto
- Referência de técnica lateral: https://github.com/dwarvesf/hidden (Hidden Bar, MIT). Só referência de estudo, o código aqui é novo
- Referência de técnica do painel: https://github.com/jordanbaird/Ice (Ice Bar, GPL-3.0). Só estudo de técnica, NUNCA copiar código (licença incompatível)
- Truque lateral: NSStatusItem separador com length 10000 empurra os ícones à esquerda dele pra fora da tela. Nunca usar isVisible (perde a posição do autosave)
- Truque do painel: CGWindowList acha os itens fora da tela, ScreenCaptureKit captura as imagens, NSPanel mostra abaixo da menu bar, clique é encaminhado via CGEvent (expande temporário + re-colapsa)
- Permissões do painel: Gravação de Tela (capturar) e Acessibilidade (encaminhar clique). Gravação de Tela exige relançar o app após conceder
- Autostart via SMAppService.mainApp
- Projeto via XcodeGen (project.yml fonte de verdade, .xcodeproj gitignored, rodar `xcodegen` após mudar)
- Repo: https://github.com/junior-rj/menubar-hide (público desde 2026-07-13, MIT, releases com DMG assinado e notarizado)

## Arquivos importantes
- project.yml — definição do projeto (rodar xcodegen após mudar)
- MenubarHide/StatusBarController.swift — botão +/− + separador #, toggle, menu, launch at login, integração do painel
- MenubarHide/HotkeyManager.swift — hotkey global ⌃⌥H via Carbon
- MenubarHide/MenuBarItemScanner.swift — descoberta dos itens escondidos via CGWindowList
- MenubarHide/ItemCapturer.swift — captura via ScreenCaptureKit
- MenubarHide/HiddenItemsPanel.swift — NSPanel + SwiftUI com os ícones
- MenubarHide/ClickForwarder.swift — clique sintético via CGEvent
- MenubarHide/MenuBarArrangement.swift — snapshot e restauração das posições de todos os ícones via CFPreferences
- MenubarHide/MenuBarSpacing.swift — leitura e escrita das duas chaves globais de espaçamento
- MenubarHide/Localizable.xcstrings — String Catalog com toda a UI em EN e pt-BR (InfoPlist.xcstrings traduz o copyright do painel About)
- Release pela skill global `release-macos` (desde 05/09/2026; o wrapper `scripts/release.sh` saiu). Um comando faz build fora do repo, Developer ID, DMG, notarização, staple, instala em /Applications e publica. Config inferida do repo, sem override. Saída `build/MenubarHide-X.Y.Z.dmg` + `build/export/MenubarHide-stapled.app`; perfil de notary `sparrow-notary` do keychain

## Regras específicas
- Pegadinhas do macOS 26 Tahoe (custaram a depuração da v1, não regredir):
  - Menu bar cheia estaciona itens novos fora da tela; as posições preferidas são RE-ASSERTADAS via UserDefaults a cada launch (regravar o valor salvo, nunca sobrescrever com constante: a config de fixo/escondido É a ordem dos ícones em relação ao separador). Padrão 250/265 só no primeiro launch ou quando o par salvo está corrompido (fora de 0..10000 ou ordem trocada: separador deve ficar > toggle)
  - Collapse inicial só depois da menu bar estabilizar: mínimo 500ms (recolher cedo embaralha as posições salvas) + polling do fingerprint (IDs+posições das janelas de status) estável por 3 polls de 2s, teto ~120s. Substituiu a guarda de uptime < 5 min, que media boot e não login (falhava com FileVault/logout) e deixava o app expandido a sessão inteira. Recolher no meio da tempestade de login engole apps que sobem tarde e corrompe as posições salvas DELES (irreversível pelo nosso lado)
  - As janelas dos status items pertencem ao Control Center (owner/pid inúteis); o scanner acha o separador pela forma (janela gigante, o length 10000 vem clampado ~5016)
  - Nenhuma API captura janela fora da tela (SCK dá -3811, legado dá nil); o painel usa flash-expand de 300ms pra capturar
- Arranjo dos ícones (v1.3): a posição de cada ícone mora no domínio de preferências do app DONO dele, chave `NSStatusItem Preferred Position <autosaveName>`, legível e gravável via CFPreferences porque não há sandbox. Isso torna reparável o dano antes tido como irreversível (ícone parqueado fora da tela). Pegadinhas:
  - `CFPreferencesCopyApplicationList` está marcada unavailable no SDK 26; enumerar domínios listando `~/Library/Preferences/*.plist` e ler/gravar via CFPreferences (mantém o cfprefsd coerente, ao contrário de mexer no plist na mão)
  - O AppKit lê a posição preferida só quando o app cria o status item, então restaurar não move nada agora, só no próximo launch do app dono. Dizer isso na UI, não prometer efeito imediato
  - Snapshot SEMPRE antes do collapse e nunca com `isCollapsed` true: recolher estaciona os ícones fora da tela e o macOS autossalva a posição ruim. O flash-expand do painel depende dessa mesma guarda (mexe no length sem passar por expand(), isCollapsed continua true)
  - Merge, nunca replace: valor corrompido é descartado no capture, então substituir esqueceria o último valor bom justo quando ele importa. Domínio cujo plist sumiu (app desinstalado) sai do snapshot
  - Custo medido do capture: 73ms frio, 2ms quente (cfprefsd cacheia). Roda inline na main de propósito, porque o collapse logo depois estragaria o que ele leria
  - Apps sandboxed guardam a chave em `~/Library/Containers/<id>/Data/Library/Preferences/<id>.plist`, e o bundle ID como domínio não enxerga esse arquivo de um processo sem sandbox (confirmado em 05/09/2026 com AirBuddy helper e NordVPN). O domínio desses vira o CAMINHO absoluto do plist, que o CFPreferences aceita como application ID (mesmo mecanismo do `defaults write /caminho.plist`), tudo ainda via cfprefsd
  - `restore` re-filtra o que o capture garantiu (só chave com prefixo `NSStatusItem Preferred Position`, nunca `.GlobalPreferences`, caminho só dentro de `~/Library/Containers`): o snapshot mora no plist do próprio app, gravável por qualquer processo do usuário. Com nenhum domínio legível o merge devolve o salvo intacto, senão apagaria o único backup antes do collapse
  - `kCGWindowName` das janelas de status entrega o autosaveName (`Item-0` pros apps que não nomeiam), mas o design não depende disso: indexa por (domínio, chave), então a ambiguidade dos `Item-0` não atrapalha
- Espaçamento: `NSStatusItemSpacing` e `NSStatusItemSelectionPadding` no domínio global (`kCFPreferencesAnyApplication`, o mesmo que `defaults write -g`). Ler por CFPreferences, não por UserDefaults.standard, que enxergaria também um valor do próprio app. Só vale após logoff ou reinício, porque cada app lê no launch
- Localização (v1.4): toda string de UI passa por `String(localized:)` e vive no `Localizable.xcstrings` (EN fonte, pt-BR traduzido). Nunca deixar literal solto no código. Pegadinhas:
  - O XcodeGen não infere build phase de `.xcstrings`: o `project.yml` exclui `**/*.xcstrings` do path de sources e adiciona cada catálogo com `buildPhase: resources`. Sem isso o catálogo não vira `.lproj` no bundle
  - A chave é o texto em inglês COM os especificadores que a interpolação gera (`%lld` pra Int, `%@` pra String). Chave que não bate sai em inglês cru no pt-BR, sem erro de build
  - Plural mora no catálogo (`variations.plural`), nunca em ternário `"s"` no código: em português muda número e concordância
  - `en.lproj` sai sem `Localizable.strings` de propósito (na língua fonte a chave é o valor); só o `stringsdict` do plural aparece
  - Conferir cobertura comparando as chaves extraídas pelo compilador (`*.stringsdata` no DerivedData, campo `tables`) com as do catálogo: os dois conjuntos têm que ser idênticos
- Ao sair (`applicationWillTerminate`) o app expande sem snapshot: sair recolhido deixaria os ícones parqueados e o dono autossalvaria isso; o próximo launch repara, uma desinstalação não
- Submenu com item desabilitado precisa de `autoenablesItems = false`, senão o AppKit reabilita tudo que tem target respondendo
- Painel clicável exige as duas subclasses em HiddenItemsPanel.swift: NSPanel com canBecomeKey=true (borderless recusa key e mata botões e Esc) + NSHostingView com acceptsFirstMouse (senão o 1º clique só foca a janela). Manter .nonactivatingPanel (app LSUIElement não ativa)
- Clique sintético precisa de mouseEventClickState=1 (clickCount 0 é ignorado pela maioria dos status items); antes de postar, validar que o frame alvo está na faixa da menu bar de algum display (anti-spoofing de janela no status layer; display à esquerda do principal tem X negativo válido)
- Qualquer collapse/expand desarma o auto-collapse pendente e cancela o poller inicial (stateWillChange) — monitor obsoleto dispararia no mouseUp sintético do clique seguinte
- Option-clique no botão sempre alterna lateral (necessário pra reorganizar ícones com cmd-drag mesmo no modo painel)
- Hardened runtime ligado (exigência da notarização); sandbox continua desligado
- Trocar a assinatura do app instalado (dev ↔ Developer ID) invalida as permissões TCC; reconceder Gravação de Tela e Acessibilidade
- Build: `xcodegen && xcodebuild -project MenubarHide.xcodeproj -scheme MenubarHide -configuration Debug build`
- Testes: `xcodebuild -project MenubarHide.xcodeproj -scheme MenubarHide -destination 'platform=macOS' test` (Swift Testing, target MenubarHideTests; o AppDelegate pula a inicialização sob XCTest pra não mexer na menu bar real)
- **Entrega não termina no build verde, nem no DMG notarizado.** Mudança de código concluída são: (1) bump de `MARKETING_VERSION` e `CURRENT_PROJECT_VERSION` no project.yml (patch pra correção interna, minor pra feature visível), (2) `xcodebuild ... test` verde, (3) commit em Conventional Commits, direto na main (padrão do histórico deste repo, não abrir branch pra release), (4) release pela skill `release-macos`, que assina, notariza, grampeia, instala em /Applications e publica num comando. Entregar pela metade e listar o resto como pendência não é entrega. As notas do release vão em INGLÊS, no estilo das anteriores (abertura, bullets, fechamento "Signed with Developer ID and notarized by Apple. Requires macOS 14+."); a v1.4.0 ficou taggeada sem release por esquecer o passo e a v1.4.1 saiu em português por engano (corrigido em 2026-08-27). A skill instala com a MESMA assinatura Developer ID, o que preserva o TCC.
- Repo público: documento interno, nota de processo e relatório em português não entram no tree. Nota de trabalho fica no `CLAUDE.local.md` (carregado junto com este arquivo, ignorado pelo git); relatório vai pro workspace. O que não deve subir entra no `.gitignore` no momento da decisão
