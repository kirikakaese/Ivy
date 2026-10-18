//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// Makes or edits a task. Changes are saved with Save (or Add) and dropped
/// with Cancel.
final class IvyTaskEditorViewController: OWSTableViewController2 {

    private var task: IvyTask
    private let isNew: Bool
    private var lists: [IvyTaskList] = []
    /// The subtask whose title field gets the focus after the next reload.
    private var subtaskToFocus: String?

    init(task: IvyTask, isNew: Bool) {
        self.task = task
        self.isNew = isNew
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = isNew
            ? IvyLocalizedString("TASK_NEW", comment: "Button that makes a new task.")
            : IvyLocalizedString("TASK_EDIT_TITLE", comment: "Title of the screen that edits a task.")
        navigationItem.leftBarButtonItem = .cancelButton(dismissingFrom: self)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: isNew ? IvyLocalizedString("TASK_ADD_BUTTON", comment: "Button that adds a new task.") : CommonStrings.saveButton,
            style: .done,
            target: self,
            action: #selector(save),
        )
        lists = IvyTaskManager.shared.lists()
        updateSaveButton()
        updateTableContents()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if isNew, task.title.isEmpty {
            titleField.becomeFirstResponder()
        }
    }

    // MARK: - Saving

    private func updateSaveButton() {
        navigationItem.rightBarButtonItem?.isEnabled = !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @objc
    private func save() {
        view.endEditing(true)
        var task = self.task
        task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        task.notes = task.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        task.subtasks = task.subtasks.compactMap { subtask in
            let title = subtask.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            var changed = subtask
            changed.title = title
            return changed
        }
        guard !task.title.isEmpty else {
            return
        }
        IvyTaskManager.shared.save(task)
        if isNew, task.source != nil {
            presentingViewController?.presentToast(text: IvyLocalizedString("TASK_ADDED", comment: "Shown after a task was made from a message."))
        }
        dismiss(animated: true)
    }

    private func deleteTask() {
        let sheet = ActionSheetController(
            title: IvyLocalizedString("TASK_DELETE_CONFIRM", comment: "Asks whether to delete a task."),
            message: nil,
        )
        sheet.addAction(ActionSheetAction(title: CommonStrings.deleteButton, style: .destructive) { [weak self] _ in
            guard let self else { return }
            IvyTaskManager.shared.delete(id: task.id)
            dismiss(animated: true)
        })
        sheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(sheet)
    }

    // MARK: - Contents

    private lazy var titleField: UITextField = {
        let field = UITextField()
        field.font = .dynamicTypeBody
        field.placeholder = IvyLocalizedString("TASK_TITLE_PLACEHOLDER", comment: "Placeholder of a task's title.")
        field.returnKeyType = .done
        field.autocapitalizationType = .sentences
        field.addAction(UIAction { [weak self, weak field] _ in
            guard let self, let field else { return }
            task.title = field.text ?? ""
            updateSaveButton()
        }, for: .editingChanged)
        field.addAction(UIAction { [weak field] _ in field?.resignFirstResponder() }, for: .editingDidEndOnExit)
        return field
    }()

    private lazy var notesView: TextViewWithPlaceholder = {
        let view = TextViewWithPlaceholder()
        view.placeholderText = IvyLocalizedString("TASK_NOTES_PLACEHOLDER", comment: "Placeholder of a task's notes.")
        view.returnKeyType = .default
        view.delegate = self
        return view
    }()

    private func updateTableContents() {
        let contents = OWSTableContents()

        let textSection = OWSTableSection()
        titleField.text = task.title
        textSection.add(Self.item(containing: titleField))
        notesView.text = task.notes
        textSection.add(Self.item(containing: notesView, minimumHeight: 88))
        contents.add(textSection)

        contents.add(dueSection())
        contents.add(detailsSection())
        contents.add(subtasksSection())

        if let source = task.source {
            contents.add(sourceSection(source))
        }

        if !isNew {
            let deleteSection = OWSTableSection()
            deleteSection.add(.actionItem(
                withText: IvyLocalizedString("TASK_DELETE", comment: "Action that deletes a task."),
                textColor: .Signal.red,
            ) { [weak self] in
                self?.deleteTask()
            })
            contents.add(deleteSection)
        }

        self.contents = contents

        if let subtaskToFocus, let field = subtaskFields[subtaskToFocus] {
            self.subtaskToFocus = nil
            DispatchQueue.main.async { field.becomeFirstResponder() }
        }
    }

    // MARK: Due date

    private func dueSection() -> OWSTableSection {
        let section = OWSTableSection()
        section.add(.switch(
            withText: IvyLocalizedString("TASK_DUE_DATE", comment: "Switch that gives a task a due date."),
            isOn: { [weak self] in self?.task.dueAt != nil },
            actionBlock: { [weak self] sender in self?.dueDateSwitchChanged(sender) },
        ))
        guard task.dueAt != nil else {
            return section
        }

        let datePicker = UIDatePicker()
        datePicker.preferredDatePickerStyle = .compact
        datePicker.datePickerMode = task.isAllDay ? .date : .dateAndTime
        datePicker.date = task.dueAt ?? Date()
        datePicker.addAction(UIAction { [weak self, weak datePicker] _ in
            guard let self, let datePicker else { return }
            task.dueAt = task.isAllDay ? Calendar.current.startOfDay(for: datePicker.date) : datePicker.date
        }, for: .valueChanged)
        section.add(Self.item(
            title: IvyLocalizedString("TASK_DUE_DATE_ROW", comment: "Row that shows and changes a task's due date."),
            accessory: datePicker,
        ))

        section.add(.switch(
            withText: IvyLocalizedString("TASK_ALL_DAY", comment: "Switch that makes a task due on a day without a time."),
            isOn: { [weak self] in self?.task.isAllDay ?? false },
            actionBlock: { [weak self] sender in self?.allDaySwitchChanged(sender) },
        ))
        section.add(.switch(
            withText: IvyLocalizedString("TASK_REMIND", comment: "Switch that makes a task notify when it's due."),
            isOn: { [weak self] in self?.task.reminds ?? false },
            actionBlock: { [weak self] sender in self?.remindSwitchChanged(sender) },
        ))
        if task.reminds, task.isAllDay {
            section.footerTitle = String.localizedStringWithFormat(
                IvyLocalizedString("TASK_REMIND_ALL_DAY_FORMAT", comment: "Explains when an all-day task notifies. Embeds {{ a time, e.g. 9:00 }}."),
                Self.allDayReminderTimeText(),
            )
        }
        return section
    }

    private static func allDayReminderTimeText() -> String {
        let date = Calendar.current.date(bySettingHour: IvyTask.allDayReminderHour, minute: 0, second: 0, of: Date()) ?? Date()
        return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
    }

    private func dueDateSwitchChanged(_ sender: UISwitch) {
        if sender.isOn {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            task.dueAt = Calendar.current.date(bySettingHour: IvyTask.allDayReminderHour, minute: 0, second: 0, of: tomorrow)
            task.isAllDay = false
        } else {
            task.dueAt = nil
            task.isAllDay = false
            task.reminds = false
        }
        updateTableContents()
    }

    private func allDaySwitchChanged(_ sender: UISwitch) {
        task.isAllDay = sender.isOn
        if let dueAt = task.dueAt {
            task.dueAt = sender.isOn
                ? Calendar.current.startOfDay(for: dueAt)
                : Calendar.current.date(bySettingHour: IvyTask.allDayReminderHour, minute: 0, second: 0, of: dueAt)
        }
        updateTableContents()
    }

    private func remindSwitchChanged(_ sender: UISwitch) {
        task.reminds = sender.isOn
        updateTableContents()
    }

    // MARK: List and priority

    private func detailsSection() -> OWSTableSection {
        let section = OWSTableSection()

        let noList = UIAction(
            title: IvyLocalizedString("TASK_NO_LIST", comment: "Option for a task that is in no list."),
            state: task.listId == nil ? .on : .off,
        ) { [weak self] _ in
            self?.task.listId = nil
            self?.updateTableContents()
        }
        let listActions = lists.map { list in
            UIAction(title: list.name, state: task.listId == list.id ? .on : .off) { [weak self] _ in
                self?.task.listId = list.id
                self?.updateTableContents()
            }
        }
        let listName = lists.first { $0.id == task.listId }?.name
            ?? IvyLocalizedString("TASK_NO_LIST", comment: "Option for a task that is in no list.")
        section.add(Self.item(
            title: IvyLocalizedString("TASK_LIST", comment: "Row that chooses a task's list."),
            accessory: Self.menuButton(title: listName, menu: UIMenu(children: [noList] + listActions)),
        ))

        let priorityActions = IvyTask.Priority.allCases.map { priority in
            UIAction(title: IvyTaskUI.title(for: priority), state: task.priority == priority ? .on : .off) { [weak self] _ in
                self?.task.priority = priority
                self?.updateTableContents()
            }
        }
        section.add(Self.item(
            title: IvyLocalizedString("TASK_PRIORITY", comment: "Row that chooses a task's priority."),
            accessory: Self.menuButton(title: IvyTaskUI.title(for: task.priority), menu: UIMenu(children: priorityActions)),
        ))
        return section
    }

    private static func menuButton(title: String, menu: UIMenu) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.image = UIImage(systemName: "chevron.up.chevron.down")
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .footnote)
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 4
        configuration.baseForegroundColor = .Signal.secondaryLabel
        configuration.contentInsets = .zero
        let button = UIButton(configuration: configuration)
        button.menu = menu
        button.showsMenuAsPrimaryAction = true
        return button
    }

    // MARK: Subtasks

    private var subtaskFields = [String: UITextField]()

    private func subtasksSection() -> OWSTableSection {
        let section = OWSTableSection()
        section.headerTitle = IvyLocalizedString("TASK_SUBTASKS", comment: "Header of a task's subtasks.")
        subtaskFields = [:]
        for subtask in task.subtasks {
            section.add(subtaskItem(subtask))
        }
        section.add(.actionItem(
            withText: IvyLocalizedString("TASK_ADD_SUBTASK", comment: "Button that adds a subtask to a task."),
            textColor: .Signal.accent,
        ) { [weak self] in
            guard let self else { return }
            let subtask = IvyTask.Subtask(title: "")
            task.subtasks.append(subtask)
            subtaskToFocus = subtask.id
            updateTableContents()
        })
        return section
    }

    private func subtaskItem(_ subtask: IvyTask.Subtask) -> OWSTableItem {
        let checkbox = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.image = IvyTaskUI.checkboxImage(isDone: subtask.isDone)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        configuration.contentInsets = .zero
        configuration.baseForegroundColor = subtask.isDone ? .Signal.accent : .Signal.tertiaryLabel
        checkbox.configuration = configuration
        checkbox.accessibilityLabel = subtask.isDone
            ? IvyLocalizedString("TASK_MARK_OPEN", comment: "Action that marks a done task as not done.")
            : IvyLocalizedString("TASK_MARK_DONE", comment: "Action that marks a task as done.")
        checkbox.addAction(UIAction { [weak self] _ in
            guard let self, let index = task.subtasks.firstIndex(where: { $0.id == subtask.id }) else { return }
            task.subtasks[index].isDone.toggle()
            updateTableContents()
        }, for: .primaryActionTriggered)
        checkbox.setContentHuggingPriority(.required, for: .horizontal)

        let field = UITextField()
        field.text = subtask.title
        field.font = .dynamicTypeBody
        field.placeholder = IvyLocalizedString("TASK_SUBTASK_PLACEHOLDER", comment: "Placeholder of a subtask's title.")
        field.returnKeyType = .next
        field.addAction(UIAction { [weak self, weak field] _ in
            guard let self, let field, let index = task.subtasks.firstIndex(where: { $0.id == subtask.id }) else { return }
            task.subtasks[index].title = field.text ?? ""
        }, for: .editingChanged)
        field.addAction(UIAction { [weak self] _ in
            // Return adds the next subtask, like in Reminders.
            guard let self else { return }
            let next = IvyTask.Subtask(title: "")
            if let index = task.subtasks.firstIndex(where: { $0.id == subtask.id }) {
                task.subtasks.insert(next, at: index + 1)
            } else {
                task.subtasks.append(next)
            }
            subtaskToFocus = next.id
            updateTableContents()
        }, for: .editingDidEndOnExit)
        subtaskFields[subtask.id] = field

        let deleteButton = UIButton(type: .system)
        var deleteConfiguration = UIButton.Configuration.plain()
        deleteConfiguration.image = UIImage(systemName: "xmark.circle.fill")
        deleteConfiguration.baseForegroundColor = .Signal.tertiaryLabel
        deleteConfiguration.contentInsets = .zero
        deleteButton.configuration = deleteConfiguration
        deleteButton.accessibilityLabel = IvyLocalizedString("TASK_DELETE_SUBTASK", comment: "Button that removes a subtask.")
        deleteButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            task.subtasks.removeAll { $0.id == subtask.id }
            updateTableContents()
        }, for: .primaryActionTriggered)
        deleteButton.setContentHuggingPriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [checkbox, field, deleteButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        return Self.item(containing: stack)
    }

    // MARK: Source message

    private func sourceSection(_ source: IvyTask.Source) -> OWSTableSection {
        let section = OWSTableSection()
        section.headerTitle = IvyLocalizedString("TASK_FROM_MESSAGE", comment: "Header of the message a task was made from.")
        if !source.quote.isEmpty {
            let label = UILabel()
            label.text = source.quote
            label.font = .dynamicTypeSubheadline
            label.textColor = .Signal.secondaryLabel
            label.numberOfLines = 6
            section.add(Self.item(containing: label))
        }
        if !isNew {
            section.add(.disclosureItem(
                withText: IvyLocalizedString("TASK_SHOW_MESSAGE", comment: "Action that opens the message a task was made from."),
            ) { [weak self] in
                guard let self else { return }
                Self.showMessage(source.message, from: self)
            })
        }
        return section
    }

    /// Opens the chat at a task's message, or says that it's gone.
    static func showMessage(_ reference: IvyMessageReference, from viewController: UIViewController) {
        let (threadId, messageId) = SSKEnvironment.shared.databaseStorageRef.read { tx in
            (reference.chat.thread(tx: tx)?.uniqueId, reference.message(tx: tx)?.uniqueId)
        }
        guard let threadId, let messageId else {
            viewController.presentToast(text: IvyLocalizedString("TASK_MESSAGE_GONE", comment: "Shown when the message a task was made from is no longer on this device."))
            return
        }
        // Closes the task list and the editor, then opens the chat.
        let root = viewController.view.window?.rootViewController ?? viewController
        root.dismiss(animated: true) {
            SignalApp.shared.presentConversationForThread(threadUniqueId: threadId, focusMessageId: messageId, animated: true)
        }
    }

    // MARK: - Cells

    private static func item(containing view: UIView, minimumHeight: CGFloat? = nil) -> OWSTableItem {
        return OWSTableItem(customCellBlock: {
            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none
            cell.contentView.addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
            var constraints = [
                view.topAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.topAnchor),
                view.bottomAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.bottomAnchor),
                view.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
            ]
            if let minimumHeight {
                constraints.append(view.heightAnchor.constraint(greaterThanOrEqualToConstant: minimumHeight))
            }
            NSLayoutConstraint.activate(constraints)
            return cell
        })
    }

    private static func item(title: String, accessory: UIView) -> OWSTableItem {
        let label = UILabel()
        label.text = title
        label.font = .dynamicTypeBody
        label.textColor = .Signal.label
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        accessory.setContentHuggingPriority(.required, for: .horizontal)
        accessory.setContentCompressionResistancePriority(.required, for: .horizontal)
        let stack = UIStackView(arrangedSubviews: [label, accessory])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        return item(containing: stack)
    }
}

extension IvyTaskEditorViewController: TextViewWithPlaceholderDelegate {
    func textViewDidUpdateText(_ textView: TextViewWithPlaceholder) {
        task.notes = textView.text ?? ""
    }
}
