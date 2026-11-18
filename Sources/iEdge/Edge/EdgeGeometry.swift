import CoreGraphics

// Peça A: funções puras e testáveis da borda (docs/SPEC.md §1.1): qual borda o ponto toca
// (`x <= minX + 1` / `x >= maxX - 2`), se é borda real (nenhuma tela vizinha naquele lado na faixa
// vertical do cursor), exclusão dos cantos e da borda do Dock. Recebem retângulos, não NSScreen.

/// Pure edge geometry, kept free of AppKit so it can be tested with plain rectangles.
enum EdgeGeometry {}
