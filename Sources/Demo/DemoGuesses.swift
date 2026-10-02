#if DEBUG
import Foundation

extension DemoData {
    /// Claude's educated guesses for the demo companies, in the same format
    /// as `Config/claude-guesses.json`. Covers every case the deck handles:
    /// - Atlas: all four guessed.
    /// - Northwind: only the type still applies; the rest are stale (already set).
    /// - Harbour Bank: everything stale, so no card.
    /// - Lumen: unknown member and option dropped; two of three company types kept.
    /// - Brightline: malformed domain dropped; no company type guessed.
    /// - Cobalt: a note plus guesses, a URL-shaped domain and an unknown confidence.
    /// - Inkwell: a note and nothing to fill.
    /// - An id that isn't in the workspace, and keys this version ignores.
    /// - Merges: Cobalt Custody Ltd into Cobalt Custody, with Claude's picks
    ///   for the name, website and address; then ones to skip (a company
    ///   that isn't in the workspace, a non-string id, nothing to merge).
    static let guessesJSON = #"""
    {
      "version": 1,
      "generatedAt": "2026-10-01T16:00:00Z",
      "generatedBy": "Claude",
      "workspaceSubdomain": "demo",
      "somethingNew": {"ignored": true},
      "companies": [
        {
          "id": "c0000000-0000-4000-8000-000000000004",
          "name": "Atlas Asset Management",
          "guesses": {
            "domainName": { "value": "atlas-am.example", "confidence": "high", "reason": "Farah emails from @atlas-am.example" },
            "accountOwner": { "value": "m0000000-0000-4000-8000-000000000001", "confidence": "medium", "reason": "Synced in from Jake's inbox" },
            "tag": { "value": "INSTITUTIONAL", "confidence": "high", "reason": "An asset manager" },
            "companyType": { "value": ["ASSET_MANGER", "CUSTODIAN"], "confidence": "medium", "reason": "Runs funds and holds client assets" }
          }
        },
        {
          "id": "c0000000-0000-4000-8000-000000000001",
          "name": "Northwind Exchange",
          "guesses": {
            "domainName": { "value": "northwind-exchange.example", "confidence": "low", "reason": "Seen in a signature" },
            "accountOwner": { "value": "m0000000-0000-4000-8000-000000000002", "confidence": "low", "reason": "Sam met them last" },
            "tag": { "value": "DEFI", "confidence": "medium", "reason": "Lists DeFi tokens and runs a DEX" },
            "companyType": { "value": ["MARKET_MAKER"], "confidence": "low", "reason": "Makes markets on its own venue" }
          }
        },
        {
          "id": "c0000000-0000-4000-8000-000000000002",
          "name": "Harbour Bank",
          "guesses": {
            "tag": { "value": "REGULATORY", "confidence": "low", "reason": "Regulated bank" },
            "companyType": { "value": ["BANK", "CUSTODIAN"], "confidence": "high", "reason": "A bank" }
          }
        },
        {
          "id": "c0000000-0000-4000-8000-000000000003",
          "name": "Lumen Payments",
          "guesses": {
            "accountOwner": { "value": "m0000000-0000-4000-8000-000000000099", "confidence": "high", "reason": "Not a member of this workspace" },
            "tag": { "value": "FINTECH", "confidence": "medium", "reason": "Not an option of Type" },
            "companyType": { "value": ["PAYMENTS_INFRA", "PAYMENT_RAILS", "CARD_PROVIDER"], "confidence": "high", "reason": "Card issuing and payouts API" }
          }
        },
        {
          "id": "c0000000-0000-4000-8000-000000000005",
          "name": "Brightline Labs",
          "guesses": {
            "domainName": { "value": "brightline labs dot com", "confidence": "low", "reason": "Not a hostname" },
            "accountOwner": { "value": "m0000000-0000-4000-8000-000000000002", "confidence": "low", "reason": "Sam added their CTO" },
            "tag": { "value": "DEFI", "confidence": "high", "reason": "Builds lending vaults" }
          }
        },
        {
          "id": "c0000000-0000-4000-8000-000000000006",
          "name": "Cobalt Custody",
          "note": "Duplicate: there's also a Cobalt Custody Ltd. Consider merging",
          "guesses": {
            "domainName": { "value": "https://www.cobaltcustody.example/", "confidence": "medium", "reason": "Linked from their LinkedIn page" },
            "companyType": { "value": ["CUSTODIAN", "COLLATERAL_PRIME_BROKER"], "confidence": "very high", "reason": "Qualified custodian with a prime desk" },
            "employees": { "value": 40 }
          }
        },
        {
          "id": "c0000000-0000-4000-8000-000000000007",
          "name": "Inkwell Sign",
          "note": "Inbox noise: e-signature notification emails. Probably delete",
          "guesses": {
            "domainName": { "value": "inkwellsign.example", "confidence": "high", "reason": "Already set" }
          }
        },
        {
          "id": "c0000000-0000-4000-8000-000000000099",
          "name": "Not in this workspace",
          "guesses": { "tag": { "value": "DEFI" } }
        }
      ],
      "merges": [
        {
          "keep": "c0000000-0000-4000-8000-000000000006",
          "merge": ["c0000000-0000-4000-8000-000000000008"],
          "confidence": "high",
          "reason": "Same custodian added twice: one from Sam's inbox, one by hand. Keep the one with the owner and Claude's guesses.",
          "fields": {
            "name": { "from": "c0000000-0000-4000-8000-000000000008", "reason": "The registered name" },
            "domainName": { "from": "c0000000-0000-4000-8000-000000000008", "reason": "Only this one has a website" },
            "address": { "from": "c0000000-0000-4000-8000-000000000008", "reason": "Their office is in London, per Gus's signature" },
            "companyType": { "from": "c0000000-0000-4000-8000-000000000008", "reason": "Custodian; the types are combined anyway" },
            "tier": { "from": "c0000000-0000-4000-8000-000000000099", "reason": "Not one of the merged companies" }
          }
        },
        {
          "keep": "c0000000-0000-4000-8000-000000000001",
          "merge": ["c0000000-0000-4000-8000-000000000099"],
          "confidence": "low",
          "reason": "Not in this workspace"
        },
        { "keep": "c0000000-0000-4000-8000-000000000002", "merge": [42], "reason": "Not an id" },
        { "keep": "c0000000-0000-4000-8000-000000000003", "merge": [] }
      ]
    }
    """#
}
#endif
