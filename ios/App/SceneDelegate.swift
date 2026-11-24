import UIKit

/// Pencere baştan sahne üzerinden kurulur (Düğünlük'ten ders: Xcode 27 ile derlenen uygulama
/// UIScene yaşam döngüsünü benimsemezse iOS 27'de açılışta çöküyor).
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = KokViewController()
        window.makeKeyAndVisible()
        self.window = window
    }

    /// Her öne gelişte zorunlu güncelleme kontrolü (Guncelleme.swift).
    func sceneDidBecomeActive(_ scene: UIScene) {
        guard let windowScene = scene as? UIWindowScene else { return }
        Guncelleme.kontrol(windowScene)
    }
}
