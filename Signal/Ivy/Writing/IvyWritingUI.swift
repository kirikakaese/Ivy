//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

// MARK: - Snippets in the composer

extension ConversationInputToolbar {

    /// Replaces `;trigger` with its snippet once the word is finished.
    func ivyExpandSnippet(in textView: UITextView) {
        let selection = textView.selectedRange
        guard selection.length == 0, selection.location > 1, let text = textView.text else {
            return
        }
        // Only look up snippets when a semicolon is close to the cursor.
        let nearby = (text as NSString).substring(with: NSRange(
            location: max(0, selection.location - IvySnippet.maxTriggerLength - 2),
            length: min(selection.location, IvySnippet.maxTriggerLength + 2),
        ))
        guard nearby.contains(IvySnippet.prefix), let store = IvyData.shared?.store else {
            return
        }
        guard
            let expansion = IvySnippets.expansion(in: text, cursor: selection.location, snippets: IvySnippets.all(store: store)),
            let start = textView.position(from: textView.beginningOfDocument, offset: expansion.range.location),
            let end = textView.position(from: start, offset: expansion.range.length),
            let range = textView.textRange(from: start, to: end)
        else {
            return
        }
        textView.replace(range, withText: expansion.text)
    }
}

// MARK: - Snippet settings

/// The snippets, with their triggers. Tapping one edits it.
final class IvySnippetsViewController: OWSTableViewController2 {

    static var title: String {
        IvyLocalizedString("SNIPPETS_TITLE", comment: "Title of the list of snippets: texts inserted by typing a short trigger.")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = Self.title
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .add, primaryAction: UIAction { [weak self] _ in
            self?.edit(nil)
        })
        NotificationCenter.default.addObserver(self, selector: #selector(updateTableContents), name: IvyDataStore.dataDidChange, object: nil)
        updateTableContents()
    }

    @objc
    private func updateTableContents() {
        let snippets = IvySnippets.all(store: IvyData.shared?.store)
        let contents = OWSTableContents(title: title)
        let section = OWSTableSection()
        section.footerTitle = IvyLocalizedString("SNIPPETS_FOOTER", comment: "Explains how snippets are inserted.")
        for snippet in snippets {
            section.add(.disclosureItem(
                withText: IvySnippet.prefix + snippet.trigger,
                subtitle: snippet.text,
                maxNameLines: 1,
            ) { [weak self] in
                self?.edit(snippet)
            })
        }
        if snippets.isEmpty {
            section.add(.label(
                withText: IvyLocalizedString("SNIPPETS_EMPTY", comment: "Shown in the list of snippets when there are none."),
                accessoryType: .none,
            ))
        }
        contents.add(section)
        self.contents = contents
    }

    private func edit(_ snippet: IvySnippet?) {
        navigationController?.pushViewController(IvySnippetEditorViewController(snippet: snippet), animated: true)
    }
}

/// Edits one snippet: its trigger and its text.
final class IvySnippetEditorViewController: UIViewController {

    private let original: IvySnippet?
    private let triggerField = UITextField()
    private let textView = UITextView()

    init(snippet: IvySnippet?) {
        self.original = snippet
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = original == nil
            ? IvyLocalizedString("SNIPPET_NEW", comment: "Title of the screen that makes a new snippet.")
            : IvyLocalizedString("SNIPPET_EDIT", comment: "Title of the screen that edits a snippet.")
        view.backgroundColor = .Signal.groupedBackground
        navigationItem.rightBarButtonItem = .doneButton { [weak self] in self?.save() }

        let prefixLabel = UILabel()
        prefixLabel.text = IvySnippet.prefix
        prefixLabel.font = .dynamicTypeBody.monospaced()
        prefixLabel.textColor = .Signal.secondaryLabel
        triggerField.leftView = prefixLabel
        triggerField.leftViewMode = .always
        triggerField.text = original?.trigger
        triggerField.placeholder = IvyLocalizedString("SNIPPET_TRIGGER_PLACEHOLDER", comment: "Placeholder of a snippet's trigger, for example addr.")
        triggerField.font = .dynamicTypeBody.monospaced()
        triggerField.autocapitalizationType = .none
        triggerField.autocorrectionType = .no
        triggerField.borderStyle = .roundedRect

        textView.text = original?.text
        textView.font = .dynamicTypeBody
        textView.layer.cornerRadius = 10
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 6, bottom: 10, right: 6)
        textView.backgroundColor = .Signal.secondaryGroupedBackground

        let triggerLabel = UILabel()
        triggerLabel.text = IvyLocalizedString("SNIPPET_TRIGGER", comment: "Label of a snippet's trigger.")
        triggerLabel.font = .dynamicTypeFootnote
        triggerLabel.textColor = .Signal.secondaryLabel
        let textLabel = UILabel()
        textLabel.text = IvyLocalizedString("SNIPPET_TEXT", comment: "Label of a snippet's text.")
        textLabel.font = .dynamicTypeFootnote
        textLabel.textColor = .Signal.secondaryLabel

        var children: [UIView] = [triggerLabel, triggerField, textLabel, textView]
        if let original {
            var configuration = UIButton.Configuration.plain()
            configuration.title = IvyLocalizedString("SNIPPET_DELETE", comment: "Button that deletes a snippet.")
            configuration.baseForegroundColor = .Signal.red
            children.append(UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
                IvySnippets.delete(id: original.id, store: IvyData.shared?.store)
                self?.navigationController?.popViewController(animated: true)
            }))
        }
        let stack = UIStackView(arrangedSubviews: children)
        stack.axis = .vertical
        stack.spacing = 8
        stack.setCustomSpacing(20, after: triggerField)
        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.readableContentGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.readableContentGuide.trailingAnchor),
            textView.heightAnchor.constraint(equalToConstant: 160),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if original == nil {
            triggerField.becomeFirstResponder()
        }
    }

    private func save() {
        let trigger = IvySnippet.cleanTrigger(triggerField.text ?? "")
        let text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trigger.isEmpty, !text.isEmpty else {
            presentToast(text: IvyLocalizedString("SNIPPET_INCOMPLETE", comment: "Shown when a snippet has no trigger or no text."))
            return
        }
        let store = IvyData.shared?.store
        if IvySnippets.all(store: store).contains(where: { $0.trigger == trigger && $0.id != original?.id }) {
            presentToast(text: IvyLocalizedString("SNIPPET_TRIGGER_TAKEN", comment: "Shown when another snippet already uses the trigger."))
            return
        }
        IvySnippets.save(IvySnippet(id: original?.id ?? UUID().uuidString, trigger: trigger, text: text), store: store)
        navigationController?.popViewController(animated: true)
    }
}
