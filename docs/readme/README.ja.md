<h3 align="left">
  <a href="../../README.md">English</a> · <a href="../../README.zh-CN.md">简体中文</a> · <a href="README.es.md">Español</a> · <a href="README.pt-BR.md">Português (Brasil)</a><br>
  <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <strong>日本語</strong> · <a href="README.ko.md">한국어</a> · <a href="README.ms.md">Bahasa Melayu</a>
</h3>

<p align="left">
  <img src="../../images/technology-badges.svg" alt="オンデバイス処理 · ネイティブ SDK · 5 プラットフォーム" width="349" height="20">
</p>

<br>

<div align="center">
  <p>
    <a href="https://www.helloface.dev/"><img src="../../images/hello-face-icon.webp" alt="" width="51" height="51" align="bottom"><img src="../../images/helloface-wordmark.svg" alt="HelloFace" width="170" height="40" align="bottom"></a>
    &nbsp; <strong>0.8.9 Beta</strong>
  </p>
  <p><strong>オフラインでの顔検出・取得・ライブネス検出・1:1 照合・1:N/M:N 検索。</strong></p>
  <p>🌍 <strong>公式サイト</strong> · <a href="https://www.helloface.dev">helloface.dev ↗</a> &nbsp; | &nbsp; <img src="../../images/github-mark.svg" alt="" width="16" height="16" align="bottom"> <strong>GitHub 連携サンプルコード</strong> · <a href="https://github.com/FaceSDKPro/HelloFace">FaceSDKPro/HelloFace</a></p>
</div>

<br>

<table>
  <tr>
    <th align="left" nowrap>機能</th>
    <th align="left">説明</th>
  </tr>
  <tr>
    <td align="left" nowrap>🔒 <strong>オフラインとプライバシー</strong></td>
    <td align="left">顔データを端末内で処理し、画像や顔特徴量をクラウドにアップロードしません。 <a href="../privacy/DATA_PROCESSING_AND_PRIVACY.ja.md"><strong>詳細</strong></a></td>
  </tr>
  <tr>
    <td align="left" nowrap>🎯 <strong>顔処理ツールキット</strong></td>
    <td align="left">顔検出、特徴量抽出、ライブネス検出、1:1 照合、1:N/M:N 検索に対応しています。</td>
  </tr>
  <tr>
    <td align="left" nowrap>🌍 <strong>クロスプラットフォーム対応</strong></td>
    <td align="left">Android · iOS · HarmonyOS · Windows · Linux に対応しています。今後の対応プラットフォームにご期待ください。ご要望は <a href="https://github.com/FaceSDKPro/HelloFace/issues">Issue</a> からお知らせいただけます。</td>
  </tr>
  <tr>
    <td align="left" nowrap>🧩 <strong>簡単な組み込み</strong></td>
    <td align="left">SDK API、導入ガイド、カスタマイズ可能なデモを使って開発を始められます。</td>
  </tr>
  <tr>
    <td align="left" nowrap>⚡ <strong>リアルタイム処理</strong></td>
    <td align="left">ミリ秒単位でリアルタイムの顔検出・照合・検索を行います。</td>
  </tr>
</table>

<details>
  <summary><strong>製品概要と利用シーンを表示（英語）</strong></summary>
  <p align="center"><img src="../../images/AboutHelloFace-EN.png" alt="HelloFace の製品概要と利用シーン（英語）" width="100%"></p>
</details>

## 対応プラットフォーム

| プラットフォーム | 動作・開発環境 | 導入資料（英語） |
|---|---|---|
| Android | Android 6.0+ · ARM64/ARMv7 · JDK 11 | [Demo](../../platforms/Android/README.md) · [SDK](../../platforms/Android/docs/SDK.md) |
| iOS | iOS 15+ · Swift 6 · Xcode | [Demo](../../platforms/iOS/README.md) · [SDK](../../platforms/iOS/SDK/API.md) |
| Harmony | HarmonyOS API 20+ · ARM64 · DevEco Studio 26 | [Demo](../../platforms/Harmony/README.md) · [SDK](../../platforms/Harmony/SDK.md) |
| Linux | Ubuntu 22.04+ · x86_64/ARM64 · X11/XWayland | [Demo](../../platforms/Linux/README.md) · [SDK](../../platforms/Linux/runtimes/x86_64/sdk/README.md) |
| Windows | Windows 10/11 x64 · CPU | [Demo](../../platforms/Windows/README.md) · [SDK](../../platforms/Windows/sdk/README.md) |
| Web 顔登録 | ブラウザー | [オンラインで試す](https://hiface-mdp.pages.dev/face/) |

**今後対応予定のプラットフォーム:** WeChat ミニプログラム、ChromeOS、uni-app、Flutter プラグイン、React Native（RN）プラグインなど。

## コードの取得

このリポジトリでは、SDK バイナリなどの大容量ファイルを Git LFS で管理しています。デフォルトブランチの最新コミットのみが必要な場合は、履歴を取得しない浅いクローンを利用してください。

```bash
git clone --depth 1 --single-branch https://github.com/FaceSDKPro/HelloFace.git
```

## 導入前の確認事項

- 各プラットフォームのデモ UI は SDK の動作を示すためのものです。UI や操作方法は自由にカスタマイズできます。
- SDK は継続的に改善しているパブリックベータ版です。SDK を最新の状態に保ってください。
- 現在のモデルは 12 歳未満の子どもの顔認識に対応しておらず、金融関連の用途には使用できません。
- 顔検索には鮮明なカメラ画像が必要です。屋外で利用する場合は、ワイドダイナミックレンジが 100 dB を超えるカメラが必要です。
- Windows/Linux のデスクトップおよびカメラの処理フローは、実際のカメラによる検証待ちです。モバイルアプリの実行には、ご自身のアプリ署名設定が必要です。

## お問い合わせ

他のプラットフォームへの対応も進めています。問題が発生した場合は Issue を作成してください。

メール: [FaceAISDK.Service@gmail.com](mailto:FaceAISDK.Service@gmail.com)

<table>
  <tr>
    <th align="center">Android APK のダウンロード</th>
    <th align="center">WeChat でのお問い合わせ</th>
  </tr>
  <tr>
    <td align="center">
      <a href="https://www.pgyer.com/HelloFace"><img src="../../images/AndroidAPK.png" alt="Android APK ダウンロード用 QR コード" width="180"></a><br>
      <a href="https://www.pgyer.com/HelloFace">クリックまたはスキャンしてダウンロード</a>
    </td>
    <td align="center">
      <img src="../../images/WeChat.jpg" alt="WeChat の QR コード" width="180"><br>
      スキャンしてお問い合わせ
    </td>
  </tr>
</table>

<p align="center">
  <strong>Google Play でダウンロード</strong><br>
  <a href="https://play.google.com/store/apps/details?id=com.hiface.sdk.debug"><img src="../../images/GooglePlay.svg" alt="Google Play ダウンロード用 QR コード" width="180" height="180"></a><br>
  <a href="https://play.google.com/store/apps/details?id=com.hiface.sdk.debug">Android デモを Google Play でダウンロード</a>
</p>
