# iEdge

Barra lateral escondida nas bordas da tela do macOS. Encoste o cursor na borda esquerda ou direita
e ela salta com os seus atalhos: capturas de tela (tela inteira, área, janela), área de
transferência com histórico e atalhos que você define (apps, links, Atalhos, comandos). Correr o
cursor pela barra amplia o item mais próximo, como no Dock.

Mesmo visual do iSessions (vidro da Central de Controle). A especificação está em
[docs/SPEC.md](docs/SPEC.md).

Requer macOS 14+ e as ferramentas de linha de comando do Xcode (Swift 5.9+). Sem dependências.

## Rodar

```bash
swift build
scripts/run-dev.sh            # = swift run iEdge (o ícone aparece na barra de menus)
scripts/run-dev.sh --demo     # dados de exemplo, nada lido nem gravado
```

## Testar

```bash
swift test
```

## Gerar o .app

```bash
bash scripts/build-app.sh     # build/iEdge.app (release, assinatura ad-hoc)
open build/iEdge.app
```

Permissões (Gravação de Tela, Acessibilidade) e "abrir ao iniciar sessão" só se comportam direito
a partir do `.app`.

## Flags de desenvolvimento

| Flag | Efeito |
| --- | --- |
| `--demo` | ajustes e clipboard em memória, com entradas de exemplo |
| `--show left\|right` | abre a barra nessa borda da tela principal ao iniciar |
| `--pin` | a barra não fecha sozinha |
| `--hover 0.0…1.0` | simula o cursor nessa fração da altura da barra (lupa) |
| `--flyout` | abre o painel do clipboard junto com a barra |
| `--settings [itens\|bordas\|capturas\|clipboard\|geral]` | abre os Ajustes nessa aba |
| `--frame-file <arquivo>` | grava `x y w h` de cada painel aberto (coordenadas do `screencapture -R`) |
| `--snapshot <nome> --out <arquivo.png> [--scheme light\|dark]` | renderiza uma view em PNG e sai, sem abrir janela |
| `--snapshot list` | lista os snapshots disponíveis |

Exemplos:

```bash
.build/debug/iEdge --snapshot sidebar --out /tmp/sidebar.png --demo
.build/debug/iEdge --snapshot clipboard --out /tmp/clip.png --scheme dark
scripts/run-dev.sh --demo --show left --pin --flyout --frame-file /tmp/frames.txt
```

O vidro não renderiza fora de uma janela; no snapshot ele vira um fundo cinza translúcido. Os
controles nativos (segmented, toggle, slider, botões, ScrollView) também não, e por isso as views usam
`.snapshotStandIn { … }` e `LiveScrollView` (veja `Sources/iEdge/Core/SnapshotSupport.swift`).
