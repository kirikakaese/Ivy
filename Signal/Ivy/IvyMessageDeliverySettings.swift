//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// The "Message Delivery" section of Settings > Notifications.
///
/// Ivy receives no push notifications. On the Mac it receives messages while
/// it runs, so it can open at login. On iPhone and iPad it relies on
/// Background App Refresh while it is not in the foreground.
enum IvyMessageDeliverySettings {

    @MainActor
    static func buildSection(from viewController: OWSTableViewController2, onChange: @escaping () -> Void) -> OWSTableSection? {
        let section = OWSTableSection()
        section.headerTitle = IvyLocalizedString(
            "NOTIFICATIONS_DELIVERY_TITLE",
            comment: "Header of the section in notification settings that explains how messages arrive.",
        )
#if targetEnvironment(macCatalyst)
        guard MacLoginItem.isAvailable else {
            return nil
        }
        section.footerTitle = IvyLocalizedString(
            "NOTIFICATIONS_OPEN_AT_LOGIN_FOOTER",
            comment: "Footer of the 'Open at Login' switch on the Mac.",
        )
        section.add(.switch(
            withText: IvyLocalizedString("NOTIFICATIONS_OPEN_AT_LOGIN", comment: "Switch that opens Ivy when the user logs in to the Mac."),
            isOn: { MacLoginItem.isEnabled },
            actionBlock: { [weak viewController] uiSwitch in
                do {
                    try MacLoginItem.setEnabled(uiSwitch.isOn)
                } catch {
                    Logger.warn("Couldn't change the login item: \(error)")
                    viewController?.presentToast(text: IvyLocalizedString(
                        "NOTIFICATIONS_OPEN_AT_LOGIN_ERROR",
                        comment: "Shown when Ivy could not add or remove its login item.",
                    ))
                }
                onChange()
            },
        ))
#else
        section.footerTitle = IvyLocalizedString(
            "NOTIFICATIONS_BACKGROUND_REFRESH_FOOTER",
            comment: "Footer explaining that on iPhone and iPad messages arrive in the background only through Background App Refresh.",
        )
        let isOn = UIApplication.shared.backgroundRefreshStatus == .available
        section.add(.disclosureItem(
            withText: IvyLocalizedString("NOTIFICATIONS_BACKGROUND_REFRESH", comment: "Item showing whether Background App Refresh is on; opens the system settings."),
            accessoryText: isOn
                ? IvyLocalizedString("NOTIFICATIONS_BACKGROUND_REFRESH_ON", comment: "Background App Refresh is turned on.")
                : IvyLocalizedString("NOTIFICATIONS_BACKGROUND_REFRESH_OFF", comment: "Background App Refresh is turned off."),
            actionBlock: {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            },
        ))
#endif
        return section
    }
}

#if targetEnvironment(macCatalyst)

/// Ivy's login item, through `SMAppService` from the ServiceManagement
/// framework. The framework is loaded at run time because its Swift interface
/// is not available to Mac Catalyst apps.
enum MacLoginItem {

    private static let service: NSObject? = {
        guard
            dlopen("/System/Library/Frameworks/ServiceManagement.framework/ServiceManagement", RTLD_LAZY) != nil,
            let serviceClass = NSClassFromString("SMAppService") as AnyObject?,
            serviceClass.responds(to: NSSelectorFromString("mainAppService"))
        else {
            return nil
        }
        return serviceClass.perform(NSSelectorFromString("mainAppService"))?.takeUnretainedValue() as? NSObject
    }()

    static var isAvailable: Bool { service != nil }

    /// `SMAppServiceStatusEnabled`
    private static let statusEnabled = 1

    static var isEnabled: Bool {
        return (service?.value(forKey: "status") as? Int) == statusEnabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard let service else {
            throw OWSGenericError("The login item service is not available.")
        }
        let selector = NSSelectorFromString(enabled ? "registerAndReturnError:" : "unregisterAndReturnError:")
        guard service.responds(to: selector) else {
            throw OWSGenericError("The login item service does not respond to \(selector).")
        }
        typealias Method = @convention(c) (NSObject, Selector, UnsafeMutablePointer<NSError?>?) -> Bool
        let method = unsafeBitCast(service.method(for: selector), to: Method.self)
        var error: NSError?
        guard method(service, selector, &error) else {
            throw error ?? OWSGenericError("The login item could not be changed.")
        }
    }
}

#endif
