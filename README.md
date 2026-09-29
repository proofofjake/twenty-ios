# TwentyCRM (iOS)

Native SwiftUI front end for a [Twenty](https://twenty.com) CRM workspace:
browse and search People, Companies and any other object, and edit records
with type-aware editors. Multi-select, select, rating, emails, phones, links,
currency, address, dates, arrays and many-to-one relations all get real
controls. Unknown field types fall back to read-only; they are never shown
as a text box.

## Run

```sh
xcodegen generate
open TwentyCRM.xcodeproj
# or: xcodebuild -project TwentyCRM.xcodeproj -scheme TwentyCRM \
#       -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build test
```

On first launch, enter your server URL (`https://api.twenty.com` for Twenty
Cloud, or your self-hosted domain) and tap **Sign in**. That opens Twenty's own
login page (Continue with Google, as on the web). The app then acts as that
person. An API key (Twenty → Settings → APIs & Webhooks) still works under
"Use an API key instead", but a key acts as the whole workspace, so records
aren't credited to anyone. Tokens and keys are stored in the Keychain. "Try demo
data" (or the `-demo` launch argument) runs against in-memory sample data.

## Sign-in (verified against twenty main, 2026-09-29)

- Standard OAuth 2.1 (`Sources/API/OAuth.swift`):
  1. Discovery at `/.well-known/oauth-authorization-server`.
  2. Dynamic client registration, once per server. The client id is cached,
     since registration is limited to 10 per hour per IP.
  3. PKCE S256.
  4. `ASWebAuthenticationSession`, which shares Safari's cookies.
  5. The authorize page opens on the workspace's own domain (the Workspace
     field, e.g. `https://tokenisedgbp.twenty.com`). The generic
     `app.twenty.com` login shows a workspace picker with "Create a workspace",
     and creates an empty Twenty user for any Google email it doesn't know.
- Twenty only accepts https, loopback or `cursor:`/`vscode:`/`code:` redirect
  URIs, matched exactly. So the redirect is `http://127.0.0.1:47823/callback`,
  caught by an in-app `NWListener`, which then closes the sheet.
- Access tokens last 30 minutes and refresh tokens last 60 days (rotating).
  `OAuthCredential` refreshes them before expiry and after any 401.
- A user token applies that person's role and sets `createdBy` to them.
- New records get the signed-in `workspaceMember` in any `accountOwner`/`owner`
  relation (`ObjectMetadata.ownerFields`). The member is looked up with the
  token's `userId` claim through `GET /rest/workspaceMembers?filter=userId[eq]:…`.

## TestFlight

```sh
scripts/testflight.sh              # Release archive + upload to App Store Connect
scripts/testflight.sh --no-upload  # archive + export an .ipa only
```

- Build numbers are UTC timestamps, so every upload is higher than the last.
- `ITSAppUsesNonExemptEncryption` is false, so uploads skip the encryption questions.
- To upload, it signs in with the Apple ID in Xcode → Settings → Accounts, or
  with an App Store Connect API key (`ASC_KEY_PATH`, `ASC_KEY_ID`, `ASC_ISSUER_ID`).
- It needs a **paid** Apple Developer Program team as `DEVELOPMENT_TEAM` in
  project.yml, plus an app record in App Store Connect for `io.tgbp.twentycrm`.
- The icon comes from `scripts/make-icon.swift`.
- No credentials are in the build: users sign in (or enter a key) on the device.

## How it talks to Twenty (verified against server v2.41.0)

- **Schema**: GraphQL `POST /metadata`, using the `objects { … fieldsList { … relation { targetObjectMetadata } } }`
  query. This is the only place relation targets are exposed. If it fails,
  the app falls back to REST `GET /rest/metadata/objects`, and relation
  pickers become read-only. The REST metadata envelope is either
  `{data:[…]}` or `{data:{objects:[…]}}`; both are handled.
- **Records**: REST `GET /rest/{plural}`
  - Lists use `depth=0`, cursor paging (`starting_after`) and `ilike` search filters.
  - Detail uses `GET /rest/{plural}/{id}?depth=1`.
- **Saves**: `PATCH /rest/{plural}/{id}` sends **only the fields that changed**
  (`Record.changes(from:writable:)`). Relations are set through their join
  column (`companyId`). `id`/`createdAt`/`updatedAt`/`position`/etc. are
  never sent. Twenty accepts writes to them and would silently overwrite them.
- **Stored values**: MULTI_SELECT is an array of option `value` keys, SELECT
  is one key, and RATING is `"RATING_1"`…`"RATING_5"`.

## Layout

- `Sources/API`: `TwentyService` protocol, `LiveTwentyService` (REST + GraphQL), `JSONValue`, Keychain
- `Sources/Models`: field/object metadata, `Record`, `FieldFormatter`
- `Sources/Views/Editors`: one editor per field type; `FieldEditorKind` decides which
- `Sources/Demo`: in-memory `DemoTwentyService` with sample data
- `Tests`: wire-format and PATCH-diff unit tests
- `UITests`: edits a multi-select end to end in demo mode

## Creating and related records

- The floating **+** on any writable object's list opens the Typeform-style
  add flow (`CreateFlowView`). It asks one question per screen, following
  `ObjectMetadata.createSteps()`: a curated order for people and companies,
  with fields missing from the workspace skipped, then a final optional
  "Anything else?" step.
  - Only the name is required, and "Create" is available from any step.
  - Saving POSTs `/rest/{plural}` with only the fields that were filled in.
- A person's "Where do they work?" step, and every relation picker, can
  create the missing company on the spot, prefilled from what was searched.
- Detail screens list one-to-many relations whose target object isn't a
  system object, with People first. On a company, that shows the people who
  work there. Each list has an "Add …" button that prefills the inverse
  join column (e.g. `companyId`), taken from the relation's `targetFieldMetadata`.
- Forms and detail screens show the title first, then `domainName` (the
  website). All other fields keep the workspace's order (`ObjectMetadata.pinnedFirst`).

## Not yet

Deleting records, rich-text (notes body) editing, and file attachments.
