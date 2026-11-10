<h3 align="left">
  <a href="../../README.md">English</a> · <a href="../../README.zh-CN.md">简体中文</a> · <a href="README.es.md">Español</a> · <a href="README.pt-BR.md">Português (Brasil)</a><br>
  <strong>Français</strong> · <a href="README.de.md">Deutsch</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.ms.md">Bahasa Melayu</a>
</h3>

<p align="left">
  <img src="../../images/technology-badges.svg" alt="Traitement sur l’appareil · SDK natifs · 5 plateformes" width="349" height="20">
</p>

<br>

<div align="center">
  <p>
    <a href="https://www.helloface.dev/"><img src="../../images/hello-face-icon.webp" alt="" width="51" height="51" align="bottom"><img src="../../images/helloface-wordmark.svg" alt="HelloFace" width="170" height="40" align="bottom"></a>
    &nbsp; <strong>0.8.11 Beta</strong>
  </p>
  <p><strong>Détection et capture de visages, détection du vivant, vérification 1:1 et recherche 1:N/M:N hors ligne.</strong></p>
  <p>🌍 <strong>Site officiel</strong> · <a href="https://www.helloface.dev">helloface.dev ↗</a> &nbsp; | &nbsp; <img src="../../images/github-mark.svg" alt="" width="16" height="16" align="bottom"> <strong>Code d’intégration sur GitHub</strong> · <a href="https://github.com/FaceSDKPro/HelloFace">FaceSDKPro/HelloFace</a></p>
</div>

<br>

<table>
  <tr>
    <th align="left" nowrap>Fonctionnalité</th>
    <th align="left">Description</th>
  </tr>
  <tr>
    <td align="left" nowrap>🔒 <strong>Hors ligne et confidentialité</strong></td>
    <td align="left">Traitez les données faciales localement, sans envoyer d’images ni de caractéristiques faciales dans le cloud. <a href="../privacy/DATA_PROCESSING_AND_PRIVACY.fr.md"><strong>En savoir plus</strong></a></td>
  </tr>
  <tr>
    <td align="left" nowrap>🎯 <strong>Outils de traitement facial</strong></td>
    <td align="left">Détection de visages, extraction de caractéristiques, détection du vivant, vérification 1:1 et recherche 1:N/M:N.</td>
  </tr>
  <tr>
    <td align="left" nowrap>🌍 <strong>Prise en charge multiplateforme</strong></td>
    <td align="left">Android · iOS · HarmonyOS · Windows · Linux sont déjà pris en charge. D’autres plateformes sont prévues ; vous pouvez aussi <a href="https://github.com/FaceSDKPro/HelloFace/issues">ouvrir une issue</a> pour décrire vos besoins.</td>
  </tr>
  <tr>
    <td align="left" nowrap>🧩 <strong>Intégration facile</strong></td>
    <td align="left">Démarrez avec les API du SDK, les guides d’intégration et les démos personnalisables.</td>
  </tr>
  <tr>
    <td align="left" nowrap>⚡ <strong>Traitement en temps réel</strong></td>
    <td align="left">Détection, vérification et recherche de visages en temps réel, à l’échelle de la milliseconde.</td>
  </tr>
</table>

<details>
  <summary><strong>Afficher la présentation du produit et ses applications (en anglais)</strong></summary>
  <p align="center"><img src="../../images/AboutHelloFace-EN.png" alt="Présentation de HelloFace et de ses applications, en anglais" width="100%"></p>
</details>

## Plateformes

| Plateforme | Prérequis | Intégration (en anglais) |
|---|---|---|
| Android | Android 6.0+ · ARM64/ARMv7 · JDK 11 | [Demo](../../platforms/Android/README.md) · [SDK](../../platforms/Android/docs/SDK.md) |
| iOS | iOS 15+ · Swift 6 · Xcode | [Demo](../../platforms/iOS/README.md) · [SDK](../../platforms/iOS/SDK/API.md) |
| Harmony | HarmonyOS API 20+ · ARM64 · DevEco Studio 26 | [Demo](../../platforms/Harmony/README.md) · [SDK](../../platforms/Harmony/SDK.md) |
| Linux | Ubuntu 22.04+ · x86_64/ARM64 · X11/XWayland | [Demo](../../platforms/Linux/README.md) · [SDK](../../platforms/Linux/runtimes/x86_64/sdk/README.md) |
| Windows | Windows 10/11 x64 · CPU | [Demo](../../platforms/Windows/README.md) · [SDK](../../platforms/Windows/sdk/README.md) |
| Enregistrement facial sur le Web | Navigateur | [Essayer en ligne](https://hiface-mdp.pages.dev/face/) |

**Autres plateformes (prévues):** Mini-programmes WeChat, ChromeOS, uni-app, extensions Flutter, extensions React Native (RN), etc.

## Obtenir le code

Ce dépôt utilise Git LFS pour gérer les fichiers volumineux, tels que les binaires du SDK. Si vous avez uniquement besoin du dernier commit de la branche par défaut, effectuez un clonage superficiel pour ne pas télécharger l’historique :

```bash
git clone --depth 1 --single-branch https://github.com/FaceSDKPro/HelloFace.git
```

## Avant le déploiement

- L’interface des démos de chaque plateforme sert à présenter le SDK ; vous pouvez personnaliser librement l’interface et les interactions.
- Le SDK est en version bêta publique et fait l’objet d’améliorations continues. Maintenez le SDK à jour.
- Le modèle actuel ne prend pas en charge la reconnaissance faciale des enfants de moins de 12 ans et ne doit pas être utilisé dans des applications financières.
- La recherche faciale exige des images nettes ; les déploiements en extérieur nécessitent une caméra dotée d’une plage dynamique étendue supérieure à 100 dB.
- Les parcours sur ordinateur et avec caméra sous Windows/Linux restent à valider avec des caméras réelles ; les applications mobiles nécessitent votre propre configuration de signature.

## Contact

La prise en charge d’autres plateformes est en cours de développement. Si vous rencontrez un problème, ouvrez une issue.

E-mail: [FaceAISDK.Service@gmail.com](mailto:FaceAISDK.Service@gmail.com)

<table>
  <tr>
    <th align="center">Télécharger l’APK Android</th>
    <th align="center">Contact WeChat</th>
    <th align="center">Télécharger sur Google Play</th>
  </tr>
  <tr>
    <td align="center">
      <a href="https://www.pgyer.com/HelloFace"><img src="../../images/AndroidAPK.png" alt="Code QR de téléchargement de l’APK Android" width="180"></a><br>
      <a href="https://www.pgyer.com/HelloFace">Cliquez ou scannez pour télécharger</a>
    </td>
    <td align="center">
      <img src="../../images/WeChat.jpg" alt="Code QR WeChat" width="180"><br>
      Scannez pour nous contacter
    </td>
    <td align="center">
      <a href="https://play.google.com/store/apps/details?id=com.hiface.sdk.debug"><img src="../../images/GooglePlay.svg" alt="Code QR de téléchargement sur Google Play" width="180" height="180"></a><br>
      <a href="https://play.google.com/store/apps/details?id=com.hiface.sdk.debug">Télécharger la démo Android sur Google Play</a>
    </td>
  </tr>
</table>
