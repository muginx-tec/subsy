import Foundation

/// Çeviriden önce İngilizce metni toparlar. Telefonun hazır çevirisi cümleyi tek başına ve kelime kelime
/// çeviriyor; deyim ve sokak ağzında bozuluyor (2026-11-16 kaydı: "The only catch" → "Tek yakalama",
/// "Sweet Jesus" → "Tatlı İsa"). Burada bilinen kalıplar düz İngilizceye çevrilir, hazır çeviri düz
/// cümleyi doğru çevirir. Telefonda, bedava, anında çalışır. Liste başlangıçtır; oyun oyun büyür.
enum Phrasebook {
    /// "Joel: I tried knocking" → ("Joel", "I tried knocking"). Ad yoksa (nil, metin).
    static func splitSpeaker(_ text: String) -> (String?, String) {
        guard let colon = text.firstIndex(of: ":") else { return (nil, text) }
        let name = text[..<colon].trimmingCharacters(in: .whitespaces)
        let body = text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        // Ad: kısa, büyük harfle başlar, en çok üç kelime, rakamsız. Saat ("10:30") ya da cümle içi iki nokta ad değildir.
        let words = name.split(separator: " ")
        guard !body.isEmpty, (1...3).contains(words.count), name.count <= 22,
              let first = name.first, first.isUppercase,
              name.allSatisfy({ $0.isLetter || $0 == " " || $0 == "." || $0 == "'" || $0 == "-" }) else { return (nil, text) }
        return (name, body)
    }

    static func normalize(_ text: String) -> String {
        var s = text
        for (pattern, replacement) in rules {
            s = s.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
        }
        return s
    }

    /// (kalıp, düz İngilizce karşılığı). Sıra önemli: uzun kalıplar önce.
    private static let rules: [(String, String)] = [
        // Deyimler
        (#"\byou almost gave me a heart attack\b"#, "you scared me very much"),
        (#"\bget(ting)? out of your hair\b"#, "stop bothering you"),
        (#"\b(get to|find some|take|get behind) cover\b"#, "take shelter"),
        (#"\bset(ting)? the charges\b"#, "placing the explosives"),
        (#"\bbrace yoursel(f|ves)\b"#, "get ready"),
        (#"\bthe only catch\b"#, "the only problem"),
        (#"\bwhat'?s the catch\b"#, "what is the problem"),
        (#"\bsweet jesus\b"#, "oh my god"),
        (#"\bjesus christ\b"#, "oh my god"),
        (#"\bbuy(ing)? into\b"#, "believe in"),
        (#"\bdo right by\b"#, "do the right thing for"),
        (#"\bwe made it\b"#, "we succeeded"),
        (#"\byou made it\b"#, "you succeeded"),
        (#"\bpiece of cake\b"#, "very easy"),
        (#"\bgive me a hand\b"#, "help me"),
        (#"\bcut it out\b"#, "stop it"),
        (#"\bknock it off\b"#, "stop it"),
        (#"\bhang in there\b"#, "stay strong"),
        (#"\bwatch your back\b"#, "be careful"),
        (#"\bmy bad\b"#, "my mistake"),
        (#"\bfor real\b"#, "really"),
        (#"\bheads up\b"#, "be careful"),
        (#"\bhold on\b"#, "wait"),
        (#"\bhang on\b"#, "wait"),
        // Konuşma dili kısaltmaları
        (#"\bgonna\b"#, "going to"),
        (#"\bgotta\b"#, "have to"),
        (#"\bwanna\b"#, "want to"),
        (#"\blemme\b"#, "let me"),
        (#"\bgimme\b"#, "give me"),
        (#"\bkinda\b"#, "kind of"),
        (#"\bsorta\b"#, "sort of"),
        (#"\boutta\b"#, "out of"),
        (#"\bdunno\b"#, "do not know"),
        (#"\by'?know\b"#, "you know"),
        (#"\bc'?mon\b"#, "come on"),
        (#"\bI ain'?t\b"#, "I am not"),
        (#"\b(you|we|they) ain'?t\b"#, "$1 are not"),
        (#"\bain'?t\b"#, "is not"),
        (#"(?<=\s)'em\b"#, "them"),
        (#"\b(\w+)in'(?=[\s.,!?\"]|$)"#, "$1ing"),   // somethin' → something, doin' → doing
    ]
}
