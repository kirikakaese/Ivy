//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing

@testable import SignalServiceKit

private struct CompletionSerializerTest {
    @Test
    func testInOrder() {
        // If this hangs, somebody probably obsoleted CompletionSerializer.
        var completionSerializer = CompletionSerializer()
        let result = runTest(enqueueInOrder: { tx, block in
            completionSerializer.addOrderedSyncCompletion(tx: tx, block: block)
        })
        #expect(result == [1, 2])
    }

    @Test
    func testOutOfOrder() {
        // If this hangs, somebody probably obsoleted CompletionSerializer.
        let result = runTest(enqueueInOrder: { tx, block in
            tx.addSyncCompletion(block: block)
        })
        #expect(result == [2, 1])
    }

    private func runTest(enqueueInOrder: @escaping (DBWriteTransaction, @escaping () -> Void) -> Void) -> [Int] {
        let inMemoryDb = InMemoryDB()
        let completions = AtomicArray<Int>(lock: .init())

        let firstWrite = DispatchSemaphore(value: 0)
        let secondCompletion = DispatchSemaphore(value: 0)
        let thirdCompletion = DispatchSemaphore(value: 0)

        // Ivy: private queues always get their own thread. Blocking work on the
        // shared global queue can starve when tests run in parallel on a
        // machine with few cores, and the test then never finishes.
        let firstQueue = DispatchQueue(label: "CompletionSerializerTest.first")
        let secondQueue = DispatchQueue(label: "CompletionSerializerTest.second")

        firstQueue.async {
            inMemoryDb.write { tx in
                firstWrite.signal()
                tx.addSyncCompletion {
                    secondCompletion.wait()
                }
                enqueueInOrder(tx, {
                    completions.append(1)
                })
                tx.addSyncCompletion {
                    thirdCompletion.signal()
                }
            }
        }

        secondQueue.async {
            firstWrite.wait()
            inMemoryDb.write { tx in
                enqueueInOrder(tx, {
                    completions.append(2)
                    secondCompletion.signal()
                })
            }
        }

        thirdCompletion.wait()
        return completions.get()
    }
}
