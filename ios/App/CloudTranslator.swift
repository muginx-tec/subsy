import Foundation

/// Kaliteli çeviri: repliği önceki replikleriyle birlikte kendi sunucumuza yollar, sunucu bir dil modeline
/// çevirtir. Telefonun hazır çevirisi cümleyi tek başına çevirdiği için özneyi ve deyimi bozuyor
/// ("And she believed you?" → "Ve sana inandın mı?"); bağlamı gören model bunu düzeltiyor.
///
/// API anahtarı burada YOK ve olmayacak: uygulamadan çıkarılabilir. Anahtar yalnız sunucuda durur
/// (sunucu/sunucu.py). Sunucu yapay zekâ çevirisini yalnız Pro (RevenueCat) ya da deneme süresindeki
/// kullanıcıya verir.
enum CloudTranslator {
    private static let d = UserDefaults.standard

    static var enabled: Bool {
        get { d.bool(forKey: "cloudOn") }
        set { d.set(newValue, forKey: "cloudOn") }
    }
    /// Çeviri sunucusu (Hetzner, Caddy arkasında HTTPS).
    static let server = "https://subsy-api.muginx.com"
    /// Sunucunun uygulamayı tanıdığı ortak sır. Kaynak koda yazılmaz: `ios/Config/Gizli.xcconfig` (git'e girmez)
    /// derlemede Info.plist'e koyar. Asıl koruma bu değil, sunucunun RevenueCat'ten yaptığı Pro denetimi.
    static let secret = (Bundle.main.object(forInfoDictionaryKey: "SubsySunucuSirri") as? String) ?? ""
    /// Oyuna özel sözlüğün adı: "genel", "tlou2", "gta5".
    static var game: String {
        get { d.string(forKey: "cloudGame") ?? "genel" }
        set { d.set(newValue, forKey: "cloudGame") }
    }
    static var configured: Bool { !server.isEmpty && !secret.isEmpty }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 3.0   // altyazı ekranda 2-4 saniye kalır; geç gelen çeviri işe yaramaz
        c.timeoutIntervalForResource = 3.5
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    struct Failure: Error { let message: String }

    /// Çeviriyi ve sunucunun bildirdiği model süresini (ms) döndürür.
    /// Sunucu en son ne zaman "Pro gerekli" (402) dedi. Bir dakika içinde yeniden sorulmaz; her replikte
    /// boşuna ağ beklemesi olmasın. Satın alma ya da deneme olunca sıfırlanır.
    nonisolated(unsafe) static var proGerekliZamani: Date?
    static var proBekleniyor: Bool { (proGerekliZamani.map { Date().timeIntervalSince($0) < 60 }) ?? false }

    static func translate(_ line: String, previous: [String]) async throws -> (String, Int) {
        if proBekleniyor { throw Failure(message: "Pro gerekli") }
        guard let url = URL(string: server + "/cevir") else { throw Failure(message: "sunucu adresi bozuk") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(secret, forHTTPHeaderField: "X-Uygulama-Anahtari")
        request.setValue(Kullanici.kimlik, forHTTPHeaderField: "X-Kullanici")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["replik": line, "onceki": previous, "oyun": game, "dil": Diller.secili.kod])
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if code == 402 {
            // Pro değil (ya da deneme bitti): bir dakika buluta gitmeden telefonun çevirisi kullanılır.
            proGerekliZamani = Date()
            throw Failure(message: "Pro gerekli")
        }
        guard code == 200, let text = json?["ceviri"] as? String, !text.isEmpty else {
            throw Failure(message: "sunucu \(code): \(json?["hata"] as? String ?? "cevap okunamadı")")
        }
        return (text, json?["ms"] as? Int ?? 0)
    }

    struct ProDurumu { let kilit: Bool; let denemeBitis: Date?; let denemeKullanildi: Bool }

    private static func durumOku(_ json: [String: Any]?) -> ProDurumu? {
        guard let json else { return nil }
        let bitis = (json["deneme_bitis"] as? Double).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
        return ProDurumu(kilit: json["kilit"] as? Bool ?? false, denemeBitis: bitis,
                         denemeKullanildi: json["deneme_kullanildi"] as? Bool ?? false)
    }

    private static func istek(_ yol: String, _ yontem: String) -> URLRequest? {
        guard configured, let url = URL(string: server + yol) else { return nil }
        var r = URLRequest(url: url)
        r.httpMethod = yontem
        r.setValue(secret, forHTTPHeaderField: "X-Uygulama-Anahtari")
        r.setValue(Kullanici.kimlik, forHTTPHeaderField: "X-Kullanici")
        return r
    }

    /// Sunucudaki Pro ve deneme durumu (GET /pro).
    static func proDurumu() async -> ProDurumu? {
        guard let r = istek("/pro", "GET"), let (data, resp) = try? await session.data(for: r),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return durumOku((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
    }

    /// Paylaşana 1 saatlik deneme ister (POST /deneme). Sunucu kişi başı bir kez verir.
    static func denemeIste() async -> ProDurumu? {
        guard let r = istek("/deneme", "POST"), let (data, resp) = try? await session.data(for: r),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        proGerekliZamani = nil
        return durumOku((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
    }

    static func ping() async -> Bool {
        guard configured, let url = URL(string: server + "/saglik") else { return false }
        return ((try? await session.data(from: url))?.1 as? HTTPURLResponse)?.statusCode == 200
    }
}
