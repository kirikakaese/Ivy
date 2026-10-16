//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

// Ivy: Wi-Fi Aware does not exist on the Mac; transfers use MultipeerConnectivity there.
#if canImport(WiFiAware)

import Foundation
import SignalServiceKit

@available(iOS 26.0, *)
struct WADeviceTransferConnectionFactory: DeviceTransfer.ConnectionFactory {
    func buildOutgoingConnection(tsAccountManager: TSAccountManager, deviceTransferURL: URL) throws -> any DeviceTransfer.OutgoingConnection {
        return try WADeviceTransferOutgoingConnection(
            tsAccountManager: tsAccountManager,
            deviceTransferURL: deviceTransferURL,
        )
    }

    func buildIncomingConnection(tsAccountManager: TSAccountManager) throws -> any DeviceTransfer.IncomingConnection {
        return try WADeviceTransferIncomingConnection()
    }
}

#endif
