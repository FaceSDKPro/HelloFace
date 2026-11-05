# Datenverarbeitung und Datenschutzkonformität

[English](DATA_PROCESSING_AND_PRIVACY.md) · [简体中文](DATA_PROCESSING_AND_PRIVACY.zh-CN.md) · [Español](DATA_PROCESSING_AND_PRIVACY.es.md) · [Português (Brasil)](DATA_PROCESSING_AND_PRIVACY.pt-BR.md)<br>
[Français](DATA_PROCESSING_AND_PRIVACY.fr.md) · **Deutsch** · [日本語](DATA_PROCESSING_AND_PRIVACY.ja.md) · [한국어](DATA_PROCESSING_AND_PRIVACY.ko.md) · [Bahasa Melayu](DATA_PROCESSING_AND_PRIVACY.ms.md)

[Zur Startseite](../readme/README.de.md)

Geltungsbereich: HelloFace SDK. Dieses Dokument richtet sich an SDK-Integratoren und beschreibt die aktuellen Datenflüsse sowie deren Verantwortung für die Datenverwaltung. Es ersetzt nicht die Datenschutzerklärung der App oder des Dienstes des Integrators und bedeutet nicht, dass eine bestimmte Bereitstellung als konform zertifiziert wurde.

## Wo die Verarbeitung stattfindet

Das SDK führt Gesichtsdetektion und -erfassung, Merkmalsextraktion, Lebenderkennung, Vergleich und Suche auf dem Gerät aus. Das SDK selbst erhebt oder überträgt keine Daten.
Die SDK-Schicht deklariert keine Netzwerkberechtigungen oder Netzwerkfähigkeiten. Die Hostanwendung muss die Zwecke ihrer Kameraberechtigungen, der Fotoauswahl und ihrer Netzwerkberechtigungen erläutern.

## Verarbeitete Daten

| Daten | Zweck und Verarbeitungsgrenzen |
|---|---|
| Kamerabilder, ausgewählte oder importierte Fotos und Gesichtsausschnitte | Detektion, Erfassung, Lebenderkennung, Merkmalsextraktion und Vorschau; ob Originalbilder zusätzlich gespeichert werden, hängt von der Anwendung ab |
| Gesichtsmerkmale, Datensatz-IDs, Gruppen und Kennzeichnungen | Registrierung, Abfrage und Vergleich in einer lokalen Galerie; nach der Registrierung oder dem Import können Datensätze dauerhaft auf dem Gerät gespeichert werden |
| Lokaler SDK-Laufzeitstatus, Anwendungseinstellungen und Protokolle | Betrieb und Fehlerdiagnose; getrennte Verwaltung von der fachlichen Gesichtsdatenbank, wobei auch für Protokolle die Datenminimierung gilt |
| Betriebssystemversion und Hardwaremodell | Ermöglichen dem SDK die Auswahl optimierter Ausführungsstrategien für unterschiedliche Betriebssysteme und Hardwarekonfigurationen |

## Verantwortung der SDK-Integratoren

SDK-Integratoren sind für die rechtmäßige und regelkonforme Verarbeitung und Verwaltung von Gesichtsdaten in den Apps oder Diensten verantwortlich, die das SDK integrieren. Maßgeblich sind die Anwendungsfälle, Verarbeitungsvorgänge und die jeweils geltenden Anforderungen im Land oder in der Region der Bereitstellung. Dies umfasst Erhebung, Nutzung, Speicherung, Zugriff, Weitergabe, Übertragung und Löschung. Integratoren müssen den Nutzern außerdem klare Informationen zur Datenverarbeitung und einen Kontaktkanal für entsprechende Anfragen bereitstellen und diese Anfragen bearbeiten.

Die aktuelle Offline-Architektur des SDK belässt die Berechnungen zu Gesichtsdaten auf dem Gerät, um Nutzerdaten bereits durch die technische Gestaltung zu schützen und das Risiko einer Offenlegung gegenüber externen Diensten zu minimieren. Bei jeder Datenspeicherung, Cloud-Synchronisierung oder sonstigen Verarbeitung, die ihre Apps oder Dienste selbst umsetzen, sind die Integratoren für Zugriffskontrollen, den Schutz gespeicherter Daten, Aufbewahrungs- und Löschmechanismen sowie die jeweils erforderlichen Informations-, Autorisierungs- und Sicherheitsmaßnahmen verantwortlich.

Das aktuelle SDK unterstützt keine Gesichtserkennung von Kindern unter 12 Jahren und darf nicht in Finanzanwendungen eingesetzt werden.

Für Unterstützung bei der SDK-Integration oder zur Meldung von SDK-Sicherheitsproblemen können sich Integratoren an [FaceAISDK.Service@gmail.com](mailto:FaceAISDK.Service@gmail.com) wenden.
