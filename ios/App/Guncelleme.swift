import SwiftUI
import UIKit

/// Zorunlu güncelleme (Selim, 2026-11-24: "girdiğinde eskiyse güncelleme alsın"). Uygulama her öne geldiğinde sunucuya
/// (GET /pro) en düşük sürümü sorar; kendi sürümü daha eskiyse her şeyin üstünde tam ekran "Güncelle" penceresi açılır
/// ve kapatılamaz. Sunucu cevap vermezse ya da alan boşsa hiçbir şey olmaz (internetsiz kullanıcı kilitlenmesin).
/// Neden: telefon çevirisi tamamen telefonda; eski sürümdeki kullanıcıyı (ör. ücretsiz süre sınırı olmayan 1.0.5)
/// sunucudan durdurmanın yolu yoktu.
@MainActor
enum Guncelleme {
    static let magaza = URL(string: "itms-apps://apps.apple.com/app/id6835622677")!
    private static var pencere: UIWindow?

    static var mevcut: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    /// "1.0.10" > "1.0.9" gibi sayısal karşılaştırma.
    static func eski(_ surum: String, enDusuk: String) -> Bool {
        !enDusuk.isEmpty && surum.compare(enDusuk, options: .numeric) == .orderedAscending
    }

    static func kontrol(_ sahne: UIWindowScene) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-guncellemeOnizleme") { goster(sahne); return }
        #endif
        Task { @MainActor in
            guard let d = await CloudTranslator.proDurumu() else { return }
            if eski(mevcut, enDusuk: d.enDusukSurum) {
                if pencere == nil { Analiz.olay("guncelleme_zorunlu", ["en_dusuk": d.enDusukSurum]) }
                goster(sahne)
            } else {
                pencere?.isHidden = true; pencere = nil
            }
        }
    }

    private static func goster(_ sahne: UIWindowScene) {
        guard pencere == nil else { return }
        let w = UIWindow(windowScene: sahne)
        w.windowLevel = .alert + 1   // tam ekran altyazı ve satış ekranı dahil her şeyin üstünde
        let ekran = GuncellemeView().environment(\.layoutDirection, ArayuzDili.sagdanSola ? .rightToLeft : .leftToRight)
        w.rootViewController = UIHostingController(rootView: ekran)
        w.makeKeyAndVisible()
        pencere = w
    }
}

struct GuncellemeView: View {
    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 18) {
                Image(uiImage: UIImage(named: "logo.png") ?? UIImage()).resizable().scaledToFit().frame(width: 96, height: 96)
                Text(L("Yeni sürüm hazır"))
                    .font(.system(size: 26, weight: .bold)).foregroundColor(.white).multilineTextAlignment(.center)
                Text(L("Bu sürüm artık desteklenmiyor. Devam etmek için Subsy'yi App Store'dan güncelle."))
                    .font(.system(size: 16)).foregroundColor(.white.opacity(0.8)).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Analiz.olay("guncelleme_basildi")
                    UIApplication.shared.open(Guncelleme.magaza)
                } label: {
                    Text(L("Güncelle")).font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                        .frame(maxWidth: 320).padding(.vertical, 14)
                        .background(Capsule().fill(Theme.accent))
                }
                .padding(.top, 8)
            }
            .padding(32)
            .frame(maxWidth: 480)
        }
    }
}
