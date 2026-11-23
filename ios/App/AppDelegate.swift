import UIKit
import FacebookCore

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        metaBaslat(application, launchOptions)
        Analiz.baslat()
        Task { await UcretsizSure.yukle() }
        return true
    }

    /// Meta (Facebook) SDK: yalnız reklam ölçümü için. Meta'ya "uygulama kuruldu / açıldı" olayı gider ki
    /// reklamlar indirene göre en iyileştirilebilsin. Reklam kimliği (IDFA) toplanmaz, izleme izni istenmez;
    /// ölçüm Apple'ın toplu sayım düzeniyle (SKAdNetwork) yapılır. Altyazı, replik ya da hesap bilgisi gitmez.
    /// İstemci anahtarı `Config/Gizli.xcconfig`'ten gelir; boşsa SDK hiç başlatılmaz.
    private func metaBaslat(_ application: UIApplication, _ launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        guard let anahtar = Bundle.main.object(forInfoDictionaryKey: "FacebookClientToken") as? String,
              !anahtar.isEmpty else { return }
        Settings.shared.isAdvertiserTrackingEnabled = false
        Settings.shared.isAdvertiserIDCollectionEnabled = false
        ApplicationDelegate.shared.application(application, didFinishLaunchingWithOptions: launchOptions)
        Self.metaAcik = true
    }
    /// Meta SDK başlatıldı mı (anahtar boşsa başlatılmaz).
    static var metaAcik = false

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}
