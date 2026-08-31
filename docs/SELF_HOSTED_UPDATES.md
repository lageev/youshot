# 自分发更新

YouShot 使用 Sparkle 2 检查、下载和安装自托管更新。更新包必须使用 EdDSA 签名；应用会在解压前验证签名。

## 一次性配置

1. 从 [Sparkle Releases](https://github.com/sparkle-project/Sparkle/releases) 下载官方发行包。
2. 已通过 `bin/generate_keys --account top.yayalu.youshot` 生成项目专用密钥。私钥保存在当前 macOS 用户的钥匙串中，请妥善备份。
3. 公钥已写入 Xcode 和命令行构建配置；也可通过 `YOUSHOT_UPDATE_PUBLIC_ED_KEY` 覆盖。
4. 确认 `YOUSHOT_UPDATE_FEED_URL` 指向实际公开的 HTTPS Appcast；默认值为 `https://youshot.yayalu.top/updates/appcast.xml`。

不要把私钥提交到仓库。丢失私钥后，已安装版本无法验证用新密钥签发的普通更新。

## Apple Developer ID 签名与公证

站外分发不能使用 `Apple Development` 证书。需要有效的 Apple Developer Program
会员，并在 Apple Developer 的 Certificates 页面创建 **Developer ID Application**
证书。下载 `.cer` 后双击安装，且钥匙串中必须同时存在对应私钥。

验证证书：

```bash
security find-identity -v -p codesigning
```

结果里应出现类似：

```text
Developer ID Application: Your Name (TEAMID)
```

然后为 `notarytool` 创建钥匙串凭据。`APPLE_ID` 是开发者账号邮箱，当前项目的
团队 ID 是 `C6H9D46LA6`。先在 Apple Account 网站生成 App 专用密码，再运行：

```bash
xcrun notarytool store-credentials focusmic-notary \
  --apple-id 'APPLE_ID' \
  --team-id C6H9D46LA6
```

命令会安全提示输入 App 专用密码，不要使用 Apple ID 登录密码，也不要把密码直接
写进命令、仓库或 CI 日志。这一步只需执行一次，凭据保存在本机钥匙串中。

## 构建发布包

FocusMic 实际使用的是共享仓库 `/Users/fring/hflcode/private-release-tools` 中的
发布脚本。YouShot 已准备好对应配置 `apps/youshot.env`，推荐直接复用这条流程：

```bash
cd /Users/fring/hflcode/private-release-tools
scripts/macos-sparkle-release.sh apps/youshot.env 1.0.0 1 --ship --notarize --overwrite
```

它会自动完成 Xcode archive/export、Developer ID 签名、公证、staple、Sparkle
签名、GitHub Release，以及把 appcast 同步到 YouShot landing 仓库。首次正式发版
前先确认两个仓库没有未提交改动；`--ship` 会提交、打 tag、推送并创建 GitHub
Release。只想先生成产物时，去掉 `--ship` 即可。

一次完成 Developer ID 签名、Apple 公证、staple 与 Sparkle 打包：

```bash
YOUSHOT_VERSION=1.0.1 \
YOUSHOT_BUILD_NUMBER=2 \
YOUSHOT_CODESIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
YOUSHOT_NOTARY_PROFILE=focusmic-notary \
./scripts/release.sh
```

发布脚本依次执行：

1. 使用 Hardened Runtime 与安全时间戳构建并签名 `YouShot.app`。
2. 用 `notarytool` 提交 Apple 公证并等待结果。
3. 把公证票据 staple 到应用，并用 Gatekeeper 再验证。
4. 生成 Sparkle EdDSA 签名 ZIP 和 `appcast.xml`。

未传 `YOUSHOT_CODESIGN_IDENTITY` 时，单独运行 `scripts/build.sh` 仍会使用 ad-hoc
签名，仅适合本地开发。`package_update.sh` 会拒绝打包未使用 Developer ID 签名、
或没有有效公证票据的应用，避免误发布。

也可以分步执行：

```bash
YOUSHOT_VERSION=1.0.1 \
YOUSHOT_BUILD_NUMBER=2 \
YOUSHOT_CODESIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
./scripts/build.sh

YOUSHOT_NOTARY_PROFILE=focusmic-notary ./scripts/notarize.sh
./scripts/package_update.sh
```

脚本默认使用 SwiftPM 下载的 Sparkle 工具和钥匙串账户 `top.yayalu.youshot`；只有工具在其他位置时才需传入 `SPARKLE_BIN_DIR`。

将 `dist/updates/` 中新生成的 ZIP 和 `appcast.xml` 上传到网站的 `/updates/` 目录。ZIP、Appcast 中的下载地址和发布说明必须通过 HTTPS 提供。

Sparkle 根据 `CFBundleVersion`（内部构建号）判断新旧版本，所以每次发布必须递增命令行构建的 `YOUSHOT_BUILD_NUMBER`，或 Xcode Target 的 `CURRENT_PROJECT_VERSION`。
