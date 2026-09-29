import Foundation

/// Converts Twenty field values to display strings.
enum FieldFormatter {
    static func plainText(_ value: JSONValue, field: FieldMetadata) -> String {
        switch field.type {
        case .fullName:
            return [value["firstName"]?.nonEmptyString, value["lastName"]?.nonEmptyString]
                .compactMap { $0 }.joined(separator: " ")
        case .emails:
            return emails(value).joined(separator: ", ")
        case .phones:
            return phones(value).joined(separator: ", ")
        case .links:
            return links(value).map { $0.label ?? $0.url }.joined(separator: ", ")
        case .currency:
            return currency(value) ?? ""
        case .address:
            return address(value)
        case .select:
            guard let raw = value.stringValue else { return "" }
            return field.option(for: raw)?.label ?? raw
        case .multiSelect:
            return (value.arrayValue ?? []).compactMap(\.stringValue)
                .map { field.option(for: $0)?.label ?? $0 }.joined(separator: ", ")
        case .rating:
            guard let stars = rating(value) else { return "" }
            return String(repeating: "★", count: stars)
        case .boolean:
            guard let flag = value.boolValue else { return "" }
            return flag ? "Yes" : "No"
        case .number, .numeric:
            guard let number = value.doubleValue else { return "" }
            return number.formatted()
        case .date:
            guard let date = parseDate(value.stringValue) else { return value.stringValue ?? "" }
            return date.formatted(date: .abbreviated, time: .omitted)
        case .dateTime:
            guard let date = parseDate(value.stringValue) else { return value.stringValue ?? "" }
            return date.formatted(date: .abbreviated, time: .shortened)
        case .array:
            return (value.arrayValue ?? []).compactMap(\.stringValue).joined(separator: ", ")
        case .actor:
            return value["name"]?.nonEmptyString ?? value["source"]?.stringValue?.capitalized ?? ""
        case .richText:
            return value["markdown"]?.nonEmptyString ?? ""
        case .relation:
            return relationTitle(value)
        default:
            switch value {
            case .string(let text): return text
            case .number(let number): return number.formatted()
            case .bool(let flag): return flag ? "Yes" : "No"
            default: return ""
            }
        }
    }

    // MARK: Composite helpers

    static func emails(_ value: JSONValue) -> [String] {
        var result: [String] = []
        if let primary = value["primaryEmail"]?.nonEmptyString { result.append(primary) }
        result += (value["additionalEmails"]?.arrayValue ?? []).compactMap(\.nonEmptyString)
        return result
    }

    static func phones(_ value: JSONValue) -> [String] {
        var result: [String] = []
        if let number = value["primaryPhoneNumber"]?.nonEmptyString {
            let code = value["primaryPhoneCallingCode"]?.nonEmptyString ?? ""
            result.append([code, number].filter { !$0.isEmpty }.joined(separator: " "))
        }
        for extra in value["additionalPhones"]?.arrayValue ?? [] {
            guard let number = extra["number"]?.nonEmptyString else { continue }
            let code = extra["callingCode"]?.nonEmptyString ?? ""
            result.append([code, number].filter { !$0.isEmpty }.joined(separator: " "))
        }
        return result
    }

    struct Link: Hashable { let url: String; let label: String? }

    static func links(_ value: JSONValue) -> [Link] {
        var result: [Link] = []
        if let url = value["primaryLinkUrl"]?.nonEmptyString {
            result.append(Link(url: url, label: value["primaryLinkLabel"]?.nonEmptyString))
        }
        for extra in value["secondaryLinks"]?.arrayValue ?? [] {
            guard let url = extra["url"]?.nonEmptyString else { continue }
            result.append(Link(url: url, label: extra["label"]?.nonEmptyString))
        }
        return result
    }

    static func currency(_ value: JSONValue) -> String? {
        guard let micros = value["amountMicros"]?.doubleValue else { return nil }
        let amount = micros / 1_000_000
        if let code = value["currencyCode"]?.nonEmptyString {
            return amount.formatted(.currency(code: code))
        }
        return amount.formatted()
    }

    static func address(_ value: JSONValue) -> String {
        ["addressStreet1", "addressStreet2", "addressCity", "addressState", "addressPostcode", "addressCountry"]
            .compactMap { value[$0]?.nonEmptyString }
            .joined(separator: ", ")
    }

    /// Twenty stores ratings as "RATING_1"..."RATING_5".
    static func rating(_ value: JSONValue) -> Int? {
        guard let raw = value.stringValue, raw.hasPrefix("RATING_") else { return nil }
        return Int(raw.dropFirst("RATING_".count))
    }

    static func relationTitle(_ value: JSONValue) -> String {
        guard let object = value.objectValue else { return "" }
        if let name = object["name"] {
            if let text = name.nonEmptyString { return text }
            let full = [name["firstName"]?.nonEmptyString, name["lastName"]?.nonEmptyString].compactMap { $0 }
            if !full.isEmpty { return full.joined(separator: " ") }
        }
        return object["title"]?.nonEmptyString ?? object["id"]?.stringValue ?? ""
    }

    // MARK: Dates

    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    nonisolated(unsafe) private static let iso = ISO8601DateFormatter()
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        return isoFractional.date(from: string) ?? iso.date(from: string) ?? dayFormatter.date(from: string)
    }

    static func dateTimeString(_ date: Date) -> String { isoFractional.string(from: date) }
    static func dayString(_ date: Date) -> String { dayFormatter.string(from: date) }
}
