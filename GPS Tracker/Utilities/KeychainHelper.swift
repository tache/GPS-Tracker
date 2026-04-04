//
//  KeychainHelper.swift
//  GPS Tracker
//
//  Created by Christopher Graham on 4/1/26.
//
// Claude Generated: version 1 - Keychain read/write for MQTT credentials

import Foundation
import Security

/// Manages MQTT credentials (username + password) in the macOS Keychain.
/// Credentials are stored as a single item: username in the account field,
/// password as the password data.
enum KeychainHelper {

  private static let service = "com.gps-tracker.mqtt-credentials"

  /// Saves username and password to the Keychain. Overwrites any existing entry.
  static func save(username: String, password: String) throws {
    delete() // remove all existing entries before adding new one

    guard let passwordData = password.data(using: .utf8) else {
      throw KeychainError.encodingFailed
    }

    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: username,
      kSecValueData: passwordData
    ]

    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw KeychainError.saveFailed(status)
    }
  }

  /// Loads credentials from the Keychain. Returns nil if no entry exists.
  static func load() -> (username: String, password: String)? {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecReturnAttributes: true,
      kSecReturnData: true,
      kSecMatchLimit: kSecMatchLimitOne
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess,
      let dict = result as? [CFString: Any],
      let account = dict[kSecAttrAccount] as? String,
      let data = dict[kSecValueData] as? Data,
      let password = String(data: data, encoding: .utf8)
    else { return nil }

    return (username: account, password: password)
  }

  /// Removes all stored credentials for this service from the Keychain.
  /// Loops until all items are gone because SecItemDelete removes one entry at a time
  /// when multiple accounts share the same service key.
  static func delete() {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service
    ]
    // Loop to delete all items matching the service (multiple accounts possible).
    var status = SecItemDelete(query as CFDictionary)
    while status == errSecSuccess {
      status = SecItemDelete(query as CFDictionary)
    }
  }
}

enum KeychainError: Error {
  case encodingFailed
  case saveFailed(OSStatus)
}
