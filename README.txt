# MUSEA V3 — application web progressive

MUSEA est une plateforme sociale créative en cours de construction. Le dépôt contient une PWA hébergée sur GitHub Pages et connectée à un projet Supabase.

## Fichiers principaux

- `index.html` : interface, navigation et logique cliente.
- `manifest.webmanifest` : métadonnées d’installation PWA.
- `sw.js` : cache hors ligne minimal.
- `icon-192.png` et `icon-512.png` : icônes de l’application.
- `supabase/migrations/` : migrations SQL des fonctionnalités serveur.

## Fonctionnalités déjà présentes dans le code

- Authentification Supabase et profil utilisateur.
- Publications réelles avec images hébergées sur Supabase Storage.
- Explorer et fil créatif basés sur les publications accessibles.
- Likes, commentaires, réponses, sauvegardes et republications.
- Notifications et préférences associées au compte.
- Découverte par affinités créatives, diversité et talents émergents.
- Profils créateurs personnalisables et portfolio de créations sélectionnées.
- Messagerie privée et espaces de collaboration avec tâches.
- Signalements, outils de modération, mesures et recours.

La présence d'une fonctionnalité dans le code ne garantit pas que toutes les migrations correspondantes ont déjà été exécutées sur le projet Supabase. Les autorisations RLS et les migrations serveur doivent être vérifiées avant toute mise en production.

## Déploiement actuel

- Dépôt : https://github.com/raydaakhbech2-maker/musea-v3
- Application : https://raydaakhbech2-maker.github.io/musea-v3/

Les modifications de `main` sont publiées par GitHub Pages après le délai de déploiement habituel.

## Configuration Supabase

Le client utilise une clé publishable côté navigateur. Aucune clé `service_role` ne doit être intégrée au code client.

Avant d'activer les fonctionnalités, vérifier dans Supabase :
1. L'URL de redirection d'authentification : `https://raydaakhbech2-maker.github.io/musea-v3/`.
2. L'existence des tables de base `profiles`, `posts` et des tables d'interactions sociales utilisées par l'application.
3. L'application des migrations du dépôt dans un ordre respectant leurs dépendances : notifications, découverte créative, réglages de la Boussole, messagerie/collaboration, modération/confiance, équité/recours, profils créateurs/portfolio, puis Studio créatif.
4. Les politiques Row Level Security (RLS), les fonctions RPC et les rôles de modération côté serveur.
5. Les règles du bucket Storage utilisé pour les images.

Ne jamais désactiver RLS pour contourner une erreur. Une erreur de permission doit être corrigée dans les politiques ou fonctions prévues.

## Limites actuelles à ne pas présenter comme des fonctionnalités terminées

- Le navigateur MUSEA ouvre les pages dans le navigateur de l'appareil ; ce n'est pas un moteur web intégré comparable à Chrome ou Opera GX.
- La génération IA n'est pas reliée à un fournisseur IA opérationnel dans cette version.
- Les offres Premium, points, récompenses et achats restent des simulations : aucun paiement réel n'est traité.
- Les notifications sont dans l'application ; les notifications push lorsque l'application est fermée ne sont pas garanties.
- Les appels audio/vidéo et les pièces jointes personnelles dans les messages ne sont pas implémentés.
- Les stories disponibles dans certaines vues sont des brouillons locaux, pas un service de stories synchronisées complet.
- La modération repose sur des signalements et des décisions humaines autorisées ; aucun système automatique ne garantit la détection de tous les abus.

## Boussole créative — transparence et contrôle

La découverte propose trois équilibres (Mes repères, Équilibré, Surprise), un contrôle de la personnalisation par interactions et un réglage de mise en avant des talents émergents. Chaque recommandation peut expliquer les signaux effectivement utilisés pour son classement. Les utilisateurs peuvent réinitialiser leurs préférences et retours.

La migration `2026-11-04_discovery_controls.sql` ajoute les réglages à `creative_preferences`. Les préférences sont privées via les politiques RLS existantes ; en cas de migration non appliquée, les réglages locaux restent disponibles sur l'appareil, sans prétendre être synchronisés.

## Pulse créateur — retour privé sur les créations

Le profil personnel affiche un tableau de bord privé calculé à partir des publications publiques du compte et des interactions réellement enregistrées : likes, commentaires et reposts. Il met en avant le volume de créations, l'activité récente sur 7 jours et la publication qui suscite le plus d'interactions.

Les brouillons ne sont pas comptabilisés. Les vues, les personnes uniques et la portée ne sont pas mesurées dans cette version : les interactions ne doivent pas être présentées comme des vues ni comme une mesure de qualité. Les données sont chargées avec pagination pour éviter de tronquer les interactions au-delà de la limite habituelle d'une requête.

Aucune migration SQL supplémentaire n'est nécessaire ; le tableau de bord utilise les tables sociales existantes et leurs politiques RLS.

## MUSEA Studio

Le Studio permet de préparer des créations avant publication :
- brief créatif, titre, légende publique et notes privées séparés ;
- recadrage réel en carré, portrait, paysage ou story ;
- réglages d'image côté appareil (ambiance, luminosité, contraste, saturation) ;
- export du visuel retouché en WebP ;
- projets privés synchronisés dans `creator_drafts` et fichiers sources dans le bucket privé `musea-drafts` ;
- états « En création » et « Prêt à publier » ;
- publication déclenchée explicitement par le créateur.

Aucun moteur de génération IA n'est connecté dans cette version. Les outils de retouche fonctionnent localement dans le navigateur ; aucune image n'est envoyée à un fournisseur IA. La migration `2026-11-04_creator_studio.sql` doit être appliquée dans Supabase pour activer les brouillons synchronisés et leur stockage privé.

## Installation sur téléphone

Le site HTTPS peut être installé comme PWA :
- Android/Chrome : menu du navigateur > Installer l'application ou Ajouter à l'écran d'accueil.
- iPhone/iPad/Safari : Partager > Sur l'écran d'accueil.

Le dépôt ne contient pas d'APK Android ni d'IPA iOS natif. Une publication sur les stores exigera un emballage natif testé, les comptes développeur, les politiques de confidentialité, les contrôles de sécurité et les tests de conformité.

## Principes produit

- Pas de faux utilisateurs, de fausses publications ou de fausses interactions.
- Pas de promesse IA, paiement, certification ou sécurité non réellement opérationnelle.
- Les profils privés et les contenus masqués doivent rester protégés par les règles serveur, pas seulement par l'interface.
- Le badge certifié nécessite une vérification indépendante ; les points ne garantissent jamais son obtention.
