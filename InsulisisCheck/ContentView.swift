import Combine
import CloudKit
import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = DoseStore.shared
    @State private var manualPeriod: InsulinPeriod?
    @State private var isSharingPresented = false
    @State private var isInviteAcceptancePresented = false
    @State private var isOpeningSyncVisible = false
    @State private var isOpeningSyncRunning = false
    private let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var todayTitle: String {
        Date.now.insulisisDayText
    }

    var body: some View {
        if store.sessionMode == nil {
            SessionModeSelectionView(store: store)
        } else {
            NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                        .accessibilityIdentifier("home.header")

                    if store.sessionMode == .caregiver {
                        SyncStatusBanner(status: store.syncStatus) {
                            Task { await store.syncFromCloud() }
                        }
                        .accessibilityIdentifier("home.sync-status")
                    }

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
                    Menu {
                        Button {
                            store.clearSessionMode()
                        } label: {
                            Label("Trocar modo", systemImage: "arrow.left.arrow.right")
                        }
                    } label: {
                        Label(store.sessionMode?.title ?? "Sessão", systemImage: "person.2")
                    }
                    .accessibilityIdentifier("home.session.menu")
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
            .task {
                await refreshAfterOpening()
            }
            .onChange(of: store.entries) {
                Task {
                    await InsulinActivityManager.shared.refresh(store: store)
                    await InsulinNotificationManager.shared.refresh(entries: store.entries)
                }
            }
            .onChange(of: scenePhase) {
                guard scenePhase == .active else { return }
                Task { await refreshAfterOpening() }
            }
            .onReceive(refreshTimer) { _ in
                Task {
                    await InsulinActivityManager.shared.refresh(store: store)
                }
            }
            .overlay {
                if isOpeningSyncVisible {
                    OpeningSyncOverlay()
                        .transition(.opacity)
                        .accessibilityIdentifier("home.opening-sync-overlay")
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isOpeningSyncVisible)
        }
        }
    }

    private func refreshAfterOpening() async {
        guard !isOpeningSyncRunning else { return }

        isOpeningSyncRunning = true
        let shouldShowLoading = store.sessionMode == .caregiver
        let start = Date()

        if shouldShowLoading {
            isOpeningSyncVisible = true
        }

        await store.syncFromCloud()
        await InsulinActivityManager.shared.refresh(store: store)
        await InsulinNotificationManager.shared.refresh(entries: store.entries)

        if shouldShowLoading {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed < 0.8 {
                try? await Task.sleep(nanoseconds: UInt64((0.8 - elapsed) * 1_000_000_000))
            }
            isOpeningSyncVisible = false
        }

        isOpeningSyncRunning = false
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

private struct OpeningSyncOverlay: View {
    @State private var isRotating = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color.accentColor.opacity(0.18), lineWidth: 8)
                        .frame(width: 86, height: 86)

                    Image(systemName: "drop.fill")
                        .font(.title)
                        .foregroundStyle(Color.accentColor)

                    Image(systemName: "syringe")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(Color.accentColor, in: Circle())
                        .offset(y: -43)
                        .rotationEffect(.degrees(isRotating ? 360 : 0))
                }
                .frame(width: 112, height: 112)

                VStack(spacing: 6) {
                    Text("Atualizando os dados")
                        .font(.headline)
                        .accessibilityIdentifier("opening-sync.title")

                    Text("Sincronizando o histórico do modo Cuidador")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("opening-sync.subtitle")
                }
            }
            .padding(24)
            .frame(maxWidth: 300)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityElement(children: .combine)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                isRotating = true
            }
        }
    }
}

private struct SyncStatusBanner: View {
    let status: CloudSyncStatus
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .accessibilityIdentifier("sync-status.icon")

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.bold())
                    .accessibilityIdentifier("sync-status.title")

                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("sync-status.message")

                if case .unavailable = status {
                    Button("Tentar novamente", action: retry)
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("sync-status.retry-button")
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var title: String {
        switch status {
        case .idle:
            return "Sincronização pronta para iniciar"
        case .syncing:
            return "Sincronizando dados reais"
        case .ready(_):
            return "Dados reais sincronizados"
        case .unavailable:
            return "Sincronização indisponível"
        }
    }

    private var message: String {
        switch status {
        case .idle:
            return "O modo Cuidador usa o iCloud para compartilhar o histórico entre os iPhones."
        case .syncing:
            return "Enviando apontamentos deste iPhone e buscando o histórico no iCloud."
        case .ready(let message):
            return message
        case .unavailable(let message):
            return message
        }
    }

    private var iconName: String {
        switch status {
        case .idle:
            return "icloud"
        case .syncing:
            return "icloud.and.arrow.up"
        case .ready(_):
            return "checkmark.icloud"
        case .unavailable:
            return "exclamationmark.icloud"
        }
    }

    private var tint: Color {
        switch status {
        case .idle, .syncing:
            return .blue
        case .ready(_):
            return .green
        case .unavailable:
            return .orange
        }
    }
}

private struct SessionModeSelectionView: View {
    @ObservedObject var store: DoseStore

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Spacer(minLength: 24)

                AppIconLogoView(size: 104)
                    .accessibilityIdentifier("session-selection.image")

                Text("Insulísis Check")
                    .font(.largeTitle.bold())
                    .accessibilityIdentifier("session-selection.title")

                Text("Escolha como este iPhone vai usar os apontamentos.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("session-selection.subtitle")

                VStack(spacing: 12) {
                    Button {
                        store.selectSessionMode(.caregiver)
                    } label: {
                        SessionModeOptionLabel(
                            title: "Cuidador",
                            subtitle: "Usa os dados reais compartilhados entre os iPhones.",
                            systemImage: "person.2.fill"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("session-selection.caregiver.button")

                    Button {
                        store.selectSessionMode(.testOnly)
                    } label: {
                        SessionModeOptionLabel(
                            title: "Test only",
                            subtitle: "Cria um ambiente local separado para testar o app.",
                            systemImage: "testtube.2"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("session-selection.test-only.button")
                }

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("session-selection.container")
        }
    }
}

private struct AppIconLogoView: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let appIcon {
                Image(uiImage: appIcon)
                    .resizable()
                    .scaledToFill()
            } else {
                Image("IsisNeutral")
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var appIcon: UIImage? {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
              let iconName = iconFiles.last else {
            return nil
        }

        return UIImage(named: iconName)
    }
}

private struct SessionModeOptionLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct CloudSharingView: View {
    @State private var shareURL: URL?
    @State private var inviteText: String?
    @State private var errorMessage: String?
    @State private var diagnosticText = CloudShareDiagnostics.text
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

                        if let inviteText {
                            Text(inviteText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .accessibilityIdentifier("sharing.invite-text.label")
                        }
                    }
                    .padding(24)
                    .accessibilityIdentifier("sharing.ready.container")
                    .sheet(isPresented: $isShareSheetPresented) {
                        ShareSheet(items: [inviteText ?? shareURL.absoluteString])
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

                    diagnosticLog

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

                    diagnosticLog
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

    private var diagnosticLog: some View {
        Group {
            if !diagnosticText.isEmpty {
                Text(diagnosticText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityIdentifier("sharing.diagnostic-log")
            }
        }
    }

    @MainActor
    private func prepareShare() async {
        shareURL = nil
        inviteText = nil
        errorMessage = nil
        diagnosticText = CloudShareDiagnostics.text

        do {
            let prepared = try await CloudDoseSync.shared.preparedShare()
            diagnosticText = CloudShareDiagnostics.text
            let url = prepared.invitationURL
            guard !url.absoluteString.isEmpty else {
                errorMessage = "O iCloud preparou o compartilhamento, mas ainda não retornou um link de convite."
                return
            }
            let appURL = CloudInviteLink.appURL(for: url) ?? url
            shareURL = appURL
            inviteText = """
            Convite do Insulísis Check.

            Abra o app InsulisisCheck, toque em iCloud > Aceitar convite e cole este texto:

            \(appURL.absoluteString)
            """
        } catch {
            diagnosticText = CloudShareDiagnostics.text
            errorMessage = CloudSharingErrorMessage.make(from: error)
        }
    }
}

private enum CloudSharingErrorMessage {
    static func make(from error: Error) -> String {
        CloudErrorMessage.make(from: error)
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct InviteAcceptanceView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: DoseStore
    @State private var inviteText = ""
    @State private var statusMessage: String?
    @State private var diagnosticText = CloudShareDiagnostics.text
    @State private var isAccepting = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Cole aqui o convite recebido. Pode ser o texto inteiro da mensagem.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("invite-accept.description")

                TextEditor(text: $inviteText)
                    .font(.body)
                    .frame(minHeight: 150)
                    .padding(8)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityIdentifier("invite-accept.text-editor")

                HStack {
                    Button {
                        inviteText = UIPasteboard.general.string ?? ""
                    } label: {
                        Label("Colar", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("invite-accept.paste.button")

                    Button {
                        Task { await acceptInvite() }
                    } label: {
                        if isAccepting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Aceitar convite", systemImage: "checkmark.icloud")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isAccepting || inviteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("invite-accept.accept.button")
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("invite-accept.status")
                }

                if !diagnosticText.isEmpty {
                    Text(diagnosticText)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityIdentifier("invite-accept.diagnostic-log")
                }

                Spacer()
            }
            .padding(20)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Aceitar convite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if inviteText.isEmpty,
                   let pastedText = UIPasteboard.general.string,
                   CloudInviteLink.shareURL(fromText: pastedText) != nil {
                    inviteText = pastedText
                }
            }
        }
    }

    @MainActor
    private func acceptInvite() async {
        guard let shareURL = CloudInviteLink.shareURL(fromText: inviteText) else {
            statusMessage = "Não encontrei um convite válido nesse texto."
            return
        }

        CloudShareDiagnostics.clear()
        diagnosticText = ""
        isAccepting = true
        statusMessage = "Aceitando convite pelo iCloud..."

        await store.syncShareInvitation(from: shareURL)

        isAccepting = false
        diagnosticText = CloudShareDiagnostics.text
        switch store.syncStatus {
        case .ready(_):
            statusMessage = "Convite aceito. Sincronização ativada."
        case .unavailable(let message):
            statusMessage = "Não deu para aceitar o convite: \(message)"
        case .idle, .syncing:
            statusMessage = "Convite processado."
        }
    }
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
