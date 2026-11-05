# Tratamiento de datos y cumplimiento de la privacidad

[English](DATA_PROCESSING_AND_PRIVACY.md) · [简体中文](DATA_PROCESSING_AND_PRIVACY.zh-CN.md) · **Español** · [Português (Brasil)](DATA_PROCESSING_AND_PRIVACY.pt-BR.md)<br>
[Français](DATA_PROCESSING_AND_PRIVACY.fr.md) · [Deutsch](DATA_PROCESSING_AND_PRIVACY.de.md) · [日本語](DATA_PROCESSING_AND_PRIVACY.ja.md) · [한국어](DATA_PROCESSING_AND_PRIVACY.ko.md)

[Volver al inicio](../readme/README.es.md)

Ámbito: HelloFace SDK. Este documento está dirigido a quienes integran el SDK y describe los flujos de datos actuales y sus responsabilidades de gestión. No sustituye la política de privacidad de la aplicación o del servicio del integrador ni indica que una implementación concreta haya sido certificada como conforme.

## Dónde se procesan los datos

El SDK realiza en el dispositivo la detección y captura de rostros, la extracción de características, la detección de vida, la comparación y la búsqueda. El propio SDK no recopila ni transmite ningún dato.
La capa del SDK no declara permisos ni capacidades de red. La aplicación anfitriona debe explicar para qué utiliza los permisos de cámara, la selección de fotos y los permisos de red.

## Datos utilizados

| Datos | Finalidad y límites del tratamiento |
|---|---|
| Fotogramas de cámara, fotos seleccionadas o importadas y recortes faciales | Detección, captura, detección de vida, extracción de características y vista previa; el almacenamiento adicional de imágenes originales depende de la aplicación |
| Características faciales, identificadores de registros, grupos y etiquetas | Registro, consulta y comparación en una galería local; tras el registro o la importación, los registros pueden almacenarse de forma persistente en el dispositivo |
| Estado local de ejecución del SDK, ajustes de la aplicación y registros de diagnóstico | Funcionamiento y resolución de problemas; se gestionan por separado de la galería facial de la aplicación y los registros también deben seguir el principio de minimización de datos |
| Versión del sistema operativo y modelo de hardware | Permiten que el SDK seleccione estrategias de ejecución optimizadas para distintos sistemas operativos y configuraciones de hardware |

## Responsabilidades de quienes integran el SDK

Quienes integran el SDK son responsables del tratamiento y la gestión lícitos y conformes de los datos faciales en sus aplicaciones o servicios, de acuerdo con sus casos de uso, sus actividades de tratamiento y los requisitos aplicables en cada país o región de implementación. Esto incluye la recopilación, el uso, el almacenamiento, el acceso, la cesión, la transferencia y la eliminación. También deben ofrecer a los usuarios información clara sobre el tratamiento de datos y un canal para presentar solicitudes relacionadas, y encargarse de atenderlas.

La arquitectura actual del SDK, sin conexión y con procesamiento en el dispositivo, mantiene los cálculos sobre datos faciales en el propio dispositivo para proteger los datos desde el diseño y minimizar el riesgo de exponerlos a servicios externos. Los integradores son responsables de los controles de acceso, la protección del almacenamiento, los mecanismos de conservación y eliminación y las medidas aplicables de información, autorización y seguridad para cualquier almacenamiento de datos, sincronización en la nube u otro tratamiento implementado por sus aplicaciones o servicios.

El SDK actual no admite el reconocimiento facial de menores de 12 años y no debe utilizarse en aplicaciones financieras.

Para obtener asistencia con la integración del SDK o comunicar problemas de seguridad del SDK, los integradores pueden contactar con [FaceAISDK.Service@gmail.com](mailto:FaceAISDK.Service@gmail.com).
