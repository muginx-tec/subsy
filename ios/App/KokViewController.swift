import SwiftUI
import UIKit

/// Uygulamanın kökü. Ana ekranı (SwiftUI) barındırır ve onun ihtiyaç duyduğu üç işi yapar: çeviri hattını
/// kurar, telefondaki dil paketinin durumuna bakar, çeviri sunucusuna ulaşılıp ulaşılmadığını denetler.
final class KokViewController: UIViewController {
    private let pipeline = Pipeline()
    private let home = HomeModel()
    private var downloadHost: UIViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        Konsol.shared.adoptLaunchArguments()
        Pipeline.main = pipeline          // Konsol okuduğu altyazıyı buraya verir

        home.onDownloadLanguage = { [weak self] in self?.downloadLanguage() }
        home.onLanguageChanged = { [weak self] in
            self?.pipeline.dilDegisti()
            self?.checkLanguage()
        }
        home.onCloudChanged = { [weak self] in self?.checkCloud() }

        let host = UIHostingController(rootView: HomeView(model: home))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        checkLanguage()
        checkCloud()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    /// Seçili dil için telefonun çevirisi hazır mı.
    private func checkLanguage() {
        Task { @MainActor in
            let state = await pipeline.translator.state()
            _ = await pipeline.translator.prepare()
            home.language = state.rawValue
        }
    }

    /// Yapay zekâ çevirisinin sunucusuna ulaşılıyor mu. Durum metni Türkçe kaynak yazıdır; gösterilirken çevrilir.
    private func checkCloud() {
        guard CloudTranslator.configured else { home.cloudStatus = "Sunucu ayarlı değil"; return }
        Task { @MainActor in
            let ok = await CloudTranslator.ping()
            home.cloudStatus = ok ? "Sunucuya bağlı" : "Sunucuya ulaşılamıyor; telefonun çevirisi kullanılır"
        }
    }

    /// Dil paketini indirtir: sistemin indirme penceresini yalnız görünür bir SwiftUI parçası açabiliyor.
    private func downloadLanguage() {
        downloadHost?.willMove(toParent: nil)
        downloadHost?.view.removeFromSuperview()
        downloadHost?.removeFromParent()
        let host = UIHostingController(rootView: LanguageDownloadView { [weak self] _ in
            DispatchQueue.main.async { self?.checkLanguage() }
        })
        host.view.backgroundColor = .clear
        host.view.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)
        downloadHost = host
    }
}
