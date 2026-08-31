import Combine
import Foundation
import Sparkle

/// 封装 Sparkle，集中管理自分发更新配置和设置页状态。
@MainActor
final class UpdateController: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var automaticallyDownloadsUpdates = false
    @Published private(set) var configurationIssue: String?

    private var updaterController: SPUStandardUpdaterController?

    init(bundle: Bundle = .main) {
        guard let issue = Self.configurationIssue(in: bundle) else {
            let controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            updaterController = controller

            controller.updater.publisher(for: \.canCheckForUpdates)
                .receive(on: RunLoop.main)
                .assign(to: &$canCheckForUpdates)
            controller.updater.publisher(for: \.automaticallyChecksForUpdates)
                .receive(on: RunLoop.main)
                .assign(to: &$automaticallyChecksForUpdates)
            controller.updater.publisher(for: \.automaticallyDownloadsUpdates)
                .receive(on: RunLoop.main)
                .assign(to: &$automaticallyDownloadsUpdates)
            return
        }

        configurationIssue = issue
    }

    func checkForUpdates() {
        updaterController?.updater.checkForUpdates()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        updaterController?.updater.automaticallyChecksForUpdates = enabled
        automaticallyChecksForUpdates = enabled
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        updaterController?.updater.automaticallyDownloadsUpdates = enabled
        automaticallyDownloadsUpdates = enabled
    }

    private static func configurationIssue(in bundle: Bundle) -> String? {
        guard let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let feedURL = URL(string: feed),
              feedURL.scheme?.lowercased() == "https",
              feedURL.host != nil,
              !feed.contains("REPLACE_WITH") else {
            return "尚未配置有效的 HTTPS Appcast 地址（SUFeedURL）。"
        }

        guard let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              !publicKey.contains("REPLACE_WITH"),
              let keyData = Data(base64Encoded: publicKey),
              keyData.count == 32 else {
            return "尚未配置 Sparkle EdDSA 公钥（SUPublicEDKey）。"
        }

        return nil
    }
}
