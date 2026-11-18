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

## Ajustes

O ícone `sidebar.squares.left` fica na barra de menus (meio apagado quando o iEdge está pausado).
**Clique** abre os Ajustes num painel de vidro logo abaixo dele; Esc ou um clique fora fecha.
**Clique direito** abre o menu rápido: Pausar/Retomar, Mostrar barra esquerda, Mostrar barra direita,
Ajustes…, Sair. Tudo salva na hora, sem botão Salvar.

| Aba | O que tem |
| --- | --- |
| **Itens** | Os itens da barra, na ordem: interruptor para cada um, arrastar (ou ↑↓ ao passar o cursor) para reordenar. **Adicionar atalho** abre um formulário: App (escolhido em /Applications, o nome vem do app), Link (endereço, domínio ou caminho `~/…`), Atalho (do app Atalhos, com a lista dos seus) ou Comando (`/bin/zsh -lc`), com nome e símbolo SF com prévia. Os atalhos criados podem ser editados e removidos; os embutidos só desligam. **Restaurar padrão** volta os embutidos à ordem original, ligados, e mantém os seus atalhos no fim, desligados. |
| **Bordas** | Borda esquerda e direita (com aviso quando o Dock está naquele lado e a opção de abrir mesmo assim), tempo na borda, empurrão, ampliação, tamanho dos itens, nome do item, toque no trackpad e os botões **Testar à esquerda/direita**. |
| **Capturas** | Destino (Arquivo, Clipboard ou Ambos), pasta (escolher uma ou usar a do sistema), som, prévia e o estado da permissão de Gravação de Tela. |
| **Clipboard** | Guardar o histórico, tamanho (20–200), colar automaticamente, apps excluídos (gerenciadores de senha por padrão) e **Limpar histórico** (as fixadas ficam). |
| **Geral** | Abrir ao iniciar sessão, pausar, permissões, versão e Sair. |

## Permissões

O iEdge pede só o que cada função precisa, e funciona sem elas (a função correspondente fica de fora).
Os Ajustes mostram o estado de cada uma e releem enquanto estão abertos, então dá para conceder nos
Ajustes do Sistema e voltar.

| Permissão | O que libera | Como conceder |
| --- | --- | --- |
| **Gravação de Tela** | Capturas de tela inteira, área e janela. | Ajustes › Capturas ou Geral › **Conceder**. Na primeira vez o macOS mostra o pedido; depois o botão vira **Abrir Ajustes** e leva a Ajustes do Sistema › Privacidade e Segurança › Gravação de Tela e Áudio do Sistema. Ligue o iEdge e reabra o app se o macOS pedir. |
| **Acessibilidade** | Colar automaticamente (⌘V no app da frente) ao escolher uma entrada do clipboard. | Ao ligar **Colar automaticamente**, ou em Geral › **Conceder**. Leva a Privacidade e Segurança › Acessibilidade; ligue o iEdge. |

Detectar a borda não pede permissão nenhuma (eventos de movimento do mouse não precisam de
Acessibilidade). **Abrir ao iniciar sessão** usa `SMAppService` e só funciona com o `iEdge.app` em
/Applications; fora disso os Ajustes dizem o que fazer. Se você desligar o iEdge em Ajustes do Sistema ›
Geral › Itens de Início, os Ajustes mostram isso com um botão para reabrir esse painel.

Como o `.app` é assinado ad-hoc, cada novo build pode ser visto pelo macOS como outro app: se uma
permissão concedida "sumir" depois de recompilar, remova o iEdge da lista e conceda de novo.

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
