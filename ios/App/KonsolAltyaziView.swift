import SwiftUI

/// Tam ekran altyazı (kendi PS5 bağlantımızla). Oyun görüntüsü gösterilmez: oyun TV'de, telefon
/// yanda duran altyazı ekranı. En yeni replik altta, büyük ve beyaz; öncekiler üstünde soluk.
struct KonsolAltyaziView: View {
    @ObservedObject private var konsol = Konsol.shared
    @Environment(\.dismiss) private var dismiss

    private static let renkler: [Color] = [
        Color(red: 1.00, green: 0.33, blue: 0.29),   // kırmızı
        Color(red: 1.00, green: 0.60, blue: 0.20),   // turuncu
        Color(red: 1.00, green: 0.84, blue: 0.25),   // sarı
    ]

    /// Altyazı açılır açılmaz yataydır (Selim'in isteği). Uygulamanın geri kalanı dik kaldığı için
    /// ekranı döndürmek yerine içeriği 90 derece çeviriyoruz. Uzun basınca öbür yana döner.
    @AppStorage("altyaziTers") private var ters = false
    /// Yazı boyu çarpanı (0,6 - 2,4). Alttaki A− / A+ ile ayarlanır, hatırlanır. İki parmakla büyütme yok (Selim istemedi).
    @AppStorage("altyaziBoy") private var boy = 1.0

    private func boyAyarla(_ yeni: Double) { boy = min(max(yeni, 0.6), 2.4) }

    /// Tablette ekran büyük: yazı baştan daha büyük başlar (Selim: "tablette de çıkacağız").
    private var taban: CGFloat { UIDevice.current.userInterfaceIdiom == .pad ? 1.7 : 1.0 }

    var body: some View {
        GeometryReader { geo in
            icerik
                .frame(width: geo.size.height, height: geo.size.width)
                // Arapça gibi sağdan sola dillerde satır, çizgi ve ad sağa yaslanır.
                .environment(\.layoutDirection, Diller.secili.sagdanSola ? .rightToLeft : .leftToRight)
                .rotationEffect(.degrees(ters ? -90 : 90))
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .ignoresSafeArea()
        .background(Color(red: 10 / 255, green: 16 / 255, blue: 40 / 255).ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { dismiss() }
        .onLongPressGesture { ters.toggle() }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true   // ekran kararmasın
            konsol.altyaziyiBaslat()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            konsol.altyaziyiDurdur()
        }
    }

    private var icerik: some View {
        ZStack(alignment: .bottom) {
            Color(red: 10 / 255, green: 16 / 255, blue: 40 / 255).ignoresSafeArea()

            if konsol.satirlar.isEmpty {
                Text(konsol.durum == .bagli ? L("Altyazı bekleniyor...") : L("PS5 bağlı değil"))
                    .font(.system(size: 22, weight: .medium)).foregroundColor(Color.white.opacity(0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Konuşma kaydırılabilir: yukarı kaydırınca eski replikler okunur; yeni replik gelince en alta döner.
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(konsol.satirlar.enumerated()), id: \.element.id) { index, satir in
                            satirView(satir, enYeni: index == konsol.satirlar.count - 1).id(satir.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 64).padding(.top, 20).padding(.bottom, 8)
                }
                .defaultScrollAnchor(.bottom)
                .padding(.bottom, 56)
                .onChange(of: konsol.satirlar) { _, yeni in
                    guard let son = yeni.last else { return }
                    withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(son.id, anchor: .bottom) }
                }
            }

            HStack {
                if konsol.proNotu {
                    // Kilit açıkken Pro olmayan kullanıcı yapay zekâyı seçtiyse sessiz kalma: nedenini söyle.
                    Label(L("Yapay zekâ çevirisi Pro'da · şimdilik telefonla çevriliyor"), systemImage: "sparkles")
                        .font(.system(size: 12 * taban, weight: .semibold)).foregroundColor(Theme.pro)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                } else {
                    Text(konsol.sonSure).font(.system(size: 11, design: .monospaced)).foregroundColor(Color.white.opacity(0.28))
                }
                Spacer()
                Text(L("iki kez dokun: kapat · uzun bas: çevir")).font(.system(size: 11)).foregroundColor(Color.white.opacity(0.28))
                boyDugmesi("A−", 15) { boyAyarla(boy - 0.1) }
                boyDugmesi("A+", 19) { boyAyarla(boy + 0.1) }
            }
            .padding(.horizontal, 64).padding(.bottom, 8)
        }
    }

    private func boyDugmesi(_ yazi: String, _ punto: CGFloat, _ eylem: @escaping () -> Void) -> some View {
        Button(action: eylem) {
            Text(yazi).font(.system(size: punto, weight: .bold)).foregroundColor(Color.white.opacity(0.75))
                .frame(width: 48, height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.10)))
        }
        .buttonStyle(Basili())
    }

    private func satirView(_ satir: Konsol.Satir, enYeni: Bool) -> some View {
        let renk = Self.renkler[satir.renk % Self.renkler.count]
        return HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(renk.opacity(enYeni ? 1 : 0.5)).frame(width: 4 * taban)
            VStack(alignment: .leading, spacing: 3) {
                if let ad = satir.konusan {
                    Text(ad.uppercased(with: Locale(identifier: Diller.secili.kod)))
                        .font(.system(size: (enYeni ? 17 : 14) * max(0.8, boy * 0.85) * taban, weight: .heavy)).kerning(0.8)
                        .foregroundColor(renk.opacity(enYeni ? 1 : 0.6))
                }
                Text(satir.metin)
                    .font(.system(size: (enYeni ? 46 : 28) * boy * taban, weight: enYeni ? .semibold : .regular))
                    .foregroundColor(Color.white.opacity(enYeni ? 1 : 0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
