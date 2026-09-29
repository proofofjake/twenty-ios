import SwiftUI
import UIKit

/// Avatar for a record row or header: the company's favicon when the record
/// has a website (like Twenty's web app), otherwise coloured initials.
struct RecordAvatar: View {
    let object: ObjectMetadata
    let record: Record
    var size: CGFloat = 38

    var body: some View {
        let title = record.title(in: object)
        if let domain = Favicons.domain(from: record["domainName"]) {
            CompanyLogo(domain: domain, title: title, size: size)
        } else {
            Avatar(title: title, isPerson: object.labelIdentifierField?.type == .fullName, size: size)
        }
    }
}

struct CompanyLogo: View {
    let domain: String
    let title: String
    var size: CGFloat = 38
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(size * 0.12)
                    .frame(width: size, height: size)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: size * 0.22))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.22).stroke(Color.secondary.opacity(0.2)))
            } else {
                Avatar(title: title, isPerson: false, size: size)
            }
        }
        .task(id: domain) { image = await Favicons.shared.image(for: domain) }
    }
}

/// Fetches and caches favicons from twenty-icons.com, the service Twenty's
/// own web app uses for company logos. Misses (404) are remembered so they
/// aren't re-requested while scrolling.
@MainActor
final class Favicons {
    static let shared = Favicons()

    private var images: [String: UIImage] = [:]
    private var missing: Set<String> = []
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    func image(for domain: String) async -> UIImage? {
        if let cached = images[domain] { return cached }
        if missing.contains(domain) { return nil }
        if let task = inFlight[domain] { return await task.value }
        let task = Task<UIImage?, Never> {
            guard let url = URL(string: "https://twenty-icons.com/\(domain)"),
                  let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return UIImage(data: data)
        }
        inFlight[domain] = task
        let image = await task.value
        inFlight[domain] = nil
        if let image { images[domain] = image } else { missing.insert(domain) }
        return image
    }

    /// "https://www.acme.com/about" → "acme.com"; nil if there's no usable host.
    nonisolated static func domain(from links: JSONValue) -> String? {
        guard var text = links["primaryLinkUrl"]?.nonEmptyString else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard var host = URL(string: text)?.host()?.lowercased(), host.contains(".") else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }
}
