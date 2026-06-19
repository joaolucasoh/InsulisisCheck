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

                    todayEntries
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Insulísis Check 💉")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isSharingPresented = true
                    } label: {
                        Label("Compartilhar com Sheila", systemImage: "person.2.badge.plus")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        manualPeriod = .morning
                    } label: {
                        Label("Fazer apontamento manual", systemImage: "plus.circle.fill")
                    }
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

            VStack(alignment: .leading, spacing: 8) {
                Text(todayTitle.capitalized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: statusIconName)
                        .font(.headline)
                        .frame(width: 18)

                    Text(overallStatusTitle)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(statusColor)

                Label(nextDoseTitle, systemImage: "calendar.badge.clock")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var todayEntries: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hoje")
                .font(.title2.bold())

            let entries = store.entries(on: Date())

            if entries.isEmpty {
                Text("Nenhum apontamento ainda.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                ForEach(entries) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.period.title)
                                .font(.headline)
                            Text("Aplicada por \(entry.caregiver)")
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text(entry.date.insulisisTimeText)
                                .font(.headline)
                            Text(entry.unitsText)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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

                        Text("Convite pronto")
                            .font(.title2.bold())

                        Text("Envie este convite para a Sheila. Quando ela abrir o link e aceitar pelo iCloud, os apontamentos ficam sincronizados nos dois iPhones.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button {
                            isShareSheetPresented = true
                        } label: {
                            Label("Enviar convite", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Text(shareURL.absoluteString)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    .padding(24)
                    .sheet(isPresented: $isShareSheetPresented) {
                        ShareSheet(items: [shareURL])
                    }
            } else if let errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "icloud.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)

                    Text("Não deu para preparar o compartilhamento.")
                        .font(.headline)
                        .multilineTextAlignment(.center)

                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Tentar novamente") {
                        Task { await prepareShare() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(24)
            } else {
                VStack(spacing: 14) {
                    ProgressView()
                    Text("Preparando compartilhamento pelo iCloud...")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text("Isso pode levar alguns segundos na primeira vez.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .task {
                    await prepareShare()
                }
            }
        }
            .navigationTitle("Compartilhar")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @MainActor
    private func prepareShare() async {
        shareURL = nil
        errorMessage = nil

        do {
            let prepared = try await CloudDoseSync.shared.preparedShare()
            guard let url = prepared.share.url else {
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
        let description = error.localizedDescription

        if description.localizedCaseInsensitiveContains("Cannot create new type") ||
            description.localizedCaseInsensitiveContains("production schema") {
            return """
            O schema de produção do CloudKit ainda não foi publicado para este app.

            Abra o CloudKit Dashboard, entre no container iCloud.com.raven.InsulisisCheck e faça o deploy do schema de Development para Production. Depois disso, tente compartilhar novamente.
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

                VStack(alignment: .leading, spacing: 5) {
                    Text(period.title)
                        .font(.title3.bold())

                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(deadlineText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(statusColor.opacity(0.12), in: Capsule())
            }

            if let entry {
                HStack(spacing: 12) {
                    Label(entry.date.insulisisTimeText, systemImage: "clock")
                    Label(entry.caregiver, systemImage: "person.fill")
                    Label(entry.unitsText, systemImage: "drop.fill")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Button(action: action) {
                Label(entry == nil ? "Fazer apontamento manual" : "Editar apontamento", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(entry == nil ? .blue : .green)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var statusColor: Color {
        if entry != nil { return .green }
        if isDue { return .orange }
        return isOverdue ? .red : .orange
    }

    private var statusText: String {
        if let entry {
            let nextDose = Calendar.current.date(byAdding: .hour, value: 12, to: entry.date) ?? entry.date.addingTimeInterval(43_200)
            return "OK às \(entry.date.insulisisTimeText), próxima às \(nextDose.insulisisTimeText)"
        }
        if let nextDoseDate {
            if isOverdue { return "Dose atrasada \(nextDoseDate.insulisisDelayText)" }
            if isDue { return "Hora de aplicar a dose da \(period.title.lowercased())" }
            return "Próxima dose às \(nextDoseDate.insulisisTimeText)"
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
                        }
                    }

                    Picker("Quem aplicou", selection: $caregiver) {
                        ForEach(Caregiver.manualEntryOptions) { caregiver in
                            Text(caregiver.displayName).tag(caregiver)
                        }
                    }

                    Stepper(value: $units, in: 0...100, step: 0.5) {
                        HStack {
                            Text("Unidades")
                            Spacer()
                            Text(units.formatted(.number.precision(.fractionLength(0...1))))
                                .foregroundStyle(.secondary)
                        }
                    }

                    DatePicker(
                        "Horário",
                        selection: $doseDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                if store.entry(for: period) != nil {
                    Section {
                        Button(role: .destructive) {
                            store.markPending(period: period)
                            dismiss()
                        } label: {
                            Label("Voltar para pendente", systemImage: "arrow.uturn.backward")
                        }
                    }
                }
            }
            .navigationTitle("Registrar dose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        store.record(period: selectedPeriod, caregiver: caregiver.displayName, units: units, date: doseDate)
                        dismiss()
                    }
                    .fontWeight(.semibold)
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
