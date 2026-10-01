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

## Point of contact (people)

- **What it is:** people in the tGBP workspace have no owner field, so the app
  infers each person's internal point of contact (`PointOfContactSources`):
  1. their company's account owner, else
  2. whoever brought them into Twenty (`createdBy.workspaceMemberId`). That's
     the member who created them, or whose inbox or calendar sync imported them.
- **Where it shows:** a **Point of contact** filter chip on People (Me, each
  team member, Unassigned), a line on each person row, and a row on the detail
  screen that says which of the two rules applied.
- **How it filters:** on the server, with twenty-server's one-hop relation
  filters, which are LEFT JOINs:
  `or(company.accountOwnerId[in]:[…],and(or(companyId[is]:NULL,company.accountOwnerId[is]:NULL),createdBy.workspaceMemberId[in]:[…]))`.
- **If People gets its own owner field:** add an `accountOwner` field to People
  in Twenty and it replaces the inference automatically.

## Deleting and undo

- **Where:** swipe left on a row, or use ⋯ → Delete on a record. Either opens a
  confirmation sheet, and nothing happens until you tap Delete there.
- **Soft deletes only:** records are always soft-deleted (`DELETE …?soft_delete=true`),
  which moves them to Twenty's trash. Without that flag, Twenty's REST DELETE
  destroys the record permanently.
- **Options in the sheet:**
  - On a company, "Also delete its N people" (off by default).
  - "Stop importing @domain" (off by default; needs a signed-in member). It
    adds a `blocklist` entry so inbox and calendar sync don't re-add it. People
    on webmail domains are blocked by exact address, not by the whole domain.
- **Undo:** a banner offers Undo for 6 seconds. Settings → **Recent actions**
  keeps each delete for 24 hours, saved per workspace, so it survives
  relaunching. Undo calls `PATCH /rest/{plural}/{id}/restore` and permanently
  removes the blocklist entry it added.
- **Commit:** a Commit button on each entry, plus **Commit all**, makes the
  delete final. It permanently deletes the record from Twenty's trash with
  `DELETE` (no `soft_delete`), which uses the same destroy code path as
  emptying the trash on the web. It asks first, and blocks it added stay.

## Local vs TestFlight builds

Debug builds, meaning anything installed from Xcode or `devicectl`, are
marked so they can't be mistaken for the TestFlight app:
- they're called **CRM Local** (`APP_DISPLAY_NAME` per config in project.yml);
- they use the orange **AppIcon-Local** icon (`swift scripts/make-icon.swift … --local`);
- they draw an orange frame around the screen (`LocalBuildFrame`, `#if DEBUG`).

Release builds (TestFlight) are unchanged: "CRM" with the blue icon.

## List filters

- Lists with select, multi-select or owner fields get a chip bar under the
  title. On Companies that's **Tier**, **Owner** and a **Filters** button with
  every filterable field (sectors and so on).
- Filters stack: AND across fields, OR within a field (Tier 1 or Tier 2, and
  owned by me). Owner options include **Me**, which follows whoever is signed
  in, and **Unassigned**. Select fields have a "No …" option.
- Picking applies straight away. The sheet's button shows the live match count ("Show 12").
- Filters are saved per workspace in UserDefaults (`listFilters.<server>|<workspace>`),
  so they survive quitting the app. Option keys deleted from the workspace are
  ignored rather than emptying the list.
- Wire format, checked against twenty-server's REST filter parser: `tier[in]:["TIER_1"]`,
  `sectors[containsAny]:[…]`, `accountOwnerId[in]:[uuid,…]`, `x[is]:NULL`, nested in
  `and(…)`/`or(…)` and combined with the search clause. See `Sources/Models/ListFilter.swift`.
- iOS 26: a horizontal `ScrollView` pinned under the navigation bar isn't drawn,
  so the chip row uses `ViewThatFits` and shows as many chips as fit. It's pinned
  with `safeAreaBar` on iOS 26 and `safeAreaInset` earlier.

## Not yet

Deleting records, rich-text (notes body) editing, and file attachments.
