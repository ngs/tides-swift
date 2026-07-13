# AGENTS.md - AI開発支援ガイド

> **注意**: このファイル (`AGENTS.md`) が原本です。`CLAUDE.md` は `AGENTS.md` へのシンボリックリンクです。編集は必ず `AGENTS.md` に対して行ってください。

## プロジェクト概要

**Tides** - 潮汐予測アプリ(iPhone / iPad / Apple Watch / Vision Pro / macOS)

マップから地点を選び、tides-api(https://api.tides.ngs.io/)から調和定数パラメータを一度ダウンロードすれば、以後はオフラインでローカル計算により潮位を予測できる。

### 技術スタック
- **言語**: Swift 6.0(StrictConcurrency 有効)
- **フレームワーク**: SwiftUI, MapKit, Swift Charts, SwiftData
- **最小OS**: iOS 18.0 / macOS 15.0 / watchOS 11.0 / visionOS 2.0
- **アーキテクチャ**: MVVM + ローカル SPM パッケージ分割
- **プロジェクト管理**: Tuist(`Project.swift`)+ Swift Package Manager(`Package.swift`)
- **コード品質**: SwiftLint / Periphery / RuboCop(Fastfile 用)
- **CI/CD**: GitHub Actions + Fastlane
- **ローカライズ**: String Catalog(en 開発言語、ja)

### モジュール構成

ロジックはローカル SPM パッケージ(`Package.swift`)の3ライブラリに分割され、
Tuist(`Project.swift`)のアプリターゲットがそれらに依存する。

| モジュール | パス | 内容 |
|---|---|---|
| `TidesCore` | `Sources/Core/` | 調和計算エンジン(HarmonicParameters / NodalCorrection / TidePredictor)+ 月相計算(MoonPhase)+ パラメータAPIクライアント。**Foundation のみに依存(UIフレームワーク禁止)** |
| `TidesPlatform` | `Sources/Platform/` | SwiftData 永続化(SavedLocation)、逆ジオコーディング |
| `TidesUI` | `Sources/UI/` | SwiftUI Views / ViewModels |

| ターゲット(Tuist) | 種別 | ソース | プラットフォーム |
|---|---|---|---|
| `Tides` | app | `Sources/App/` | iPhone / iPad / macOS / Vision Pro |
| `TidesWatch` | app | `Sources/Watch/` | watchOS(iOSビルドに埋め込み) |
| `TidesWidget` | appExtension | `Sources/Widget/` | iOS / macOS(WidgetKit、各アプリビルドに埋め込み) |
| `TidesTests` | unitTests | `Tests/TidesUITests/` | iOS / macOS / visionOS |

アプリとウィジェットは App Group の SwiftData ストアを共有する(`TidesModelContainer`)。
- **App Group ID はプラットフォームで異なる**: iOS / visionOS / watchOS は `group.io.ngs.Tides`、macOS は Team ID プレフィックス必須で `3Y8APYUG2G.group.io.ngs.Tides`(`$(TeamIdentifierPrefix)group.io.ngs.Tides`)。ポータル上は同一グループ。
- entitlements: macOS = `Resources/Tides.entitlements`(sandbox + team-prefixed group)/ iOS・visionOS = `Resources/Tides-iOS.entitlements`(`CODE_SIGN_ENTITLEMENTS[sdk=iphone*|xr*]` で切替)。ウィジェットは `TidesWidget-macOS.entitlements`(base)と `TidesWidget.entitlements`(iOS)。
- App Group が使えない環境ではローカルストアへ自動フォールバックする(アプリは動くがウィジェットにデータが見えない)。

保存地点(`SavedLocation`)は CloudKit プライベート DB(`iCloud.io.ngs.Tides` / `TidesCloudKit.containerIdentifier`)経由で全プラットフォームに同期される。
- **CloudKit ミラーリングの制約**: 永続プロパティは全て optional かデフォルト値必須、`@Attribute(.unique)` / リレーションシップ不可。`Tests/TidesUITests/CloudKitSyncTests.swift` がスキーマを検証する。
- フォールバック階段(`TidesModelContainer.configurations(cloudKit:)`): CloudKit+App Group → CloudKit のみ(watch)→ App Group のみ → ローカル → インメモリ。entitlement 無し / iCloud 未サインイン / プレビュー / テストでは自動的に CloudKit 無しの構成になる(`TidesCloudKit.isAvailable`)。
- watch アプリは App Group を持たず、CloudKit 同期された SwiftData ストアから地点を読む(`@Query`)。地点が複数あればリストで選択できる。
- entitlements: 各ターゲットに `com.apple.developer.icloud-container-identifiers` / `icloud-services`(CloudKit)、アプリと watch には push 用の `aps-environment`(macOS は `com.apple.developer.aps-environment`)。watch は `Resources/TidesWatch.entitlements`。アプリの Info.plist には `UIBackgroundModes: [remote-notification]`。
- `TidesPlatform` の MapKit 依存(`PlaceSearchService` / `ReverseGeocoder`)は watchOS で `#if !os(watchOS)` により除外される。

SPM テストターゲット: `Tests/TidesCoreTests/`(ゴールデンフィクスチャ)、`Tests/TidesUITests/`(ViewModel テスト)。`swift test` で実行できる。

### TidesCore(潮汐計算エンジン)の要点
- tides-api の Go 実装(`internal/domain/tide.go`, `nodal.go`)の移植。
- 予測式: `h(t) = msl + Σ f_k(t)·A_k·cos(ω_k·Δt + V_k + u_k(t) − φ_k)`
  - Δt: `referenceTime`(FES: 2012-01-01 UTC)からの経過時間[時]
  - V_k: サーバが `equilibrium_argument_deg` として配信(基準エポック評価値、静的)
  - f/u(nodal補正): クライアントで絶対時刻の天文引数(Schureman)から計算
- **ゴールデンフィクスチャ**: `Tests/TidesCoreTests/Fixtures/*.json` は Go 実装から生成した正解値。Swift 移植はこれと一致しなければならない(許容誤差はフィクスチャ側に記載)。Go 側の計算式を変えた場合はフィクスチャ再生成が必要(tides-api リポジトリの `tmp/fixturegen` 参照)。

### MoonPhase(月相)
- Meeus『Astronomical Algorithms』(ch.25 / 47)の主要項による月-太陽の離角から、月齢・輝面比・8相(SF Symbols の `moonphase.*`)を算出。Foundation のみ。
- テストは実測の新月・満月・上下弦の時刻(USNO/IMCCE)と照合(`Tests/TidesCoreTests/MoonPhaseTests.swift`)。
- 月齢の日次増加は 0.85〜1.15日/日で変動する(軌道離心率による正しい挙動)。

### API
- `GET /v1/tides/parameters?lat=&lon=` … 調和定数パラメータ(このアプリの主要API)
- `GET /v1/tides/predictions` … サーバ計算の潮位(検証用)
- パラメータは `HarmonicParameters` (Codable) にそのままデコードできる。
- API ホストは Info.plist の `API_HOST` キー(既定 `api.tides.ngs.io`)。

## 開発コマンド

```bash
tuist generate --no-open   # Xcodeプロジェクト/ワークスペース生成
swift test                 # SPMテスト(エンジンのフィクスチャテスト含む)
xcodebuild test -workspace Tides.xcworkspace -scheme Tides \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'   # Xcodeテスト
Scripts/lint.sh strict     # SwiftLint(CIは --strict)
periphery scan --strict    # 未使用コード検出
bundle exec rubocop        # Fastfile等のRubyコード
```

## 規約
- コミットメッセージは英語・命令形。PRタイトルにAIツール名を入れない。
- コメント・ドキュメントは英語で書く。
- ユーザー向け文字列は必ず String Catalog(`Resources/Localizable.xcstrings`、watch は `WatchResources/Localizable.xcstrings`)経由。ハードコード禁止。
- TidesCore は UI フレームワークに依存しない(Foundation のみ)。
- SwiftLint / Periphery / RuboCop がすべて 0 violations であること(CI で強制)。
