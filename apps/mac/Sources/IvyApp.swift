import SwiftUI

@main
struct IvyApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Ivy", id: "main") {
            RootView(model: model)
                .frame(minWidth: 760, minHeight: 440)
                .tint(Design.accent)
                .task { model.start() }
        }
    }
}

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        switch model.screen {
        case .starting:
            ProgressView()
        case .link:
            LinkView(model: model)
        case .linked:
            ConversationsView(model: model)
        case .existingData(let summary):
            notice(
                symbol: "tray.full",
                title: IvyLocalizedString("CORE_EXISTING_DATA_TITLE"),
                message: String(format: IvyLocalizedString("CORE_EXISTING_DATA_MESSAGE_FORMAT"), summary.chats, summary.messages))
        case .failed(let message):
            notice(symbol: "exclamationmark.triangle", title: IvyLocalizedString("CORE_START_FAILED_TITLE"), message: message)
        }
    }

    private func notice(symbol: String, title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.s) {
            Label(title, systemImage: symbol).font(.title2.weight(.semibold))
            Text(message).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .frame(maxWidth: Design.textColumn, alignment: .leading)
        .padding(Design.Space.xxl)
    }
}
