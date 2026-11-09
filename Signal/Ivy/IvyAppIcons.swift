//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// Ivy's app icons: the Ivy i in five colours, seven pride versions and the
/// four earlier designs. On iPhone and iPad they are the system's alternate
/// icons (`Signal/AppIcons/AppIcon-ivy-*.icon`); on the Mac the Dock icon
/// is set through the AppKit plugin while Ivy runs.
enum IvyAppIcon: String, CaseIterable {
    case dark = "AppIcon"
    case light = "AppIcon-ivy-light"
    case midnight = "AppIcon-ivy-midnight"
    case mint = "AppIcon-ivy-mint"
    case autumn = "AppIcon-ivy-autumn"
    case rainbow = "AppIcon-ivy-rainbow"
    case progress = "AppIcon-ivy-progress"
    case trans = "AppIcon-ivy-trans"
    case bi = "AppIcon-ivy-bi"
    case nonbinary = "AppIcon-ivy-nonbinary"
    case lesbian = "AppIcon-ivy-lesbian"
    case pan = "AppIcon-ivy-pan"
    case leaf = "AppIcon-ivy-leaf"
    case vine = "AppIcon-ivy-vine"
    case chat = "AppIcon-ivy-chat"
    case glass = "AppIcon-ivy-glass"

    enum Group: CaseIterable {
        case ivy
        case pride
        case classic
    }

    var group: Group {
        switch self {
        case .dark, .light, .midnight, .mint, .autumn: return .ivy
        case .rainbow, .progress, .trans, .bi, .nonbinary, .lesbian, .pan: return .pride
        case .leaf, .vine, .chat, .glass: return .classic
        }
    }

    static func icons(in group: Group) -> [IvyAppIcon] {
        allCases.filter { $0.group == group }
    }

    /// The name for `setAlternateIconName`; nil for the main icon.
    var alternateIconName: String? {
        self == .dark ? nil : rawValue
    }

    init(alternateIconName: String?) {
        self = alternateIconName.flatMap(IvyAppIcon.init(rawValue:)) ?? .dark
    }

    /// Name of the images in the asset catalog.
    private var assetName: String {
        self == .dark ? "default" : String(rawValue.dropFirst("AppIcon-".count))
    }

    /// A square preview; round its corners to show it.
    var previewImage: UIImage? {
        UIImage(named: "IvyAppIconPreview/" + assetName)
    }

    /// The Mac's icon: rounded, with its shadow, on the icon grid.
    var macImage: UIImage? {
        UIImage(named: "IvyMacIcon/" + assetName)
    }

    var title: String {
        switch self {
        case .dark: return IvyLocalizedString("APP_ICON_DARK", comment: "Name of the dark green app icon.")
        case .light: return IvyLocalizedString("APP_ICON_LIGHT", comment: "Name of the light cream app icon.")
        case .midnight: return IvyLocalizedString("APP_ICON_MIDNIGHT", comment: "Name of the black app icon.")
        case .mint: return IvyLocalizedString("APP_ICON_MINT", comment: "Name of the mint green app icon.")
        case .autumn: return IvyLocalizedString("APP_ICON_AUTUMN", comment: "Name of the brown and orange app icon.")
        case .rainbow: return IvyLocalizedString("APP_ICON_RAINBOW", comment: "Name of the app icon with the rainbow pride flag.")
        case .progress: return IvyLocalizedString("APP_ICON_PROGRESS", comment: "Name of the app icon with the progress pride flag.")
        case .trans: return IvyLocalizedString("APP_ICON_TRANS", comment: "Name of the app icon with the transgender flag.")
        case .bi: return IvyLocalizedString("APP_ICON_BI", comment: "Name of the app icon with the bisexual flag.")
        case .nonbinary: return IvyLocalizedString("APP_ICON_NONBINARY", comment: "Name of the app icon with the non-binary flag.")
        case .lesbian: return IvyLocalizedString("APP_ICON_LESBIAN", comment: "Name of the app icon with the lesbian flag.")
        case .pan: return IvyLocalizedString("APP_ICON_PAN", comment: "Name of the app icon with the pansexual flag.")
        case .leaf: return IvyLocalizedString("APP_ICON_LEAF", comment: "Name of the app icon with a white leaf.")
        case .vine: return IvyLocalizedString("APP_ICON_VINE", comment: "Name of the app icon with an ivy vine.")
        case .chat: return IvyLocalizedString("APP_ICON_CHAT", comment: "Name of the app icon with a leaf in a speech bubble.")
        case .glass: return IvyLocalizedString("APP_ICON_GLASS", comment: "Name of the app icon with two glass leaves.")
        }
    }
}

extension IvyAppIcon.Group {
    var title: String {
        switch self {
        case .ivy: return "Ivy"
        case .pride: return IvyLocalizedString("APP_ICON_GROUP_PRIDE", comment: "Header of the pride app icons.")
        case .classic: return IvyLocalizedString("APP_ICON_GROUP_CLASSIC", comment: "Header of Ivy's earlier app icon designs.")
        }
    }
}

// MARK: - Choosing

@MainActor
enum IvyAppIcons {

    private static let choiceKey = "IvyAppIconChoice"
    private static let prideInJuneKey = "IvyAppIconPrideInJune"

    /// Whether this device can change the app icon.
    static var isAvailable: Bool {
#if targetEnvironment(macCatalyst)
        return true
#else
        return UIApplication.shared.supportsAlternateIcons
#endif
    }

    /// The icon the user chose.
    static var chosen: IvyAppIcon {
        get { UserDefaults.standard.string(forKey: choiceKey).flatMap(IvyAppIcon.init(rawValue:)) ?? .dark }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: choiceKey) }
    }

    /// Whether June shows the rainbow icon. Off by default.
    static var prideInJune: Bool {
        get { UserDefaults.standard.bool(forKey: prideInJuneKey) }
        set { UserDefaults.standard.set(newValue, forKey: prideInJuneKey) }
    }

    /// The icon to show now: the rainbow in June when asked for, otherwise
    /// the chosen one.
    nonisolated static func effectiveIcon(chosen: IvyAppIcon, prideInJune: Bool, now: Date = Date(), calendar: Calendar = .current) -> IvyAppIcon {
        if prideInJune, calendar.component(.month, from: now) == 6, chosen.group != .pride {
            return .rainbow
        }
        return chosen
    }

    static var current: IvyAppIcon {
        effectiveIcon(chosen: chosen, prideInJune: prideInJune)
    }

    static func choose(_ icon: IvyAppIcon) {
        chosen = icon
        apply()
    }

    /// Shows the icon that should show now, when it doesn't yet. Called at
    /// launch and whenever Ivy becomes active, so June starts and ends by
    /// itself.
    static func apply() {
        guard isAvailable else {
            return
        }
        let icon = current
#if targetEnvironment(macCatalyst)
        IvyMenuBar.shared.setAppIcon(icon == .dark ? nil : icon.macImage?.pngData())
#else
        guard IvyAppIcon(alternateIconName: UIApplication.shared.alternateIconName) != icon else {
            return
        }
        UIApplication.shared.setAlternateIconName(icon.alternateIconName) { error in
            if let error {
                Logger.warn("Couldn't change the app icon: \(error)")
            }
        }
#endif
    }

    static func start() {
        NotificationCenter.default.addObserver(forName: .OWSApplicationDidBecomeActive, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { apply() }
        }
        apply()
    }

    static var settingsTitle: String {
        OWSLocalizedString("SETTINGS_APPEARANCE_APP_ICON", comment: "The title for the app icon section in the appearance settings.")
    }

    /// Rounds a preview like an app icon.
    static func roundCorners(of view: UIView, size: CGFloat) {
        view.layer.cornerRadius = size * 0.2237
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
    }
}

// MARK: - Picker

/// Settings > Appearance > App Icon: the current icon, then the Ivy, Pride
/// and Classic icons in grids, and the switch for pride in June.
final class IvyAppIconViewController: OWSTableViewController2 {

    var onChange: (() -> Void)?

    private static var isMac: Bool { UIDevice.current.userInterfaceIdiom == .mac }
    private static var columns: Int { isMac ? 7 : 4 }
    private static var iconSize: CGFloat { isMac ? 50 : 60 }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = IvyAppIcons.settingsTitle
        updateTableContents()
    }

    private func updateTableContents() {
        let contents = OWSTableContents(title: IvyAppIcons.settingsTitle)
        let current = IvyAppIcons.current

        let currentSection = OWSTableSection()
        currentSection.add(OWSTableItem(customCellBlock: {
            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none
            let imageView = UIImageView(image: current.previewImage)
            IvyAppIcons.roundCorners(of: imageView, size: 64)
            imageView.autoSetDimensions(to: .square(64))
            let name = UILabel()
            name.text = current.title
            name.font = UIFont.dynamicTypeHeadline
            name.textColor = .Signal.label
            let detail = UILabel()
            detail.text = IvyLocalizedString("APP_ICON_CURRENT", comment: "Under the name of the app icon in use, on the App Icon page.")
            detail.font = .dynamicTypeSubheadline
            detail.textColor = .Signal.secondaryLabel
            let texts = UIStackView(arrangedSubviews: [name, detail])
            texts.axis = .vertical
            texts.spacing = 2
            let row = UIStackView(arrangedSubviews: [imageView, texts])
            row.spacing = 14
            row.alignment = .center
            cell.contentView.addSubview(row)
            row.autoPinEdgesToSuperviewMargins()
            return cell
        }))
        if Self.isMac {
            currentSection.footerTitle = IvyLocalizedString("APP_ICON_MAC_FOOTER", comment: "Under the current app icon on the Mac: the icon changes in the Dock while Ivy runs.")
        }
        contents.add(currentSection)

        for group in IvyAppIcon.Group.allCases {
            let section = OWSTableSection()
            section.headerTitle = group.title
            let icons = IvyAppIcon.icons(in: group)
            section.add(OWSTableItem(customCellBlock: { [weak self] in
                self?.gridCell(icons: icons, selected: current) ?? UITableViewCell()
            }))
            if group == .pride {
                section.add(.switch(
                    withText: IvyLocalizedString("APP_ICON_PRIDE_IN_JUNE", comment: "Switch on the App Icon page: show the rainbow icon in June."),
                    isOn: { IvyAppIcons.prideInJune },
                    actionBlock: { [weak self] sender in
                        IvyAppIcons.prideInJune = sender.isOn
                        IvyAppIcons.apply()
                        self?.didChange()
                    },
                ))
                section.footerTitle = IvyLocalizedString("APP_ICON_PRIDE_IN_JUNE_FOOTER", comment: "Footer under the pride in June switch.")
            }
            contents.add(section)
        }

        self.contents = contents
    }

    private func didChange() {
        updateTableContents()
        onChange?()
    }

    private func gridCell(icons: [IvyAppIcon], selected: IvyAppIcon) -> UITableViewCell {
        let cell = OWSTableItem.newCell()
        cell.selectionStyle = .none
        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 14
        var index = 0
        while index < icons.count {
            let row = UIStackView()
            row.axis = .horizontal
            row.distribution = .fillEqually
            row.spacing = 6
            for column in 0..<Self.columns {
                let position = index + column
                if position < icons.count {
                    row.addArrangedSubview(tile(for: icons[position], isSelected: icons[position] == selected))
                } else {
                    row.addArrangedSubview(UIView())
                }
            }
            grid.addArrangedSubview(row)
            index += Self.columns
        }
        cell.contentView.addSubview(grid)
        grid.autoPinEdgesToSuperviewMargins(with: UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0))
        return cell
    }

    private func tile(for icon: IvyAppIcon, isSelected: Bool) -> UIView {
        let size = Self.iconSize
        let imageView = UIImageView(image: icon.previewImage)
        IvyAppIcons.roundCorners(of: imageView, size: size)
        imageView.autoSetDimensions(to: .square(size))

        // A green ring around the chosen icon.
        let ring = UIView()
        ring.layer.cornerRadius = (size + 10) * 0.2237
        ring.layer.cornerCurve = .continuous
        ring.layer.borderWidth = 2.5
        ring.layer.borderColor = isSelected ? UIColor.Signal.accent.cgColor : UIColor.clear.cgColor
        ring.addSubview(imageView)
        imageView.autoCenterInSuperview()
        ring.autoSetDimensions(to: .square(size + 10))
        ring.isUserInteractionEnabled = false

        let label = UILabel()
        label.text = icon.title
        label.font = isSelected ? UIFont.dynamicTypeCaption1Clamped.semibold() : .dynamicTypeCaption1Clamped
        label.textColor = isSelected ? .Signal.label : .Signal.secondaryLabel
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8

        let stack = UIStackView(arrangedSubviews: [ring, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 5
        stack.isUserInteractionEnabled = false

        let button = UIButton(type: .custom)
        button.addSubview(stack)
        stack.autoPinEdgesToSuperviewEdges()
        if isSelected {
            let check = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
            check.tintColor = .Signal.accent
            check.backgroundColor = .Signal.secondaryGroupedBackground
            check.layer.cornerRadius = 10
            check.clipsToBounds = true
            button.addSubview(check)
            check.autoSetDimensions(to: .square(20))
            check.autoPinEdge(.top, to: .top, of: ring, withOffset: -6)
            check.autoPinEdge(.trailing, to: .trailing, of: ring, withOffset: 6)
        }
        button.accessibilityLabel = icon.title
        button.accessibilityTraits = isSelected ? [.button, .selected] : .button
        button.addAction(UIAction { [weak self] _ in
            IvyAppIcons.choose(icon)
            self?.didChange()
        }, for: .touchUpInside)
        return button
    }
}
