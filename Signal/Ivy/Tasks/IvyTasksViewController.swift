//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// All tasks, grouped by when they're due, optionally filtered by list.
final class IvyTasksViewController: OWSTableViewController2 {

    /// Nil shows every task.
    private var selectedListId: String?
    private var showsDone = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = IvyTaskUI.tasksTitle
        if navigationController?.viewControllers.first === self {
            navigationItem.leftBarButtonItem = .doneButton(dismissingFrom: self)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateTableContents),
            name: IvyTaskManager.tasksDidChange,
            object: nil,
        )
        updateTableContents()
    }

    @objc
    private func updateTableContents() {
        let manager = IvyTaskManager.shared
        let lists = manager.lists()
        if let selectedListId, !lists.contains(where: { $0.id == selectedListId }) {
            self.selectedListId = nil
        }
        let listNames = Dictionary(uniqueKeysWithValues: lists.map { ($0.id, $0.name) })
        let tasks = manager.allTasks().filter { selectedListId == nil || $0.listId == selectedListId }

        title = selectedListId.flatMap { listNames[$0] } ?? IvyTaskUI.tasksTitle
        updateBarButtons(lists: lists)

        let contents = OWSTableContents(title: title)
        let now = Date()
        let grouped = Dictionary(grouping: tasks) { $0.group(at: now) }

        if tasks.filter({ !$0.isDone }).isEmpty {
            let emptySection = OWSTableSection()
            emptySection.customHeaderView = Self.emptyStateView()
            contents.add(emptySection)
        }
        for group in IvyTask.Group.allCases where group != .done {
            guard let groupTasks = grouped[group], !groupTasks.isEmpty else {
                continue
            }
            let section = OWSTableSection()
            section.headerTitle = IvyTaskUI.title(for: group)
            for task in groupTasks {
                section.add(item(for: task, listName: selectedListId == nil ? task.listId.flatMap { listNames[$0] } : nil, now: now))
            }
            contents.add(section)
        }
        if let doneTasks = grouped[.done], !doneTasks.isEmpty {
            let section = OWSTableSection()
            section.headerTitle = IvyTaskUI.title(for: .done)
            if showsDone {
                for task in doneTasks.prefix(Self.maxDoneTasks) {
                    section.add(item(for: task, listName: nil, now: now))
                }
            }
            let toggleTitle = showsDone
                ? IvyLocalizedString("TASKS_HIDE_DONE", comment: "Button that hides the tasks that are done.")
                : String.localizedStringWithFormat(
                    IvyLocalizedString("TASKS_SHOW_DONE_FORMAT", comment: "Button that shows the tasks that are done. Embeds {{ how many }}."),
                    doneTasks.count,
                )
            section.add(.actionItem(withText: toggleTitle) { [weak self] in
                guard let self else { return }
                showsDone.toggle()
                updateTableContents()
            })
            contents.add(section)
        }
        self.contents = contents
    }

    /// Done tasks shown at most, most recent first.
    private static let maxDoneTasks = 50

    // MARK: - Rows

    private func item(for task: IvyTask, listName: String?, now: Date) -> OWSTableItem {
        return OWSTableItem(
            customCellBlock: {
                let cell = OWSTableItem.newCell()
                let row = IvyTaskRowView(task: task, listName: listName, now: now)
                cell.contentView.addSubview(row)
                row.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    row.topAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.topAnchor),
                    row.bottomAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.bottomAnchor),
                    row.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                    row.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
                ])
                cell.accessibilityLabel = task.title
                cell.accessibilityValue = IvyTaskUI.subtitle(for: task, listName: listName)
                if task.isDone {
                    cell.accessibilityTraits.insert(.selected)
                }
                return cell
            },
            actionBlock: { [weak self] in
                self?.ivyPresentTaskEditor(task, isNew: false)
            },
            contextMenuActionProvider: { [weak self] _ in
                self?.menu(for: task)
            },
        )
    }

    private func menu(for task: IvyTask) -> UIMenu {
        let manager = IvyTaskManager.shared
        var children = [UIMenuElement]()
        if task.isDone {
            children.append(UIAction(
                title: IvyLocalizedString("TASK_MARK_OPEN", comment: "Action that marks a done task as not done."),
                image: UIImage(systemName: "circle"),
            ) { _ in manager.setDone(id: task.id, false) })
        } else {
            children.append(UIAction(
                title: IvyLocalizedString("TASK_MARK_DONE", comment: "Action that marks a task as done."),
                image: UIImage(systemName: "checkmark.circle"),
            ) { _ in manager.setDone(id: task.id, true) })
            children.append(UIAction(
                title: IvyLocalizedString("TASK_DUE_TOMORROW", comment: "Action that moves a task's due date to tomorrow."),
                image: UIImage(systemName: "sunrise"),
            ) { _ in manager.moveToTomorrow(id: task.id) })
        }
        if let source = task.source {
            children.append(UIAction(
                title: IvyLocalizedString("TASK_SHOW_MESSAGE", comment: "Action that opens the message a task was made from."),
                image: UIImage(systemName: "text.bubble"),
            ) { [weak self] _ in self?.showMessage(source.message) })
        }
        children.append(UIAction(
            title: IvyLocalizedString("TASK_DELETE", comment: "Action that deletes a task."),
            image: UIImage(systemName: "trash"),
            attributes: .destructive,
        ) { _ in manager.delete(id: task.id) })
        return UIMenu(children: children)
    }

    private func showMessage(_ reference: IvyMessageReference) {
        IvyTaskEditorViewController.showMessage(reference, from: self)
    }

    // MARK: - Lists

    private func updateBarButtons(lists: [IvyTaskList]) {
        let addButton = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                ivyPresentTaskEditor(IvyTask(title: "", listId: selectedListId), isNew: true)
            },
        )
        addButton.accessibilityLabel = IvyLocalizedString("TASK_NEW", comment: "Button that makes a new task.")

        let listButton = UIBarButtonItem(
            title: nil,
            image: UIImage(systemName: "line.3.horizontal.decrease.circle"),
            primaryAction: nil,
            menu: listMenu(lists: lists),
        )
        listButton.accessibilityLabel = IvyLocalizedString("TASK_LISTS", comment: "Title of the menu that chooses and manages task lists.")
        navigationItem.rightBarButtonItems = [addButton, listButton]
    }

    private func listMenu(lists: [IvyTaskList]) -> UIMenu {
        let allTasks = UIAction(
            title: IvyLocalizedString("TASKS_ALL", comment: "Shows the tasks of every list."),
            image: UIImage(systemName: "tray.full"),
            state: selectedListId == nil ? .on : .off,
        ) { [weak self] _ in
            self?.selectList(nil)
        }
        let listActions = lists.map { list in
            UIAction(title: list.name, image: UIImage(systemName: "list.bullet"), state: selectedListId == list.id ? .on : .off) { [weak self] _ in
                self?.selectList(list.id)
            }
        }
        var manage = [UIMenuElement]()
        manage.append(UIAction(
            title: IvyLocalizedString("TASK_LIST_NEW", comment: "Action that makes a new task list."),
            image: UIImage(systemName: "plus"),
        ) { [weak self] _ in
            self?.editList(nil)
        })
        if let list = lists.first(where: { $0.id == selectedListId }) {
            manage.append(UIAction(
                title: IvyLocalizedString("TASK_LIST_RENAME", comment: "Action that renames a task list."),
                image: UIImage(systemName: "pencil"),
            ) { [weak self] _ in
                self?.editList(list)
            })
            manage.append(UIAction(
                title: IvyLocalizedString("TASK_LIST_DELETE", comment: "Action that deletes a task list. Its tasks stay."),
                image: UIImage(systemName: "trash"),
                attributes: .destructive,
            ) { [weak self] _ in
                self?.confirmDelete(list)
            })
        }
        return UIMenu(children: [
            UIMenu(options: .displayInline, children: [allTasks] + listActions),
            UIMenu(options: .displayInline, children: manage),
        ])
    }

    private func selectList(_ listId: String?) {
        selectedListId = listId
        updateTableContents()
    }

    private func editList(_ list: IvyTaskList?) {
        let alert = UIAlertController(
            title: list == nil
                ? IvyLocalizedString("TASK_LIST_NEW", comment: "Action that makes a new task list.")
                : IvyLocalizedString("TASK_LIST_RENAME", comment: "Action that renames a task list."),
            message: nil,
            preferredStyle: .alert,
        )
        alert.addTextField { field in
            field.text = list?.name
            field.placeholder = IvyLocalizedString("TASK_LIST_NAME_PLACEHOLDER", comment: "Placeholder of the name of a task list.")
            field.autocapitalizationType = .sentences
        }
        alert.addAction(UIAlertAction(title: CommonStrings.cancelButton, style: .cancel))
        alert.addAction(UIAlertAction(title: CommonStrings.saveButton, style: .default) { [weak self, weak alert] _ in
            let name = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { return }
            var changed = list ?? IvyTaskList(name: name)
            changed.name = name
            IvyTaskManager.shared.save(changed)
            self?.selectList(changed.id)
        })
        present(alert, animated: true)
    }

    private func confirmDelete(_ list: IvyTaskList) {
        let sheet = ActionSheetController(
            title: String.localizedStringWithFormat(
                IvyLocalizedString("TASK_LIST_DELETE_TITLE_FORMAT", comment: "Title when deleting a task list. Embeds {{ the list's name }}."),
                list.name,
            ),
            message: IvyLocalizedString("TASK_LIST_DELETE_MESSAGE", comment: "Explains that deleting a task list keeps its tasks."),
        )
        sheet.addAction(ActionSheetAction(
            title: IvyLocalizedString("TASK_LIST_DELETE", comment: "Action that deletes a task list. Its tasks stay."),
            style: .destructive,
        ) { [weak self] _ in
            IvyTaskManager.shared.delete(list: list)
            self?.selectList(nil)
        })
        sheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(sheet)
    }

    // MARK: - Empty

    private static func emptyStateView() -> UIView {
        let iconView = UIImageView(image: UIImage(systemName: "checklist"))
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 36, weight: .light)
        iconView.tintColor = .Signal.tertiaryLabel
        iconView.contentMode = .center

        let titleLabel = UILabel()
        titleLabel.text = IvyLocalizedString("TASKS_EMPTY_TITLE", comment: "Title shown in the list of tasks when there are no open tasks.")
        titleLabel.font = .dynamicTypeHeadline
        titleLabel.textColor = .Signal.label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

#if targetEnvironment(macCatalyst)
        let format = IvyLocalizedString(
            "TASKS_EMPTY_CLICK_FORMAT",
            comment: "Shown in the list of tasks when there are none, on the Mac. Embeds {{ the name of the Add Task action }}.",
        )
#else
        let format = IvyLocalizedString(
            "TASKS_EMPTY_TOUCH_FORMAT",
            comment: "Shown in the list of tasks when there are none, on iPhone and iPad. Embeds {{ the name of the Add Task action }}.",
        )
#endif
        let bodyLabel = UILabel()
        bodyLabel.text = String(format: format, IvyTaskUI.addTaskTitle)
        bodyLabel.font = .dynamicTypeSubheadline
        bodyLabel.textColor = .Signal.secondaryLabel
        bodyLabel.textAlignment = .center
        bodyLabel.numberOfLines = 0

        let stackView = UIStackView(arrangedSubviews: [iconView, titleLabel, bodyLabel])
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 8
        stackView.setCustomSpacing(16, after: iconView)

        let container = UIView()
        container.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: container.topAnchor, constant: 48),
            stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),
            stackView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: container.layoutMarginsGuide.leadingAnchor, constant: 16),
            stackView.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
        ])
        return container
    }
}

// MARK: - Row

/// A task in a list: a checkbox, the title and a line with its details.
final class IvyTaskRowView: UIView {

    let checkbox = UIButton(type: .system)
    let titleLabel = UILabel()
    let subtitleLabel = UILabel()

    init(task: IvyTask, listName: String?, now: Date) {
        super.init(frame: .zero)

        var configuration = UIButton.Configuration.plain()
        configuration.image = IvyTaskUI.checkboxImage(isDone: task.isDone)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        configuration.contentInsets = .zero
        configuration.baseForegroundColor = task.isDone ? .Signal.accent : .Signal.tertiaryLabel
        checkbox.configuration = configuration
        checkbox.accessibilityLabel = task.isDone
            ? IvyLocalizedString("TASK_MARK_OPEN", comment: "Action that marks a done task as not done.")
            : IvyLocalizedString("TASK_MARK_DONE", comment: "Action that marks a task as done.")
        checkbox.addAction(UIAction { _ in
            IvyTaskManager.shared.setDone(id: task.id, !task.isDone)
        }, for: .primaryActionTriggered)
        checkbox.setContentHuggingPriority(.required, for: .horizontal)

        let title = NSMutableAttributedString()
        if let marker = IvyTaskUI.marker(for: task.priority), !task.isDone {
            title.append(NSAttributedString(string: marker + " ", attributes: [.foregroundColor: UIColor.Signal.accent]))
        }
        var titleAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.Signal.label]
        if task.isDone {
            titleAttributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            titleAttributes[.foregroundColor] = UIColor.Signal.secondaryLabel
        }
        title.append(NSAttributedString(string: task.title, attributes: titleAttributes))
        titleLabel.font = .dynamicTypeBody
        titleLabel.attributedText = title
        titleLabel.numberOfLines = 2

        let subtitle = IvyTaskUI.subtitle(for: task, listName: listName)
        subtitleLabel.text = subtitle
        subtitleLabel.font = .dynamicTypeFootnote
        subtitleLabel.textColor = task.isOverdue(at: now) ? .Signal.red : .Signal.secondaryLabel
        subtitleLabel.isHidden = subtitle == nil

        let sourceIcon = UIImageView(image: UIImage(systemName: "text.bubble"))
        sourceIcon.tintColor = .Signal.tertiaryLabel
        sourceIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .footnote)
        sourceIcon.isHidden = task.source == nil
        sourceIcon.setContentHuggingPriority(.required, for: .horizontal)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        let stack = UIStackView(arrangedSubviews: [checkbox, textStack, sourceIcon])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
