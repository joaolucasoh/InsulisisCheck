import Foundation

enum Caregiver: String, CaseIterable, Identifiable, Hashable, Sendable {
    case joaoLucas
    case sheila
    case naoInformado

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .joaoLucas: "João Lucas"
        case .sheila: "Sheila"
        case .naoInformado: "Não informado"
        }
    }
}
