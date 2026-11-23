import SwiftUI

/// Apple'ın telefondaki çevirisi seçili dili hiç desteklemiyorsa (ör. Macarca, Çekçe, Yunanca) ücretsiz yol yoktur.
/// Selim (2026-11-22): "Apple bunu desteklemiyor diyelim, çeviri istiyorsa Pro almalı". Deneme kullanılmadıysa önce
/// 45 dakikalık deneme önerilir (denemeyi sonuna kadar kullananların üçte ikisi satın aldı). Pro ya da deneme açıkken görünmez.
struct DilDestekKarti: View {
    @ObservedObject private var magaza = ProMagaza.shared
    /// Yazı ölçeği (altyazı ekranında tablette büyür).
    var olcek: CGFloat = 1
    /// Nerede gösterildi: "ana" ya da "altyazi" (PostHog için).
    let yer: String
    let proAc: () -> Void

    static func gorunur(dilDesteklenmiyor: Bool) -> Bool {
        dilDesteklenmiyor && !ProMagaza.shared.aktif
    }

    private var denemeVar: Bool {
        ProMagaza.ucretsizDeneme && magaza.kilit && !magaza.denemeKullanildi && !magaza.aktif
    }

    @ViewBuilder private var dugmeler: some View {
                if denemeVar {
                    Button {
                        Analiz.olay("dil_destek_deneme", ["yer": yer, "dil": Diller.secili.kod])
                        Task { await magaza.denemeAl() }
                    } label: {
                        HStack(spacing: 6) {
                            if magaza.islenen == "deneme" { ProgressView().tint(Theme.proKoyu1) }
                            Text(L("45 dakika ücretsiz dene")).lineLimit(1).fixedSize()
                        }
                        .font(.system(size: 14 * olcek, weight: .bold)).foregroundColor(Theme.proKoyu1)
                        .padding(.horizontal, 14).padding(.vertical, 9).background(Capsule().fill(Theme.pro))
                    }
                    .buttonStyle(Basili()).disabled(magaza.calisiyor)
                }
                Button {
                    Analiz.olay("dil_destek_pro", ["yer": yer, "dil": Diller.secili.kod])
                    proAc()
                } label: {
                    Text(L("Subsy Pro'ya bak")).lineLimit(1).fixedSize()
                        .font(.system(size: 14 * olcek, weight: denemeVar ? .semibold : .bold))
                        .foregroundColor(denemeVar ? Theme.pro : Theme.proKoyu1)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Capsule().fill(denemeVar ? Color.white.opacity(0.08) : Theme.pro))
                        .overlay(Capsule().stroke(Theme.pro.opacity(denemeVar ? 0.5 : 0), lineWidth: 1))
                }
                .buttonStyle(Basili())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10 * olcek) {
            Label(Diller.secili.ad + " · " + L("Apple desteklemiyor"), systemImage: "exclamationmark.bubble.fill")
                .font(.system(size: 15 * olcek, weight: .bold)).foregroundColor(Theme.pro)
            Text(L("Apple'ın telefon çevirisi senin dilini desteklemiyor. Bu dilde altyazı için Subsy Pro gerekir."))
                .font(.system(size: 13.5 * olcek)).foregroundColor(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            // Uzun dillerde (ör. Slovakça) iki düğme yan yana sığmayınca alt alta dizilir, yazı kesilmez.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { dugmeler }
                VStack(alignment: .leading, spacing: 8) { dugmeler }
            }
            if !magaza.mesaj.isEmpty, magaza.denemeKullanildi {
                Text(magaza.mesaj).font(.system(size: 12.5 * olcek)).foregroundColor(Theme.dim)
            }
        }
        .padding(16 * olcek)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(LinearGradient(colors: [Theme.proKoyu1, Theme.proKoyu2], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 1))
        .onAppear { Analiz.olay("dil_destek_karti", ["yer": yer, "dil": Diller.secili.kod, "deneme_var": denemeVar]) }
    }
}
