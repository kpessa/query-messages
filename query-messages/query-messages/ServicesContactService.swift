//
//  ContactService.swift
//  query-messages
//
//  Created by Kurt Pessa on 2/21/26.
//

import Foundation
import Contacts

actor ContactService {
    private let store = CNContactStore()
    private var cache: [String: String] = [:]       // raw identifier → display name
    private var phoneIndex: [String: String] = [:]  // last 10 digits → display name
    private var emailIndex: [String: String] = [:]  // email → display name
    private var photoCache: [String: Data] = [:]    // last 10 digits or email → thumbnail data
    private var indexed = false

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .notDetermined {
            do {
                try await store.requestAccess(for: .contacts)
            } catch {
                print("Contacts authorization failed: \(error)")
                return false
            }
        }
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
            return false
        }
        buildIndex()
        return true
    }

    // MARK: - Index (load all contacts once)

    private func buildIndex() {
        guard !indexed else { return }
        indexed = true

        let keys = [
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactNicknameKey,
            CNContactPhoneNumbersKey,
            CNContactEmailAddressesKey,
            CNContactThumbnailImageDataKey,
            CNContactImageDataAvailableKey
        ] as [CNKeyDescriptor]

        let request = CNContactFetchRequest(keysToFetch: keys)
        try? store.enumerateContacts(with: request) { contact, _ in
            let name = self.formatContactName(contact)
            let photoData = contact.imageDataAvailable ? contact.thumbnailImageData : nil
            for phone in contact.phoneNumbers {
                let digits = phone.value.stringValue.filter { $0.isNumber }
                let last10 = String(digits.suffix(10))
                if last10.count == 10 {
                    self.phoneIndex[last10] = name
                    if let data = photoData {
                        self.photoCache[last10] = data
                    }
                }
            }
            for email in contact.emailAddresses {
                let emailStr = email.value as String
                self.emailIndex[emailStr] = name
                if let data = photoData {
                    self.photoCache[emailStr] = data
                }
            }
        }
    }

    // MARK: - Contact Resolution

    func resolve(_ identifier: String) async -> String {
        if let cached = cache[identifier] { return cached }
        // Build index on first resolve if authorization was already granted before app launch
        if !indexed && CNContactStore.authorizationStatus(for: .contacts) == .authorized {
            buildIndex()
        }
        let name = lookupContact(identifier)
        cache[identifier] = name
        return name
    }

    private func lookupContact(_ identifier: String) -> String {
        if identifier.contains("@") {
            return emailIndex[identifier] ?? identifier
        }
        let digits = identifier.filter { $0.isNumber }
        let last10 = String(digits.suffix(10))
        if last10.count == 10, let name = phoneIndex[last10] {
            return name
        }
        return cleanPhoneNumber(identifier)
    }

    // MARK: - Helpers

    private func formatContactName(_ contact: CNContact) -> String {
        if !contact.nickname.isEmpty { return contact.nickname }
        let first = contact.givenName
        let last = contact.familyName
        if !first.isEmpty && !last.isEmpty { return "\(first) \(last)" }
        if !first.isEmpty { return first }
        if !last.isEmpty { return last }
        return "Unknown"
    }

    private func cleanPhoneNumber(_ phone: String) -> String {
        let cleaned = phone
            .replacingOccurrences(of: "+1", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
        if cleaned.contains("@") { return phone }
        if cleaned.count == 10 {
            let areaCode = cleaned.prefix(3)
            let prefix = cleaned.dropFirst(3).prefix(3)
            let suffix = cleaned.suffix(4)
            return "(\(areaCode)) \(prefix)-\(suffix)"
        }
        return phone
    }

    // MARK: - Batch Resolution

    func resolveMultiple(_ identifiers: [String]) async -> [String: String] {
        var results: [String: String] = [:]
        for identifier in identifiers {
            results[identifier] = await resolve(identifier)
        }
        return results
    }

    // MARK: - Photo Resolution

    func resolvePhoto(_ identifier: String) async -> Data? {
        if !indexed && CNContactStore.authorizationStatus(for: .contacts) == .authorized {
            buildIndex()
        }
        if identifier.contains("@") {
            return photoCache[identifier]
        }
        let digits = identifier.filter { $0.isNumber }
        let last10 = String(digits.suffix(10))
        if last10.count == 10 {
            return photoCache[last10]
        }
        return nil
    }
}
