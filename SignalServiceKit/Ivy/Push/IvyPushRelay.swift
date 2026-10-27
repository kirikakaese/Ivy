//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Foundation
import LibSignalClient

/// Ivy Push: a relay on the user's own server wakes Ivy with Apple push
/// notifications when messages arrive, as Signal's servers only push to the
/// official app.
///
/// Ivy adds a linked device called "Ivy Push" to the account, with keys made
/// only for it and then thrown away, so the device can't read anything. The
/// relay (MollySocket, see relay/ and docs/PUSH_RELAY.md) stays connected as
/// that device and calls Ivy's push gateway whenever an urgent message waits.
/// Ivy's notification service then fetches and shows the messages.
///
/// Builds with a built-in relay connect to it by themselves unless the user
/// turns instant notifications off; any relay can also be entered by hand.
public final class IvyPushRelay {

    public static let shared = IvyPushRelay()

    /// The relay's push gateway as MollySocket reaches it inside the relay's
    /// Docker network (relay/docker-compose.yml).
    static let gatewayBaseURL = "http://ivy-gateway:8080/apns/"
    static let deviceName = "Ivy Push"
    /// How often Ivy confirms its registration with the relay, so the relay
    /// notices a removed device or an unreachable gateway.
    static let reregistrationInterval: TimeInterval = 7 * .day

    public struct Connection: Codable, Equatable {
        public var relayURL: URL
        public var deviceId: UInt32
        var password: String
        var registeredToken: String?
        var registeredAt: Date?
    }

    public enum RelayError: Error, Equatable {
        case notPrimaryDevice
        case invalidAddress
        case notARelay
        case accountNotAllowed
        case endpointNotAllowed
        case tooManyDevices
        case relayFailed(String)
    }

    private let store = KeyValueStore(collection: "IvyPushRelay")
    private static let connectionKey = "connection"
    private static let optedOutKey = "optedOut"
    private static let lastAutomaticAttemptKey = "lastAutomaticAttempt"

    /// How long Ivy waits after an automatic connection attempt before it
    /// tries again, for example after the relay was unreachable.
    static let automaticRetryInterval: TimeInterval = .day

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration)
    }()

    /// Serializes connecting, registering and disconnecting.
    private let serialQueue = ConcurrentTaskQueue(concurrentLimit: 1)

    // MARK: - State

    public var connection: Connection? {
        SSKEnvironment.shared.databaseStorageRef.read { tx -> Connection? in
            let connection: Connection? = try? store.getCodableValue(forKey: Self.connectionKey, transaction: tx)
            return connection
        }
    }

    public var isConnected: Bool { connection != nil }

    private func save(_ connection: Connection?) async {
        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            if let connection {
                try? self.store.setCodable(connection, key: Self.connectionKey, transaction: tx)
            } else {
                self.store.removeValue(forKey: Self.connectionKey, transaction: tx)
            }
        }
    }

    /// The relay this build connects to by itself, from the build setting
    /// `IVY_PUSH_RELAY_HOST` (a GitHub variable for TestFlight builds).
    public static var builtInRelayURL: URL? {
        guard let host = Bundle.main.object(forInfoDictionaryKey: "IvyPushRelayHost") as? String else {
            return nil
        }
        return relayURL(from: host)
    }

    /// Whether the user turned instant notifications off.
    public var isOptedOut: Bool {
        SSKEnvironment.shared.databaseStorageRef.read { tx in
            store.getBool(Self.optedOutKey, defaultValue: false, transaction: tx)
        }
    }

    private func setOptedOut(_ optedOut: Bool) async {
        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            self.store.setBool(optedOut, key: Self.optedOutKey, transaction: tx)
        }
    }

    /// The built-in relay, if Ivy should connect to it by itself now: the
    /// user didn't opt out, this is the primary device, and the last attempt
    /// is more than a day ago.
    public func relayForAutomaticConnection() async -> URL? {
        guard let relayURL = Self.builtInRelayURL, connection == nil else {
            return nil
        }
        return await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx -> URL? in
            guard
                !self.store.getBool(Self.optedOutKey, defaultValue: false, transaction: tx),
                DependenciesBridge.shared.tsAccountManager.registrationState(tx: tx).isPrimaryDevice == true
            else {
                return nil
            }
            if
                let lastAttempt = self.store.getDate(Self.lastAutomaticAttemptKey, transaction: tx),
                -lastAttempt.timeIntervalSinceNow < Self.automaticRetryInterval
            {
                return nil
            }
            self.store.setDate(Date(), key: Self.lastAutomaticAttemptKey, transaction: tx)
            return relayURL
        }
    }

    /// The account ID a relay can be limited to (`IVY_ALLOWED_ACCOUNTS`).
    public var accountId: String? {
        DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?
            .aci.rawUUID.uuidString.lowercased()
    }

    /// The relay address as typed by the user, with `https://` added when
    /// missing. Only HTTPS addresses are accepted.
    public static func relayURL(from text: String) -> URL? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") {
            text.removeLast()
        }
        if !text.contains("://") {
            text = "https://" + text
        }
        guard
            let components = URLComponents(string: text),
            components.scheme?.lowercased() == "https",
            let host = components.host, !host.isEmpty,
            components.query == nil, components.fragment == nil
        else {
            return nil
        }
        return components.url
    }

    static func endpoint(forToken token: String, sandbox: Bool) -> String {
        return gatewayBaseURL + token + (sandbox ? "?sandbox=1" : "")
    }

    private static var usesSandbox: Bool {
#if DEBUG
        return true
#else
        return false
#endif
    }

    // MARK: - Connecting

    /// Adds the push device if needed and registers it with the relay.
    public func connect(relayURL: URL, apnsToken: Data) async throws {
        try await serialQueue.runWithoutTaskCancellationHandler {
            try await self._connect(relayURL: relayURL, token: apnsToken.hexadecimalString)
        }
        await setOptedOut(false)
    }

    private func _connect(relayURL: URL, token: String) async throws {
        try await discover(relayURL)

        var connection = self.connection
        if let existing = connection, existing.relayURL != relayURL {
            // A different relay gets a new device; the old relay loses access.
            try? await unlink(existing)
            connection = nil
            await save(nil)
        }
        if connection == nil {
            let device = try await createDevice()
            connection = Connection(relayURL: relayURL, deviceId: device.deviceId, password: device.password)
            await save(connection)
        }
        try await register(connection!, token: token, allowingNewDevice: true)
    }

    /// Called with each push token iOS hands Ivy. Registers again when the
    /// token changed or the last registration is older than a week.
    public func didReceive(apnsToken: Data) {
        let token = apnsToken.hexadecimalString
        Task {
            await self.serialQueue.runWithoutTaskCancellationHandler {
                guard let connection = self.connection else {
                    return
                }
                let isFresh = connection.registeredToken == token
                    && (connection.registeredAt.map { -$0.timeIntervalSinceNow < Self.reregistrationInterval } ?? false)
                guard !isFresh else {
                    return
                }
                do {
                    try await self.register(connection, token: token, allowingNewDevice: true)
                } catch {
                    Logger.warn("Couldn't renew the push relay registration: \(error)")
                }
            }
        }
    }

    /// Removes the push device from the account and forgets the relay. With
    /// `optOut`, Ivy doesn't connect to the built-in relay by itself again.
    public func disconnect(optOut: Bool) async throws {
        try await serialQueue.runWithoutTaskCancellationHandler {
            if let connection = self.connection {
                try await self.unlink(connection)
                await self.save(nil)
            }
        }
        if optOut {
            await setOptedOut(true)
        }
    }

    /// Whether the push device is still linked. `nil` if that couldn't be
    /// checked, for example while offline.
    public func isDeviceLinked() async -> Bool? {
        guard let connection else {
            return nil
        }
        do {
            _ = try await DependenciesBridge.shared.deviceService.refreshDevices()
        } catch {
            return nil
        }
        return SSKEnvironment.shared.databaseStorageRef.read { tx in
            DependenciesBridge.shared.deviceStore.fetchAll(tx: tx)
                .contains { $0.deviceId.uint32Value == connection.deviceId }
        }
    }

    // MARK: - Relay

    private struct RelayResponse: Decodable {
        struct Body: Decodable {
            var version: String?
            var status: String?
        }

        var mollysocket: Body
    }

    /// Makes sure the address belongs to a MollySocket relay.
    private func discover(_ relayURL: URL) async throws {
        let (data, response) = try await session.data(from: relayURL.appendingPathComponent("discover"))
        guard
            (response as? HTTPURLResponse)?.statusCode == 200,
            (try? JSONDecoder().decode(RelayResponse.self, from: data)) != nil
        else {
            throw RelayError.notARelay
        }
    }

    private func register(_ connection: Connection, token: String, allowingNewDevice: Bool) async throws {
        guard let accountId else {
            throw RelayError.notPrimaryDevice
        }
        var request = URLRequest(url: connection.relayURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "uuid": accountId,
            "device_id": connection.deviceId,
            "password": connection.password,
            "endpoint": Self.endpoint(forToken: token, sandbox: Self.usesSandbox),
            "ping": false,
        ] as [String: Any])

        let (data, response) = try await session.data(for: request)
        guard
            (response as? HTTPURLResponse)?.statusCode == 200,
            let status = (try? JSONDecoder().decode(RelayResponse.self, from: data))?.mollysocket.status
        else {
            throw RelayError.notARelay
        }
        switch status {
        case "ok":
            var updated = connection
            updated.registeredToken = token
            updated.registeredAt = Date()
            await save(updated)
        case "forbidden" where allowingNewDevice:
            // The push device was removed, for example under Linked Devices.
            Logger.info("The push device is gone; adding a new one.")
            let device = try await createDevice()
            let replacement = Connection(relayURL: connection.relayURL, deviceId: device.deviceId, password: device.password)
            await save(replacement)
            try await register(replacement, token: token, allowingNewDevice: false)
        case "invalid_uuid":
            throw RelayError.accountNotAllowed
        case "invalid_endpoint":
            throw RelayError.endpointNotAllowed
        default:
            throw RelayError.relayFailed(status)
        }
    }

    // MARK: - Push device

    private struct LinkDeviceResponse: Decodable {
        var deviceId: UInt32
    }

    /// Links a device that can receive but not read messages: its keys are
    /// signed with the account's identity keys, as the server requires, and
    /// never stored.
    private func createDevice() async throws -> (deviceId: UInt32, password: String) {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        let identityManager = DependenciesBridge.shared.identityManager

        let account = databaseStorage.read { tx -> (
            aci: Aci,
            aciKeys: IdentityKeyPair,
            pniKeys: IdentityKeyPair?,
            pniRegistrationId: UInt32?,
            discoverability: PhoneNumberDiscoverability?,
            unrestrictedAccess: Bool,
        )? in
            guard
                tsAccountManager.registrationState(tx: tx).isPrimaryDevice == true,
                let identifiers = tsAccountManager.localIdentifiers(tx: tx),
                let aciKeys = identityManager.identityKeyPair(for: .aci, tx: tx)?.keyPair
            else {
                return nil
            }
            return (
                identifiers.aci,
                aciKeys,
                identityManager.identityKeyPair(for: .pni, tx: tx)?.keyPair,
                tsAccountManager.getRegistrationId(for: .pni, tx: tx),
                tsAccountManager.phoneNumberDiscoverability(tx: tx),
                SSKEnvironment.shared.udManagerRef.shouldAllowUnrestrictedAccessLocal(transaction: tx),
            )
        }
        guard let account else {
            throw RelayError.notPrimaryDevice
        }

        let provisioning = DeviceProvisioningServiceImpl(networkManager: SSKEnvironment.shared.networkManagerRef)
        let code: DeviceProvisioningCodeResponse
        do {
            code = try await provisioning.requestDeviceProvisioningCode()
        } catch is DeviceLimitExceededError {
            throw RelayError.tooManyDevices
        }

        let password = Randomness.generateRandomBytes(18).base64EncodedString()
        let name = try OWSDeviceNames.encryptDeviceName(plaintext: Self.deviceName, identityKeyPair: account.aciKeys)
        let attributes = AccountAttributes(
            isManualMessageFetchEnabled: true,
            registrationId: RegistrationIdGenerator.generate(),
            pniRegistrationId: account.pniRegistrationId,
            unidentifiedAccessKey: nil,
            unrestrictedUnidentifiedAccess: account.unrestrictedAccess,
            reglockToken: nil,
            registrationRecoveryPassword: nil,
            encryptedDeviceName: name.base64EncodedString(),
            discoverableByPhoneNumber: account.discoverability,
            capabilities: AccountAttributes.Capabilities(hasSVRBackups: false),
        )
        let request = ProvisioningRequestFactory.verifySecondaryDeviceRequest(
            verificationCode: code.verificationCode,
            aci: account.aci,
            aciPreKeyBundle: Self.throwawayKeys(.aci, signedBy: account.aciKeys),
            pniPreKeyBundle: account.pniKeys.map { Self.throwawayKeys(.pni, signedBy: $0) },
            authPassword: password,
            attributes: attributes,
            apnRegistrationId: nil,
        )
        let response = try await SSKEnvironment.shared.networkManagerRef.asyncRequest(request)
        guard
            let body = response.responseBodyData,
            let linked = try? JSONDecoder().decode(LinkDeviceResponse.self, from: body)
        else {
            throw OWSAssertionError("Missing device ID in the link response.")
        }
        Logger.info("Linked the push device \(linked.deviceId).")
        return (linked.deviceId, password)
    }

    static func throwawayKeys(_ identity: OWSIdentity, signedBy identityKeys: IdentityKeyPair) -> RegistrationPreKeyUploadBundle {
        return RegistrationPreKeyUploadBundle(
            identity: identity,
            identityKeyPair: identityKeys,
            signedPreKey: SignedPreKeyStoreImpl.generateSignedPreKey(keyId: PreKeyId.random(), signedBy: identityKeys.privateKey),
            lastResortPreKey: KyberPreKeyStoreImpl.generatePreKeyRecord(keyId: PreKeyId.random(), now: Date(), signedBy: identityKeys.privateKey),
        )
    }

    private func unlink(_ connection: Connection) async throws {
        guard let deviceId = DeviceId(validating: connection.deviceId) else {
            return
        }
        do {
            try await DependenciesBridge.shared.deviceService.unlinkDevice(deviceId: deviceId)
        } catch where error.httpStatusCode == 404 {
            // Already removed.
        }
    }
}
