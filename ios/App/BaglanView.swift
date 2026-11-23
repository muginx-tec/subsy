import SwiftUI
import Network

/// Konsola bağlanma ekranı: konsolu bul, bir kez eşleştir, bağlan, altyazıyı aç.
/// Oyun görüntüsü burada gösterilmez; oyun TV'de, telefon altyazı ekranı.
struct BaglanView: View {
    /// Alt sekme çubuğunun içindeyken L("Kapat") düğmesi gösterilmez.
    var gomulu = false
    @ObservedObject private var konsol = Konsol.shared
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @State private var showAltyazi = ProcessInfo.processInfo.arguments.contains("-altyaziOnizleme")
    @State private var showKutu = false
    @State private var showAyrinti = false
    @State private var showGiris = false
    /// Konsol 15 saniyede bulunamadı: bekleme yerine yapılacakları göster (2026-11-22: aramaya başlayan 343 kişiden 93'ü bulamadı).
    @State private var bulunamadi = false
    /// Telefon Wi-Fi'da (ya da kabloda) değil: konsol hiç bulunamaz (2026-11-23: bulamayanların %26'sı mobil verideydi).
    @State private var wifiYok = false
    @State private var agIzleyici: NWPathMonitor?
    @State private var aramaTuru = 0
    /// PSN girişi bitince yapılacak iş (ör. bağlanma). Giriş ayrı bir adım değil, bağlanmanın parçası (Selim).
    @State private var giristenSonra: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(L("Konsola bağlan")).font(.system(size: 28, weight: .bold)).foregroundColor(.white)
                    Spacer()
                    if !gomulu { Button(L("Kapat")) { dismiss() }.font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.accent) }
                }

                if konsol.gosterilemez {
                    kart(vurgulu: true) {
                        Label(L("Konsolda açık olan içerik Uzaktan Oynama'da gösterilemiyor. Bir oyun aç, altyazı kendiliğinden gelir."), systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 15, weight: .semibold)).foregroundColor(.white).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if bagli {
                    bagliKart
                } else if konsol.hosts.isEmpty {
                    if wifiYok { wifiKarti } else if bulunamadi { bulunamadiKarti } else { araniyor }
                } else {
                    ForEach(konsol.hosts, id: \.self) { host in konsolKarti(host) }
                }
                if !bagli {
                    // Konsolu yanında olmayan (App Store incelemecisi dahil) çeviriyi örnek repliklerle görsün.
                    ikincilDugme(L("Konsolsuz örnekle dene"), simge: "play.rectangle") {
                        konsol.ornegiHazirla(); showAltyazi = true
                    }
                }

                DisclosureGroup(isExpanded: $showAyrinti) {
                    #if DEBUG
                    // Geliştirici kaydı yalnız deneme derlemesinde (Apple 2.1: yayında geliştirici ekranı olmasın).
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(konsol.gunluk.suffix(8).enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(size: 12, design: .monospaced)).foregroundColor(Color.white.opacity(0.7))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, 8)
                    #endif
                    if !konsol.hesapNo.isEmpty {
                        Button(L("PSN hesabını değiştir") + (UserDefaults.standard.string(forKey: "psnAd").map { " (\($0))" } ?? "")) { showGiris = true }
                            .font(.system(size: 13)).foregroundColor(Theme.dim).padding(.top, 8)
                    }
                } label: {
                    Text(L("Ayrıntı")).font(.system(size: 13)).foregroundColor(Theme.dim)
                }
                .tint(Theme.dim)
            }
            .padding(20)
        }
        .background(gomulu ? AnyView(Color.clear) : AnyView(Backdrop()))
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showAltyazi) { KonsolAltyaziView() }
        .fullScreenCover(isPresented: $showKutu) { KonsolKutuView().environment(\.layoutDirection, ArayuzDili.sagdanSola ? .rightToLeft : .leftToRight) }
        .sheet(isPresented: $showGiris) { PsnGirisView { giristenSonra?(); giristenSonra = nil } }
        .onAppear {
            konsol.aramayiBaslat()
            let m = NWPathMonitor()
            m.pathUpdateHandler = { yol in
                let yok = !(yol.usesInterfaceType(.wifi) || yol.usesInterfaceType(.wiredEthernet))
                DispatchQueue.main.async { if wifiYok != yok { wifiYok = yok; if yok { Analiz.olay("wifi_yok") } } }
            }
            m.start(queue: .global(qos: .utility)); agIzleyici = m
        }
        .onDisappear { agIzleyici?.cancel(); agIzleyici = nil }
        .task(id: aramaTuru) {
            bulunamadi = false
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, konsol.hosts.isEmpty, !bagli else { return }
            withAnimation { bulunamadi = true }
            Analiz.olay("konsol_bulunamadi", ["tur": aramaTuru])
        }
        .onDisappear { konsol.aramayiDurdur() }
        // Bağlanınca altyazı kendiliğinden açılmaz (Selim, 2026-11-16); kullanıcı L("Altyazıyı aç")a basar.
    }

    private var bagli: Bool { konsol.durum == .bagli }

    // MARK: Parçalar

    private var hesapYok: some View {
        kart(vurgulu: true) {
            Label(L("PSN hesabı gerekli"), systemImage: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 17, weight: .bold)).foregroundColor(.white)
            Text(L("Konsol, bağlanan cihazın hangi PSN hesabına ait olduğunu bilmek ister. Giriş Sony'nin kendi sayfasında yapılır; parolan bu uygulamaya gelmez."))
                .font(.system(size: 14)).foregroundColor(Color.white.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
            buyukDugme(L("PSN ile giriş yap"), simge: "person.crop.circle") { showGiris = true }
        }
    }

    /// Telefon Wi-Fi'da değil: aramayı beklemeden söyle.
    private var wifiKarti: some View {
        kart(vurgulu: true) {
            Label(L("Telefon Wi-Fi'a bağlı değil"), systemImage: "wifi.slash")
                .font(.system(size: 17, weight: .bold)).foregroundColor(.white)
            Text(L("Konsol yalnız aynı Wi-Fi ağından bulunur. Telefonu konsolun bağlı olduğu Wi-Fi ağına bağla; mobil veriyle olmaz."))
                .font(.system(size: 14)).foregroundColor(Color.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 15 saniyede konsol çıkmadı: en sık dört neden ve iki düğme (izin ayarı, yeniden ara).
    private var bulunamadiKarti: some View {
        kart(vurgulu: true) {
            Label(L("Telefon ve konsol aynı Wi-Fi'da mı?"), systemImage: "wifi.exclamationmark")
                .font(.system(size: 17, weight: .bold)).foregroundColor(.white)
            VStack(alignment: .leading, spacing: 10) {
                madde("wifi", L("Telefon ve konsol aynı Wi-Fi ağında olmalı (misafir ağı ya da mobil veri olmaz)."))
                madde("power", L("PS5 açık olmalı. Dinlenme modundaysa: Ayarlar > Sistem > Güç Tasarrufu > Dinlenme Modunda Kullanılabilen Özellikler > İnternete Bağlı Kal."))
                madde("antenna.radiowaves.left.and.right", L("Telefonun Ayarlar'ında Subsy için \"Yerel Ağ\" izni açık olmalı."))
                madde("gamecontroller", L("Şimdilik yalnız PS5 ve PS4 destekleniyor; Xbox desteklenmiyor."))
            }
            HStack(spacing: 10) {
                buyukDugme(L("İzni aç"), simge: "gearshape") {
                    Analiz.olay("konsol_bulunamadi_ayarlar")
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                buyukDugme(L("Yeniden ara"), simge: "arrow.clockwise") {
                    konsol.aramayiDurdur(); konsol.aramayiBaslat(); aramaTuru += 1
                }
            }
        }
    }

    private func madde(_ simge: String, _ yazi: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: simge).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.accent).frame(width: 22)
            Text(yazi).font(.system(size: 14)).foregroundColor(Color.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var araniyor: some View {
        kart {
            HStack(spacing: 12) {
                ProgressView().tint(Theme.accent)
                Text(L("Konsol aranıyor...")).font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
            }
            Text(L("Konsol açık olmalı ve telefonla aynı Wi-Fi ağında bulunmalı. İlk açılışta çıkan “yerel ağdaki cihazları bul” iznine izin ver."))
                .font(.system(size: 14)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var bagliKart: some View {
        VStack(alignment: .leading, spacing: 12) {
            kart {
                Label(L("Konsol bağlı"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 19, weight: .bold)).foregroundColor(Theme.good)
                Text(L("Oyununu TV'den, kendi kumandanla oyna. Telefonu yanına koy; altyazı çıktıkça çevirisi ekrana gelir."))
                    .font(.system(size: 14)).foregroundColor(Color.white.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
            }
            buyukDugme(L("Altyazıyı aç"), simge: "captions.bubble.fill") { showAltyazi = true }
            ikincilDugme(L("Altyazının yeri"), simge: "rectangle.dashed") { showKutu = true }
            ikincilDugme(L("Bağlantıyı kes"), simge: "xmark.circle") { konsol.kop() }
        }
    }

    private func konsolKarti(_ host: PyluxDiscoveredHost) -> some View {
        kart {
            HStack(spacing: 12) {
                Image(systemName: "gamecontroller.fill").font(.system(size: 22)).foregroundColor(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(host.hostName ?? L("Konsol")).font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                    Text(host.state == .ready ? L("Açık, hazır") : L("Uykuda")).font(.system(size: 13)).foregroundColor(Theme.dim)
                }
                Spacer(minLength: 0)
            }
            if konsol.kayitli {
                buyukDugme(konsol.uyandiriliyor ? L("Konsol uyandırılıyor...") : (konsol.durum == .baglaniyor ? L("Bağlanıyor...") : L("Bağlan")), simge: "dot.radiowaves.left.and.right") {
                    if konsol.hesapNo.isEmpty {
                        giristenSonra = { konsol.baglan(host: host) }
                        showGiris = true
                    } else {
                        konsol.baglan(host: host)
                    }
                }
                .disabled(konsol.durum == .baglaniyor || konsol.uyandiriliyor)
                if konsol.uyandiriliyor {
                    Text(L("Uyanmazsa kumandadaki PS tuşuyla aç; açılınca kendiliğinden bağlanır."))
                        .font(.system(size: 13)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
                }
                if !konsol.baglantiHatasi.isEmpty {
                    Label(konsol.baglantiHatasi, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 14)).foregroundColor(.white.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
                } else if case .koptu = konsol.durum {
                    Text(L("Bağlantı kesildi")).font(.system(size: 13)).foregroundColor(Theme.dim)
                }
                Button(L("Eşleştirmeyi sil")) { konsol.kaydiSil() }.font(.system(size: 13)).foregroundColor(Theme.dim)
            } else if konsol.hesapNo.isEmpty {
                buyukDugme(L("Bağlan"), simge: "dot.radiowaves.left.and.right") { showGiris = true }
            } else {
                Text(L("Bir kez eşleştir")).font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                Text(host.isPS5
                     ? L("PS5'te Ayarlar > Sistem > Uzaktan Oynama > Cihaz Bağla ekranını aç. Çıkan 8 haneli kodu buraya yaz.")
                     : L("PS4'te Ayarlar > Uzaktan Oynama Bağlantı Ayarları > Cihaz Ekle ekranını aç. Çıkan 8 haneli kodu buraya yaz."))
                    .font(.system(size: 14)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    TextField(L("8 haneli kod"), text: $pin)
                        .keyboardType(.numberPad).font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.35)))
                        .foregroundColor(.white)
                    Button(konsol.durum == .kaydoluyor ? "..." : L("Eşleştir")) { konsol.kaydol(host: host, pin: pin) }
                        .font(.system(size: 17, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 18).padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent))
                        .disabled(konsol.durum == .kaydoluyor)
                }
                if konsol.eslesmeHatasi {
                    // Önceden eşleşme olmayınca kullanıcı hiçbir şey görmüyordu (3 günde 58 kişide 344 başarısız deneme).
                    Label(L("Eşleşme olmadı. Kodu ekranda göründüğü sürede gir. Konsolda kodu açan kullanıcı, burada giriş yaptığın PSN hesabıyla aynı olmalı."),
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 14)).foregroundColor(.white.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func kart<Content: View>(vurgulu: Bool = false, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(vurgulu ? Theme.accent.opacity(0.10) : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(vurgulu ? Theme.accent.opacity(0.55) : Theme.stroke))
    }

    private func buyukDugme(_ yazi: String, simge: String, _ eylem: @escaping () -> Void) -> some View {
        Button(action: eylem) {
            HStack(spacing: 10) {
                Image(systemName: simge).font(.system(size: 18, weight: .bold))
                Text(yazi).font(.system(size: 19, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.accent))
        }
        .buttonStyle(Basili())
    }

    private func ikincilDugme(_ yazi: String, simge: String, _ eylem: @escaping () -> Void) -> some View {
        Button(action: eylem) {
            HStack(spacing: 10) {
                Image(systemName: simge).font(.system(size: 16))
                Text(yazi).font(.system(size: 16, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.stroke))
        }
        .buttonStyle(Basili())
    }
}
