//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

extension HomeScreenSearchResultSet {

    /// Ivy: the results without hidden chats and their messages, while the
    /// hidden chats aren't revealed.
    public func ivyWithoutHiddenChats() -> HomeScreenSearchResultSet {
        let hiddenChats = IvyHiddenChats.shared
        guard !hiddenChats.isEmpty, !hiddenChats.isRevealed else {
            return self
        }
        func isHidden(_ threadViewModel: ThreadViewModel) -> Bool {
            hiddenChats.isHidden(thread: threadViewModel.threadRecord)
        }
        return HomeScreenSearchResultSet(
            searchText: searchText,
            contactThreadResults: contactThreadResults.filter { !isHidden($0.threadViewModel) },
            groupThreadResults: groupThreadResults.filter { !isHidden($0.threadViewModel) },
            contactResults: contactResults,
            messageResults: messageResults.filter { !isHidden($0.threadViewModel) },
        )
    }
}
