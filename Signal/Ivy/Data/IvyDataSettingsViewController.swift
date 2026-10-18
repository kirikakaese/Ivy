//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UniformTypeIdentifiers

/// Settings > Folders, Reminders and Sync: Ivy's own data, its sync with the
/// user's other Ivy devices, and encrypted export and import.
final class IvyDataSettingsViewController: OWSTableViewController2, UIDocumentPickerDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()
        title = IvyLocalizedString("IVY_DATA_TITLE", comment: "Title of the settings for Ivy's own data: folders, reminders, sync and backup.")
        updateTableContents()
    }

    private func updateTableContents() {
        let contents = OWSTableContents(title: title)

        let organizeSection = OWSTableSection()
        organizeSection.add(.disclosureItem(
            withText: IvyLocalizedString("CHAT_FOLDERS_TITLE", comment: "Title of the chat folder settings."),
            actionBlock: { [weak self] in
                self?.navigationController?.pushViewController(ChatFoldersSettingsViewController(), animated: true)
            },
        ))
        organizeSection.add(.disclosureItem(
            withText: IvyLocalizedString("REMINDERS_TITLE", comment: "Title of the list of reminders."),
            actionBlock: { [weak self] in
                self?.navigationController?.pushViewController(IvyRemindersViewController(), animated: true)
            },
        ))
        organizeSection.add(.disclosureItem(
            withText: IvyTaskUI.tasksTitle,
            actionBlock: { [weak self] in
                self?.navigationController?.pushViewController(IvyTasksViewController(), animated: true)
            },
        ))
        organizeSection.add(.disclosureItem(
            withText: IvyCalendarUI.calendarTitle,
            actionBlock: { [weak self] in
                self?.navigationController?.pushViewController(IvyCalendarViewController(), animated: true)
            },
        ))
        contents.add(organizeSection)

        let syncSection = OWSTableSection()
        syncSection.headerTitle = IvyLocalizedString("IVY_DATA_SYNC_HEADER", comment: "Header of the Ivy data sync section.")
        syncSection.footerTitle = IvyLocalizedString(
            "IVY_DATA_SYNC_FOOTER",
            comment: "Footer explaining how Ivy data syncs between the user's devices.",
        )
        syncSection.add(.actionItem(
            withText: IvyLocalizedString("IVY_DATA_SYNC_NOW", comment: "Item that asks the user's other Ivy devices for all Ivy data."),
            actionBlock: { [weak self] in
                IvyData.shared?.sync.requestSnapshotIfNeeded(force: true)
                self?.presentToast(text: IvyLocalizedString("IVY_DATA_SYNC_REQUESTED", comment: "Shown after asking the other devices for Ivy data."))
            },
        ))
        contents.add(syncSection)

        let backupSection = OWSTableSection()
        backupSection.headerTitle = IvyLocalizedString("IVY_DATA_BACKUP_HEADER", comment: "Header of the Ivy data export and import section.")
        backupSection.footerTitle = IvyLocalizedString(
            "IVY_DATA_BACKUP_FOOTER",
            comment: "Footer explaining Ivy data export and import.",
        )
        backupSection.add(.actionItem(
            withText: IvyLocalizedString("IVY_DATA_EXPORT", comment: "Item that exports all Ivy data to an encrypted file."),
            actionBlock: { [weak self] in
                self?.askForPassphrase(isExport: true) { passphrase in self?.export(passphrase: passphrase) }
            },
        ))
        backupSection.add(.actionItem(
            withText: IvyLocalizedString("IVY_DATA_IMPORT", comment: "Item that imports Ivy data from an encrypted file."),
            actionBlock: { [weak self] in
                self?.pickFileToImport()
            },
        ))
        contents.add(backupSection)

        self.contents = contents
    }

    // MARK: - Passphrase

    private static let minimumPassphraseLength = 8

    private func askForPassphrase(isExport: Bool, completion: @escaping (String) -> Void) {
        let alert = UIAlertController(
            title: isExport
                ? IvyLocalizedString("IVY_DATA_EXPORT_PASSPHRASE_TITLE", comment: "Title of the prompt for the passphrase that encrypts an Ivy data export.")
                : IvyLocalizedString("IVY_DATA_IMPORT_PASSPHRASE_TITLE", comment: "Title of the prompt for the passphrase of an Ivy data file."),
            message: isExport
                ? String.localizedStringWithFormat(
                    IvyLocalizedString("IVY_DATA_EXPORT_PASSPHRASE_MESSAGE_FORMAT", comment: "Explains the export passphrase. Embeds {{ the minimum length }}."),
                    Self.minimumPassphraseLength,
                )
                : nil,
            preferredStyle: .alert,
        )
        alert.addTextField { field in
            field.isSecureTextEntry = true
            field.textContentType = isExport ? .newPassword : .password
        }
        alert.addAction(UIAlertAction(title: CommonStrings.cancelButton, style: .cancel))
        alert.addAction(UIAlertAction(title: CommonStrings.continueButton, style: .default) { [weak self, weak alert] _ in
            let passphrase = alert?.textFields?.first?.text ?? ""
            guard !isExport || passphrase.count >= Self.minimumPassphraseLength else {
                self?.presentToast(text: String.localizedStringWithFormat(
                    IvyLocalizedString("IVY_DATA_EXPORT_PASSPHRASE_MESSAGE_FORMAT", comment: "Explains the export passphrase. Embeds {{ the minimum length }}."),
                    Self.minimumPassphraseLength,
                ))
                return
            }
            completion(passphrase)
        })
        present(alert, animated: true)
    }

    // MARK: - Export

    private func export(passphrase: String) {
        guard let store = IvyData.shared?.store else {
            showError()
            return
        }
        ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false, backgroundBlock: { modal in
            let result = Result { try IvyDataBackup.export(store.allChanges(), passphrase: passphrase) }
            DispatchQueue.main.async {
                modal.dismiss {
                    switch result {
                    case .success(let data):
                        self.share(data)
                    case .failure:
                        self.showError()
                    }
                }
            }
        })
    }

    private func share(_ data: Data) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let fileName = "Ivy \(formatter.string(from: Date())).\(IvyDataBackup.fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .completeFileProtection)
        } catch {
            showError()
            return
        }
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = self
        present(picker, animated: true)
    }

    // MARK: - Import

    private var isImporting = false

    private func pickFileToImport() {
        isImporting = true
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true)
        picker.delegate = self
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard isImporting else {
            presentToast(text: IvyLocalizedString("IVY_DATA_EXPORTED", comment: "Shown after Ivy data was exported."))
            return
        }
        isImporting = false
        guard let url = urls.first, let data = try? Data(contentsOf: url) else {
            showError()
            return
        }
        askForPassphrase(isExport: false) { [weak self] passphrase in
            self?.importData(data, passphrase: passphrase)
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        isImporting = false
    }

    private func importData(_ fileData: Data, passphrase: String) {
        guard let store = IvyData.shared?.store else {
            showError()
            return
        }
        ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false, backgroundBlock: { modal in
            let result = Result { try IvyDataBackup.import(fileData, passphrase: passphrase) }
            // Imported edits merge like edits from another device: newer
            // values on this device are kept. What changed syncs on.
            let applied = (try? result.get()).map { store.applyImported($0) }
            DispatchQueue.main.async {
                modal.dismiss {
                    switch result {
                    case .success:
                        self.presentToast(text: String.localizedStringWithFormat(
                            IvyLocalizedString("IVY_DATA_IMPORTED_FORMAT", comment: "Shown after an Ivy data import. Embeds {{ the number of changed values }}."),
                            applied ?? 0,
                        ))
                    case .failure(let error as IvyDataBackup.Error) where error == .wrongPassphrase:
                        self.showError(IvyLocalizedString("IVY_DATA_WRONG_PASSPHRASE", comment: "Shown when the passphrase of an Ivy data file is wrong."))
                    case .failure(let error as IvyDataBackup.Error) where error == .notAnIvyDataFile:
                        self.showError(IvyLocalizedString("IVY_DATA_NOT_A_FILE", comment: "Shown when the chosen file is not an Ivy data file."))
                    case .failure:
                        self.showError()
                    }
                }
            }
        })
    }

    private func showError(_ message: String? = nil) {
        OWSActionSheets.showActionSheet(
            title: IvyLocalizedString("IVY_DATA_ERROR", comment: "Title shown when an Ivy data export or import failed."),
            message: message,
        )
    }
}
