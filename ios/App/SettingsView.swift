import SwiftUI

/// Ayarlar. Asıl seçim çevirinin nasıl yapılacağı: telefonla (bedava taban) ya da yapay zekâyla
/// (bağlamı gören, daha doğru çeviri; ileride ücretli özellik olacak, şimdilik deneme).
struct SettingsView: View {
    @ObservedObject var model: HomeModel
    /// Alt sekme çubuğunun içindeyken L("Bitti") düğmesi gösterilmez.
    var gomulu = false
    @Environment(\.dismiss) private var dismiss
    @State private var showHakkinda = ProcessInfo.processInfo.arguments.contains("-hakkinda")
    @State private var showPro = false
    @ObservedObject private var magaza = ProMagaza.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text(L("Ayarlar")).font(.system(size: 30, weight: .bold)).foregroundColor(.white)
                    Spacer()
                    if !gomulu { Button(L("Bitti")) { dismiss() }.font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.accent) }
                }

                section(L("Altyazı dili")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(L("Oyun bu dile çevrilir")).font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                            Spacer()
                            Picker(L("Altyazı dili"), selection: $model.hedefDil) {
                                ForEach(Diller.hepsi) { d in Text(d.ad).tag(d.kod) }
                            }
                            .pickerStyle(.menu).tint(Theme.accent)
                        }
                        Text(dilDurumu).font(.system(size: 13)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
                        if model.language == "indirilmeli" {
                            Button(L("Dil paketini indir")) { dismiss(); model.onDownloadLanguage() }
                                .font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.accent)
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
                }

                section(L("Çeviri")) {
                    choice(selected: !model.cloud, icon: "iphone", title: L("Telefonla çevir"), badge: L("Ücretsiz"),
                           lines: [L("İnternet gerekmez, telefonun içinde çalışır."),
                                   L("Çok hızlı: yaklaşık 0,3 saniye."),
                                   L("Her cümleyi tek başına çevirir; deyimlerde ve kimin kime konuştuğunda yanılabilir.")]) {
                        model.cloud = false
                    }
                    choice(selected: model.cloud, icon: "sparkles", title: L("Yapay zekâ ile çevir"), badge: "Pro",
                           lines: [L("Önceki replikleri de görerek çevirir: özne, deyim ve argo yerine oturur."),
                                   L("İnternet ister, yaklaşık 1 saniye sürer."),
                                   L("Bağlantı olmazsa kendiliğinden telefonun çevirisine döner.")]) {
                        // Sunucuda Pro kilidi açıkken Pro (ya da 1 saatlik deneme) yoksa önce Pro ekranı açılır.
                        // İzin penceresi yok (Selim, 2026-11-17): giden şey oyunun altyazısı, kişisel veri değil.
                        if magaza.kilit && !magaza.aktif { showPro = true } else { model.cloud = true }
                    }
                    if model.cloud {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L("Oyun sözlüğü")).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                            Picker(L("Oyun sözlüğü"), selection: $model.cloudGame) {
                                Text(L("Genel")).tag("genel")
                                Text("The Last of Us 2").tag("tlou2")
                                Text("GTA V").tag("gta5")
                            }
                            .pickerStyle(.segmented)
                            Text(L("Oyuna özel adlar ve terimler hep aynı çevrilir."))
                                .font(.system(size: 13)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
                            // Bağlantı durumu ayrı ve belirgin: Selim ilk denemede bu yazıyı görememişti.
                            HStack(spacing: 8) {
                                Circle().fill(model.cloudStatus == "Sunucuya bağlı" ? Theme.good : Color.red.opacity(0.85)).frame(width: 10, height: 10)
                                Text(model.cloudStatus.isEmpty ? L("Sunucu denetleniyor...") : L(model.cloudStatus))
                                    .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                            }
                            .padding(.top, 4)
                        }
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
                    }
                }

                Button { showHakkinda = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle").font(.system(size: 18)).foregroundColor(Theme.accent)
                        Text(L("Hakkında")).font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.forward").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.dim)
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
                }
                .buttonStyle(Basili())
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 30)
        }
        .background(gomulu ? AnyView(Color.clear) : AnyView(Backdrop()))
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPro, onDismiss: { if magaza.aktif { model.cloud = true } }) {
            ProView().environment(\.layoutDirection, ArayuzDili.sagdanSola ? .rightToLeft : .leftToRight)
        }
        .sheet(isPresented: $showHakkinda) {
            HakkindaView().environment(\.layoutDirection, ArayuzDili.sagdanSola ? .rightToLeft : .leftToRight)
        }
    }

    private var dilDurumu: String {
        switch model.language {
        case "kurulu": return L("Telefonla çeviri bu dilde hazır.")
        case "indirilmeli": return L("Telefonla çeviri için dil paketi bir kez indirilmeli (ücretsiz).")
        case "desteklenmiyor": return L("Telefonun hazır çevirisi bu dili desteklemiyor. Bu dilde yalnız \"Yapay zekâ ile çevir\" çalışır.")
        default: return L("Denetleniyor...")
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased(with: ArayuzDili.yerel)).font(.system(size: 13, weight: .bold)).kerning(1.1).foregroundColor(Theme.dim)
            content()
        }
    }

    private func choice(selected: Bool, icon: String, title: String, badge: String, lines: [String], action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon).font(.system(size: 22, weight: .semibold))
                    .foregroundColor(selected ? Theme.accent : Theme.dim).frame(width: 30)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(title).font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                        Text(badge).font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill((selected ? Theme.accent : Color.white).opacity(0.16)))
                            .foregroundColor(selected ? Theme.accent : Theme.dim)
                    }
                    ForEach(lines, id: \.self) { line in
                        Text(line).font(.system(size: 14)).foregroundColor(Color.white.opacity(0.72))
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24)).foregroundColor(selected ? Theme.accent : Color.white.opacity(0.25))
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(selected ? Theme.accent.opacity(0.10) : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(selected ? Theme.accent.opacity(0.7) : Theme.stroke, lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(Basili())
    }
}
