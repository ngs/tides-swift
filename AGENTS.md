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
| `TidesCore` | `Sources/Core/` | 調和計算エンジン(HarmonicParameters / NodalCorrection / TidePredictor)+ パラメータAPIクライアント。**Foundation のみに依存(UIフレームワーク禁止)** |
| `TidesPlatform` | `Sources/Platform/` | SwiftData 永続化(SavedLocation)、逆ジオコーディング |
| `TidesUI` | `Sources/UI/` | SwiftUI Views / ViewModels |

| ターゲット(Tuist) | 種別 | ソース | プラットフォーム |
|---|---|---|---|
| `Tides` | app | `Sources/App/` | iPhone / iPad / macOS / Vision Pro |
| `TidesWatch` | app | `Sources/Watch/` | watchOS(iOSビルドに埋め込み) |
| `TidesTests` | unitTests | `Tests/TidesUITests/` | iOS / macOS / visionOS |

SPM テストターゲット: `Tests/TidesCoreTests/`(ゴールデンフィクスチャ)、`Tests/TidesUITests/`(ViewModel テスト)。`swift test` で実行できる。

### TidesCore(潮汐計算エンジン)の要点
- tides-api の Go 実装(`internal/domain/tide.go`, `nodal.go`)の移植。
- 予測式: `h(t) = msl + Σ f_k(t)·A_k·cos(ω_k·Δt + V_k + u_k(t) − φ_k)`
  - Δt: `referenceTime`(FES: 2012-01-01 UTC)からの経過時間[時]
  - V_k: サーバが `equilibrium_argument_deg` として配信(基準エポック評価値、静的)
  - f/u(nodal補正): クライアントで絶対時刻の天文引数(Schureman)から計算
- **ゴールデンフィクスチャ**: `Tests/TidesCoreTests/Fixtures/*.json` は Go 実装から生成した正解値。Swift 移植はこれと一致しなければならない(許容誤差はフィクスチャ側に記載)。Go 側の計算式を変えた場合はフィクスチャ再生成が必要(tides-api リポジトリの `tmp/fixturegen` 参照)。

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
