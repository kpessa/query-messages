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
    private var phoneIndex: [String: String] = [:]  // normalized digits → display name
    private var emailIndex: [String: String] = [:]  // email → display name
    private var photoCache: [String: Data] = [:]    // normalized digits or email → image data
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
            CNContactImageDataKey,
            CNContactImageDataAvailableKey
        ] as [CNKeyDescriptor]

        let request = CNContactFetchRequest(keysToFetch: keys)
        try? store.enumerateContacts(with: request) { contact, _ in
            let name = self.formatContactName(contact)
            // Prefer thumbnail (smaller/faster); fall back to full image data
            let photoData: Data?
            if contact.imageDataAvailable {
                photoData = contact.thumbnailImageData ?? contact.imageData
            } else {
                photoData = nil
            }
            for phone in contact.phoneNumbers {
                let digits = phone.value.stringValue.filter { $0.isNumber }
                // Index by last 10 digits (US numbers) and full digit string (international / short)
                let last10 = String(digits.suffix(10))
                if !last10.isEmpty {
                    self.phoneIndex[last10] = name
                    if let data = photoData { self.photoCache[last10] = data }
                }
                // Also store the full digit string when it differs from last10
                if digits.count > 10 || digits.count < 10, !digits.isEmpty {
                    self.phoneIndex[digits] = name
                    if let data = photoData { self.photoCache[digits] = data }
                }
            }
            for email in contact.emailAddresses {
                let emailStr = (email.value as String).lowercased()
                self.emailIndex[emailStr] = name
                if let data = photoData { self.photoCache[emailStr] = data }
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
            return emailIndex[identifier.lowercased()] ?? identifier
        }
        let digits = identifier.filter { $0.isNumber }
        let last10 = String(digits.suffix(10))
        // Try last-10 first (covers US numbers), then full digit string (international/short)
        if let name = phoneIndex[last10] { return name }
        if !digits.isEmpty, let name = phoneIndex[digits] { return name }
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
            return photoCache[identifier.lowercased()]
        }
        let digits = identifier.filter { $0.isNumber }
        let last10 = String(digits.suffix(10))
        if let data = photoCache[last10] { return data }
        if !digits.isEmpty, let data = photoCache[digits] { return data }
        return nil
    }
}
