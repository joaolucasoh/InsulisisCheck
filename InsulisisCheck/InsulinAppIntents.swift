import AppIntents
import Foundation

extension InsulinPeriod: AppEnum {
    nonisolated static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Período")

    nonisolated static let caseDisplayRepresentations: [InsulinPeriod: DisplayRepresentation] = [
        .morning: DisplayRepresentation(title: "Manhã"),
        .night: DisplayRepresentation(title: "Noite")
    ]
}

extension Caregiver: AppEnum {
    nonisolated static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Pessoa")

    nonisolated static let caseDisplayRepresentations: [Caregiver: DisplayRepresentation] = [
        .joaoLucas: DisplayRepresentation(title: "João Lucas"),
        .sheila: DisplayRepresentation(title: "Sheila"),
        .naoInformado: DisplayRepresentation(title: "Não informado")
    ]
}

struct MarkInsulinIntent: AppIntent {
    static var title: LocalizedStringResource = "Registrar insulina da Isis"
    static var description = IntentDescription("Registra que a insulina da Isis foi aplicada no período informado.")
    static var openAppWhenRun = true

    @Parameter(title: "Período")
    var period: InsulinPeriod

    @Parameter(title: "Quem aplicou")
    var caregiver: Caregiver

    @Parameter(title: "Unidades")
    var units: Double

    init() {
        period = .morning
        caregiver = .joaoLucas
        units = DoseEntry.defaultUnits
    }

    init(period: InsulinPeriod, caregiver: Caregiver, units: Double = DoseEntry.defaultUnits) {
        self.period = period
        self.caregiver = caregiver
        self.units = units
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Registrar \(\.$period) para Isis por \(\.$caregiver)") {
            \.$units
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        DoseStore.shared.record(period: period, caregiver: caregiver.displayName, units: units)
        return .result(dialog: "Insulisis da \(period.spokenTitle) ok, aplicada por \(caregiver.displayName).")
    }
}

struct InsulisisShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MarkInsulinIntent(period: .morning, caregiver: .joaoLucas),
            phrases: [
                "\(.applicationName) da manhã ok",
                "\(.applicationName) da manhã ok dada pelo \(\.$caregiver)"
            ],
            shortTitle: "Manhã ok",
            systemImageName: "sun.max.fill"
        )

        AppShortcut(
            intent: MarkInsulinIntent(period: .night, caregiver: .joaoLucas),
            phrases: [
                "\(.applicationName) da noite ok",
                "\(.applicationName) da noite ok dada pelo \(\.$caregiver)"
            ],
            shortTitle: "Noite ok",
            systemImageName: "moon.fill"
        )

        AppShortcut(
            intent: MarkInsulinIntent(period: .morning, caregiver: .sheila),
            phrases: [
                "\(.applicationName) da manhã ok dada pela Sheila"
            ],
            shortTitle: "Manhã Sheila",
            systemImageName: "sun.max.fill"
        )

        AppShortcut(
            intent: MarkInsulinIntent(period: .night, caregiver: .sheila),
            phrases: [
                "\(.applicationName) da noite ok dada pela Sheila"
            ],
            shortTitle: "Noite Sheila",
            systemImageName: "moon.fill"
        )

        AppShortcut(
            intent: MarkInsulinIntent(),
            phrases: [
                "Registrar \(.applicationName) da \(\.$period)"
            ],
            shortTitle: "Registrar dose",
            systemImageName: "syringe"
        )
    }
}
