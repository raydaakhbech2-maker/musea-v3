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
3. L'application des migrations du dépôt dans un ordre respectant leurs dépendances : notifications, découverte créative, messagerie/collaboration, modération/confiance, équité/recours, profils créateurs/portfolio.
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
