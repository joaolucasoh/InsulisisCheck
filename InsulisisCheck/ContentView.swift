import Combine
import CloudKit
import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var store = DoseStore.shared
    @State private var manualPeriod: InsulinPeriod?
    @State private var isSharingPresented = false
    private let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var todayTitle: String {
        Date.now.insulisisDayText
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                        .accessibilityIdentifier("home.header")

                    VStack(spacing: 14) {
                        ForEach(InsulinPeriod.allCases) { period in
                            PeriodStatusCard(
                                period: period,
                                entry: store.entry(for: period),
                                isDue: isDue(period),
                                isOverdue: isOverdue(period),
                                nextDoseDate: currentSchedule.nextPeriod == period ? currentSchedule.nextDoseDate : nil
                            ) {
                                manualPeriod = period
                            }
                        }
                    }
                    .accessibilityIdentifier("home.period-cards")

                    todayEntries
                        .accessibilityIdentifier("home.today-entries")
                }
                .padding(20)
            }
            .accessibilityIdentifier("home.scroll-view")
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Insulísis Check 💉")
            .accessibilityIdentifier("home.navigation")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isSharingPresented = true
                    } label: {
                        Label("Compartilhar com Sheila", systemImage: "person.2.badge.plus")
                    }
                    .accessibilityIdentifier("home.share-with-sheila.button")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        manualPeriod = .morning
                    } label: {
                        Label("Fazer apontamento manual", systemImage: "plus.circle.fill")
                    }
                    .accessibilityIdentifier("home.manual-entry.button")
                }
            }
            .sheet(item: $manualPeriod) { period in
                ManualEntryView(period: period, store: store)
            }
            .sheet(isPresented: $isSharingPresented) {
                CloudSharingView()
            }
            .task {
                await store.syncFromCloud()
                await InsulinActivityManager.shared.refresh(store: store)
                await InsulinNotificationManager.shared.refresh(entries: store.entries)
            }
            .onChange(of: store.entries) {
                Task {
                    await InsulinActivityManager.shared.refresh(store: store)
                    await InsulinNotificationManager.shared.refresh(entries: store.entries)
                }
            }
            .onReceive(refreshTimer) { _ in
                Task {
                    await InsulinActivityManager.shared.refresh(store: store)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(headerImageName)
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityIdentifier("home.header.image")

            VStack(alignment: .leading, spacing: 8) {
                Text(todayTitle.capitalized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("home.header.date-label")

                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: statusIconName)
                        .font(.headline)
                        .frame(width: 18)
                        .accessibilityIdentifier("home.header.status-icon")

                    Text(overallStatusTitle)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("home.header.status-title")
                }
                .foregroundStyle(statusColor)
                .accessibilityIdentifier("home.header.status-row")

                Label(nextDoseTitle, systemImage: "calendar.badge.clock")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("home.header.next-dose-label")
            }
            .padding(.top, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var todayEntries: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hoje")
                .font(.title2.bold())
                .accessibilityIdentifier("today.title")

            let entries = store.entries(on: Date())

            if entries.isEmpty {
                Text("Nenhum apontamento ainda.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityIdentifier("today.empty-label")
            } else {
                ForEach(entries) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.period.title)
                                .font(.headline)
                                .accessibilityIdentifier("today.entry.\(entry.id.uuidString).period-label")
                            Text("Aplicada por \(entry.caregiver)")
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("today.entry.\(entry.id.uuidString).caregiver-label")
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text(entry.date.insulisisTimeText)
                                .font(.headline)
                                .accessibilityIdentifier("today.entry.\(entry.id.uuidString).time-label")
                            Text(entry.unitsText)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("today.entry.\(entry.id.uuidString).units-label")
                        }
                    }
                    .padding(16)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityIdentifier("today.entry.\(entry.id.uuidString).row")
                }
            }
        }
    }

    private var allDone: Bool {
        InsulinPeriod.allCases.allSatisfy { store.isComplete(period: $0) }
    }

    private var hasOverdue: Bool {
        currentSchedule.isOverdue
    }

    private var hasDueDose: Bool {
        currentSchedule.isDue
    }

    private var currentSchedule: DoseSchedule {
        DoseSchedule.make(entries: store.entries)
    }

    private var overallStatusTitle: String {
        if hasOverdue { return "Dose da \(currentSchedule.nextPeriod.title) atrasada" }
        if hasDueDose { return "Hora da dose da \(currentSchedule.nextPeriod.title.lowercased()) 💉" }
        return "Zizi tá de boa, só esperando a próxima 💉"
    }

    private var nextDoseTitle: String {
        "Próxima aplicação: \(currentSchedule.nextDoseText)"
    }

    private var headerImageName: String {
        if hasOverdue { return "IsisWaiting" }
        if hasDueDose { return "IsisDue" }
        return "IsisNeutral"
    }

    private var statusIconName: String {
        if hasOverdue { return "clock.badge.exclamationmark" }
        if hasDueDose { return "syringe" }
        return "clock"
    }

    private var statusColor: Color {
        if hasOverdue { return .red }
        if hasDueDose { return .orange }
        return .green
    }

    private func isDue(_ period: InsulinPeriod) -> Bool {
        currentSchedule.isDue && currentSchedule.nextPeriod == period
    }

    private func isOverdue(_ period: InsulinPeriod) -> Bool {
        currentSchedule.isOverdue && currentSchedule.nextPeriod == period
    }
}

private struct CloudSharingView: View {
    @State private var shareURL: URL?
    @State private var errorMessage: String?
    @State private var isShareSheetPresented = false

    var body: some View {
        NavigationStack {
            Group {
                if let shareURL {
                    VStack(spacing: 18) {
                        Image(systemName: "person.2.badge.plus")
                            .font(.largeTitle)
                            .foregroundStyle(.green)
                            .accessibilityIdentifier("sharing.ready.icon")

                        Text("Convite pronto")
                            .font(.title2.bold())
                            .accessibilityIdentifier("sharing.ready.title")

                        Text("Envie este convite para a Sheila. Quando ela abrir o link e aceitar pelo iCloud, os apontamentos ficam sincronizados nos dois iPhones.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("sharing.ready.description")

                        Button {
                            isShareSheetPresented = true
                        } label: {
                            Label("Enviar convite", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("sharing.send-invite.button")

                        Text(shareURL.absoluteString)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .accessibilityIdentifier("sharing.invite-url.label")
                    }
                    .padding(24)
                    .accessibilityIdentifier("sharing.ready.container")
                    .sheet(isPresented: $isShareSheetPresented) {
                        ShareSheet(items: [shareURL])
                    }
            } else if let errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "icloud.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("sharing.error.icon")

                    Text("Não deu para preparar o compartilhamento.")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("sharing.error.title")

                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("sharing.error.message")

                    Button("Tentar novamente") {
                        Task { await prepareShare() }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("sharing.retry.button")
                }
                .padding(24)
                .accessibilityIdentifier("sharing.error.container")
            } else {
                VStack(spacing: 14) {
                    ProgressView()
                        .accessibilityIdentifier("sharing.loading.progress")
                    Text("Preparando compartilhamento pelo iCloud...")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("sharing.loading.title")
                    Text("Isso pode levar alguns segundos na primeira vez.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("sharing.loading.subtitle")
                }
                .padding(24)
                .accessibilityIdentifier("sharing.loading.container")
                .task {
                    await prepareShare()
                }
            }
        }
            .navigationTitle("Compartilhar")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("sharing.navigation")
        }
    }

    @MainActor
    private func prepareShare() async {
        shareURL = nil
        errorMessage = nil

        do {
            let prepared = try await CloudDoseSync.shared.preparedShare()
            let url = prepared.invitationURL
            guard !url.absoluteString.isEmpty else {
                errorMessage = "O iCloud preparou o compartilhamento, mas ainda não retornou um link de convite."
                return
            }
            shareURL = url
        } catch {
            errorMessage = CloudSharingErrorMessage.make(from: error)
        }
    }
}

private enum CloudSharingErrorMessage {
    static func make(from error: Error) -> String {
        if let ckError = error as? CKError {
            return """
            O iCloud recusou o compartilhamento.

            Detalhes técnicos: \(ckError.localizedDescription)
            Código CloudKit: \(ckError.code.rawValue)
            """
        }

        let description = error.localizedDescription

        if description.localizedCaseInsensitiveContains("Cannot create new type") ||
            description.localizedCaseInsensitiveContains("production schema") {
            return """
            O iCloud recusou o compartilhamento por uma diferença de schema ou permissão em produção.

            Detalhes técnicos: \(description)
            """
        }

        return description
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct PeriodStatusCard: View {
    let period: InsulinPeriod
    let entry: DoseEntry?
    let isDue: Bool
    let isOverdue: Bool
    let nextDoseDate: Date?
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: entry == nil ? "syringe" : "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(entry == nil ? statusColor : .green)
                    .frame(width: 36, height: 36)
                    .background(statusColor.opacity(0.14), in: Circle())
                    .accessibilityIdentifier("dose-card.\(period.rawValue).status-icon")

                VStack(alignment: .leading, spacing: 5) {
                    Text(period.title)
                        .font(.title3.bold())
                        .accessibilityIdentifier("dose-card.\(period.rawValue).title")

                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("dose-card.\(period.rawValue).status-label")
                }

                Spacer()

                Text(deadlineText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(statusColor.opacity(0.12), in: Capsule())
                    .accessibilityIdentifier("dose-card.\(period.rawValue).deadline-label")
            }
            .accessibilityIdentifier("dose-card.\(period.rawValue).header-row")

            if let entry {
                HStack(spacing: 12) {
                    Label(entry.date.insulisisTimeText, systemImage: "clock")
                        .accessibilityIdentifier("dose-card.\(period.rawValue).entry-time-label")
                    Label(entry.caregiver, systemImage: "person.fill")
                        .accessibilityIdentifier("dose-card.\(period.rawValue).entry-caregiver-label")
                    Label(entry.unitsText, systemImage: "drop.fill")
                        .accessibilityIdentifier("dose-card.\(period.rawValue).entry-units-label")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("dose-card.\(period.rawValue).entry-details-row")
            }

            Button(action: action) {
                Label(entry == nil ? "Fazer apontamento manual" : "Editar apontamento", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(entry == nil ? .blue : .green)
            .accessibilityIdentifier("dose-card.\(period.rawValue).action-button")
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityIdentifier("dose-card.\(period.rawValue).container")
    }

    private var statusColor: Color {
        if entry != nil { return .green }
        if isDue { return .orange }
        return isOverdue ? .red : .orange
    }

    private var statusText: String {
        if let entry {
            return "Aplicada às \(entry.date.insulisisTimeText)"
        }
        if let nextDoseDate {
            if isOverdue { return "Dose atrasada \(nextDoseDate.insulisisDelayText)" }
            if isDue { return "Hora de aplicar a dose da \(period.title.lowercased())" }
            return "Aguardando horário da dose"
        }
        return isOverdue ? "Ainda não registrada" : "Pendente"
    }

    private var deadlineText: String {
        if let nextDoseDate {
            let prefix = isOverdue ? "Desde" : "Às"
            return "\(prefix) \(nextDoseDate.insulisisTimeText)"
        }
        return entry == nil ? "Aguardando" : "OK"
    }
}

private struct ManualEntryView: View {
    let period: InsulinPeriod
    @ObservedObject var store: DoseStore

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPeriod: InsulinPeriod
    @State private var caregiver: Caregiver
    @State private var units = DoseEntry.defaultUnits
    @State private var doseDate = Date()

    init(period: InsulinPeriod, store: DoseStore) {
        self.period = period
        self.store = store

        let existingEntry = store.entry(for: period)
        _selectedPeriod = State(initialValue: existingEntry?.period ?? period)
        _caregiver = State(initialValue: existingEntry.map { Caregiver.fromDisplayName($0.caregiver) } ?? .joaoLucas)
        _units = State(initialValue: existingEntry?.units ?? DoseEntry.defaultUnits)
        _doseDate = State(initialValue: existingEntry?.date ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Apontamento") {
                    Picker("Período", selection: $selectedPeriod) {
                        ForEach(InsulinPeriod.allCases) { period in
                            Text(period.title).tag(period)
                                .accessibilityIdentifier("manual.period.option.\(period.rawValue)")
                        }
                    }
                    .accessibilityIdentifier("manual.period.picker")

                    Picker("Quem aplicou", selection: $caregiver) {
                        ForEach(Caregiver.manualEntryOptions) { caregiver in
                            Text(caregiver.displayName).tag(caregiver)
                                .accessibilityIdentifier("manual.caregiver.option.\(caregiver.rawValue)")
                        }
                    }
                    .accessibilityIdentifier("manual.caregiver.picker")

                    Stepper(value: $units, in: 0...100, step: 0.5) {
                        HStack {
                            Text("Unidades")
                                .accessibilityIdentifier("manual.units.title-label")
                            Spacer()
                            Text(units.formatted(.number.precision(.fractionLength(0...1))))
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("manual.units.value-label")
                        }
                    }
                    .accessibilityIdentifier("manual.units.stepper")

                    DatePicker(
                        "Horário",
                        selection: $doseDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .accessibilityIdentifier("manual.date-picker")
                }
                .accessibilityIdentifier("manual.entry.section")

                if store.entry(for: period) != nil {
                    Section {
                        Button(role: .destructive) {
                            store.markPending(period: period)
                            dismiss()
                        } label: {
                            Label("Voltar para pendente", systemImage: "arrow.uturn.backward")
                        }
                        .accessibilityIdentifier("manual.mark-pending.button")
                    }
                    .accessibilityIdentifier("manual.pending.section")
                }
            }
            .accessibilityIdentifier("manual.form")
            .navigationTitle("Registrar dose")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("manual.navigation")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                    .accessibilityIdentifier("manual.cancel.button")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        store.record(period: selectedPeriod, caregiver: caregiver.displayName, units: units, date: doseDate)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("manual.save.button")
                }
            }
        }
    }
}

private extension DoseEntry {
    var unitsText: String {
        let value = units.formatted(.number.precision(.fractionLength(0...1)))
        return "\(value) U"
    }
}

#Preview {
    ContentView()
}
