import Foundation

/// Side of the screen the sidebar hides behind.
enum ScreenEdge: String, Codable, CaseIterable {
    case left, right

    var title: String {
        switch self {
        case .left: return "Esquerda"
        case .right: return "Direita"
        }
    }
}
