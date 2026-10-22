import Foundation

/// Local script conversion keeps Uzbek Latin ↔ Cyrillic available without
/// spending a public translation quota. Addresses and document links survive.
public enum UzbekScript {
    private static let apostrophes = Set("'‘’ʻʼ`´′")
    private static let cyrillic: [String: String] = ["ё":"yo", "ю":"yu", "я":"ya", "щ":"shch", "ў":"o‘", "ғ":"g‘", "ҳ":"h", "қ":"q", "ц":"ts", "ч":"ch", "ш":"sh", "а":"a", "б":"b", "в":"v", "г":"g", "д":"d", "ж":"j", "з":"z", "и":"i", "й":"y", "к":"k", "л":"l", "м":"m", "н":"n", "о":"o", "п":"p", "р":"r", "с":"s", "т":"t", "у":"u", "ф":"f", "х":"x", "ъ":"’", "ы":"i", "ь":"", "э":"e"]
    private static let latin: [(String, String)] = [("tsiya","ция"), ("sh","ш"), ("ch","ч"), ("yo","ё"), ("yu","ю"), ("ya","я"), ("ye","е"), ("o‘","ў"), ("g‘","ғ"), ("ö","ў"), ("ğ","ғ"), ("ş","ш"), ("ç","ч"), ("a","а"), ("b","б"), ("d","д"), ("f","ф"), ("g","г"), ("h","ҳ"), ("i","и"), ("j","ж"), ("k","к"), ("l","л"), ("m","м"), ("n","н"), ("o","о"), ("p","п"), ("q","қ"), ("r","р"), ("s","с"), ("t","т"), ("u","у"), ("v","в"), ("x","х"), ("y","й"), ("z","з"), ("’","ъ")]
    public static func convert(_ text: String, toCyrillic: Bool) -> String {
        let regex = try! NSRegularExpression(pattern: #"https?://\S+|www\.\S+|[\w.+-]+@[\w-]+\.[\w.-]+|\b[\w-]+(?:\.[\w-]+)*\.(?:uz|com|org|net|edu|gov|ru|io|info|pdf|docx?|xlsx?)\b"#, options: .caseInsensitive)
        let ns = text as NSString
        var output = "", cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            output += map(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)), toCyrillic: toCyrillic)
            output += ns.substring(with: match.range); cursor = NSMaxRange(match.range)
        }
        return output + map(ns.substring(from: cursor), toCyrillic: toCyrillic)
    }
    private static func map(_ original: String, toCyrillic: Bool) -> String {
        let input = Array(original)
        var source: [Character] = []
        for (index, char) in input.enumerated() {
            if toCyrillic, apostrophes.contains(char) {
                source.append(index > 0 && "oOgG".contains(input[index - 1]) ? "‘" : "’")
            } else { source.append(char) }
        }
        let lower = source.map { String($0).lowercased() }
        var result = "", index = 0
        while index < source.count {
            let letter = lower[index], initial = index == 0 || !source[index - 1].isLetter
            var previous = index - 1
            if previous >= 0, lower[previous] == "‘" { previous -= 1 }
            let before = previous >= 0 ? lower[previous] : ""
            var replacement: String?, length = 1
            if toCyrillic {
                if letter == "e" { replacement = initial || "aeiou".contains(before) && !before.isEmpty ? "э" : "е" }
                else if initial, index + 1 < lower.count, lower[index...index + 1].joined() == "ts" { replacement = "ц"; length = 2 }
                else {
                    for (from, to) in latin where index + from.count <= lower.count && lower[index..<index + from.count].joined() == from {
                        replacement = to; length = from.count; break
                    }
                }
            } else if letter == "е" { replacement = initial || "аеёиоуэюяў".contains(before) && !before.isEmpty ? "ye" : "e" }
            else { replacement = cyrillic[letter] }
            guard var target = replacement else { result.append(source[index]); index += 1; continue }
            if source[index].isUppercase {
                var start = index, end = index + length
                while start > 0, source[start - 1].isLetter { start -= 1 }
                while end < source.count, source[end].isLetter { end += 1 }
                let letters = source[start..<end].filter(\.isLetter)
                let allCaps = letters.count > 1 && letters.allSatisfy(\.isUppercase)
                target = allCaps ? target.uppercased() : target.prefix(1).uppercased() + target.dropFirst()
            }
            result += target; index += length
        }
        return result
    }
}
