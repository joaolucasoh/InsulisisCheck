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

    static var manualEntryOptions: [Caregiver] {
        [.joaoLucas, .sheila]
    }

    static func fromDisplayName(_ name: String) -> Caregiver {
        let normalizedName = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        return manualEntryOptions.first { caregiver in
            caregiver.displayName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) == normalizedName
        } ?? .joaoLucas
    }
}
