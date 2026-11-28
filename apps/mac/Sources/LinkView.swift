import SwiftUI

/// "Link this Mac": steps on the leading side, the QR code on its paper card on the trailing side.
struct LinkView: View {
    @ObservedObject var model: AppModel

    private let steps = [
        "SECONDARY_ONBOARDING_SCAN_CODE_STEP_OPEN_PRIMARY",
        "SECONDARY_ONBOARDING_SCAN_CODE_STEP_OPEN_SETTINGS",
        "SECONDARY_ONBOARDING_SCAN_CODE_STEP_LINK_DEVICE",
    ]

    var body: some View {
        HStack(alignment: .center, spacing: Design.Space.xxxl) {
            VStack(alignment: .leading, spacing: Design.Space.xl) {
                Text(localized("SECONDARY_ONBOARDING_SCAN_CODE_TITLE"))
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: Design.Space.m) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, key in
                        HStack(alignment: .firstTextBaseline, spacing: Design.Space.s) {
                            Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary)
                            Text(localized(key))
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .font(.body)
            }
            .frame(maxWidth: Design.textColumn, alignment: .leading)

            card
        }
        .padding(Design.Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static let cardSide: CGFloat = 264

    @ViewBuilder private var card: some View {
        switch model.link {
        case .code(let code):
            QRCodeView(code: code)
                .padding(Design.Space.l)
                // White in both appearances: a phone camera needs dark modules on a light ground.
                .background(.white, in: RoundedRectangle(cornerRadius: Design.Radius.card))
                .overlay(RoundedRectangle(cornerRadius: Design.Radius.card).strokeBorder(.separator))
                .frame(width: Self.cardSide, height: Self.cardSide)
                .accessibilityElement()
                .accessibilityLabel(localized("GROUP_LINK_QR_CODE_VIEW_TITLE"))
        case .connecting:
            ProgressView().frame(width: Self.cardSide, height: Self.cardSide)
        case .registering:
            VStack(spacing: Design.Space.m) {
                ProgressView()
                Text(IvyLocalizedString("CORE_LINK_REGISTERING")).foregroundStyle(.secondary)
            }
            .frame(width: Self.cardSide, height: Self.cardSide)
        case .failed(let title, let message):
            VStack(alignment: .leading, spacing: Design.Space.m) {
                Label(title, systemImage: "exclamationmark.triangle").font(.headline)
                Text(message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(localized("LINK_DEVICE_RESTART")) { model.startLinking() }
                    .keyboardShortcut(.defaultAction)
            }
            .frame(width: Self.cardSide, alignment: .leading)
        }
    }
}

/// Draws the modules the core computed.
struct QRCodeView: View {
    let code: QrCode

    var body: some View {
        Canvas { context, size in
            let n = Int(code.size)
            let side = min(size.width, size.height) / CGFloat(n)
            var path = Path()
            for (i, dark) in code.modules.enumerated() where dark {
                path.addRect(CGRect(x: CGFloat(i % n) * side, y: CGFloat(i / n) * side, width: side, height: side))
            }
            context.fill(path, with: .color(.black))
        }
        .aspectRatio(1, contentMode: .fit)
        // A QR code is never mirrored.
        .environment(\.layoutDirection, .leftToRight)
    }
}
