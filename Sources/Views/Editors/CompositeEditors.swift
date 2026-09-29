import SwiftUI

struct FullNameEditor: View {
    let field: FieldMetadata
    @Binding var value: JSONValue

    var body: some View {
        TextField("First name", text: $value.string("firstName"))
            .textContentType(.givenName)
            .accessibilityIdentifier("edit.\(field.name).firstName")
        TextField("Last name", text: $value.string("lastName"))
            .textContentType(.familyName)
            .accessibilityIdentifier("edit.\(field.name).lastName")
    }
}

/// EMAILS: `{ primaryEmail, additionalEmails: [String] }`.
struct EmailsEditor: View {
    let field: FieldMetadata
    @Binding var value: JSONValue

    private var additional: [String] { (value["additionalEmails"]?.arrayValue ?? []).compactMap(\.stringValue) }

    var body: some View {
        TextField("Primary email", text: $value.string("primaryEmail"))
            .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
        ForEach(additional.indices, id: \.self) { index in
            HStack {
                TextField("Email", text: Binding(
                    get: { additional.indices.contains(index) ? additional[index] : "" },
                    set: { setAdditional(index, $0) }
                ))
                .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                RemoveButton { removeAdditional(index) }
            }
        }
        Button("Add email", systemImage: "plus") {
            value = value.setting("additionalEmails", to: .array((additional + [""]).map(JSONValue.string)))
        }
    }

    private func setAdditional(_ index: Int, _ text: String) {
        var list = additional
        guard list.indices.contains(index) else { return }
        list[index] = text
        value = value.setting("additionalEmails", to: .array(list.map(JSONValue.string)))
    }

    private func removeAdditional(_ index: Int) {
        var list = additional
        list.remove(at: index)
        value = value.setting("additionalEmails", to: .array(list.map(JSONValue.string)))
    }
}

/// PHONES: `{ primaryPhoneNumber, primaryPhoneCountryCode, primaryPhoneCallingCode, additionalPhones: [{number, countryCode, callingCode}] }`.
struct PhonesEditor: View {
    let field: FieldMetadata
    @Binding var value: JSONValue

    private var additional: [JSONValue] { value["additionalPhones"]?.arrayValue ?? [] }

    var body: some View {
        HStack {
            CountryCodeMenu(
                countryCode: value["primaryPhoneCountryCode"]?.stringValue,
                callingCode: value["primaryPhoneCallingCode"]?.stringValue
            ) { country in
                value = value
                    .setting("primaryPhoneCountryCode", to: .string(country.iso))
                    .setting("primaryPhoneCallingCode", to: .string(country.callingCode))
            }
            TextField("Phone", text: $value.string("primaryPhoneNumber"))
                .keyboardType(.phonePad)
        }
        ForEach(additional.indices, id: \.self) { index in
            HStack {
                CountryCodeMenu(
                    countryCode: additional[index]["countryCode"]?.stringValue,
                    callingCode: additional[index]["callingCode"]?.stringValue
                ) { country in
                    update(index) { $0.setting("countryCode", to: .string(country.iso)).setting("callingCode", to: .string(country.callingCode)) }
                }
                TextField("Phone", text: Binding(
                    get: { additional.indices.contains(index) ? additional[index]["number"]?.stringValue ?? "" : "" },
                    set: { text in update(index) { $0.setting("number", to: .string(text)) } }
                ))
                .keyboardType(.phonePad)
                RemoveButton {
                    var list = additional
                    list.remove(at: index)
                    value = value.setting("additionalPhones", to: .array(list))
                }
            }
        }
        Button("Add phone", systemImage: "plus") {
            let template: JSONValue = [
                "number": "",
                "countryCode": value["primaryPhoneCountryCode"] ?? "",
                "callingCode": value["primaryPhoneCallingCode"] ?? "",
            ]
            value = value.setting("additionalPhones", to: .array(additional + [template]))
        }
    }

    private func update(_ index: Int, _ transform: (JSONValue) -> JSONValue) {
        var list = additional
        guard list.indices.contains(index) else { return }
        list[index] = transform(list[index])
        value = value.setting("additionalPhones", to: .array(list))
    }
}

struct CountryCodeMenu: View {
    struct Country: Hashable { let iso: String; let callingCode: String; let flag: String }

    static let countries: [Country] = [
        ("GB", "+44"), ("US", "+1"), ("IE", "+353"), ("FR", "+33"), ("DE", "+49"), ("ES", "+34"),
        ("IT", "+39"), ("NL", "+31"), ("BE", "+32"), ("CH", "+41"), ("PT", "+351"), ("SE", "+46"),
        ("NO", "+47"), ("DK", "+45"), ("PL", "+48"), ("AE", "+971"), ("SG", "+65"), ("HK", "+852"),
        ("JP", "+81"), ("KR", "+82"), ("IN", "+91"), ("AU", "+61"), ("CA", "+1"), ("BR", "+55"),
    ].map { Country(iso: $0.0, callingCode: $0.1, flag: flag($0.0)) }

    let countryCode: String?
    let callingCode: String?
    let onSelect: (Country) -> Void

    var body: some View {
        Menu {
            ForEach(Self.countries, id: \.self) { country in
                Button("\(country.flag) \(country.iso) \(country.callingCode)") { onSelect(country) }
            }
        } label: {
            Text(label).monospacedDigit()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var label: String {
        if let countryCode, !countryCode.isEmpty {
            return "\(Self.flag(countryCode)) \(callingCode ?? "")"
        }
        return callingCode?.nilIfEmpty ?? "+…"
    }

    static func flag(_ iso: String) -> String {
        iso.uppercased().unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }.map(String.init).joined()
    }
}

/// LINKS: `{ primaryLinkUrl, primaryLinkLabel, secondaryLinks: [{url, label}] }`.
struct LinksEditor: View {
    let field: FieldMetadata
    @Binding var value: JSONValue

    private var secondary: [JSONValue] { value["secondaryLinks"]?.arrayValue ?? [] }

    var body: some View {
        TextField("URL", text: $value.string("primaryLinkUrl"))
            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
        ForEach(secondary.indices, id: \.self) { index in
            HStack {
                TextField("URL", text: Binding(
                    get: { secondary.indices.contains(index) ? secondary[index]["url"]?.stringValue ?? "" : "" },
                    set: { text in
                        var list = secondary
                        guard list.indices.contains(index) else { return }
                        list[index] = list[index].setting("url", to: .string(text))
                        value = value.setting("secondaryLinks", to: .array(list))
                    }
                ))
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                RemoveButton {
                    var list = secondary
                    list.remove(at: index)
                    value = value.setting("secondaryLinks", to: .array(list))
                }
            }
        }
        Button("Add link", systemImage: "plus") {
            value = value.setting("secondaryLinks", to: .array(secondary + [["url": "", "label": ""]]))
        }
    }
}

/// CURRENCY: `{ amountMicros, currencyCode }`; the user edits whole units.
struct CurrencyEditor: View {
    let field: FieldMetadata
    @Binding var value: JSONValue
    @State private var text = ""

    static let codes = ["GBP", "USD", "EUR", "CHF", "JPY", "CAD", "AUD", "SGD", "HKD", "AED"]

    var body: some View {
        LabeledContent(field.label) {
            HStack {
                TextField("0", text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                Picker("", selection: Binding(
                    get: { value["currencyCode"]?.stringValue ?? "" },
                    set: { value = value.setting("currencyCode", to: .string($0)) }
                )) {
                    let current = value["currencyCode"]?.stringValue ?? ""
                    if !current.isEmpty, !Self.codes.contains(current) { Text(current).tag(current) }
                    if current.isEmpty { Text("—").tag("") }
                    ForEach(Self.codes, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
        .onAppear {
            text = value["amountMicros"]?.doubleValue.map { ($0 / 1_000_000).formatted(.number.grouping(.never)) } ?? ""
        }
        .onChange(of: text) { _, newText in
            let normalized = newText.replacingOccurrences(of: ",", with: ".")
            if newText.isEmpty {
                value = value.setting("amountMicros", to: .null)
            } else if let amount = Double(normalized) {
                value = value.setting("amountMicros", to: .number((amount * 1_000_000).rounded()))
            }
        }
    }
}

struct AddressEditor: View {
    let field: FieldMetadata
    @Binding var value: JSONValue

    var body: some View {
        TextField("Street", text: $value.string("addressStreet1")).textContentType(.streetAddressLine1)
        TextField("Street line 2", text: $value.string("addressStreet2")).textContentType(.streetAddressLine2)
        TextField("City", text: $value.string("addressCity")).textContentType(.addressCity)
        TextField("State / county", text: $value.string("addressState")).textContentType(.addressState)
        TextField("Postcode", text: $value.string("addressPostcode")).textContentType(.postalCode)
        TextField("Country", text: $value.string("addressCountry")).textContentType(.countryName)
    }
}

struct RemoveButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
        }
        .buttonStyle(.plain)
    }
}
