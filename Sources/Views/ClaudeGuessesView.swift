#if DEBUG
import SwiftUI

/// More → "Claude's educated guesses", with how many cards are left to review.
struct ClaudeGuessesRow: View {
    @Environment(AppModel.self) private var app
    @State private var count: Int?

    var body: some View {
        NavigationLink { ClaudeGuessesView() } label: {
            HStack {
                Label {
                    Text("Claude's educated guesses")
                } icon: {
                    Image(systemName: "sparkles").foregroundStyle(.orange)
                }
                Spacer()
                if let count { Text("\(count)").foregroundStyle(.secondary).monospacedDigit() }
            }
        }
        .accessibilityIdentifier("more.guesses")
        // Staging, discarding or declining changes the count.
        .task(id: "\(app.recentActions.count)#\(app.declinedGuesses.count)") {
            count = try? await app.loadGuessCards().cards.count
        }
    }
}

/// Tinder-style review of Claude's guesses for empty company fields. Swipe
/// right to stage a card's guesses in Recent actions (nothing is written to
/// Twenty until Apply there), left to decline them for good, up to skip it to
/// the bottom of the pile.
struct ClaudeGuessesView: View {
    typealias Card = ClaudeGuesses.Card
    typealias Field = ClaudeGuesses.Field

    @Environment(AppModel.self) private var app

    private enum Phase { case loading, ready, missing, failed(String) }
    private enum Direction { case left, right, up }

    /// What a swipe did, so ↶ can take it back.
    private struct Swipe {
        let card: Card
        let excluded: Set<Field>
        let stagedID: UUID?
        let declined: [String]
        /// A skip, and the card's earlier skip time to restore on undo.
        var skipped = false
        var previousSkip: Date?
        /// A delete (Recent actions entry), restored from Twenty's trash on undo.
        var deletedActionID: UUID?
        /// A merge staged or dismissed from the card's merge window.
        var merge: MergeEdit?
    }

    /// What staging a merge (or "Not duplicates") changed on the deck.
    private struct MergeEdit {
        /// The staged merge (Recent actions entry), discarded on undo.
        let stagedID: UUID?
        /// Cards taken off the deck (companies the merge deletes), with where they were.
        let removed: [(index: Int, card: Card)]
        /// Cards whose merge button went away, by card id.
        let cleared: [String: ClaudeGuesses.MergeSuggestion]
    }

    @State private var phase: Phase = .loading
    /// Cards left, top first.
    @State private var cards: [Card] = []
    @State private var total = 0
    @State private var generatedAt: Date?
    @State private var history: [Swipe] = []
    /// Guesses tapped off per card; a right swipe leaves them out.
    @State private var excluded: [String: Set<Field>] = [:]
    /// Owners picked in the "Swipe as" bar, by card id, over Claude's guess.
    @State private var owners: [String: String] = [:]
    @State private var drag: CGSize = .zero
    @State private var isFlying = false
    @State private var peopleCounts: [String: Int] = [:]
    @State private var swipes = 0
    /// The card whose company is being deleted (the confirm sheet is up).
    @State private var deleting: Card?
    /// The card whose merge window is up.
    @State private var merging: Card?
    /// Cards whose merge is staged in Recent actions: card id → action id.
    @State private var stagedMerges: [String: UUID] = [:]
    @State private var message: String?

    /// Past this, or on a fast flick, a drag commits.
    private static let threshold: CGFloat = 120

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Claude's guesses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Reload", systemImage: "arrow.clockwise") { Task { await load() } }
                    .disabled(isFlying)
            }
            .task { if case .loading = phase { await load() } }
            .task(id: cards.first?.id) { await loadPeopleCount() }
            .sensoryFeedback(.impact(weight: .light), trigger: swipes)
            .sheet(item: $deleting) { card in
                if let company = app.object(named: "company") {
                    DeleteRecordSheet(object: company, record: card.company, slideToConfirm: true, preselectExtras: true) {
                        deleted(card)
                    }
                }
            }
            .sheet(item: $merging) { card in
                if let suggestion = card.merge {
                    MergeCompaniesSheet(suggestion: suggestion) { action in
                        stagedMerge(action, from: card)
                    } onNotDuplicates: {
                        notDuplicates(card)
                    }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView("Loading guesses…")
        case .missing:
            ContentUnavailableView {
                Label("No guesses file", systemImage: "doc.questionmark")
            } description: {
                Text("This build doesn't include `Config/claude-guesses.json`. Ask Claude to generate it, then rebuild CRM Local from Xcode.")
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't load guesses", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") { Task { await load() } }.buttonStyle(.borderedProminent)
            }
        case .ready:
            if cards.isEmpty { emptyState } else { deck }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            ContentUnavailableView {
                Label("No guesses to review", systemImage: "sparkles")
            } description: {
                Text("Every guess has been accepted, declined or filled in since. Accepted ones wait in Settings → Recent actions until you apply them.\n\nFor new guesses, ask Claude to refresh `Config/claude-guesses.json`, then rebuild CRM Local.")
            }
            .accessibilityIdentifier("guess.empty")
            // Outside ContentUnavailableView, whose identifier would hide the button's.
            if !history.isEmpty {
                Button("Undo last swipe", systemImage: "arrow.uturn.backward") { undo() }
                    .buttonStyle(.bordered)
                    .disabled(isFlying)
                    .padding(.bottom, 40)
                    .accessibilityIdentifier("guess.undo")
            }
        }
    }

    // MARK: Deck

    private var deck: some View {
        VStack(spacing: 18) {
            if let card = cards.first { swipeAsBar(card) }
            Text(progress)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("guess.progress")
            if let message {
                Text(message).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center).padding(.horizontal)
            }
            ZStack {
                ForEach(Array(cards.prefix(3).enumerated()).reversed(), id: \.element.id) { index, card in
                    if index == 0 { topCard(card) } else { peekingCard(card, depth: index) }
                }
            }
            // Clear of the screen edge, where the back swipe starts, with
            // room below for the cards peeking out.
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            buttons
        }
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    /// "3 of 140 · from 1 Oct"
    private var progress: String {
        let position = "\(total - cards.count + 1) of \(total)"
        guard let generatedAt else { return position }
        return position + " · from " + generatedAt.formatted(.dateTime.day().month(.abbreviated))
    }

    /// Mostly upwards: heading for a skip rather than a left/right swipe.
    private var isDraggingUp: Bool { -drag.height > abs(drag.width) }
    /// 0…1 towards accepting or declining, signed by direction.
    private var dragProgress: CGFloat { isDraggingUp ? 0 : max(-1, min(1, drag.width / Self.threshold)) }
    /// 0…1 towards skipping.
    private var skipProgress: CGFloat { isDraggingUp ? max(0, min(1, -drag.height / Self.threshold)) : 0 }
    /// Skipping needs another card to come up.
    private var canSkip: Bool { cards.count > 1 }

    private func topCard(_ card: Card) -> some View {
        let canAccept = acceptable(card)
        return GuessCardView(card: withOwner(card), object: app.object(named: "company"), excluded: excluded[card.id] ?? [],
                             peopleCount: peopleCounts[card.id],
                             toggle: { field in excluded[card.id, default: []].formSymmetricDifference([field]) },
                             onDelete: card.suggestsDelete ? { deleting = card } : nil,
                             mergeWith: card.merge?.others(than: card.id), mergeStaged: stagedMerges[card.id] != nil,
                             onMerge: card.merge != nil && stagedMerges[card.id] == nil ? { merging = card } : nil)
        .overlay(alignment: .topLeading) {
            if dragProgress > 0 {
                Stamp(text: canAccept ? "ACCEPT" : "DONE", color: canAccept ? .green : .blue)
                    .rotationEffect(.degrees(-14))
                    .padding(.top, 28).padding(.leading, 18)
                    .opacity(Double(dragProgress))
            }
        }
        .overlay(alignment: .topTrailing) {
            if dragProgress < 0 {
                Stamp(text: "DECLINE", color: .red)
                    .rotationEffect(.degrees(14))
                    .padding(.top, 28).padding(.trailing, 18)
                    .opacity(Double(-dragProgress))
            }
        }
        .overlay(alignment: .bottom) {
            if skipProgress > 0 {
                Stamp(text: "SKIP", color: .gray)
                    .padding(.bottom, 44)
                    .opacity(Double(skipProgress))
            }
        }
        // Follows the finger upwards (towards a skip); damped otherwise.
        .offset(x: drag.width, y: drag.height < 0 && canSkip ? drag.height : drag.height * 0.3)
        .rotationEffect(.degrees(Double(drag.width / 18)), anchor: .bottom)
        // High priority so a drag that starts on a guess row moves the card;
        // a tap (no movement) still toggles the row.
        .highPriorityGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in if !isFlying { drag = value.translation } }
                .onEnded { value in
                    guard !isFlying else { return }
                    let width = value.translation.width, flick = value.predictedEndTranslation.width
                    let height = value.translation.height, flickUp = value.predictedEndTranslation.height
                    if canSkip, -height > abs(width), height < -Self.threshold || flickUp < -500 {
                        swipe(.up)
                    } else if width > Self.threshold || flick > 400 {
                        swipe(.right)
                    } else if width < -Self.threshold || flick < -400 {
                        swipe(.left)
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { drag = .zero }
                    }
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("guess.card")
        .accessibilityAction(named: canAccept ? "Accept" : "Done") { swipe(.right) }
        .accessibilityAction(named: "Decline") { swipe(.left) }
        .accessibilityAction(named: "Skip") { swipe(.up) }
        .zIndex(1)
    }

    /// The next one or two cards, peeking out below; the next grows as the top one leaves.
    private func peekingCard(_ card: Card, depth: Int) -> some View {
        let lift = depth == 1 ? max(abs(dragProgress), skipProgress) : 0
        return GuessCardView(card: withOwner(card), object: app.object(named: "company"), excluded: excluded[card.id] ?? [],
                             peopleCount: peopleCounts[card.id], toggle: nil, onDelete: nil,
                             mergeWith: nil, mergeStaged: false, onMerge: nil)
            .scaleEffect(1 - (CGFloat(depth) - lift) * 0.05, anchor: .bottom)
            .offset(y: (CGFloat(depth) - lift) * 12)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityHidden(true)
    }

    private var buttons: some View {
        let canAccept = cards.first.map(acceptable) ?? false
        return HStack(alignment: .top, spacing: 22) {
            DeckButton(systemImage: "xmark", title: "Decline", color: .red, size: 64) { swipe(.left) }
                .accessibilityIdentifier("guess.decline")
            DeckButton(systemImage: "arrow.uturn.backward", title: "Undo", color: .secondary, size: 50) { undo() }
                .disabled(history.isEmpty || isFlying)
                .accessibilityIdentifier("guess.undo")
            DeckButton(systemImage: "arrow.up", title: "Skip", color: .secondary, size: 50) { swipe(.up) }
                .disabled(!canSkip || isFlying)
                .accessibilityIdentifier("guess.skip")
            DeckButton(systemImage: "checkmark", title: canAccept ? "Accept" : "Done", color: canAccept ? .green : .blue, size: 64) { swipe(.right) }
                .accessibilityIdentifier("guess.accept")
        }
        .disabled(isFlying)
    }

    // MARK: Swipe as

    /// The team, by first name, for the "Swipe as" bar.
    private var teammates: [(id: String, name: String)] {
        app.members.map { member in
            let name = member["name"]["firstName"]?.nonEmptyString ?? app.memberName(member.id) ?? "Someone"
            return (member.id, name)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Who the card's company will be owned by: picked here, else Claude's
    /// guess; nil when left out or already owned.
    private func owner(of card: Card) -> String? {
        guard !(excluded[card.id] ?? []).contains(.accountOwner) else { return nil }
        let row = card.rows.first { $0.field == .accountOwner }
        if case .current = row?.kind { return nil }
        if let picked = owners[card.id] { return picked }
        return claudesOwner(card)
    }

    private func claudesOwner(_ card: Card) -> String? {
        card.suggestions.first { $0.field == .accountOwner }?.value.stringValue
    }

    /// The current owner's id, when the company already has one.
    private func currentOwner(of card: Card) -> String? {
        let row = card.rows.first { $0.field == .accountOwner }
        guard case .current = row?.kind, let field = app.object(named: "company")?.field(named: "accountOwner") else { return nil }
        return card.company[field.joinColumnName].stringValue ?? card.company[field.name]["id"]?.stringValue
    }

    /// The card with its owner row showing who the bar has picked.
    private func withOwner(_ card: Card) -> Card {
        guard let picked = owners[card.id], picked != claudesOwner(card),
              let index = card.rows.firstIndex(where: { $0.field == .accountOwner }),
              let field = app.object(named: "company")?.field(named: "accountOwner"),
              let suggestion = ClaudeGuesses.suggestion(ClaudeGuesses.Guess(value: .string(picked), confidence: nil, reason: "Your pick"),
                                                        for: .accountOwner, metadata: field, members: app.members,
                                                        memberObject: app.object(named: "workspaceMember")) else { return card }
        if case .current = card.rows[index].kind { return card }
        var rows = card.rows
        rows[index] = ClaudeGuesses.Row(field: .accountOwner, label: rows[index].label, kind: .guess(suggestion))
        return ClaudeGuesses.Card(company: card.company, title: card.title, note: card.note, suggestsDelete: card.suggestsDelete,
                                  rows: rows, merge: card.merge)
    }

    /// Tapping the picked person again leaves the owner out.
    private func pickOwner(_ id: String, for card: Card) {
        if owner(of: card) == id {
            excluded[card.id, default: []].insert(.accountOwner)
        } else {
            owners[card.id] = id
            excluded[card.id, default: []].remove(.accountOwner)
        }
    }

    /// "Swipe as  [Jake] [Raph]": who a right swipe makes the account owner,
    /// starting on Claude's guess. Read-only when the company has an owner.
    @ViewBuilder
    private func swipeAsBar(_ card: Card) -> some View {
        let team = teammates
        if team.count > 1, app.object(named: "company")?.field(named: "accountOwner") != nil {
            let current = currentOwner(of: card)
            let selected = current ?? owner(of: card)
            let claudes = claudesOwner(card)
            HStack(spacing: 8) {
                Text(current == nil ? "Swipe as" : "Owned by")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(team, id: \.id) { member in
                    let isSelected = member.id == selected
                    Button { pickOwner(member.id, for: card) } label: {
                        HStack(spacing: 4) {
                            if member.id == claudes && current == nil { Image(systemName: "sparkles").font(.caption2) }
                            Text(member.name).lineLimit(1)
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .background(isSelected ? (current == nil ? Color.orange : Color.secondary) : Color.secondary.opacity(0.12), in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityHint(member.id == claudes ? "Claude's guess" : "")
                    .accessibilityIdentifier("guess.owner.\(member.id)")
                }
            }
            .disabled(current != nil || isFlying)
            .padding(.horizontal, 24)
            .animation(.snappy, value: selected)
        }
    }

    // MARK: Swiping

    /// Whether a right swipe would stage anything (else it just dismisses).
    private func acceptable(_ card: Card) -> Bool {
        let off = excluded[card.id] ?? []
        return withOwner(card).suggestions.contains { !off.contains($0.field) }
    }

    /// Right stages the guesses left on; anything tapped off, everything on a
    /// left swipe, and the note are remembered as declined.
    private func swipe(_ direction: Direction) {
        guard let card = cards.first, !isFlying else { return }
        if direction == .up { return skip(card) }
        let off = excluded[card.id] ?? []
        let accepted = direction == .right ? withOwner(card).suggestions.filter { !off.contains($0.field) } : []
        let declined = (card.suggestions.filter { !accepted.contains($0) }.map(card.declineKey) + [card.noteKey].compactMap { $0 })
            .filter { !app.declinedGuesses.contains($0) }
        var stagedID: UUID?
        if !accepted.isEmpty, let company = app.object(named: "company") {
            stagedID = app.stage(accepted.map(ClaudeGuesses.change(for:)), for: card.company, of: company).id
        }
        app.declineGuesses(declined)
        history.append(Swipe(card: card, excluded: off, stagedID: stagedID, declined: declined))
        swipes += 1

        isFlying = true
        let goesRight = direction == .right
        withAnimation(.easeIn(duration: 0.22)) {
            drag = CGSize(width: goesRight ? 600 : -600, height: drag.height + 60)
        } completion: {
            cards.removeFirst()
            drag = .zero
            isFlying = false
        }
    }

    /// Sends the top card to the bottom of the pile, keeping any guesses tapped off.
    private func skip(_ card: Card) {
        guard canSkip else { return }
        let previous = app.skipGuess(card.id)
        history.append(Swipe(card: card, excluded: excluded[card.id] ?? [], stagedID: nil, declined: [], skipped: true, previousSkip: previous))
        swipes += 1

        isFlying = true
        withAnimation(.easeIn(duration: 0.22)) {
            drag = CGSize(width: drag.width, height: -900)
        } completion: {
            cards.removeFirst()
            cards.append(card)
            drag = .zero
            isFlying = false
        }
    }

    /// The company went to Twenty's trash (logged in Recent actions): take its card off the deck.
    private func deleted(_ card: Card) {
        guard cards.first?.id == card.id else { return }
        let action = app.recentActions.first { action in
            action.items.contains { if case .deleted("company", card.id, _) = $0 { true } else { false } }
        }
        history.append(Swipe(card: card, excluded: excluded[card.id] ?? [], stagedID: nil, declined: [], deletedActionID: action?.id))
        swipes += 1
        message = nil
        isFlying = true
        withAnimation(.easeIn(duration: 0.22)) {
            drag = CGSize(width: drag.width, height: 900)
        } completion: {
            cards.removeFirst()
            drag = .zero
            isFlying = false
        }
    }

    /// The merge window staged a merge: the card stays (its guesses are still
    /// to review) and says so; cards for the companies it deletes go.
    private func stagedMerge(_ action: RecentAction, from card: Card) {
        guard let merge = action.pendingMerge, let key = card.merge?.key else { return }
        let gone = Set(merge.mergeIDs)
        let removed = cards.enumerated().filter { $0.element.id != card.id && gone.contains($0.element.id) }.map { (index: $0.offset, card: $0.element) }
        for item in removed.reversed() { cards.remove(at: item.index) }
        total -= removed.count
        let cleared = clearMerge(key, except: card.id)
        stagedMerges[card.id] = action.id
        history.append(Swipe(card: card, excluded: excluded[card.id] ?? [], stagedID: nil, declined: [],
                             merge: MergeEdit(stagedID: action.id, removed: removed, cleared: cleared)))
        swipes += 1
    }

    /// "Not duplicates": never suggested again (undo brings it back).
    private func notDuplicates(_ card: Card) {
        guard let key = card.merge?.key else { return }
        app.declineGuesses([key])
        let cleared = clearMerge(key, except: nil)
        history.append(Swipe(card: card, excluded: excluded[card.id] ?? [], stagedID: nil, declined: [key],
                             merge: MergeEdit(stagedID: nil, removed: [], cleared: cleared)))
        swipes += 1
    }

    /// Takes the merge button off every card offering `key` (bar one).
    private func clearMerge(_ key: String, except id: String?) -> [String: ClaudeGuesses.MergeSuggestion] {
        var cleared: [String: ClaudeGuesses.MergeSuggestion] = [:]
        for index in cards.indices where cards[index].id != id {
            guard let merge = cards[index].merge, merge.key == key else { continue }
            cleared[cards[index].id] = merge
            cards[index].merge = nil
        }
        return cleared
    }

    private func undo() {
        guard !isFlying, let last = history.popLast() else { return }
        if let edit = last.merge {
            if let id = edit.stagedID {
                app.discard(id)
                stagedMerges[last.card.id] = nil
            }
            app.undeclineGuesses(last.declined)
            withAnimation(.snappy) {
                for index in cards.indices { if let merge = edit.cleared[cards[index].id] { cards[index].merge = merge } }
                for item in edit.removed { cards.insert(item.card, at: min(item.index, cards.count)) }
            }
            total += edit.removed.count
            return
        }
        if let id = last.deletedActionID {
            // Restores the company (and anything deleted with it) from Twenty's trash first.
            guard let action = app.recentActions.first(where: { $0.id == id }) else {
                message = "That delete is no longer in Recent actions, so it can't be undone here."
                return
            }
            isFlying = true
            Task {
                defer { isFlying = false }
                do {
                    try await app.undo(action)
                    message = nil
                    excluded[last.card.id] = last.excluded
                    withAnimation(.snappy) { cards.insert(last.card, at: 0) }
                } catch {
                    history.append(last)
                    message = "Couldn't restore \(last.card.title): \(error.localizedDescription)"
                }
            }
            return
        }
        if last.skipped {
            app.unskipGuess(last.card.id, restoring: last.previousSkip)
            cards.removeAll { $0.id == last.card.id }
        }
        if let id = last.stagedID { app.discard(id) }
        app.undeclineGuesses(last.declined)
        excluded[last.card.id] = last.excluded
        withAnimation(.snappy) { cards.insert(last.card, at: 0) }
    }

    // MARK: Loading

    private func load() async {
        do {
            let loaded = try await app.loadGuessCards()
            cards = loaded.cards
            total = loaded.cards.count
            generatedAt = loaded.file.generatedAt
            history = []
            excluded = [:]
            owners = [:]
            stagedMerges = [:]
            phase = .ready
        } catch let error as ClaudeGuesses.LoadError where error == .missing {
            phase = .missing
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// "4 people" for the top card's subtitle (lists don't fetch relations).
    private func loadPeopleCount() async {
        guard let card = cards.first, peopleCounts[card.id] == nil, let service = app.service,
              let company = app.object(named: "company"),
              let people = company.relatedLists(in: app.objects).first(where: { $0.target.nameSingular == "person" })?.field,
              let detail = try? await service.fetchRecord(company, id: card.id) else { return }
        peopleCounts[card.id] = detail[people.name].arrayValue?.count ?? 0
    }
}

/// One company: what's set, and Claude's guesses in orange. Tapping a guess
/// leaves it out of the accept (struck through).
private struct GuessCardView: View {
    let card: ClaudeGuesses.Card
    let object: ObjectMetadata?
    let excluded: Set<ClaudeGuesses.Field>
    let peopleCount: Int?
    /// Nil on the cards peeking out behind.
    let toggle: ((ClaudeGuesses.Field) -> Void)?
    /// Set when Claude suggests deleting the company (top card only).
    let onDelete: (() -> Void)?
    /// "Cobalt Custody Ltd": the others in a merge Claude suggests (top card only).
    let mergeWith: String?
    /// The merge is waiting in Recent actions.
    let mergeStaged: Bool
    let onMerge: (() -> Void)?

    private var subtitle: String? {
        let people = peopleCount.map { $0 == 0 ? "No people yet" : $0 == 1 ? "1 person" : "\($0) people" }
        let parts = [card.website, people].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Claude's educated guess", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            HStack(spacing: 12) {
                if let object { RecordAvatar(object: object, record: card.company, size: 48) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title).font(.title3.bold()).lineLimit(2)
                    if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                }
            }
            if let note = card.note {
                Label {
                    Text(note).font(.caption)
                } icon: {
                    Image(systemName: "info.circle")
                }
                .foregroundStyle(.secondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityIdentifier(toggle == nil ? "" : "guess.note")
            }
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete \(card.title)…", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .accessibilityIdentifier("guess.delete")
            }
            if let mergeWith {
                if mergeStaged {
                    Label("Merge with \(mergeWith) is in Recent actions", systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("guess.mergeStaged")
                } else if let onMerge {
                    Button(action: onMerge) {
                        Label("Merge with \(mergeWith)…", systemImage: "arrow.triangle.merge")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.secondary)
                    .accessibilityIdentifier("guess.merge")
                }
            }
            Divider()
            ForEach(card.rows) { row in
                GuessRowView(row: row, isExcluded: excluded.contains(row.field), toggle: toggle.map { toggle in { toggle(row.field) } })
            }
            Spacer(minLength: 0)
            Text(card.suggestions.isEmpty ? "Nothing to fill in. Swipe either way to dismiss." : "Tap a guess to leave it out.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        }
        .padding(20)
        .frame(maxWidth: 440, maxHeight: .infinity, alignment: .top)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.orange.opacity(0.3)))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    }
}

private struct GuessRowView: View {
    let row: ClaudeGuesses.Row
    let isExcluded: Bool
    let toggle: (() -> Void)?

    var body: some View {
        switch row.kind {
        case .guess(let suggestion):
            Button { toggle?() } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        label
                        Spacer()
                        if let confidence = suggestion.confidence { ConfidenceBadge(confidence: confidence) }
                    }
                    if suggestion.field == .companyType {
                        FlowLayout(spacing: 4) {
                            ForEach(suggestion.chips, id: \.self) { GuessChip(label: $0, isExcluded: isExcluded) }
                        }
                    } else {
                        Text(suggestion.display)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(isExcluded ? Color.secondary : Color.orange)
                            .strikethrough(isExcluded)
                    }
                    if let reason = suggestion.reason {
                        Text(reason).font(.caption).foregroundStyle(.secondary).strikethrough(isExcluded)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityValue(isExcluded ? "Left out" : "Included")
            .accessibilityHint(isExcluded ? "Includes this guess" : "Leaves this guess out")
            // Only the top card's rows; the ones peeking out behind can't be tapped.
            .accessibilityIdentifier(toggle == nil ? "" : "guess.row.\(row.field.rawValue)")
        case .current(let text, let chips):
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    label
                    Spacer()
                    Text("Current")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
                if chips.isEmpty {
                    Text(text)
                } else {
                    FlowLayout(spacing: 4) {
                        ForEach(chips, id: \.self) { chip in
                            Text(chip).font(.subheadline).padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }
            .accessibilityElement(children: .combine)
        case .empty:
            VStack(alignment: .leading, spacing: 4) {
                label
                Text("—").foregroundStyle(.tertiary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var label: some View {
        Text(row.label).font(.subheadline).foregroundStyle(.secondary)
    }
}

/// An orange chip for a guessed option; grey and struck through when left out.
private struct GuessChip: View {
    let label: String
    let isExcluded: Bool

    var body: some View {
        let tint = isExcluded ? Color.secondary : Color.orange
        Text(label)
            .font(.subheadline.weight(.semibold))
            .strikethrough(isExcluded)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(tint.opacity(0.15), in: Capsule())
    }
}

/// Signal bars: three for high confidence, one for low.
struct ConfidenceBadge: View {
    let confidence: ClaudeGuesses.Confidence

    var body: some View {
        let level: Double = switch confidence { case .high: 1; case .medium: 0.66; case .low: 0.33 }
        HStack(spacing: 3) {
            Image(systemName: "cellularbars", variableValue: level)
            Text(confidence.rawValue.capitalized)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(confidence.rawValue.capitalized) confidence")
    }
}

/// "ACCEPT" / "DECLINE", fading in as the card is dragged.
private struct Stamp: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.title2.weight(.heavy))
            .tracking(2)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(.secondarySystemGroupedBackground).opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color, lineWidth: 3))
            .accessibilityHidden(true)
    }
}

private struct DeckButton: View {
    let systemImage: String
    let title: String
    let color: Color
    let size: CGFloat
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: size, height: size)
                    .background(Color(.secondarySystemGroupedBackground), in: Circle())
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
#endif
