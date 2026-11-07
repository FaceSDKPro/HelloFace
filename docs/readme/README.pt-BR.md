<h3 align="left">
  <a href="../../README.md">English</a> · <a href="../../README.zh-CN.md">简体中文</a> · <a href="README.es.md">Español</a> · <strong>Português (Brasil)</strong><br>
  <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.ms.md">Bahasa Melayu</a>
</h3>

<p align="left">
  <img src="../../images/technology-badges.svg" alt="Processamento no dispositivo · SDKs nativos · 5 plataformas" width="349" height="20">
</p>

<br>

<div align="center">
  <p>
    <a href="https://www.helloface.dev/"><img src="../../images/hello-face-icon.webp" alt="" width="51" height="51" align="bottom"><img src="../../images/helloface-wordmark.svg" alt="HelloFace" width="170" height="40" align="bottom"></a>
    &nbsp; <strong>0.8.8 Beta</strong>
  </p>
  <p><strong>Detecção e captura de rostos, prova de vida, verificação 1:1 e busca 1:N/M:N, tudo offline.</strong></p>
  <p>🌍 <strong>Site oficial</strong> · <a href="https://www.helloface.dev">helloface.dev ↗</a> &nbsp; | &nbsp; <img src="../../images/github-mark.svg" alt="" width="16" height="16" align="bottom"> <strong>Código de integração no GitHub</strong> · <a href="https://github.com/FaceSDKPro/HelloFace">FaceSDKPro/HelloFace</a></p>
</div>

<br>

<table>
  <tr>
    <th align="left" nowrap>Recurso</th>
    <th align="left">Descrição</th>
  </tr>
  <tr>
    <td align="left" nowrap>🔒 <strong>Offline e com privacidade</strong></td>
    <td align="left">Processe os dados faciais localmente, sem enviar imagens ou características faciais para a nuvem. <a href="../privacy/DATA_PROCESSING_AND_PRIVACY.pt-BR.md"><strong>Saiba mais</strong></a></td>
  </tr>
  <tr>
    <td align="left" nowrap>🎯 <strong>Recursos faciais</strong></td>
    <td align="left">Detecção de rostos, extração de características, prova de vida, verificação 1:1 e busca 1:N/M:N.</td>
  </tr>
  <tr>
    <td align="left" nowrap>🌍 <strong>Suporte multiplataforma</strong></td>
    <td align="left">Já oferece suporte a Android · iOS · HarmonyOS · Windows · Linux. Aguarde mais plataformas ou <a href="https://github.com/FaceSDKPro/HelloFace/issues">abra uma issue</a> para descrever suas necessidades.</td>
  </tr>
  <tr>
    <td align="left" nowrap>🧩 <strong>Integração fácil</strong></td>
    <td align="left">Comece com as APIs do SDK, os guias de integração e as demos personalizáveis.</td>
  </tr>
  <tr>
    <td align="left" nowrap>⚡ <strong>Processamento em tempo real</strong></td>
    <td align="left">Detecção, verificação e busca de rostos em tempo real, em milissegundos.</td>
  </tr>
</table>

<details>
  <summary><strong>Ver a visão geral do produto e suas aplicações (em inglês)</strong></summary>
  <p align="center"><img src="../../images/AboutHelloFace-EN.png" alt="Visão geral do HelloFace e suas aplicações, em inglês" width="100%"></p>
</details>

## Plataformas

| Plataforma | Requisitos | Integração (em inglês) |
|---|---|---|
| Android | Android 6.0+ · ARM64/ARMv7/X86 · JDK 11 | [Demo](../../platforms/Android/README.md) · [SDK](../../platforms/Android/docs/SDK.md) |
| iOS | iOS 15+ · Swift 6 · Xcode | [Demo](../../platforms/iOS/README.md) · [SDK](../../platforms/iOS/SDK/API.md) |
| Harmony | HarmonyOS API 20+ · ARM64 · DevEco Studio 26 | [Demo](../../platforms/Harmony/README.md) · [SDK](../../platforms/Harmony/SDK.md) |
| Linux | Ubuntu 22.04+ · x86_64/ARM64 · X11/XWayland | [Demo](../../platforms/Linux/README.md) · [SDK](../../platforms/Linux/runtimes/x86_64/sdk/README.md) |
| Windows | Windows 10/11 x64 · CPU | [Demo](../../platforms/Windows/README.md) · [SDK](../../platforms/Windows/sdk/README.md) |
| Cadastro facial pela web | Navegador | [Experimentar online](https://hiface-mdp.pages.dev/face/) |

**Mais plataformas (planejadas):** Miniprogramas do WeChat, ChromeOS, uni-app, plugins para Flutter, plugins para React Native (RN) e muito mais.

## Obter o código

Este repositório usa o Git LFS para gerenciar arquivos grandes, como os binários do SDK. Se você precisar apenas do commit mais recente da branch padrão, faça um clone superficial para não baixar o histórico:

```bash
git clone --depth 1 --single-branch https://github.com/FaceSDKPro/HelloFace.git
```

## Antes de implantar

- A interface das demos de cada plataforma serve para demonstrar o SDK; você pode personalizar livremente a interface e as interações.
- O SDK está em Beta público e passa por melhorias contínuas. Mantenha a versão do SDK atualizada.
- O modelo atual não oferece suporte ao reconhecimento facial de crianças menores de 12 anos e não deve ser usado em aplicações financeiras.
- A busca facial exige imagens nítidas da câmera; implantações em ambientes externos exigem uma câmera com faixa dinâmica ampla superior a 100 dB.
- Os fluxos de desktop e câmera no Windows/Linux ainda aguardam validação com câmeras reais; os aplicativos móveis exigem sua própria configuração de assinatura.

## Contato

O suporte a outras plataformas está em desenvolvimento. Se encontrar algum problema, abra uma issue.

E-mail: [FaceAISDK.Service@gmail.com](mailto:FaceAISDK.Service@gmail.com)

<table>
  <tr>
    <th align="center">Baixar o APK para Android</th>
    <th align="center">Contato pelo WeChat</th>
  </tr>
  <tr>
    <td align="center">
      <a href="https://www.pgyer.com/HelloFace"><img src="../../images/AndroidAPK.png" alt="Código QR para baixar o APK para Android" width="180"></a><br>
      <a href="https://www.pgyer.com/HelloFace">Clique ou escaneie para baixar</a>
    </td>
    <td align="center">
      <img src="../../images/WeChat.jpg" alt="Código QR do WeChat" width="180"><br>
      Escaneie para entrar em contato
    </td>
  </tr>
</table>
