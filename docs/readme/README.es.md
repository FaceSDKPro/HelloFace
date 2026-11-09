<h3 align="left">
  <a href="../../README.md">English</a> · <a href="../../README.zh-CN.md">简体中文</a> · <strong>Español</strong> · <a href="README.pt-BR.md">Português (Brasil)</a><br>
  <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.ms.md">Bahasa Melayu</a>
</h3>

<p align="left">
  <img src="../../images/technology-badges.svg" alt="Procesamiento local · SDK nativos · 5 plataformas" width="349" height="20">
</p>

<br>

<div align="center">
  <p>
    <a href="https://www.helloface.dev/"><img src="../../images/hello-face-icon.webp" alt="" width="51" height="51" align="bottom"><img src="../../images/helloface-wordmark.svg" alt="HelloFace" width="170" height="40" align="bottom"></a>
    &nbsp; <strong>0.8.9 Beta</strong>
  </p>
  <p><strong>Detección y captura de rostros, detección de vida, verificación 1:1 y búsqueda 1:N/M:N sin conexión.</strong></p>
  <p>🌍 <strong>Sitio web oficial</strong> · <a href="https://www.helloface.dev">helloface.dev ↗</a> &nbsp; | &nbsp; <img src="../../images/github-mark.svg" alt="" width="16" height="16" align="bottom"> <strong>Código de integración en GitHub</strong> · <a href="https://github.com/FaceSDKPro/HelloFace">FaceSDKPro/HelloFace</a></p>
</div>

<br>

<table>
  <tr>
    <th align="left" nowrap>Función</th>
    <th align="left">Descripción</th>
  </tr>
  <tr>
    <td align="left" nowrap>🔒 <strong>Sin conexión y con privacidad</strong></td>
    <td align="left">Procesa los datos faciales localmente, sin subir imágenes ni características faciales a la nube. <a href="../privacy/DATA_PROCESSING_AND_PRIVACY.es.md"><strong>Más</strong></a></td>
  </tr>
  <tr>
    <td align="left" nowrap>🎯 <strong>Herramientas faciales</strong></td>
    <td align="left">Detección de rostros, extracción de características, detección de vida, verificación 1:1 y búsqueda 1:N/M:N.</td>
  </tr>
  <tr>
    <td align="left" nowrap>🌍 <strong>Compatibilidad multiplataforma</strong></td>
    <td align="left">Ya es compatible con Android · iOS · HarmonyOS · Windows · Linux. Se prevén más plataformas; también puedes <a href="https://github.com/FaceSDKPro/HelloFace/issues">abrir una issue</a> para describir tus necesidades.</td>
  </tr>
  <tr>
    <td align="left" nowrap>🧩 <strong>Integración sencilla</strong></td>
    <td align="left">Empieza con las API del SDK, las guías de integración y las demos personalizables.</td>
  </tr>
  <tr>
    <td align="left" nowrap>⚡ <strong>Procesamiento en tiempo real</strong></td>
    <td align="left">Detección, verificación y búsqueda de rostros en tiempo real, en milisegundos.</td>
  </tr>
</table>

<details>
  <summary><strong>Ver la descripción del producto y sus aplicaciones (en inglés)</strong></summary>
  <p align="center"><img src="../../images/AboutHelloFace-EN.png" alt="Descripción del producto HelloFace y sus aplicaciones, en inglés" width="100%"></p>
</details>

## Plataformas

| Plataforma | Requisitos | Integración (en inglés) |
|---|---|---|
| Android | Android 6.0+ · ARM64/ARMv7/X86 · JDK 11 | [Demo](../../platforms/Android/README.md) · [SDK](../../platforms/Android/docs/SDK.md) |
| iOS | iOS 15+ · Swift 6 · Xcode | [Demo](../../platforms/iOS/README.md) · [SDK](../../platforms/iOS/SDK/API.md) |
| Harmony | HarmonyOS API 20+ · ARM64 · DevEco Studio 26 | [Demo](../../platforms/Harmony/README.md) · [SDK](../../platforms/Harmony/SDK.md) |
| Linux | Ubuntu 22.04+ · x86_64/ARM64 · X11/XWayland | [Demo](../../platforms/Linux/README.md) · [SDK](../../platforms/Linux/runtimes/x86_64/sdk/README.md) |
| Windows | Windows 10/11 x64 · CPU | [Demo](../../platforms/Windows/README.md) · [SDK](../../platforms/Windows/sdk/README.md) |
| Registro facial web | Navegador | [Probar en línea](https://hiface-mdp.pages.dev/face/) |

**Más plataformas (previstas):** Miniprogramas de WeChat, ChromeOS, uni-app, complementos de Flutter, complementos de React Native (RN) y más.

## Obtener el código

Este repositorio utiliza Git LFS para gestionar archivos grandes, como los binarios del SDK. Si solo necesitas el último commit de la rama predeterminada, utiliza una clonación superficial para omitir el historial:

```bash
git clone --depth 1 --single-branch https://github.com/FaceSDKPro/HelloFace.git
```

## Antes de implementar

- La interfaz de las demos de cada plataforma sirve para mostrar el SDK; puedes personalizar libremente la interfaz y las interacciones.
- El SDK está en fase Beta pública y evoluciona de forma continua. Mantén actualizada la versión del SDK.
- El modelo actual no admite el reconocimiento facial de menores de 12 años y no debe utilizarse en aplicaciones financieras.
- La búsqueda facial requiere imágenes nítidas de la cámara; las instalaciones en exteriores necesitan una cámara con un rango dinámico amplio superior a 100 dB.
- Los flujos de escritorio y cámara de Windows/Linux están pendientes de validación con cámaras reales; las aplicaciones móviles requieren tu propia configuración de firma.

## Contacto

La compatibilidad con otras plataformas está en desarrollo. Si encuentras algún problema, abre una issue.

Correo electrónico: [FaceAISDK.Service@gmail.com](mailto:FaceAISDK.Service@gmail.com)

<table>
  <tr>
    <th align="center">Descargar el APK de Android</th>
    <th align="center">Contacto por WeChat</th>
  </tr>
  <tr>
    <td align="center">
      <a href="https://www.pgyer.com/HelloFace"><img src="../../images/AndroidAPK.png" alt="Código QR para descargar el APK de Android" width="180"></a><br>
      <a href="https://www.pgyer.com/HelloFace">Haz clic o escanea para descargar</a>
    </td>
    <td align="center">
      <img src="../../images/WeChat.jpg" alt="Código QR de WeChat" width="180"><br>
      Escanea para contactar
    </td>
  </tr>
</table>
