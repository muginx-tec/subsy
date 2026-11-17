import SwiftUI

/// Mağaza ekran görüntüleri için örnekler. Replikler ve sahne hiçbir oyundan alınmadı:
/// ad, karakter, küfür ve şiddet yok. Yalnız açılış seçenekleriyle (-altyaziOnizleme, -kutuOnizleme) görünür.
enum Onizleme {
    /// Örnek replikler, hedef dile göre. İngilizce arayüz seçiliyse İngilizce.
    static var replikler: [String] {
        let kod = ArayuzDili.secilen == "en" ? "en" : Diller.secili.kod
        return metinler[kod] ?? metinler["en"]!
    }

    private static let metinler: [String: [String]] = [
        "en": ["Where have you been? I waited all night.",
               "The bridge was closed, so I took the long way.",
               "Fine. Grab the map, we leave at sunrise.",
               "Stay close. This road gets dark fast."],
        "tr": ["Neredeydin? Bütün gece bekledim.",
               "Köprü kapalıydı, uzun yoldan geldim.",
               "Peki. Haritayı al, gün doğarken çıkıyoruz.",
               "Yanımdan ayrılma. Bu yol çabuk kararır."],
        "ar": ["أين كنت؟ انتظرتك طوال الليل.",
               "كان الجسر مغلقًا، فسلكت الطريق الطويل.",
               "حسنًا. خذ الخريطة، سننطلق عند الفجر.",
               "ابقَ قريبًا. هذا الطريق يُظلم بسرعة."],
        "id": ["Kamu dari mana? Aku menunggu semalaman.",
               "Jembatannya ditutup, jadi aku lewat jalan memutar.",
               "Oke. Ambil petanya, kita berangkat saat matahari terbit.",
               "Jangan jauh-jauh. Jalan ini cepat gelap."],
        "hi": ["तुम कहाँ थे? मैं पूरी रात इंतज़ार करता रहा।",
               "पुल बंद था, इसलिए मैं लंबे रास्ते से आया।",
               "ठीक है। नक्शा ले लो, हम सूरज निकलते ही चलेंगे।",
               "पास रहना। इस रास्ते पर जल्दी अँधेरा हो जाता है।"],
        "th": ["นายไปไหนมา ฉันรอทั้งคืนเลย",
               "สะพานปิด เลยต้องอ้อมไปอีกทาง",
               "ก็ได้ หยิบแผนที่มา เราจะออกเดินทางตอนรุ่งเช้า",
               "อยู่ใกล้ๆ ไว้ ถนนเส้นนี้มืดเร็ว"],
        "vi": ["Cậu đã ở đâu vậy? Tớ đợi cả đêm.",
               "Cây cầu bị đóng nên tớ phải đi đường vòng.",
               "Được rồi. Cầm bản đồ đi, bình minh ta xuất phát.",
               "Đi sát vào. Con đường này tối rất nhanh."],
        "nl": ["Waar was je? Ik heb de hele nacht gewacht.",
               "De brug was dicht, dus ik nam de lange weg.",
               "Goed. Pak de kaart, we vertrekken bij zonsopgang.",
               "Blijf dichtbij. Op deze weg wordt het snel donker."],
        "uk": ["Де ти був? Я чекав цілу ніч.",
               "Міст був закритий, тож я їхав в об'їзд.",
               "Гаразд. Бери мапу, вирушаємо на світанку.",
               "Тримайся поруч. На цій дорозі швидко темніє."],
        "el": ["Πού ήσουν; Περίμενα όλη νύχτα.",
               "Η γέφυρα ήταν κλειστή, πήρα τον μακρύ δρόμο.",
               "Εντάξει. Πάρε τον χάρτη, φεύγουμε με το χάραμα.",
               "Μείνε κοντά. Αυτός ο δρόμος σκοτεινιάζει γρήγορα."],
        "cs": ["Kde jsi byl? Čekal jsem celou noc.",
               "Most byl zavřený, tak jsem jel oklikou.",
               "Dobře. Vezmi mapu, vyrážíme za svítání.",
               "Drž se blízko. Na téhle cestě se rychle stmívá."],
        "hu": ["Hol voltál? Egész éjjel vártam.",
               "A híd le volt zárva, ezért kerülővel jöttem.",
               "Rendben. Fogd a térképet, napkeltekor indulunk.",
               "Maradj a közelemben. Ezen az úton gyorsan sötétedik."],
        "sv": ["Var har du varit? Jag väntade hela natten.",
               "Bron var stängd, så jag tog den långa vägen.",
               "Okej. Ta kartan, vi ger oss av i gryningen.",
               "Håll dig nära. Den här vägen blir snabbt mörk."],
    ]

    /// Konsolsuz örnek kipinde gerçek çeviri hattına verilen İngilizce replikler (oyunun kaynak dili).
    static let ornekIngilizce = [
        "Mara: Where have you been? I waited all night.",
        "Theo: The bridge was closed, so I took the long way.",
        "Mara: Fine. Grab the map, we leave at sunrise.",
        "Theo: You almost gave me a heart attack back there.",
        "Mara: Stay close. This road gets dark fast.",
        "Theo: If they find us, we run. No arguments.",
        "Mara: Get to cover! They're coming from the north.",
        "Theo: I'll get out of your hair once we reach the city.",
    ]

    /// Kutu ayarı ekranındaki örnek altyazı (oyunun kaynak dili İngilizce olduğu için hep İngilizce).
    static let kutuAltyazisi = "Stay close. This road gets dark fast."

    /// Kutu ayarı ekranı için çizilmiş örnek sahne (16:9). Gerçek oyun karesi değil.
    @MainActor static func sahne() -> UIImage? {
        let r = ImageRenderer(content: OrnekSahne().frame(width: 1280, height: 720))
        r.scale = 1
        return r.uiImage
    }
}

private struct OrnekSahne: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                LinearGradient(colors: [Color(red: 0.10, green: 0.12, blue: 0.30), Color(red: 0.55, green: 0.30, blue: 0.40), Color(red: 0.98, green: 0.62, blue: 0.35)],
                               startPoint: .top, endPoint: .bottom)
                Circle().fill(Color(red: 1, green: 0.85, blue: 0.55)).frame(width: h * 0.22).position(x: w * 0.68, y: h * 0.52)
                // Uzak ve yakın tepeler
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.62))
                    p.addCurve(to: CGPoint(x: w, y: h * 0.58), control1: CGPoint(x: w * 0.3, y: h * 0.40), control2: CGPoint(x: w * 0.65, y: h * 0.75))
                    p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: 0, y: h)); p.closeSubpath()
                }.fill(Color(red: 0.25, green: 0.16, blue: 0.30))
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.78))
                    p.addCurve(to: CGPoint(x: w, y: h * 0.72), control1: CGPoint(x: w * 0.35, y: h * 0.66), control2: CGPoint(x: w * 0.7, y: h * 0.86))
                    p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: 0, y: h)); p.closeSubpath()
                }.fill(Color(red: 0.08, green: 0.07, blue: 0.14))
                // Köşede oyun göstergesi: kutunun dışında kalması gereken türden
                HStack(spacing: 10) {
                    Circle().stroke(Color.white.opacity(0.8), lineWidth: 5).frame(width: 46, height: 46)
                    RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.8)).frame(width: 160, height: 12)
                }.position(x: w * 0.14, y: h * 0.09)
                Text(Onizleme.kutuAltyazisi)
                    .font(.system(size: 40, weight: .semibold)).foregroundColor(.white)
                    .shadow(color: .black.opacity(0.9), radius: 3, x: 0, y: 2)
                    .position(x: w / 2, y: h * 0.86)
            }
        }
    }
}
