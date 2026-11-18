# iEdge — especificação

App nativo do macOS (Swift + SwiftUI + AppKit, SwiftPM, sem Xcode project) que esconde uma
**barra lateral nas bordas da tela**. Encostar o cursor na borda esquerda ou direita faz a barra
**saltar da borda** com mola; correr o cursor ao longo dela **amplia o item mais próximo** (lupa
vertical, como a do Dock); clicar executa. Os itens são capturas de tela, a área de transferência
(clipboard) e atalhos que o usuário configura.

Visual: o mesmo do **iSessions** (`~/iSessions`): vidro Liquid Glass no macOS 26
(`NSGlassEffectView`) e `NSVisualEffectView(.popover)` antes disso, cantos contínuos, faixas
`primary.opacity(0.05)` sem borda, cores do sistema, SF Symbols, controles nativos, aparência da
Central de Controle. Textos da interface em **pt-BR**. Código e comentários em inglês, como no iSessions.

- macOS 14+ (`LSMinimumSystemVersion 14.0`), Swift 5 language mode, `swift-tools-version:5.9`.
- App de barra de menus: `LSUIElement`, `NSApp.setActivationPolicy(.accessory)`, sem Dock.
- Bundle id `br.dinsights.iedge`, nome `iEdge`, copyright `© 2026 dinsights`.
- Sem dependências externas. Sem rede.

---

## 1. Experiência

### 1.1 Gatilho na borda

- Vale para a tela onde o cursor está, e só para uma borda **de verdade**: se outra tela encosta
  naquele lado na faixa vertical do cursor (o cursor passaria para ela), aquela borda não dispara.
- A barra abre quando o cursor fica na borda (`x <= minX + 1` ou `x >= maxX - 2`) e:
  - **permanece** lá por `dwellMs` (padrão 150 ms), **ou**
  - **empurra** a borda: a soma dos `deltaX` na direção da borda, com o cursor já parado nela,
    passa de `pushDistance` (padrão 14 pt). É o "triscar".
- Não dispara:
  - nos `cornerExclusion` pt de cima e de baixo (padrão 32 pt; protege os cantos ativos e a barra de menus);
  - com botão do mouse pressionado (arrastando janela, selecionando texto);
  - na borda em que o Dock está (`UserDefaults(suiteName: "com.apple.dock")` chave `orientation` =
    `left`/`right`); os Ajustes mostram o aviso e deixam forçar;
  - com o app pausado ou a borda desligada nos Ajustes.
- Depois de fechar, a mesma borda só dispara de novo quando o cursor sair dela (sem reabrir em loop).
- Detecção por `NSEvent.addGlobalMonitorForEvents` + `addLocalMonitorForEvents` de `mouseMoved`
  (eventos de mouse não pedem Acessibilidade). Se precisar de polling, só perto da borda e com `leeway`.
  Nada de timer contínuo a 60 Hz com a barra fechada.

### 1.2 A barra

- Janela própria: `NSPanel` sem borda, `.nonactivatingPanel` (o app da frente **continua ativo**,
  então colar e capturar funcionam nele), nível `.statusBar`, `collectionBehavior`
  `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`, sem sombra de janela,
  `acceptsFirstMouse` no conteúdo.
- Vidro como o `StatusPanel` do iSessions (janela maior que o vidro por margens, para a sombra do
  vidro e para a ampliação vazarem sem corte).
- Cápsula vertical flutuando **8 pt** afastada da borda, centrada na altura do cursor no disparo e
  presa dentro de `visibleFrame`. Raio 22, contínuo. Largura = tile + 2 × 10 pt.
- Itens: **tiles circulares de 44 pt** (`tileSize`), fundo `primary.opacity(0.08)`, SF Symbol
  18 pt semibold. Item selecionado: fundo `accentColor`, símbolo branco (o "ligado" da Central de
  Controle). Atalho de app usa o ícone do app.
- **Lupa**: com a barra aberta, um display link (só enquanto ela está visível) lê `NSEvent.mouseLocation`
  e atualiza a ampliação. Escala de cada tile pela distância vertical `d` entre o cursor e o centro
  do tile: `1 + (m - 1) * exp(-d² / (2σ²))`, `m = magnification` (padrão 1.6), `σ ≈ 1.2 × tileSize`.
  O tile cresce **para dentro da tela** (ancorado no lado da borda) e empurra os vizinhos na vertical,
  como no Dock. Os tiles ampliados podem passar da cápsula de vidro. O cálculo fica numa função pura testável.
- Item selecionado = o mais próximo do cursor enquanto o cursor está sobre a barra (com folga de
  ~24 pt para dentro). Ao lado dele, para dentro da tela, aparece o **rótulo** numa cápsula de vidro
  pequena (`showLabels`). Ao trocar de item, toque háptico leve no trackpad
  (`NSHapticFeedbackManager`, `.alignment`) se `haptics`.
- **Salto ao abrir**: a cápsula entra de fora da tela com mola (`response ≈ 0.38`, `damping ≈ 0.72`,
  passa ~6 pt do ponto e volta), com escala 0.92 → 1 ancorada na borda e opacidade 0 → 1. Os tiles
  entram em cascata a partir do mais próximo do cursor (15 ms entre cada), cada um com a própria mola.
  **Ao fechar**: sai para a borda em ~0.18 s, ease-in.
- Fecha quando: o cursor se afasta mais de 40 pt do vidro (com 250 ms de tolerância), clique fora,
  depois de executar um item, ou pelo menu. Clique na margem transparente conta como clique fora.
- Clique (mouseDown) num tile executa o item. Antes de executar qualquer item que não seja o
  clipboard, a barra **fecha primeiro** (as capturas não podem pegar a barra).

### 1.3 Clipboard (área de transferência)

- O tile "Área de transferência" abre um **painel lateral** (flyout) ao parar 250 ms sobre ele ou
  ao clicar: outro vidro, filho da barra (`addChildWindow`), colado ao lado de dentro da cápsula,
  alinhado ao tile, que salta do tile com mola (escala 0.85 → 1 ancorada no tile, opacidade).
- Largura 300 pt, até 10 entradas visíveis (rola se houver mais), fixadas primeiro.
  Cabeçalho "Área de transferência", contagem e "Limpar". Cada linha (raio 10, fundo da faixa no hover):
  texto em até 2 linhas, ou miniatura 40 pt para imagem, ou ícone + nome para arquivo; ícone pequeno
  do app de origem; tempo relativo ("agora", "há 2 min"); botão de fixar no hover. A linha sob o
  cursor amplia de leve (1.0 → 1.04) com mola.
- Clicar numa entrada: copia para o pasteboard, fecha a barra, e se `autoPaste` estiver ligado **e**
  o app tiver Acessibilidade (`AXIsProcessTrusted()`), manda ⌘V ao app da frente (CGEvent) ~120 ms depois.
- Monitor: timer de 0.5 s comparando `NSPasteboard.general.changeCount`. Guarda texto, imagem (PNG
  em arquivo + miniatura), URLs de arquivo e URL. Mudanças feitas pelo próprio iEdge não entram.
- Privacidade: ignora pasteboard com `org.nspasteboard.ConcealedType`, `org.nspasteboard.TransientType`
  ou `org.nspasteboard.AutoGeneratedType`, e cópias vindas de apps excluídos (padrão: 1Password,
  Bitwarden, Senhas e Acesso às Chaves da Apple). Texto acima de 200 KB e imagem acima de 20 MB não entram.
- Conteúdo igual a uma entrada existente sobe para o topo (sem duplicar). Limite `maxEntries`
  (padrão 50); fixadas não saem pelo limite.
- Persistência (se `persist`): `~/Library/Application Support/iEdge/clipboard.json` e imagens em
  `clipboard/`. "Limpar" apaga as não fixadas e os arquivos delas.

### 1.4 Capturas de tela

- Usa `/usr/sbin/screencapture` via `Process` com argumentos em array (nunca shell):
  - **Tela inteira**: a tela onde a barra estava (`-D n`, `n` = posição do `CGDirectDisplayID` em
    `CGGetActiveDisplayList` + 1). Espera ~150 ms depois de fechar a barra.
  - **Área**: `-i -s`. **Janela**: `-i -w`. Esc na seleção = cancelado, sem arquivo, sem aviso.
  - **Ferramenta de captura**: abre `/System/Applications/Utilities/Screenshot.app` (⌘⇧5, gravar tela).
- Destino (`destination`): `file`, `clipboard` ou `both` (padrão). Arquivo na pasta de capturas do
  sistema (`com.apple.screencapture` `location`, senão `~/Desktop`) ou na pasta escolhida, nome
  `Captura de Tela 2026-11-18 às 14.05.33.png`. Em `both`, depois de salvar copia a imagem para o
  pasteboard (e ela entra no histórico do clipboard).
- Som: `-x` quando `playSound` está desligado.
- Permissão de Gravação de Tela: `CGPreflightScreenCaptureAccess()`; se faltar, `CGRequestScreenCaptureAccess()`
  e um aviso com botão para `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`.
- **Prévia** (`showToast`): cartão de vidro com a miniatura que salta da mesma borda perto do fim
  da tela, some em 3 s (pausa com o cursor em cima). Clique abre no Pré-Visualização; arrastar o
  cartão arrasta o arquivo.

### 1.5 Atalhos personalizados

Tipos de item que o usuário cria nos Ajustes:

| Tipo | Ação | Ícone |
| --- | --- | --- |
| Abrir app | `NSWorkspace.openApplication(at:)` | ícone do app |
| Abrir link/arquivo | `NSWorkspace.open(URL)` | `link` |
| Atalho (app Atalhos) | `/usr/bin/shortcuts run <nome>` | `square.2.layers.3d` |
| Comando | `/bin/zsh -lc <comando>` | `terminal` |

Falha de execução vira um aviso curto (mesmo estilo da prévia), nunca um alerta modal.

### 1.6 Barra de menus e Ajustes

- Ícone SF `sidebar.squares.left` na barra de menus. Clique esquerdo abre os **Ajustes** num painel
  de vidro sob o ícone (o mesmo padrão do iSessions: `StatusPanel`, largura 400). Clique direito:
  menu rápido com Pausar/Retomar, Mostrar barra esquerda, Mostrar barra direita, Ajustes…, Sair.
- Abas (segmented nativo): **Itens · Bordas · Capturas · Clipboard · Geral**.
  - **Itens**: lista dos itens com ícone, nome, interruptor e reordenar (arrastar ou ↑↓);
    "Adicionar atalho" (app via `NSOpenPanel`, link, Atalho, comando) com nome e símbolo SF; editar e
    remover os criados. Os embutidos podem ser desligados, não removidos. "Restaurar padrão".
  - **Bordas**: esquerda/direita; sensibilidade (tempo de espera 80–400 ms); empurrão; ampliação
    (1.0–2.0); tamanho do tile (36–56); rótulos; háptico; aviso do Dock; botões "Testar à esquerda/direita".
  - **Capturas**: destino, pasta (escolher/padrão do sistema), som, prévia; estado da permissão de Gravação de Tela.
  - **Clipboard**: guardar histórico, tamanho (20–200), colar automaticamente (pede Acessibilidade
    com `AXIsProcessTrustedWithOptions` ao ligar), apps excluídos (adicionar app / remover), Limpar histórico.
  - **Geral**: abrir ao iniciar sessão (`SMAppService.mainApp`), pausar, permissões (Gravação de Tela,
    Acessibilidade) com estado e botão, versão, Sair.
- Os Ajustes salvam na hora (sem botão Salvar).

## 2. Dados

`~/Library/Application Support/iEdge/`: `settings.json`, `clipboard.json`, `clipboard/` (imagens).

```swift
enum ScreenEdge: String, Codable, CaseIterable { case left, right }

enum ActionKind: Codable, Hashable {
    case screenshotFull, screenshotArea, screenshotWindow, captureTool, clipboard
    case openApp(path: String)
    case openURL(String)
    case shortcut(name: String)
    case shell(command: String)
}

struct SidebarItem: Identifiable, Codable, Hashable {
    var id: UUID
    var kind: ActionKind
    var title: String
    var symbol: String        // SF Symbol (ignored for openApp, which shows the app icon)
    var enabled: Bool
    var isBuiltIn: Bool
}

struct AppSettings: Codable, Equatable {
    var edges: Set<ScreenEdge> = [.left, .right]
    var forceEdgeWithDock = false
    var dwellMs = 150
    var pushDistance = 14.0
    var cornerExclusion = 32.0
    var magnification = 1.6
    var tileSize = 44.0
    var showLabels = true
    var haptics = true
    var items: [SidebarItem] = SidebarItem.defaults
    var screenshot = ScreenshotSettings()      // destination, folderPath?, playSound, showToast
    var clipboard = ClipboardSettings()        // persist, maxEntries, autoPaste, excludedBundleIDs
    var launchAtLogin = false
    var paused = false
}
```

Decodificação tolerante: chave nova ausente usa o padrão (`decodeIfPresent`), para versões futuras
não perderem os ajustes.

Itens padrão, nesta ordem: Tela inteira (`display`), Área (`rectangle.dashed`), Janela
(`macwindow`), Área de transferência (`doc.on.clipboard`), Ferramenta de captura (`record.circle`).

## 3. Código

```
Package.swift
Resources/Info.plist
scripts/build-app.sh  scripts/run-dev.sh
Sources/iEdge/
  App/        main.swift, AppDelegate.swift (liga tudo), LaunchOptions.swift (flags de dev)
  Core/       Theme.swift, GlassPanel.swift (porta do StatusPanel), AppPaths.swift, Log.swift,
              Snapshot.swift (modo --snapshot)
  Models/     ScreenEdge, ActionKind, SidebarItem, AppSettings (+ ScreenshotSettings, ClipboardSettings),
              ClipboardEntry
  Stores/     SettingsStore.swift
  Edge/       EdgeMonitor.swift, EdgeGeometry.swift (funções puras)              ← peça A
  Sidebar/    SidebarController, SidebarPanel, SidebarView, Magnification (pura),
              ClipboardFlyout                                                    ← peça A
  Actions/    ActionRunner, ScreenshotService, CaptureToast, CustomActions       ← peça B
  Clipboard/  ClipboardMonitor, ClipboardStore, ClipboardListView                ← peça B
  MenuBar/    StatusItemController                                               ← peça C
  Settings/   SettingsRootView e uma view por aba, PermissionCenter, LoginItem   ← peça C
Tests/iEdgeTests/
```

### 3.1 Contratos entre as peças

A fundação cria estes tipos com implementação mínima que compila e roda; cada peça troca o
recheio dos seus sem mudar a assinatura (pode **acrescentar** membros).

```swift
@MainActor final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings          // didSet grava settings.json (com debounce)
    init(demo: Bool)                              // demo: não lê nem grava disco
}

struct ActionContext { var edge: ScreenEdge; var screen: NSScreen; var anchor: CGRect }  // anchor = tile na tela

@MainActor protocol ActionPerforming: AnyObject {
    func perform(_ item: SidebarItem, context: ActionContext)     // chamado com a barra já fechada
}

@MainActor final class ClipboardStore: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry]
    init(settings: SettingsStore, demo: Bool)
    func start(); func stop()
    func copy(_ entry: ClipboardEntry, paste: Bool)
    func togglePin(_ entry: ClipboardEntry); func remove(_ entry: ClipboardEntry); func clear()
}

struct ClipboardListView: View {                  // a peça A embute no flyout
    @ObservedObject var store: ClipboardStore
    var onPick: (ClipboardEntry) -> Void
}

@MainActor final class SidebarController {
    init(settings: SettingsStore, clipboard: ClipboardStore, actions: ActionPerforming)
    var isVisible: Bool { get }
    func show(edge: ScreenEdge, on screen: NSScreen, atY y: CGFloat)
    func hide(animated: Bool)
}

@MainActor final class EdgeMonitor {
    init(settings: SettingsStore, isSidebarVisible: @escaping () -> Bool)
    var onTrigger: ((ScreenEdge, NSScreen, CGFloat) -> Void)?   // borda, tela, y do cursor
    func start(); func stop()
}

@MainActor final class StatusItemController {
    init(settings: SettingsStore, sidebar: SidebarController, clipboard: ClipboardStore)
}
```

`AppDelegate`: `SettingsStore` → `ClipboardStore` → `ActionRunner` (implementa `ActionPerforming`)
→ `SidebarController` → `EdgeMonitor` (`onTrigger` chama `sidebar.show`) → `StatusItemController`.

### 3.2 Flags de desenvolvimento

- `--demo`: ajustes e clipboard em memória, com 8 entradas de exemplo (texto curto, texto longo,
  imagem gerada, arquivo, link); nada lido nem gravado.
- `--show left|right`: abre a barra nessa borda da tela principal, na altura do meio, ao iniciar.
  `--pin`: não fecha sozinha. `--hover 0.0…1.0`: simula o cursor nessa fração da altura da barra
  (para ver a lupa). `--flyout`: abre o clipboard junto.
- `--settings [itens|bordas|capturas|clipboard|geral]`: abre os Ajustes nessa aba.
- `--frame-file <path>`: grava o retângulo na tela dos painéis abertos (`x y w h` por linha, em
  coordenadas de `screencapture -R`, origem no canto superior esquerdo) 1.5 s depois de abrir.
- `--snapshot <nome> --out <arquivo.png> [--scheme light|dark]`: renderiza uma view SwiftUI com
  `ImageRenderer` (escala 2), **sem abrir janela nem ícone**, grava o PNG e sai. Como o vidro não
  renderiza fora da janela, o snapshot desenha um fundo cinza translúcido no lugar.
  `--snapshot list` imprime os nomes. Catálogo dividido por peça, cada uma no seu arquivo:
  `Sidebar/Snapshots+Sidebar.swift`, `Clipboard/Snapshots+Clipboard.swift`,
  `Settings/Snapshots+Settings.swift` (a fundação cria os três com um exemplo cada).

## 4. Qualidade

- `swift build` sem warnings novos; `swift test` verde. Testes para as funções puras: geometria da
  borda (borda real × tela vizinha, cantos, Dock), lupa (escala, deslocamento, item selecionado),
  dedup/limite/fixadas do clipboard, nome do arquivo de captura, `AppSettings` (ida e volta e JSON antigo
  sem chaves novas).
- Concorrência: tipos de UI em `@MainActor`; `main.swift` com `MainActor.assumeIsolated`, como no iSessions.
- Sem `print` em produção: `Logger(subsystem: "br.dinsights.iedge", category: ...)`.
- Nada de força-desembrulho em dado externo (pasteboard, JSON, `Process`).
- Comentários só quando explicam o porquê.
