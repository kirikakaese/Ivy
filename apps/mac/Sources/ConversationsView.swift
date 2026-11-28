import SwiftUI

/// The chat list in the sidebar; the chat itself comes with the next slice.
struct ConversationsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(model.conversations, id: \.id, selection: $model.selected) { conversation in
                ConversationRow(conversation: conversation, isSelected: model.selected == conversation.id)
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 320)
            .overlay {
                if model.conversations.isEmpty {
                    Text(IvyLocalizedString("CORE_NO_CHATS"))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(Design.Space.xl)
                }
            }
        } detail: {
            Text(IvyLocalizedString("CORE_SELECT_CHAT"))
                .foregroundStyle(.secondary)
        }
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    let isSelected: Bool

    private var title: String {
        conversation.title ?? (conversation.isGroup ? IvyLocalizedString("CORE_GROUP_UNNAMED") : localized("UNKNOWN_USER"))
    }

    private var snippet: String {
        conversation.snippet.isEmpty ? localized("ATTACHMENT_LABEL") : conversation.snippet
    }

    private var time: String {
        let date = Date(timeIntervalSince1970: TimeInterval(conversation.timestampMs) / 1000)
        return Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.day().month(.abbreviated))
    }

    var body: some View {
        HStack(spacing: Design.Space.s) {
            // The tendril: the selected chat is the one that is currently yours (docs/DESIGN.md).
            Rectangle()
                .fill(isSelected ? Design.accent : .clear)
                .frame(width: 2)
            VStack(alignment: .leading, spacing: Design.Space.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.body.weight(conversation.unread > 0 ? .medium : .regular))
                        .lineLimit(1)
                    Spacer(minLength: Design.Space.s)
                    Text(time)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(snippet)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: Design.Space.s)
                    if conversation.unread > 0 {
                        Text(conversation.unread.formatted())
                            .font(.footnote.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(Design.accent)
                    }
                }
            }
        }
        .padding(.vertical, Design.Space.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        var parts = [snippet, time]
        if conversation.unread > 0 {
            parts.append(String(format: IvyLocalizedString("CORE_UNREAD_FORMAT"), Int(conversation.unread)))
        }
        return parts.joined(separator: ", ")
    }
}
