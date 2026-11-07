<h3 align="left">
  <a href="../../README.md">English</a> · <a href="../../README.zh-CN.md">简体中文</a> · <a href="README.es.md">Español</a> · <a href="README.pt-BR.md">Português (Brasil)</a><br>
  <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.ja.md">日本語</a> · <strong>한국어</strong> · <a href="README.ms.md">Bahasa Melayu</a>
</h3>

<p align="left">
  <img src="../../images/technology-badges.svg" alt="온디바이스 처리 · 네이티브 SDK · 5개 플랫폼" width="349" height="20">
</p>

<br>

<div align="center">
  <p>
    <a href="https://www.helloface.dev/"><img src="../../images/hello-face-icon.webp" alt="" width="51" height="51" align="bottom"><img src="../../images/helloface-wordmark.svg" alt="HelloFace" width="170" height="40" align="bottom"></a>
    &nbsp; <strong>0.8.8 Beta</strong>
  </p>
  <p><strong>얼굴 검출, 캡처, 라이브니스 검출, 1:1 검증 및 1:N/M:N 검색을 오프라인으로 제공합니다.</strong></p>
  <p>🌍 <strong>공식 웹사이트</strong> · <a href="https://www.helloface.dev">helloface.dev ↗</a> &nbsp; | &nbsp; <img src="../../images/github-mark.svg" alt="" width="16" height="16" align="bottom"> <strong>GitHub 연동 소스 코드</strong> · <a href="https://github.com/FaceSDKPro/HelloFace">FaceSDKPro/HelloFace</a></p>
</div>

<br>

<table>
  <tr>
    <th align="left" nowrap>기능</th>
    <th align="left">설명</th>
  </tr>
  <tr>
    <td align="left" nowrap>🔒 <strong>오프라인 및 개인정보 보호</strong></td>
    <td align="left">이미지나 얼굴 특징값을 클라우드에 업로드하지 않고 얼굴 데이터를 기기에서 처리합니다. <a href="../privacy/DATA_PROCESSING_AND_PRIVACY.ko.md"><strong>자세히</strong></a></td>
  </tr>
  <tr>
    <td align="left" nowrap>🎯 <strong>얼굴 처리 도구</strong></td>
    <td align="left">얼굴 검출, 특징 추출, 라이브니스 검출, 1:1 검증 및 1:N/M:N 검색을 지원합니다.</td>
  </tr>
  <tr>
    <td align="left" nowrap>🌍 <strong>크로스 플랫폼 지원</strong></td>
    <td align="left">Android · iOS · HarmonyOS · Windows · Linux를 지원합니다. 추가 플랫폼 지원을 기대해 주세요. 필요한 플랫폼은 <a href="https://github.com/FaceSDKPro/HelloFace/issues">이슈</a>에 요청 사항을 남겨 주세요.</td>
  </tr>
  <tr>
    <td align="left" nowrap>🧩 <strong>간편한 연동</strong></td>
    <td align="left">SDK API, 연동 가이드, 맞춤 설정이 가능한 데모로 개발을 시작할 수 있습니다.</td>
  </tr>
  <tr>
    <td align="left" nowrap>⚡ <strong>실시간 처리</strong></td>
    <td align="left">밀리초 단위로 실시간 얼굴 검출, 검증 및 검색을 수행합니다.</td>
  </tr>
</table>

<details>
  <summary><strong>제품 개요 및 활용 사례 보기(영문)</strong></summary>
  <p align="center"><img src="../../images/AboutHelloFace-EN.png" alt="HelloFace 제품 개요 및 활용 사례(영문)" width="100%"></p>
</details>

## 지원 플랫폼

| 플랫폼 | 실행 및 개발 환경 | 연동 자료(영문) |
|---|---|---|
| Android | Android 6.0+ · ARM64/ARMv7/X86 · JDK 11 | [Demo](../../platforms/Android/README.md) · [SDK](../../platforms/Android/docs/SDK.md) |
| iOS | iOS 15+ · Swift 6 · Xcode | [Demo](../../platforms/iOS/README.md) · [SDK](../../platforms/iOS/SDK/API.md) |
| Harmony | HarmonyOS API 20+ · ARM64 · DevEco Studio 26 | [Demo](../../platforms/Harmony/README.md) · [SDK](../../platforms/Harmony/SDK.md) |
| Linux | Ubuntu 22.04+ · x86_64/ARM64 · X11/XWayland | [Demo](../../platforms/Linux/README.md) · [SDK](../../platforms/Linux/runtimes/x86_64/sdk/README.md) |
| Windows | Windows 10/11 x64 · CPU | [Demo](../../platforms/Windows/README.md) · [SDK](../../platforms/Windows/sdk/README.md) |
| 웹 얼굴 등록 | 브라우저 | [온라인 체험](https://hiface-mdp.pages.dev/face/) |

**추가 지원 예정 플랫폼:** WeChat 미니 프로그램, ChromeOS, uni-app, Flutter 플러그인, React Native(RN) 플러그인 등.

## 코드 받기

이 저장소는 SDK 바이너리와 같은 대용량 파일을 Git LFS로 관리합니다. 기본 브랜치의 최신 커밋만 필요한 경우, 기록을 내려받지 않는 얕은 복제를 사용하세요.

```bash
git clone --depth 1 --single-branch https://github.com/FaceSDKPro/HelloFace.git
```

## 배포 전 확인 사항

- 각 플랫폼의 데모 UI는 SDK 시연용입니다. UI와 상호작용은 자유롭게 변경할 수 있습니다.
- SDK는 지속적으로 개선 중인 공개 베타 버전입니다. SDK를 최신 버전으로 유지하세요.
- 현재 모델은 12세 미만 아동의 얼굴 인식을 지원하지 않으며 금융 관련 용도로 사용할 수 없습니다.
- 얼굴 검색에는 선명한 카메라 영상이 필요합니다. 실외 배포에는 와이드 다이내믹 레인지가 100 dB를 초과하는 카메라가 필요합니다.
- Windows/Linux의 데스크톱 및 카메라 처리 흐름은 실제 카메라 검증을 기다리고 있습니다. 모바일 앱 실행에는 자체 앱 서명 설정이 필요합니다.

## 문의

다른 플랫폼에 대한 지원도 개선하고 있습니다. 문제가 발생하면 이슈를 등록해 주세요.

이메일: [FaceAISDK.Service@gmail.com](mailto:FaceAISDK.Service@gmail.com)

<table>
  <tr>
    <th align="center">Android APK 다운로드</th>
    <th align="center">WeChat 문의</th>
  </tr>
  <tr>
    <td align="center">
      <a href="https://www.pgyer.com/HelloFace"><img src="../../images/AndroidAPK.png" alt="Android APK 다운로드 QR 코드" width="180"></a><br>
      <a href="https://www.pgyer.com/HelloFace">클릭하거나 스캔하여 다운로드</a>
    </td>
    <td align="center">
      <img src="../../images/WeChat.jpg" alt="WeChat QR 코드" width="180"><br>
      스캔하여 문의
    </td>
  </tr>
</table>
