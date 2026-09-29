# Agent Instructions

- See README.md for status and the Twenty API facts (verified against twenty v2.41.0 source).
- Edit `project.yml`, never the generated `TwentyCRM.xcodeproj`; run `xcodegen generate` after adding files.
- Records are schema-driven `JSONValue`, never fixed structs; field behaviour goes through `FieldEditorKind`.
- PATCH only changed fields via `Record.changes(from:writable:)`; never send system fields (see `FieldEditorKind.systemFieldNames`).
- Test: `xcodebuild -project TwentyCRM.xcodeproj -scheme TwentyCRM -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build test`
