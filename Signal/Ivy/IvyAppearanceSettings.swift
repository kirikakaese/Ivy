//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// Ivy's sections in Settings > Appearance: the accent colour with a
/// preview, the kind of dark mode, the chat list's density and the shape of
/// message bubbles (see `IvyAppearance`). Every change redraws the app, and
/// this page with it.
extension AppearanceSettingsTableViewController {

    private static var isMac: Bool { UIDevice.current.userInterfaceIdiom == .mac }

    func ivyAddAccentSection(to contents: OWSTableContents) {
        let section = OWSTableSection()
        section.headerTitle = IvyLocalizedString("APPEARANCE_ACCENT", comment: "Header of the accent colour choice in Settings > Appearance.")
        section.add(OWSTableItem(customCellBlock: { Self.swatchesCell() }))
        section.add(OWSTableItem(customCellBlock: { Self.previewCell() }))
        section.add(.switch(
            withText: IvyLocalizedString("APPEARANCE_ACCENT_OWN_BUBBLES", comment: "Switch in Settings > Appearance: the user's own messages use the accent colour."),
            isOn: { IvyAppearance.colorsOwnBubbles },
            actionBlock: { IvyAppearance.colorsOwnBubbles = $0.isOn },
        ))
        section.add(.switch(
            withText: IvyLocalizedString("APPEARANCE_ACCENT_FOLDER", comment: "Switch in Settings > Appearance: a coloured chat folder lends the app its colour while it is open."),
            isOn: { IvyAppearance.followsFolderColor },
            actionBlock: { IvyAppearance.followsFolderColor = $0.isOn },
        ))
        section.footerTitle = IvyLocalizedString("APPEARANCE_ACCENT_FOOTER", comment: "Footer under the accent colour switches in Settings > Appearance.")
        contents.add(section)
    }

    func ivyAddLayoutSections(to contents: OWSTableContents) {
        let section = OWSTableSection()
        section.add(.menuPicker(
            withText: IvyLocalizedString("APPEARANCE_DARK_STYLE", comment: "Setting in Settings > Appearance: which kind of dark mode."),
            menuTitle: nil,
            menuOptions: IvyAppearance.DarkStyle.allCases.map { style in
                OWSTableItem.MenuPickerOption(title: Self.title(for: style), value: style) { IvyAppearance.darkStyle = style }
            },
            selectedMenuOption: IvyAppearance.darkStyle,
        ))
        section.add(.menuPicker(
            withText: IvyLocalizedString("APPEARANCE_DENSITY", comment: "Setting in Settings > Appearance: how dense the chat list is."),
            menuTitle: nil,
            menuOptions: IvyAppearance.Density.allCases.map { density in
                OWSTableItem.MenuPickerOption(title: Self.title(for: density), value: density) { IvyAppearance.density = density }
            },
            selectedMenuOption: IvyAppearance.density,
        ))
        section.add(.menuPicker(
            withText: IvyLocalizedString("APPEARANCE_BUBBLE_SHAPE", comment: "Setting in Settings > Appearance: the shape of message bubbles."),
            menuTitle: nil,
            menuOptions: IvyAppearance.BubbleShape.allCases.map { shape in
                OWSTableItem.MenuPickerOption(title: Self.title(for: shape), value: shape) { IvyAppearance.bubbleShape = shape }
            },
            selectedMenuOption: IvyAppearance.bubbleShape,
        ))
        section.add(.switch(
            withText: IvyLocalizedString("APPEARANCE_BUBBLE_TAIL", comment: "Switch in Settings > Appearance: messages in a row get a smaller corner where they meet."),
            isOn: { IvyAppearance.bubbleTail },
            actionBlock: { IvyAppearance.bubbleTail = $0.isOn },
        ))
        section.footerTitle = IvyLocalizedString("APPEARANCE_DARK_STYLE_FOOTER", comment: "Footer under the dark mode, density and bubble settings.")
        contents.add(section)
    }

    // MARK: - Names

    static func title(for accent: IvyAppearance.Accent) -> String {
        switch accent {
        case .ivy: return "Ivy"
        case .moss: return IvyLocalizedString("ACCENT_MOSS", comment: "Accent colour: moss green.")
        case .petrol: return IvyLocalizedString("ACCENT_PETROL", comment: "Accent colour: teal.")
        case .blue: return IvyLocalizedString("ACCENT_BLUE", comment: "Accent colour: blue.")
        case .violet: return IvyLocalizedString("ACCENT_VIOLET", comment: "Accent colour: violet.")
        case .pink: return IvyLocalizedString("ACCENT_PINK", comment: "Accent colour: pink.")
        case .coral: return IvyLocalizedString("ACCENT_CORAL", comment: "Accent colour: coral.")
        case .orange: return IvyLocalizedString("ACCENT_ORANGE", comment: "Accent colour: orange.")
        case .gold: return IvyLocalizedString("ACCENT_GOLD", comment: "Accent colour: gold.")
        case .icon: return IvyLocalizedString("ACCENT_ICON", comment: "Accent colour that follows the app icon.")
        }
    }

    static func title(for style: IvyAppearance.DarkStyle) -> String {
        switch style {
        case .dark: return IvyLocalizedString("DARK_STYLE_DARK", comment: "Kind of dark mode: today's dark grey and black.")
        case .black: return IvyLocalizedString("DARK_STYLE_BLACK", comment: "Kind of dark mode: black, for OLED screens.")
        case .dimmed: return IvyLocalizedString("DARK_STYLE_DIMMED", comment: "Kind of dark mode: soft grey.")
        }
    }

    static func title(for density: IvyAppearance.Density) -> String {
        switch density {
        case .compact: return IvyLocalizedString("DENSITY_COMPACT", comment: "Chat list density: compact.")
        case .normal: return IvyLocalizedString("DENSITY_NORMAL", comment: "Chat list density: normal.")
        case .airy: return IvyLocalizedString("DENSITY_AIRY", comment: "Chat list density: airy, with more space.")
        }
    }

    static func title(for shape: IvyAppearance.BubbleShape) -> String {
        switch shape {
        case .round: return IvyLocalizedString("BUBBLE_ROUND", comment: "Bubble shape: round.")
        case .soft: return IvyLocalizedString("BUBBLE_SOFT", comment: "Bubble shape: softly rounded, the default.")
        case .square: return IvyLocalizedString("BUBBLE_SQUARE", comment: "Bubble shape: nearly square.")
        }
    }

    // MARK: - Cells

    /// The colours as circles, the chosen one with a ring.
    private static func swatchesCell() -> UITableViewCell {
        let cell = OWSTableItem.newCell()
        cell.selectionStyle = .none
        let columns = isMac ? 10 : 5
        let accents = IvyAppearance.Accent.allCases
        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 14
        var index = 0
        while index < accents.count {
            let row = UIStackView()
            row.distribution = .fillEqually
            row.spacing = 4
            for column in 0..<columns {
                let position = index + column
                row.addArrangedSubview(position < accents.count ? swatch(accents[position]) : UIView())
            }
            grid.addArrangedSubview(row)
            index += columns
        }
        cell.contentView.addSubview(grid)
        grid.autoPinEdgesToSuperviewMargins(with: UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0))
        return cell
    }

    private static func swatch(_ accent: IvyAppearance.Accent) -> UIView {
        let isSelected = IvyAppearance.accent == accent
        let size: CGFloat = isMac ? 30 : 40
        let dot = UIView()
        dot.autoSetDimensions(to: .square(size))
        dot.layer.cornerRadius = size / 2
        if accent == .icon {
            // The app icon's colour, with a small leaf on it.
            dot.backgroundColor = IvyAppearance.accent(forAppIcon: UserDefaults.standard.string(forKey: "IvyAppIconChoice")).swatch
            let leaf = UIImageView(image: UIImage(systemName: "leaf.fill"))
            leaf.tintColor = .white
            dot.addSubview(leaf)
            leaf.autoCenterInSuperview()
            leaf.autoSetDimensions(to: .square(size * 0.45))
            leaf.contentMode = .scaleAspectFit
        } else {
            dot.backgroundColor = accent.swatch
        }
        let ring = UIView()
        ring.autoSetDimensions(to: .square(size + 10))
        ring.layer.cornerRadius = (size + 10) / 2
        ring.layer.borderWidth = 2.5
        ring.layer.borderColor = isSelected ? accent.swatch.cgColor : UIColor.clear.cgColor
        ring.addSubview(dot)
        dot.autoCenterInSuperview()
        ring.isUserInteractionEnabled = false

        let label = UILabel()
        label.text = title(for: accent)
        label.font = isSelected ? UIFont.dynamicTypeCaption1Clamped.semibold() : .dynamicTypeCaption1Clamped
        label.textColor = isSelected ? .Signal.label : .Signal.secondaryLabel
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.75

        let stack = UIStackView(arrangedSubviews: [ring, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4
        stack.isUserInteractionEnabled = false
        let button = UIButton(type: .custom)
        button.addSubview(stack)
        stack.autoPinEdgesToSuperviewEdges()
        button.accessibilityLabel = title(for: accent)
        button.accessibilityTraits = isSelected ? [.button, .selected] : .button
        button.addAction(UIAction { _ in IvyAppearance.accent = accent }, for: .touchUpInside)
        return button
    }

    /// A chat row, two bubbles and a button in the accent colour.
    private static func previewCell() -> UITableViewCell {
        let cell = OWSTableItem.newCell()
        cell.selectionStyle = .none
        let accent = UIColor.Signal.accent

        let name = UILabel()
        name.text = IvyLocalizedString("APPEARANCE_PREVIEW_CHAT", comment: "Name of the sample chat in the accent colour preview.")
        name.font = UIFont.dynamicTypeSubheadlineClamped.semibold()
        let badge = UILabel()
        badge.text = " 3 "
        badge.font = UIFont.dynamicTypeCaption1Clamped.semibold()
        badge.textColor = .white
        badge.backgroundColor = accent
        badge.layer.cornerRadius = 9
        badge.clipsToBounds = true
        badge.textAlignment = .center
        badge.autoSetDimension(.height, toSize: 18)
        badge.autoSetDimension(.width, toSize: 22, relation: .greaterThanOrEqual)
        let chatRow = UIStackView(arrangedSubviews: [name, UIView(), badge])
        chatRow.alignment = .center

        func bubble(_ text: String, outgoing: Bool) -> UIView {
            let label = UILabel()
            label.text = text
            label.font = .dynamicTypeSubheadlineClamped
            label.numberOfLines = 0
            let view = UIView()
            if outgoing {
                // The accent colour, or a chat colour when the switch is off.
                view.backgroundColor = IvyAppearance.colorsOwnBubbles ? accent : UIColor(rgbHex: 0x2C58C3)
                label.textColor = .white
            } else {
                view.backgroundColor = .Signal.secondaryFill
                label.textColor = .Signal.label
            }
            view.layer.cornerRadius = IvyAppearance.bubbleWideCornerRadius
            view.layer.cornerCurve = .continuous
            view.layer.maskedCorners = outgoing
                ? [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner]
                : [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner]
            view.addSubview(label)
            label.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 7, left: 12, bottom: 7, right: 12))
            let row = UIStackView(arrangedSubviews: outgoing ? [UIView(), view] : [view, UIView()])
            return row
        }

        var buttonConfiguration = UIButton.Configuration.filled()
        buttonConfiguration.title = IvyLocalizedString("DATE_REPLY_ACCEPT", comment: "Button under a message with a date: accept, add it to the calendar and reply.")
        buttonConfiguration.baseBackgroundColor = accent
        buttonConfiguration.cornerStyle = .capsule
        buttonConfiguration.buttonSize = .small
        let button = UIButton(configuration: buttonConfiguration)
        button.isUserInteractionEnabled = false
        let toggle = UISwitch()
#if targetEnvironment(macCatalyst)
        toggle.preferredStyle = .sliding // a switch on the Mac too, not a checkbox
        toggle.tintColor = accent
#endif
        toggle.isOn = true
        toggle.onTintColor = accent
        toggle.isUserInteractionEnabled = false
        let controls = UIStackView(arrangedSubviews: [button, UIView(), toggle])
        controls.alignment = .center

        let stack = UIStackView(arrangedSubviews: [
            chatRow,
            bubble(IvyLocalizedString("APPEARANCE_PREVIEW_INCOMING", comment: "Incoming sample message in the accent colour preview."), outgoing: false),
            bubble(IvyLocalizedString("APPEARANCE_PREVIEW_OUTGOING", comment: "Outgoing sample message in the accent colour preview."), outgoing: true),
            controls,
        ])
        stack.axis = .vertical
        stack.spacing = 8
        stack.isAccessibilityElement = false
        cell.contentView.addSubview(stack)
        stack.autoPinEdgesToSuperviewMargins(with: UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0))
        return cell
    }
}

/// Keeps the windows' tint, which system controls follow, on the accent
/// colour.
@MainActor
enum IvyAccentTint {

    static func start() {
        NotificationCenter.default.addObserver(forName: .themeDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { apply() }
        }
        apply()
    }

    static func apply() {
        // Switches made from now on; open settings pages are rebuilt.
        UISwitch.appearance().onTintColor = UIColor.Signal.accent
        for window in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows) {
            window.tintColor = UIColor.Signal.accent
            // Every colour on screen is drawn again.
            if #available(iOS 17, *) {
                window.traitOverrides[IvyAppearanceTrait.self] = IvyAppearance.generation
            }
        }
    }
}
