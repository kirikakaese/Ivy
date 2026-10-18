//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// Makes or edits a calendar event.
final class IvyEventEditorViewController: OWSTableViewController2 {

    private var event: IvyEvent
    private let isNew: Bool

    init(event: IvyEvent, isNew: Bool) {
        self.event = event
        self.isNew = isNew
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = isNew
            ? IvyLocalizedString("EVENT_NEW", comment: "Action that makes a new calendar event.")
            : IvyLocalizedString("EVENT_EDIT_TITLE", comment: "Title of the screen that edits a calendar event.")
        navigationItem.leftBarButtonItem = .cancelButton(dismissingFrom: self)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: isNew ? IvyLocalizedString("TASK_ADD_BUTTON", comment: "Button that adds a new task.") : CommonStrings.saveButton,
            style: .done,
            target: self,
            action: #selector(save),
        )
        updateSaveButton()
        updateTableContents()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if isNew, event.title.isEmpty {
            titleField.becomeFirstResponder()
        }
    }

    // MARK: - Saving

    private func updateSaveButton() {
        navigationItem.rightBarButtonItem?.isEnabled = !event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The event as it would be saved.
    private var cleanedEvent: IvyEvent {
        var event = self.event
        event.title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        event.location = event.location.trimmingCharacters(in: .whitespacesAndNewlines)
        event.notes = event.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return event
    }

    @objc
    private func save() {
        view.endEditing(true)
        let event = cleanedEvent
        guard !event.title.isEmpty else {
            return
        }
        IvyEventManager.shared.save(event)
        if isNew, event.source != nil {
            presentingViewController?.presentToast(text: IvyLocalizedString("EVENT_ADDED", comment: "Shown after an event was made from a message."))
        }
        dismiss(animated: true)
    }

    private func deleteEvent() {
        let sheet = ActionSheetController(
            title: IvyLocalizedString("EVENT_DELETE_CONFIRM", comment: "Asks whether to delete a calendar event."),
            message: event.recurrence == nil ? nil : IvyLocalizedString("EVENT_DELETE_REPEATING", comment: "Explains that deleting a repeating event deletes all of its occurrences."),
        )
        sheet.addAction(ActionSheetAction(title: CommonStrings.deleteButton, style: .destructive) { [weak self] _ in
            guard let self else { return }
            IvyEventManager.shared.delete(id: event.id)
            dismiss(animated: true)
        })
        sheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(sheet)
    }

    // MARK: - Contents

    private lazy var titleField = makeField(
        placeholder: IvyLocalizedString("EVENT_TITLE_PLACEHOLDER", comment: "Placeholder of a calendar event's title."),
    ) { [weak self] text in
        self?.event.title = text
        self?.updateSaveButton()
    }

    private lazy var locationField = makeField(
        placeholder: IvyLocalizedString("EVENT_LOCATION_PLACEHOLDER", comment: "Placeholder of a calendar event's location."),
    ) { [weak self] text in
        self?.event.location = text
    }

    private func makeField(placeholder: String, onChange: @escaping (String) -> Void) -> UITextField {
        let field = UITextField()
        field.font = .dynamicTypeBody
        field.placeholder = placeholder
        field.returnKeyType = .done
        field.autocapitalizationType = .sentences
        field.addAction(UIAction { [weak field] _ in onChange(field?.text ?? "") }, for: .editingChanged)
        field.addAction(UIAction { [weak field] _ in field?.resignFirstResponder() }, for: .editingDidEndOnExit)
        return field
    }

    private lazy var notesView: TextViewWithPlaceholder = {
        let view = TextViewWithPlaceholder()
        view.placeholderText = IvyLocalizedString("TASK_NOTES_PLACEHOLDER", comment: "Placeholder of a task's notes.")
        view.delegate = self
        return view
    }()

    private func updateTableContents() {
        let contents = OWSTableContents()

        let textSection = OWSTableSection()
        titleField.text = event.title
        textSection.add(Self.item(containing: titleField))
        locationField.text = event.location
        textSection.add(Self.item(containing: locationField))
        contents.add(textSection)

        contents.add(timeSection())
        contents.add(optionsSection())

        let notesSection = OWSTableSection()
        notesView.text = event.notes
        notesSection.add(Self.item(containing: notesView, minimumHeight: 88))
        contents.add(notesSection)

        if let source = event.source {
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
                    IvyTaskEditorViewController.showMessage(source.message, from: self)
                })
            }
            contents.add(section)
        }

        let shareSection = OWSTableSection()
        shareSection.add(.disclosureItem(
            withText: IvyLocalizedString("EVENT_SEND_TO_CHAT", comment: "Action that sends an event as a calendar file in a chat."),
        ) { [weak self] in
            guard let self else { return }
            let event = cleanedEvent
            guard !event.title.isEmpty else { return }
            ivySendEventToChat(event)
        })
        shareSection.add(.disclosureItem(
            withText: IvyLocalizedString("EVENT_EXPORT", comment: "Action that saves one event as a calendar file."),
        ) { [weak self] in
            guard let self else { return }
            let event = cleanedEvent
            guard !event.title.isEmpty else { return }
            ivyExportCalendarFile([event])
        })
        shareSection.footerTitle = IvyLocalizedString(
            "EVENT_SHARE_FOOTER",
            comment: "Explains that a shared event is a calendar file that other apps can open.",
        )
        contents.add(shareSection)

        if !isNew {
            let deleteSection = OWSTableSection()
            deleteSection.add(.actionItem(
                withText: IvyLocalizedString("EVENT_DELETE", comment: "Action that deletes a calendar event."),
                textColor: .Signal.red,
            ) { [weak self] in
                self?.deleteEvent()
            })
            contents.add(deleteSection)
        }

        self.contents = contents
    }

    // MARK: Time

    private func timeSection() -> OWSTableSection {
        let section = OWSTableSection()
        section.add(.switch(
            withText: IvyLocalizedString("TASK_ALL_DAY", comment: "Switch that makes a task due on a day without a time."),
            isOn: { [weak self] in self?.event.isAllDay ?? false },
            actionBlock: { [weak self] sender in self?.setAllDay(sender.isOn) },
        ))
        section.add(Self.item(
            title: IvyLocalizedString("EVENT_STARTS", comment: "Row that shows and changes when a calendar event starts."),
            accessory: datePicker(date: event.startAt) { [weak self] date in self?.setStart(date) },
        ))
        section.add(Self.item(
            title: IvyLocalizedString("EVENT_ENDS", comment: "Row that shows and changes when a calendar event ends."),
            accessory: datePicker(date: event.endAt, minimumDate: event.startAt) { [weak self] date in self?.setEnd(date) },
        ))
        return section
    }

    private func datePicker(date: Date, minimumDate: Date? = nil, onChange: @escaping (Date) -> Void) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.preferredDatePickerStyle = .compact
        picker.datePickerMode = event.isAllDay ? .date : .dateAndTime
        picker.minimumDate = minimumDate.map { event.isAllDay ? Calendar.current.startOfDay(for: $0) : $0 }
        picker.date = date
        picker.addAction(UIAction { [weak picker] _ in
            guard let picker else { return }
            onChange(picker.date)
        }, for: .valueChanged)
        return picker
    }

    private func setAllDay(_ isAllDay: Bool) {
        let calendar = Calendar.current
        event.isAllDay = isAllDay
        if isAllDay {
            event.startAt = calendar.startOfDay(for: event.startAt)
            event.endAt = max(calendar.startOfDay(for: event.endAt), event.startAt)
        } else {
            event.startAt = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: event.startAt) ?? event.startAt
            event.endAt = event.startAt.addingTimeInterval(60 * 60)
        }
        updateTableContents()
    }

    /// Moving the start keeps the event's length.
    private func setStart(_ date: Date) {
        let length = event.endAt.timeIntervalSince(event.startAt)
        event.startAt = event.isAllDay ? Calendar.current.startOfDay(for: date) : date
        event.endAt = event.startAt.addingTimeInterval(max(length, 0))
        updateTableContents()
    }

    private func setEnd(_ date: Date) {
        let end = event.isAllDay ? Calendar.current.startOfDay(for: date) : date
        event.endAt = max(end, event.startAt)
    }

    // MARK: Repeat and alert

    private func optionsSection() -> OWSTableSection {
        let section = OWSTableSection()

        let frequencies: [IvyRecurrence.Frequency?] = [nil] + IvyRecurrence.Frequency.allCases
        let repeatActions = frequencies.map { frequency in
            UIAction(title: IvyCalendarUI.title(for: frequency), state: event.recurrence?.frequency == frequency ? .on : .off) { [weak self] _ in
                guard let self else { return }
                event.recurrence = frequency.map { IvyRecurrence(frequency: $0, until: event.recurrence?.until) }
                updateTableContents()
            }
        }
        section.add(Self.item(
            title: IvyLocalizedString("EVENT_REPEAT", comment: "Row that chooses whether a calendar event repeats."),
            accessory: Self.menuButton(title: IvyCalendarUI.title(for: event.recurrence?.frequency), menu: UIMenu(children: repeatActions)),
        ))
        if event.recurrence != nil {
            section.add(.switch(
                withText: IvyLocalizedString("EVENT_REPEAT_ENDS", comment: "Switch that makes a repeating event end on a date."),
                isOn: { [weak self] in self?.event.recurrence?.until != nil },
                actionBlock: { [weak self] sender in
                    guard let self else { return }
                    let defaultEnd = Calendar.current.date(byAdding: .month, value: 3, to: event.startAt) ?? event.startAt
                    event.recurrence?.until = sender.isOn ? defaultEnd : nil
                    updateTableContents()
                },
            ))
            if let until = event.recurrence?.until {
                let picker = UIDatePicker()
                picker.preferredDatePickerStyle = .compact
                picker.datePickerMode = .date
                picker.minimumDate = event.startAt
                picker.date = until
                picker.addAction(UIAction { [weak self, weak picker] _ in
                    guard let self, let picker else { return }
                    // The whole last day counts.
                    let day = Calendar.current.startOfDay(for: picker.date)
                    event.recurrence?.until = Calendar.current.date(byAdding: .second, value: 86_399, to: day)
                }, for: .valueChanged)
                section.add(Self.item(
                    title: IvyLocalizedString("EVENT_REPEAT_UNTIL", comment: "Row that shows the last day a repeating event happens."),
                    accessory: picker,
                ))
            }
        }

        let alertActions = IvyCalendarUI.alertChoices.map { minutes in
            UIAction(title: IvyCalendarUI.title(forAlert: minutes), state: event.alertMinutes == minutes ? .on : .off) { [weak self] _ in
                self?.event.alertMinutes = minutes
                self?.updateTableContents()
            }
        }
        section.add(Self.item(
            title: IvyLocalizedString("EVENT_ALERT", comment: "Row that chooses when a calendar event notifies."),
            accessory: Self.menuButton(title: IvyCalendarUI.title(forAlert: event.alertMinutes), menu: UIMenu(children: alertActions)),
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

extension IvyEventEditorViewController: TextViewWithPlaceholderDelegate {
    func textViewDidUpdateText(_ textView: TextViewWithPlaceholder) {
        event.notes = textView.text ?? ""
    }
}
