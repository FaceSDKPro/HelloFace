# Tratamento de dados e conformidade com a privacidade

[English](DATA_PROCESSING_AND_PRIVACY.md) · [简体中文](DATA_PROCESSING_AND_PRIVACY.zh-CN.md) · [Español](DATA_PROCESSING_AND_PRIVACY.es.md) · **Português (Brasil)**<br>
[Français](DATA_PROCESSING_AND_PRIVACY.fr.md) · [Deutsch](DATA_PROCESSING_AND_PRIVACY.de.md) · [日本語](DATA_PROCESSING_AND_PRIVACY.ja.md) · [한국어](DATA_PROCESSING_AND_PRIVACY.ko.md)

[Voltar à página inicial](../readme/README.pt-BR.md)

Escopo: HelloFace SDK. Este documento se destina aos integradores do SDK e descreve os fluxos de dados atuais e suas responsabilidades de gestão. Ele não substitui a política de privacidade do aplicativo ou serviço do integrador e não indica que uma implantação específica tenha sido certificada como estando em conformidade.

## Onde os dados são processados

O SDK realiza no dispositivo a detecção e captura de rostos, a extração de características, a prova de vida, a comparação e a busca. O próprio SDK não coleta nem transmite dados.
A camada do SDK não declara permissões nem capacidades de rede. O aplicativo hospedeiro deve explicar as finalidades das permissões de câmera, da seleção de fotos e das permissões de rede.

## Dados envolvidos

| Dados | Finalidade e limites do tratamento |
|---|---|
| Quadros da câmera, fotos selecionadas ou importadas e recortes faciais | Detecção, captura, prova de vida, extração de características e pré-visualização; o armazenamento adicional das imagens originais depende da aplicação |
| Características faciais, IDs de registros, grupos e etiquetas | Cadastro, consulta e comparação em uma galeria local; após o cadastro ou a importação, os registros podem ser armazenados de forma persistente no dispositivo |
| Estado local de execução do SDK, configurações da aplicação e logs | Operação e diagnóstico; são gerenciados separadamente da galeria facial da aplicação, e os logs também devem seguir o princípio de minimização de dados |
| Versão do sistema operacional e modelo de hardware | Permitem que o SDK selecione estratégias de execução otimizadas para diferentes sistemas operacionais e configurações de hardware |

## Responsabilidades dos integradores do SDK

Os integradores do SDK são responsáveis pelo tratamento e pela gestão lícitos e em conformidade dos dados faciais nos aplicativos ou serviços que integram o SDK, considerando os casos de uso, as atividades de tratamento e os requisitos aplicáveis em cada país ou região de implantação. Isso inclui coleta, uso, armazenamento, acesso, compartilhamento, transferência e exclusão. Os integradores também devem fornecer aos usuários informações claras sobre o tratamento de dados e um canal para solicitações relacionadas, além de se responsabilizarem pelo atendimento dessas solicitações.

A arquitetura atual do SDK, offline e com processamento no dispositivo, mantém os cálculos de dados faciais no próprio dispositivo para proteger os dados desde a concepção e minimizar o risco de exposição a serviços externos. Os integradores são responsáveis pelos controles de acesso, pela proteção do armazenamento, pelos mecanismos de retenção e exclusão e pelas medidas aplicáveis de informação, autorização e segurança para qualquer armazenamento de dados, sincronização na nuvem ou outro tratamento implementado por seus aplicativos ou serviços.

O SDK atual não oferece suporte ao reconhecimento facial de crianças menores de 12 anos e não deve ser usado em aplicações financeiras.

Para obter suporte à integração do SDK ou relatar problemas de segurança do SDK, os integradores podem entrar em contato pelo e-mail [FaceAISDK.Service@gmail.com](mailto:FaceAISDK.Service@gmail.com).
