<h3 align="left">
  <a href="../../README.md">English</a> · <a href="../../README.zh-CN.md">简体中文</a> · <a href="README.es.md">Español</a> · <a href="README.pt-BR.md">Português (Brasil)</a><br>
  <a href="README.fr.md">Français</a> · <strong>Deutsch</strong> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.ms.md">Bahasa Melayu</a>
</h3>

<p align="left">
  <img src="../../images/technology-badges.svg" alt="Verarbeitung auf dem Gerät · Native SDKs · 5 Plattformen" width="349" height="20">
</p>

<br>

<div align="center">
  <p>
    <a href="https://www.helloface.dev/"><img src="../../images/hello-face-icon.webp" alt="" width="51" height="51" align="bottom"><img src="../../images/helloface-wordmark.svg" alt="HelloFace" width="170" height="40" align="bottom"></a>
    &nbsp; <strong>0.8.8 Beta</strong>
  </p>
  <p><strong>Offline-Gesichtsdetektion und -erfassung, Lebenderkennung, 1:1-Verifizierung sowie 1:N-/M:N-Suche.</strong></p>
  <p>🌍 <strong>Offizielle Website</strong> · <a href="https://www.helloface.dev">helloface.dev ↗</a> &nbsp; | &nbsp; <img src="../../images/github-mark.svg" alt="" width="16" height="16" align="bottom"> <strong>Integrationscode auf GitHub</strong> · <a href="https://github.com/FaceSDKPro/HelloFace">FaceSDKPro/HelloFace</a></p>
</div>

<br>

<table>
  <tr>
    <th align="left" nowrap>Funktion</th>
    <th align="left">Beschreibung</th>
  </tr>
  <tr>
    <td align="left" nowrap>🔒 <strong>Offline und datenschutzfreundlich</strong></td>
    <td align="left">Verarbeiten Sie Gesichtsdaten lokal, ohne Bilder oder Gesichtsmerkmale in die Cloud hochzuladen. <a href="../privacy/DATA_PROCESSING_AND_PRIVACY.de.md"><strong>Mehr</strong></a></td>
  </tr>
  <tr>
    <td align="left" nowrap>🎯 <strong>Gesichtsfunktionen</strong></td>
    <td align="left">Gesichtsdetektion, Merkmalsextraktion, Lebenderkennung, 1:1-Verifizierung sowie 1:N-/M:N-Suche.</td>
  </tr>
  <tr>
    <td align="left" nowrap>🌍 <strong>Plattformübergreifende Unterstützung</strong></td>
    <td align="left">Android · iOS · HarmonyOS · Windows · Linux werden bereits unterstützt. Weitere Plattformen sind geplant; Sie können auch <a href="https://github.com/FaceSDKPro/HelloFace/issues">ein Issue erstellen</a>, um Ihre Anforderungen zu beschreiben.</td>
  </tr>
  <tr>
    <td align="left" nowrap>🧩 <strong>Einfache Integration</strong></td>
    <td align="left">Nutzen Sie die SDK-APIs, Integrationsanleitungen und anpassbaren Demos für den Einstieg.</td>
  </tr>
  <tr>
    <td align="left" nowrap>⚡ <strong>Echtzeitverarbeitung</strong></td>
    <td align="left">Gesichtsdetektion, Verifizierung und Suche in Echtzeit im Millisekundenbereich.</td>
  </tr>
</table>

<details>
  <summary><strong>Produktübersicht und Anwendungsszenarien anzeigen (auf Englisch)</strong></summary>
  <p align="center"><img src="../../images/AboutHelloFace-EN.png" alt="HelloFace-Produktübersicht und Anwendungsszenarien auf Englisch" width="100%"></p>
</details>

## Plattformen

| Plattform | Voraussetzungen | Integration (auf Englisch) |
|---|---|---|
| Android | Android 6.0+ · ARM64/ARMv7/X86 · JDK 11 | [Demo](../../platforms/Android/README.md) · [SDK](../../platforms/Android/docs/SDK.md) |
| iOS | iOS 15+ · Swift 6 · Xcode | [Demo](../../platforms/iOS/README.md) · [SDK](../../platforms/iOS/SDK/API.md) |
| Harmony | HarmonyOS API 20+ · ARM64 · DevEco Studio 26 | [Demo](../../platforms/Harmony/README.md) · [SDK](../../platforms/Harmony/SDK.md) |
| Linux | Ubuntu 22.04+ · x86_64/ARM64 · X11/XWayland | [Demo](../../platforms/Linux/README.md) · [SDK](../../platforms/Linux/runtimes/x86_64/sdk/README.md) |
| Windows | Windows 10/11 x64 · CPU | [Demo](../../platforms/Windows/README.md) · [SDK](../../platforms/Windows/sdk/README.md) |
| Gesichtsregistrierung im Web | Browser | [Online ausprobieren](https://hiface-mdp.pages.dev/face/) |

**Weitere Plattformen (geplant):** WeChat-Miniprogramme, ChromeOS, uni-app, Flutter-Plug-ins, React-Native-Plug-ins (RN) und mehr.

## Code beziehen

Dieses Repository verwendet Git LFS für große Dateien wie die SDK-Binärdateien. Wenn Sie nur den neuesten Commit des Standardbranches benötigen, können Sie mit einem flachen Klon den Download der Versionshistorie überspringen:

```bash
git clone --depth 1 --single-branch https://github.com/FaceSDKPro/HelloFace.git
```

## Vor der Bereitstellung

- Die Demo-Oberflächen der einzelnen Plattformen dienen der Veranschaulichung des SDK. Sie können die Oberfläche und Interaktionen frei anpassen.
- Das SDK befindet sich in einer öffentlichen Betaphase und wird fortlaufend weiterentwickelt. Halten Sie die SDK-Version aktuell.
- Das aktuelle Modell unterstützt keine Gesichtserkennung von Kindern unter 12 Jahren und darf nicht in Finanzanwendungen eingesetzt werden.
- Die Gesichtssuche erfordert klare Kamerabilder. Für den Außeneinsatz ist eine Kamera mit einem weiten Dynamikbereich von über 100 dB erforderlich.
- Die Desktop- und Kameraabläufe unter Windows/Linux müssen noch mit realen Kameras validiert werden. Mobile Apps erfordern Ihre eigene Konfiguration zur Anwendungssignierung.

## Kontakt

Die Unterstützung weiterer Plattformen wird ausgebaut. Erstellen Sie bei Problemen bitte ein Issue.

E-Mail: [FaceAISDK.Service@gmail.com](mailto:FaceAISDK.Service@gmail.com)

<table>
  <tr>
    <th align="center">Android-APK herunterladen</th>
    <th align="center">WeChat-Kontakt</th>
  </tr>
  <tr>
    <td align="center">
      <a href="https://www.pgyer.com/HelloFace"><img src="../../images/AndroidAPK.png" alt="QR-Code zum Download der Android-APK" width="180"></a><br>
      <a href="https://www.pgyer.com/HelloFace">Zum Herunterladen klicken oder scannen</a>
    </td>
    <td align="center">
      <img src="../../images/WeChat.jpg" alt="WeChat-QR-Code" width="180"><br>
      Für die Kontaktaufnahme scannen
    </td>
  </tr>
</table>
