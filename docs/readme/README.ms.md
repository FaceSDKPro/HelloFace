<h3 align="left">
  <a href="../../README.md">English</a> · <a href="../../README.zh-CN.md">简体中文</a> · <a href="README.es.md">Español</a> · <a href="README.pt-BR.md">Português (Brasil)</a><br>
  <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <strong>Bahasa Melayu</strong>
</h3>

<p align="left">
  <img src="../../images/technology-badges.svg" alt="Pemprosesan pada peranti · SDK natif · 5 platform" width="349" height="20">
</p>

<br>

<div align="center">
  <p>
    <a href="https://www.helloface.dev/"><img src="../../images/hello-face-icon.webp" alt="" width="51" height="51" align="bottom"><img src="../../images/helloface-wordmark.svg" alt="HelloFace" width="170" height="40" align="bottom"></a>
    &nbsp; <strong>0.8.7 Beta</strong>
  </p>
  <p><strong>Pengesanan dan penangkapan wajah, pengesanan liveness, pengesahan 1:1 serta carian 1:N/M:N secara luar talian.</strong></p>
  <p>🌍 <strong>Laman web rasmi</strong> · <a href="https://www.helloface.dev">helloface.dev ↗</a> &nbsp; | &nbsp; <img src="../../images/github-mark.svg" alt="" width="16" height="16" align="bottom"> <strong>Kod integrasi GitHub</strong> · <a href="https://github.com/FaceSDKPro/HelloFace">FaceSDKPro/HelloFace</a></p>
</div>

<br>

<table>
  <tr>
    <th align="left" nowrap>Keupayaan</th>
    <th align="left">Penerangan</th>
  </tr>
  <tr>
    <td align="left" nowrap>🔒 <strong>Luar Talian &amp; Privasi</strong></td>
    <td align="left">Memproses data wajah secara setempat tanpa memuat naik imej atau ciri wajah ke awan. <a href="../privacy/DATA_PROCESSING_AND_PRIVACY.ms.md"><strong>Ketahui lanjut</strong></a></td>
  </tr>
  <tr>
    <td align="left" nowrap>🎯 <strong>Alat Wajah</strong></td>
    <td align="left">Pengesanan wajah, pengekstrakan ciri, pengesanan liveness, pengesahan 1:1 dan carian 1:N/M:N.</td>
  </tr>
  <tr>
    <td align="left" nowrap>🌍 <strong>Sokongan Pelbagai Platform</strong></td>
    <td align="left">Menyokong Android · iOS · HarmonyOS · Windows · Linux. Lebih banyak platform dirancang; anda juga boleh <a href="https://github.com/FaceSDKPro/HelloFace/issues">membuka isu</a> untuk menerangkan keperluan anda.</td>
  </tr>
  <tr>
    <td align="left" nowrap>🧩 <strong>Integrasi Mudah</strong></td>
    <td align="left">Mulakan dengan API SDK, panduan integrasi dan demo yang boleh disesuaikan.</td>
  </tr>
  <tr>
    <td align="left" nowrap>⚡ <strong>Pemprosesan Masa Nyata</strong></td>
    <td align="left">Pengesanan, pengesahan dan carian wajah dalam masa nyata pada skala milisaat.</td>
  </tr>
</table>

<details>
  <summary><strong>Lihat gambaran keseluruhan produk dan kegunaannya (dalam bahasa Inggeris)</strong></summary>
  <p align="center"><img src="../../images/AboutHelloFace-EN.png" alt="Gambaran keseluruhan produk HelloFace dan senario penggunaan, dalam bahasa Inggeris" width="100%"></p>
</details>

## Platform

| Platform | Keperluan | Integrasi (dalam bahasa Inggeris) |
|---|---|---|
| Android | Android 6.0+ · ARM64/ARMv7/X86 · JDK 11 | [Demo](../../platforms/Android/README.md) · [SDK](../../platforms/Android/docs/SDK.md) |
| iOS | iOS 15+ · Swift 6 · Xcode | [Demo](../../platforms/iOS/README.md) · [SDK](../../platforms/iOS/SDK/API.md) |
| Harmony | HarmonyOS API 20+ · ARM64 · DevEco Studio 26 | [Demo](../../platforms/Harmony/README.md) · [SDK](../../platforms/Harmony/SDK.md) |
| Linux | Ubuntu 22.04+ · x86_64/ARM64 · X11/XWayland | [Demo](../../platforms/Linux/README.md) · [SDK](../../platforms/Linux/runtimes/x86_64/sdk/README.md) |
| Windows | Windows 10/11 x64 · CPU | [Demo](../../platforms/Windows/README.md) · [SDK](../../platforms/Windows/sdk/README.md) |
| Pendaftaran wajah melalui web | Pelayar | [Cuba dalam talian](https://hiface-mdp.pages.dev/face/) |

**Lebih banyak platform (dirancang):** Program Mini WeChat, ChromeOS, uni-app, pemalam Flutter, pemalam React Native (RN) dan lain-lain.

## Dapatkan kod

Repositori ini menggunakan Git LFS untuk mengurus fail besar seperti binari SDK. Jika anda hanya memerlukan komit terkini daripada cabang lalai, gunakan pengklonan cetek untuk melangkau sejarah komit:

```bash
git clone --depth 1 --single-branch https://github.com/FaceSDKPro/HelloFace.git
```

## Sebelum digunakan dalam aplikasi anda

- Antara muka Demo bagi setiap platform hanya untuk menunjukkan SDK; anda bebas menyesuaikan antara muka dan interaksinya.
- SDK ini berada dalam ujian Beta awam yang sentiasa dikemas kini. Sila pastikan versi SDK anda terkini.
- Model semasa tidak menyokong pengecaman wajah bagi kanak-kanak di bawah umur 12 tahun dan tidak boleh digunakan dalam senario kewangan.
- Carian wajah memerlukan imej kamera yang jelas; penggunaan di luar bangunan memerlukan kamera dengan julat dinamik luas melebihi 100 dB.
- Aliran kerja desktop dan kamera Windows/Linux masih menunggu ujian dengan kamera sebenar; aplikasi mudah alih memerlukan tandatangan aplikasi anda sendiri.

## Hubungi kami

Sokongan untuk platform lain sedang dipertingkatkan. Jika anda menghadapi masalah, sila buka isu.

E-mel: [FaceAISDK.Service@gmail.com](mailto:FaceAISDK.Service@gmail.com)

<table>
  <tr>
    <th align="center">Muat turun APK Android</th>
    <th align="center">Hubungi melalui WeChat</th>
  </tr>
  <tr>
    <td align="center">
      <a href="https://www.pgyer.com/HelloFace"><img src="../../images/AndroidAPK.png" alt="Kod QR untuk memuat turun APK Android" width="180"></a><br>
      <a href="https://www.pgyer.com/HelloFace">Klik atau imbas untuk memuat turun</a>
    </td>
    <td align="center">
      <img src="../../images/WeChat.jpg" alt="Kod QR WeChat" width="180"><br>
      Imbas untuk menghubungi kami
    </td>
  </tr>
</table>
