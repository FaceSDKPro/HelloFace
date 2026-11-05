# Traitement des données et conformité en matière de confidentialité

[English](DATA_PROCESSING_AND_PRIVACY.md) · [简体中文](DATA_PROCESSING_AND_PRIVACY.zh-CN.md) · [Español](DATA_PROCESSING_AND_PRIVACY.es.md) · [Português (Brasil)](DATA_PROCESSING_AND_PRIVACY.pt-BR.md)<br>
**Français** · [Deutsch](DATA_PROCESSING_AND_PRIVACY.de.md) · [日本語](DATA_PROCESSING_AND_PRIVACY.ja.md) · [한국어](DATA_PROCESSING_AND_PRIVACY.ko.md)

[Retour à l’accueil](../readme/README.fr.md)

Périmètre : HelloFace SDK. Ce document s’adresse aux intégrateurs du SDK et décrit les flux de données actuels ainsi que leurs responsabilités de gestion. Il ne remplace pas la politique de confidentialité de l’application ou du service de l’intégrateur et ne signifie pas qu’un déploiement particulier a été certifié conforme.

## Où les données sont traitées

Le SDK effectue sur l’appareil la détection et la capture de visages, l’extraction de caractéristiques, la détection du vivant, la comparaison et la recherche. Le SDK lui-même ne collecte ni ne transmet aucune donnée.
La couche SDK ne déclare aucune autorisation ni capacité réseau. L’application hôte doit expliquer les finalités de ses autorisations d’accès à la caméra, de la sélection de photos et de ses autorisations réseau.

## Données concernées

| Données | Finalité et limites du traitement |
|---|---|
| Images de la caméra, photos sélectionnées ou importées et zones de visage recadrées | Détection, capture, détection du vivant, extraction de caractéristiques et aperçu ; l’enregistrement supplémentaire des images d’origine dépend de l’application |
| Caractéristiques faciales, identifiants d’enregistrement, groupes et étiquettes | Enregistrement, consultation et comparaison dans une galerie locale ; les enregistrements peuvent être conservés durablement sur l’appareil après leur création ou leur importation |
| État local d’exécution du SDK, paramètres de l’application et journaux | Fonctionnement et diagnostic ; gérés séparément de la galerie faciale métier, avec application du principe de minimisation des données aux journaux également |
| Version du système d’exploitation et modèle matériel | Permettent au SDK de choisir des stratégies d’exécution optimisées pour différents systèmes d’exploitation et configurations matérielles |

## Responsabilités des intégrateurs du SDK

Les intégrateurs du SDK sont responsables du traitement et de la gestion licites et conformes des données faciales dans les applications ou services qui intègrent le SDK, en fonction de leurs cas d’usage, de leurs activités de traitement et des exigences applicables dans chaque pays ou région de déploiement. Cela comprend la collecte, l’utilisation, le stockage, l’accès, le partage, le transfert et la suppression. Les intégrateurs doivent également fournir aux utilisateurs des informations claires sur le traitement des données et un canal pour les demandes associées, puis prendre en charge ces demandes.

L’architecture actuelle du SDK, hors ligne et sur l’appareil, conserve les calculs portant sur les données faciales dans l’appareil afin de protéger les données dès la conception et de réduire autant que possible le risque d’exposition à des services externes. Les intégrateurs sont responsables des contrôles d’accès, de la protection du stockage, des mécanismes de conservation et de suppression, ainsi que des mesures applicables d’information, d’autorisation et de sécurité pour tout stockage, toute synchronisation dans le cloud ou tout autre traitement mis en œuvre par leurs applications ou services.

Le SDK actuel ne prend pas en charge la reconnaissance faciale des enfants de moins de 12 ans et ne doit pas être utilisé dans des applications financières.

Pour obtenir de l’aide à l’intégration du SDK ou signaler un problème de sécurité du SDK, les intégrateurs peuvent écrire à [FaceAISDK.Service@gmail.com](mailto:FaceAISDK.Service@gmail.com).
