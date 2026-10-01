import Foundation

extension DemoData {
    static func records() -> [String: [Record]] {
        let now = FieldFormatter.dateTimeString(Date())
        func stamp(_ values: [String: JSONValue]) -> Record {
            var values = values
            values["createdAt"] = .string(now)
            values["updatedAt"] = .string(now)
            values["createdBy"] = ["source": "MANUAL", "name": "Demo", "workspaceMemberId": nil]
            return Record(id: values["id"]!.stringValue!, values: values)
        }

        let companies: [Record] = [
            stamp([
                "id": "c0000000-0000-4000-8000-000000000001", "name": "Northwind Exchange",
                "domainName": ["primaryLinkUrl": "northwind.example", "primaryLinkLabel": "", "secondaryLinks": []],
                "employees": 240, "idealCustomerProfile": true,
                "annualRecurringRevenue": ["amountMicros": 4_500_000_000_000, "currencyCode": "GBP"],
                "address": ["addressStreet1": "1 Finsbury Sq", "addressCity": "London", "addressPostcode": "EC2A 1AE", "addressCountry": "United Kingdom"],
                "sectors": ["EXCHANGE", "DEFI"], "tier": "TIER_1", "accountOwnerId": "m0000000-0000-4000-8000-000000000001",
            ]),
            stamp([
                "id": "c0000000-0000-4000-8000-000000000002", "name": "Harbour Bank",
                "domainName": ["primaryLinkUrl": "harbourbank.example", "primaryLinkLabel": "", "secondaryLinks": []],
                "employees": 5200, "idealCustomerProfile": false,
                "sectors": ["BANK", "CUSTODY", "PAYMENTS"], "tier": "TIER_2", "accountOwnerId": "m0000000-0000-4000-8000-000000000002",
            ]),
            stamp([
                "id": "c0000000-0000-4000-8000-000000000003", "name": "Lumen Payments",
                "domainName": ["primaryLinkUrl": "lumenpay.example", "primaryLinkLabel": "", "secondaryLinks": []],
                "employees": 58, "sectors": ["FINTECH", "PAYMENTS"], "tier": nil, "accountOwnerId": nil,
            ]),
        ]

        func person(_ n: Int, _ first: String, _ last: String, _ email: String, _ title: String, _ company: Int?,
                    tags: [JSONValue], stage: JSONValue, warmth: JSONValue = nil, addedBy: Int? = nil) -> Record {
            var record = stamp([
                "id": .string("p0000000-0000-4000-8000-00000000000\(n)"),
                "name": ["firstName": .string(first), "lastName": .string(last)],
                "emails": ["primaryEmail": .string(email), "additionalEmails": []],
                "phones": ["primaryPhoneNumber": .string("7700 900\(n)\(n)\(n)"), "primaryPhoneCountryCode": "GB", "primaryPhoneCallingCode": "+44", "additionalPhones": []],
                "jobTitle": .string(title), "city": "London",
                "linkedinLink": ["primaryLinkUrl": "", "primaryLinkLabel": "", "secondaryLinks": []],
                "tags": .array(tags), "stage": stage, "warmth": warmth,
                "interests": ["Stablecoins", "Tokenisation"],
                "lastMet": "2026-09-01",
                "companyId": company.map { .string("c0000000-0000-4000-8000-00000000000\($0)") } ?? .null,
            ])
            // Who added them (manually, or from their inbox/calendar sync).
            if let addedBy {
                record["createdBy"] = ["source": "EMAIL", "name": "Demo", "workspaceMemberId": .string("m0000000-0000-4000-8000-00000000000\(addedBy)")]
            }
            return record
        }

        let people: [Record] = [
            person(1, "Ada", "Hart", "ada@northwind.example", "Head of Listings", 1, tags: ["PARTNER", "CUSTOMER"], stage: "ACTIVE", warmth: "RATING_4"),
            person(2, "Ben", "Okafor", "ben@harbourbank.example", "Digital Assets Lead", 2, tags: ["INVESTOR"], stage: "WARM", warmth: "RATING_3"),
            person(3, "Chloe", "Marsh", "chloe@lumenpay.example", "CTO", 3, tags: [], stage: nil, addedBy: 2),
            person(4, "Dev", "Patel", "dev@press.example", "Reporter", nil, tags: ["PRESS"], stage: "COLD", warmth: "RATING_1", addedBy: 1),
            person(5, "Eve", "Lindqvist", "eve@northwind.example", "Compliance", 1, tags: ["REGULATOR", "ADVISOR", "PARTNER", "INVESTOR"], stage: "DORMANT"),
        ]

        let opportunities: [Record] = [
            stamp([
                "id": "o0000000-0000-4000-8000-000000000001", "name": "Northwind GBP pair",
                "amount": ["amountMicros": 250_000_000_000, "currencyCode": "GBP"],
                "closeDate": "2026-11-30T12:00:00.000Z", "stage": "PROPOSAL",
                "companyId": "c0000000-0000-4000-8000-000000000001",
                "pointOfContactId": "p0000000-0000-4000-8000-000000000001",
            ]),
        ]

        let members: [Record] = [
            stamp(["id": "m0000000-0000-4000-8000-000000000001", "name": ["firstName": "Jake", "lastName": "Demo"]]),
            stamp(["id": "m0000000-0000-4000-8000-000000000002", "name": ["firstName": "Sam", "lastName": "Rivera"]]),
        ]

        return ["companies": companies, "people": people, "opportunities": opportunities, "workspaceMembers": members]
    }
}
