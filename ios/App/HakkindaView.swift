import SwiftUI

/// Hakkında: uygulamanın kim olduğu, Sony ile bağlantısız olduğu, açık kaynak atıfları ve destek adresi.
/// Lisans gereği bu bilgiler uygulamanın içinde durmalı (AGPL: kaynak koda nasıl ulaşılacağı; gömülü
/// kütüphanelerin telif bildirimleri). Kütüphane adları ve lisansları `dis/Pylux` içindeki lisans
/// dosyalarından alındı (2026-11-16), hafızadan değil.
enum Hakkinda {
    /// Kaynak kodun herkese açık adresi. Depo henüz açılmadı; boşken ekran bunu açıkça söyler.
    /// Mağazaya gönderilmeden önce DOLDURULMALI: AGPL kaynak koda erişim yolunun gösterilmesini şart koşar.
    static let kaynakAdresi = "https://github.com/muginx-tec/subsy"
    static let destek = "support@muginx.com"
    /// Gizlilik metni (muginx.com/subsy/gizlilik/) ve Apple'ın standart kullanım koşulları (abonelik için, kural 3.1.2).
    static let gizlilikAdresi = URL(string: "https://muginx.com/subsy/gizlilik/")!
    static let kosullarAdresi = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// (ad, lisans). Lisans adları çevrilmez.
    static let kutuphaneler: [(String, String)] = [
        ("Chiaki · chiaki-ng · Pylux", "AGPL-3.0-only (OpenSSL istisnasıyla)"),
        ("Mbed TLS", "Apache-2.0"),
        ("curl", "curl License"),
        ("Opus", "BSD (Xiph.Org)"),
        ("miniupnpc", "BSD-3-Clause"),
        ("nanopb", "zlib"),
        ("Jerasure · GF-Complete", "BSD"),
        ("json-c", "MIT"),
        ("RevenueCat", "MIT"),
        ("Facebook SDK for iOS", "Meta Platform License"),
    ]

    static var surum: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return b.isEmpty ? v : "\(v) (\(b))"
    }
}

struct HakkindaView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var acikKaynak = false
    @State private var kutuphaneler = false
    @State private var yasal = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(L("Hakkında")).font(.system(size: 28, weight: .bold)).foregroundColor(.white)
                    Spacer()
                    Button(L("Kapat")) { dismiss() }.font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.accent)
                }

                kart {
                    HStack(spacing: 12) {
                        Image(uiImage: UIImage(named: "logo.png") ?? UIImage()).resizable().scaledToFit().frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Subsy").font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                            Text(Hakkinda.surum).font(.system(size: 13)).foregroundColor(Theme.dim)
                        }
                    }
                    Text(L("Subsy, senin dilinde olmayan konsol oyunlarının altyazısını telefonunda senin diline çevirir. Oyun TV'de kalır, kumanda elinde."))
                        .font(.system(size: 14)).foregroundColor(Color.white.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
                }

                acilir(L("Açık kaynak"), $acikKaynak) {
                    Text(L("Bu uygulamanın kaynak kodu AGPL-3.0 lisansıyla açıktır. Konsola bağlanan kısım Chiaki açık kaynak projesine ve onun devamı olan chiaki-ng ile Pylux'a dayanır."))
                        .font(.system(size: 14)).foregroundColor(Color.white.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
                    if let url = URL(string: Hakkinda.kaynakAdresi), !Hakkinda.kaynakAdresi.isEmpty {
                        Button { openURL(url) } label: {
                            Label(L("Kaynak kodu gör"), systemImage: "chevron.left.forwardslash.chevron.right")
                                .font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.accent)
                        }
                    } else {
                        Text(L("Kaynak kod bağlantısı uygulama yayımlanmadan önce buraya eklenecek."))
                            .font(.system(size: 13)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
                    }
                }

                acilir(L("Kullanılan açık kaynak kütüphaneler"), $kutuphaneler) {
                    ForEach(Hakkinda.kutuphaneler, id: \.0) { ad, lisans in
                        HStack(alignment: .firstTextBaseline) {
                            Text(ad).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                            Spacer(minLength: 12)
                            Text(lisans).font(.system(size: 12.5)).foregroundColor(Theme.dim).multilineTextAlignment(.trailing)
                        }
                    }
                }

                acilir(L("Yasal bilgi"), $yasal) {
                    Text(L("Subsy bağımsız bir uygulamadır. Sony Interactive Entertainment ile bağlantılı değildir; onun tarafından desteklenmez ya da onaylanmaz. PlayStation, PS5 ve PS4, Sony Interactive Entertainment Inc. şirketinin ticari markalarıdır."))
                        .font(.system(size: 14)).foregroundColor(Color.white.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
                }

                kart {
                    Text(L("Destek")).font(.system(size: 17, weight: .bold)).foregroundColor(.white)
                    Button { if let u = URL(string: "mailto:\(Hakkinda.destek)") { openURL(u) } } label: {
                        Label(Hakkinda.destek, systemImage: "envelope")
                            .font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.accent)
                    }
                    // Gizlilik ve koşullar her zaman görünür (Apple 5.1.1: gizlilik bağlantısı uygulamada kolay bulunmalı).
                    Button { openURL(Hakkinda.gizlilikAdresi) } label: {
                        Label(L("Gizlilik"), systemImage: "hand.raised")
                            .font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.accent)
                    }
                    Button { openURL(Hakkinda.kosullarAdresi) } label: {
                        Label(L("Kullanım Koşulları"), systemImage: "doc.text")
                            .font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.accent)
                    }
                }
            }
            .padding(20)
        }
        .background(Backdrop())
        .preferredColorScheme(.dark)
    }

    /// Başlığına dokununca açılıp kapanan kutu. Kapalıyken yalnız başlık ve ok görünür.
    private func acilir<Content: View>(_ baslik: String, _ acik: Binding<Bool>, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { acik.wrappedValue.toggle() }
            } label: {
                HStack {
                    Text(baslik).font(.system(size: 17, weight: .bold)).foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 12)
                    Image(systemName: "chevron.down").font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.dim)
                        .rotationEffect(.degrees(acik.wrappedValue ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if acik.wrappedValue { content() }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Glass(radius: 20))
    }

    private func kart<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Glass(radius: 20))
    }
}
