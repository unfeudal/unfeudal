// SPDX-License-Identifier: Apache-2.0
import FlutterMacOS
import LocalAuthentication
import Security

/// The fr.unfeudal/biometric channel: a 32-byte secret in the Keychain that only Touch ID releases.
/// A new fingerprint enrolment invalidates it (.biometryCurrentSet): the app then asks for the password.
final class BiometricVault {
  private static let service = "fr.unfeudal.biometric"
  private static let account = "secret"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "fr.unfeudal/biometric", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "available":
        result(available())
      case "secret":
        let args = call.arguments as? [String: Any]
        let create = args?["create"] as? Bool ?? false
        let reason = args?["reason"] as? String ?? ""
        // the Keychain prompt blocks: off the main thread, answered on it
        DispatchQueue.global(qos: .userInitiated).async {
          let secret = create ? makeSecret() : readSecret(reason: reason)
          DispatchQueue.main.async { result(secret.map { FlutterStandardTypedData(bytes: $0) }) }
        }
      case "delete":
        SecItemDelete(baseQuery() as CFDictionary)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func baseQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecUseDataProtectionKeychain as String: true,
    ]
  }

  private static func accessControl() -> SecAccessControl? {
    SecAccessControlCreateWithFlags(
      nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet, nil)
  }

  /// Touch ID enrolled and the Keychain usable: a build without the keychain entitlement fails here.
  private static func available() -> Bool {
    guard LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil),
      let access = accessControl()
    else { return false }
    var probe = baseQuery()
    probe[kSecAttrAccount as String] = "probe"
    SecItemDelete(probe as CFDictionary)
    probe[kSecValueData as String] = Data([0])
    probe[kSecAttrAccessControl as String] = access
    let status = SecItemAdd(probe as CFDictionary, nil)
    probe.removeValue(forKey: kSecValueData as String)
    probe.removeValue(forKey: kSecAttrAccessControl as String)
    SecItemDelete(probe as CFDictionary)
    return status == errSecSuccess
  }

  private static func makeSecret() -> Data? {
    var bytes = Data(count: 32)
    let random = bytes.withUnsafeMutableBytes {
      SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
    }
    guard random == errSecSuccess, let access = accessControl() else { return nil }
    SecItemDelete(baseQuery() as CFDictionary)
    var query = baseQuery()
    query[kSecValueData as String] = bytes
    query[kSecAttrAccessControl as String] = access
    return SecItemAdd(query as CFDictionary, nil) == errSecSuccess ? bytes : nil
  }

  /// Nil when the user cancels, the check fails, or the fingerprints changed (the item is gone).
  private static func readSecret(reason: String) -> Data? {
    let context = LAContext()
    context.localizedReason = reason
    var query = baseQuery()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecUseAuthenticationContext as String] = context
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data, data.count == 32
    else { return nil }
    return data
  }
}
