import Foundation

/// Finds settings by loosely typed words: "fde" finds "Fade when idle", "obsid" finds the
/// note folder (by its keyword "obsidian"). Letters scattered through a long text don't
/// count: a match must contain the query as typed, or hit mostly word starts and runs.
public enum SettingsSearch {
    /// The items matching `query`, best first; `fields` gives an item's title, then its keywords.
    public static func rank<Item>(_ items: [Item], query: String, fields: (Item) -> [String]) -> [Item] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return items }
        return items.enumerated()
            .compactMap { index, item -> (Item, Int, Int)? in
                let texts = fields(item)
                let best = texts.enumerated().compactMap { position, text -> Int? in
                    guard let score = score(query, in: text) else { return nil }
                    return position == 0 ? score * 2 : score // the title counts more
                }.max()
                return best.map { (item, $0, index) }
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
            .map(\.0)
    }

    private static func score(_ query: String, in text: String) -> Int? {
        guard let score = FuzzyMatch.score(query, in: text) else { return nil }
        if text.localizedCaseInsensitiveContains(query) { return score + 1000 }
        let letters = query.filter { !$0.isWhitespace }.count
        let perLetter = Double(score + text.count) / 100 / Double(letters)
        return perLetter >= 3 ? score : nil
    }
}
