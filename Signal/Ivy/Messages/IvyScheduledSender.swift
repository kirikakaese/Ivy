//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// Sends scheduled messages when they are due (see
/// `IvyScheduledMessage.decision(for:now:)` for which device sends).
@MainActor
final class IvyScheduledSender {

    static let shared = IvyScheduledSender()

    /// Posted on the main thread when scheduled messages changed.
    static let scheduledDidChange = Notification.Name("IvyScheduledDidChange")

    private var isStarted = false
    private var timer: Timer?

    private var store: IvyDataStore? { IvyData.shared?.store }

    /// Called when the app is ready and whenever it becomes active.
    func start() {
        if !isStarted {
            isStarted = true
            NotificationCenter.default.addObserver(self, selector: #selector(dataDidChange(_:)), name: IvyDataStore.dataDidChange, object: nil)
        }
        IvyScheduledStore.removeOldSent(store: store)
        check()
    }

    @objc
    private nonisolated func dataDidChange(_ notification: Notification) {
        guard let kinds = notification.userInfo?["kinds"] as? Set<String>, kinds.contains(IvyScheduledStore.kind) else {
            return
        }
        Task { @MainActor [weak self] in
            self?.check()
            NotificationCenter.default.post(name: Self.scheduledDidChange, object: nil)
        }
    }

    // MARK: - Changing

    func schedule(_ body: MessageBody, in thread: TSThread, at date: Date) {
        guard
            let chat = IvyChatReference(thread: thread),
            let data = try? NSKeyedArchiver.archivedData(withRootObject: body, requiringSecureCoding: true)
        else {
            return
        }
        IvyScheduledStore.save(IvyScheduledMessage(
            chat: chat,
            body: data,
            previewText: body.text,
            sendAt: date,
            createdBy: IvyData.localDeviceId(),
        ), store: store)
        changed()
    }

    func reschedule(id: String, to date: Date) {
        guard var message = IvyScheduledStore.message(id: id, store: store), message.state == .pending else {
            return
        }
        message.sendAt = date
        // The device that changes the time sends it.
        message.createdBy = IvyData.localDeviceId()
        message.claimedBy = nil
        message.claimedAt = nil
        IvyScheduledStore.save(message, store: store)
        changed()
    }

    func sendNow(id: String) {
        reschedule(id: id, to: Date())
    }

    func delete(id: String) {
        IvyScheduledStore.delete(id: id, store: store)
        changed()
    }

    private func changed() {
        check()
        NotificationCenter.default.post(name: Self.scheduledDidChange, object: nil)
    }

    // MARK: - Sending

    private func check() {
        timer?.invalidate()
        timer = nil
        let device = IvyData.localDeviceId()
        guard device != 0 else {
            return
        }
        let now = Date()
        var nextCheck: Date?
        for message in IvyScheduledStore.pending(store: store) {
            switch message.decision(for: device, now: now) {
            case .none:
                break
            case .wait(let date):
                nextCheck = min(nextCheck ?? date, date)
            case .claim:
                var claimed = message
                claimed.claimedBy = device
                claimed.claimedAt = now
                IvyScheduledStore.save(claimed, store: store)
                let settled = now.addingTimeInterval(IvyScheduledMessage.claimSettleTime)
                nextCheck = min(nextCheck ?? settled, settled)
            case .send:
                send(message, now: now)
            }
        }
        if let nextCheck {
            let timer = Timer(fire: max(nextCheck, Date().addingTimeInterval(1)), interval: 0, repeats: false) { _ in
                Task { @MainActor in IvyScheduledSender.shared.check() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    private func send(_ message: IvyScheduledMessage, now: Date) {
        let thread = SSKEnvironment.shared.databaseStorageRef.read { tx in message.chat.thread(tx: tx) }
        guard
            let body = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MessageBody.self, from: message.body),
            let thread
        else {
            Logger.warn("A scheduled message's chat or text is missing")
            return
        }
        // Marked sent first, so other devices learn of it as early as
        // possible; Signal's send queue retries until it goes out.
        var sent = message
        sent.state = .sent
        sent.sentAt = now
        IvyScheduledStore.save(sent, store: store)
        ThreadUtil.enqueueMessage(body: body, thread: thread)
        NotificationCenter.default.post(name: Self.scheduledDidChange, object: nil)
    }
}
