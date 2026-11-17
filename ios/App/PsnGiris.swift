import SwiftUI
import WebKit

/// PSN girişi: konsol, bağlanan cihazın hangi PSN hesabına ait olduğunu bilmek ister (8 baytlık hesap numarası).
/// Giriş **Sony'nin kendi sayfasında** yapılır; parola bu uygulamaya gelmez, görülmez, saklanmaz.
/// Uygulama yalnız girişin sonunda dönen tek kullanımlık kodu Sony'ye geri yollar ve hesap numarasını alır.
/// Geçici erişim anahtarı saklanmaz. Başka hiçbir sunucuya (bizimki dahil) bir şey gitmez.
/// `deneme/hesap_no.py` betiğinin telefondaki karşılığı; o betik 2026-11-16'da çalıştı.
enum PsnGiris {
    // Sony'nin Windows Remote Play uygulamasının kimliği: açık kaynak istemcilerin (Chiaki, Pylux)
    // kullandığı, herkese açık değerler. Kullanıcıya özel bir sır değildir.
    static let clientId = "ba495a24-818c-472b-b12d-ff231c1b5745"
    static let clientSecret = "mvaiZkRsAsI1IBkY"
    static let redirect = "https://remoteplay.dl.playstation.net/remoteplay/redirect"
    static let tokenURL = "https://auth.api.sonyentertainmentnetwork.com/2.0/oauth/token"

    static var loginURL: URL {
        var c = URLComponents(string: "https://auth.api.sonyentertainmentnetwork.com/2.0/oauth/authorize")!
        c.queryItems = [
            .init(name: "service_entity", value: "urn:service-entity:psn"), .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: clientId), .init(name: "redirect_uri", value: redirect),
            .init(name: "scope", value: "psn:clientapp"), .init(name: "request_locale", value: "en_US"),
            .init(name: "ui", value: "pr"), .init(name: "service_logo", value: "ps"),
            .init(name: "layout_type", value: "popup"), .init(name: "smcid", value: "remoteplay"),
            .init(name: "prompt", value: "always"), .init(name: "PlatformPrivacyWs1", value: "minimal"),
        ]
        return c.url!
    }

    struct Hata: Error { let mesaj: String }

    /// Tek kullanımlık kodu hesap numarasına çevirir. (hesap numarası base64, PSN adı)
    static func hesap(kod: String) async throws -> (String, String) {
        let basic = "Basic " + Data("\(clientId):\(clientSecret)".utf8).base64EncodedString()
        func cagir(_ url: URL, govde: String?) async throws -> [String: Any] {
            var r = URLRequest(url: url)
            r.timeoutInterval = 20
            r.setValue(basic, forHTTPHeaderField: "Authorization")
            if let govde {
                r.httpMethod = "POST"
                r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                r.httpBody = Data(govde.utf8)
            }
            let (data, yanit) = try await URLSession(configuration: .ephemeral).data(for: r)
            guard (yanit as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw Hata(mesaj: L("Sony'den cevap alınamadı"))
            }
            return json
        }
        let izinli = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let k = kod.addingPercentEncoding(withAllowedCharacters: izinli) ?? kod
        let y = redirect.addingPercentEncoding(withAllowedCharacters: izinli) ?? redirect
        let token = try await cagir(URL(string: tokenURL)!, govde: "grant_type=authorization_code&code=\(k)&redirect_uri=\(y)&")
        guard let anahtar = token["access_token"] as? String,
              let bilgiURL = URL(string: tokenURL + "/" + (anahtar.addingPercentEncoding(withAllowedCharacters: izinli) ?? anahtar)) else {
            throw Hata(mesaj: L("Sony erişim anahtarı vermedi"))
        }
        let bilgi = try await cagir(bilgiURL, govde: nil)
        // user_id metin olarak gelir; 8 bayt, küçük uçtan (little endian), base64.
        guard let idMetni = bilgi["user_id"] as? String ?? (bilgi["user_id"] as? NSNumber)?.stringValue,
              let id = UInt64(idMetni) else { throw Hata(mesaj: L("hesap numarası okunamadı")) }
        var le = id.littleEndian
        let hesap = Data(bytes: &le, count: 8).base64EncodedString()
        return (hesap, bilgi["online_id"] as? String ?? "")
    }
}

/// Sony'nin giriş sayfası. Kalıcı çerez ve veri tutulmaz: her açılışta temiz başlar.
struct PsnGirisSayfasi: UIViewRepresentable {
    @Binding var adres: String
    let kodGeldi: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(adres: $adres, kodGeldi: kodGeldi) }

    func makeUIView(context: Context) -> WKWebView {
        let ayar = WKWebViewConfiguration()
        ayar.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: ayar)
        web.navigationDelegate = context.coordinator
        // Sayfa yukarı aşağı esnemesin ve kenarından beyaz görünmesin (Selim): esneme kapalı, sayfanın
        // arkası ve taşma rengi uygulamanın koyu laciverti.
        let koyu = UIColor(red: 0.03, green: 0.06, blue: 0.13, alpha: 1)
        web.scrollView.bounces = false
        web.scrollView.alwaysBounceVertical = false
        web.scrollView.alwaysBounceHorizontal = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.backgroundColor = koyu
        web.isOpaque = false
        web.backgroundColor = koyu
        web.underPageBackgroundColor = koyu
        web.load(URLRequest(url: PsnGiris.loginURL))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let kodGeldi: (String) -> Void
        private var adres: Binding<String>
        private var bitti = false
        init(adres: Binding<String>, kodGeldi: @escaping (String) -> Void) { self.adres = adres; self.kodGeldi = kodGeldi }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            adres.wrappedValue = webView.url?.host ?? ""
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Giriş bitince Sony tarayıcıyı bu adrese yollar; adresteki "code" tek kullanımlıktır.
            if let url = action.request.url, url.absoluteString.hasPrefix(PsnGiris.redirect), !bitti,
               let kod = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value {
                bitti = true
                decisionHandler(.cancel)
                kodGeldi(kod)
                return
            }
            decisionHandler(.allow)
        }
    }
}

/// Giriş ekranı bir tarayıcı gibi görünür: üstte kilit ve o an açık olan sitenin adresi, altında sayfa.
/// Uyarı yazısı yok (Selim: korkutmaya gerek yok); güveni adres çubuğu verir.
/// Gerçek Safari kullanılamıyor: giriş bitince Sony tarayıcıyı kendi adresine yolluyor, o adresteki
/// kodu yalnız uygulamanın içindeki sayfa yakalayabiliyor.
struct PsnGirisView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var durum = ""
    @State private var calisiyor = false
    @State private var adres = ""
    let tamam: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill").font(.system(size: 12)).foregroundColor(Color.white.opacity(0.6))
                    Text(adres.isEmpty ? L("yükleniyor...") : adres)
                        .font(.system(size: 15, weight: .medium)).foregroundColor(.white).lineLimit(1)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(Color.white.opacity(0.10)))
                HStack {
                    Button(L("Vazgeç")) { dismiss() }.font(.system(size: 16)).foregroundColor(Theme.accent)
                    Spacer()
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            if !durum.isEmpty {
                Text(durum).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 10)
            }
            if calisiyor {
                Spacer(); ProgressView().tint(Theme.accent); Spacer()
            } else {
                PsnGirisSayfasi(adres: $adres) { kod in
                    calisiyor = true
                    durum = L("Bağlanıyor...")
                    Task { @MainActor in
                        do {
                            let (hesap, ad) = try await PsnGiris.hesap(kod: kod)
                            Konsol.shared.hesapNo = hesap
                            UserDefaults.standard.set(ad, forKey: "psnAd")
                            Konsol.shared.objectWillChange.send()
                            tamam()
                            dismiss()
                        } catch {
                            calisiyor = false
                            durum = "Olmadı: \((error as? PsnGiris.Hata)?.mesaj ?? error.localizedDescription). Yeniden dene."
                        }
                    }
                }
            }
        }
        .background(Theme.night.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
