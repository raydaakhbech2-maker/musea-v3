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

## Courants créatifs — tendances fondées sur les publications réelles

L'écran Tendances ne présente plus de classement individuel fictif. Il calcule des courants par style à partir des publications publiques réellement chargées, avec trois périodes (7 jours, 30 jours, publications récentes). Les courants sont ordonnés d'abord par nombre de créations, puis par diversité de créateurs ; le nombre d'interactions est affiché comme contexte et ne décide pas seul de l'ordre.

Une sélection « Des créations à rencontrer » fait ressortir des publications ayant peu d'interactions. Aucun profil ou engagement fictif n'est généré et aucun point n'est attribué par cet écran. Les tendances sont limitées aux 100 dernières publications publiques accessibles via le chargement communautaire : elles ne prétendent pas représenter l'intégralité de la plateforme.

Le parcours créatif « Mes repères » remplace les points et la boutique simulés. Cinq jalons privés sont calculés à partir des données réelles du compte : première publication publique, trois publications, diversité de trois styles, première pièce de portfolio et identité créative renseignée. Aucun classement, série quotidienne, dépense de points ou avantage Premium n'est associé à ces jalons. Ils ne sont pas une monnaie et ne peuvent pas être achetés.

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


## MUSEA Signature — modèle Premium (étape 22)

L'offre est conçue autour d'outils créatifs et de confort, sans vendre la popularité :
- la formule gratuite conserve les fonctions sociales essentielles, la sécurité, la confidentialité et les outils de base ;
- la formule envisagée « MUSEA Signature » vise la personnalisation approfondie du profil/portfolio, une bibliothèque de projets privés plus généreuse, des outils avancés de présentation/export, des analyses créatives personnelles et des options d'organisation des ateliers ;
- aucun avantage payant ne doit acheter des likes, des abonnés, une certification, une portée ou une priorité dans les recommandations ;
- le prix de travail affiché est de 5,99 €/mois, non validé commercialement.

L'interface présente cette formule comme étant en préparation. Aucun abonnement n'est vendu, aucun paiement n'est collecté et aucun compte ne peut activer Signature depuis le navigateur. Les avantages listés sont une proposition de produit à implémenter et à vérifier avant commercialisation.

## MUSEA Encaissement — étape 23 prévue

Une étape distincte est réservée à l'intégration d'un prestataire de paiement et au véritable cycle de facturation. Elle devra inclure au minimum : création de session de paiement côté serveur, confirmation exclusivement par webhook signé, gestion des abonnements et de leur état, droits Premium contrôlés côté serveur, factures/reçus, annulation et remboursement, journal de transactions, suivi des frais et des virements, protection contre les doubles événements et tests en environnement sandbox. Aucune clé secrète de paiement ne devra être exposée dans le fichier client.

L'activation commerciale dépendra de la structure juridique, des conditions du prestataire, de la vérification du titulaire du compte et des obligations fiscales applicables. Pour un créateur mineur, le représentant légal devra intervenir selon les règles du prestataire ; aucun contrôle d'âge ou d'identité ne doit être contourné.


## MUSEA Encaissement — architecture technique (étape 23)

Le dépôt contient désormais le socle serveur Stripe, mais **aucun paiement n'est activé** et aucun prélèvement réel ne peut être lancé tant que le titulaire légal du compte marchand n'a pas configuré et validé le prestataire et les secrets côté serveur.

### Composants ajoutés

- `supabase/migrations/2026-11-04_billing_core.sql` : correspondance client, abonnements, factures et journal d'événements.
- `supabase/functions/create-signature-checkout/` : crée une session Checkout après vérification de la session MUSEA et de l'absence d'abonnement actif. Le tarif est lu depuis une variable serveur, jamais depuis le navigateur, et doit être un prix mensuel actif en euros.
- `supabase/functions/stripe-webhook/` : vérifie la signature Stripe sur le corps brut, relit l'état actuel de l'abonnement chez Stripe et synchronise les droits et factures côté serveur.
- `supabase/functions/create-billing-portal/` : crée un accès authentifié au portail de facturation.
- `supabase/config.toml` : seul le webhook Stripe est public au niveau JWT Supabase ; sa signature Stripe reste obligatoire.

### Secrets attendus côté Supabase

`STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SIGNING_SECRET`, `STRIPE_SIGNATURE_PRICE_ID`, `SUPABASE_URL`, `SUPABASE_ANON_KEY` et `SUPABASE_SERVICE_ROLE_KEY`.

Les secrets Stripe et la clé de service Supabase ne doivent jamais être placés dans `index.html`, dans GitHub Pages, dans le dépôt public ou dans un message. Les valeurs doivent être configurées uniquement dans le coffre de secrets Supabase par l'adulte ou la structure légalement responsable du compte marchand.

### État d'activation

1. La migration SQL doit être appliquée dans le projet Supabase.
2. Le compte marchand, le produit mensuel Signature et le webhook doivent être configurés et vérifiés par le titulaire légal autorisé.
3. Les Edge Functions doivent être déployées avec les secrets ci-dessus.
4. Les événements de test doivent confirmer que seul un webhook signé active un abonnement.
5. Le portail client doit être activé côté prestataire pour permettre la gestion et la résiliation.

L'interface MUSEA ne donne toujours aucun accès Premium par simple modification du navigateur. La fonction SQL `musea_has_signature_access()` fournit le contrôle serveur de base pour les futures fonctions Signature, mais aucune fonction Premium n'est encore déverrouillée dans l'interface. La résiliation est prévue via le portail prestataire lorsqu'il sera configuré ; les remboursements et les éventuels litiges restent gérés par le titulaire du compte et le prestataire. Aucun outil de remboursement automatisé n'est présenté comme déjà disponible.

**Cadre légal :** comme le projet est porté par un mineur, toute ouverture et gestion du compte marchand, acceptation des contrats, vérification d'identité et réception des fonds doivent être prises en charge avec le représentant légal ou la structure habilitée, selon les conditions du prestataire. Aucun contrôle d'âge, d'identité ou de conformité ne doit être contourné.


**Validation réalisée pour l'étape 23 :** revue statique des chemins d'authentification, contrôle de l'origine, validation du prix mensuel en EUR, vérification de signature du webhook sur le corps brut, synchronisation serveur et politiques RLS. Aucune migration n'a été exécutée sur le projet Supabase, aucune Edge Function n'a été déployée et aucun paiement de test ou réel n'a été effectué.


## MUSEA Empreinte — maîtrise des données personnelles (étape 24 proposée)

Le centre « Mon dossier MUSEA » permet à un membre connecté de télécharger un export JSON des données de son compte accessibles via sa session et les politiques Row Level Security : profil, publications, interactions envoyées, collections, commentaires, portfolio, brouillons Studio, notifications, préférences, messages envoyés, conversations accessibles, tâches liées, blocages et signalements envoyés.

- Les lectures sont effectuées avec la session utilisateur, jamais avec une clé privilégiée.
- Les catégories sont paginées et chaque erreur ou migration absente est signalée dans le fichier au lieu d'être masquée.
- Les messages d'autres membres ne sont pas exportés ; seuls les messages envoyés par le compte le sont.
- Les images et autres fichiers binaires ne sont pas intégrés au JSON ; les références disponibles sont conservées.
- La suppression définitive du compte n'est pas activée : elle nécessitera un flux serveur dédié qui traite les sessions, les fichiers Storage et les dépendances sans exposer de clé secrète.

Cette étape est une proposition cohérente pour la suite du projet ; aucun titre ni périmètre original confirmé des étapes 24 à 26 n'a été retrouvé dans les échanges précédents.

**Validation effectuée :** vérification statique des catégories interrogées, de leurs filtres d'identité, de l'utilisation de la session Supabase côté client et de l'absence de clé privilégiée dans le code ajouté. L'export doit encore être essayé avec un compte de test sur le projet Supabase réel ; il ne peut inclure que les tables et politiques effectivement déployées.


## MUSEA Filiations — transmission créative (étape 25 proposée)

Une publication peut être reliée à une œuvre publique MUSEA comme « Inspirée par » ou « Réinterprétation ». Le crédit de l'œuvre source apparaît sur la publication dérivée, avec un lien pour retrouver l'origine et une note facultative sur ce qui a été transformé.

- La filiation est facultative : une publication sans source reste une création indépendante.
- La migration `supabase/migrations/2026-11-05_creative_lineage.sql` crée une relation unique par publication dérivée, avec RLS, vérification de propriété de l'œuvre dérivée, source publique, interdiction de l'auto-référence et suppression réservée à son créateur.
- Le fil récupère les filiations des publications chargées et affiche le crédit. Le sélecteur de Studio propose les publications publiques déjà chargées dans le fil (limite actuelle : 100).
- Si la migration n'est pas appliquée, les publications normales continuent de fonctionner ; une filiation choisie affichera un avertissement si son enregistrement échoue.
- Aucune rémunération, propriété intellectuelle ou licence n'est transférée par ce lien. Les droits et autorisations nécessaires restent à respecter.
- L'export MUSEA Empreinte a été déplacé dans le script applicatif exécutable : il n'est plus inséré dans la balise du SDK Supabase, dont le contenu inline est ignoré lorsqu'un attribut `src` est présent.

Cette étape est une proposition de continuité produit, les intitulés originaux des étapes 25–26 n'ayant pas été retrouvés.

**Validation statique :** présence du formulaire de filiation, du chargement des relations, de l'affichage du crédit, de l'insertion liée à la publication, de la migration RLS et du déplacement du code d'export. Pas de test en direct Supabase ni de migration exécutée à distance.


## Étape 26 — MUSEA Signal : fiabilité, transparence et continuité

MUSEA Signal ajoute dans les paramètres un diagnostic local lisible : état réseau déclaré par le navigateur, contexte HTTPS, chargement du client Supabase, présence d'une session locale, disponibilité du stockage, état du service worker et préférence de réduction des mouvements. Le rapport peut être copié par l'utilisateur, mais il n'est envoyé à aucun serveur.

Une bannière hors ligne prévient lorsque le navigateur déclare une absence de réseau et rappelle que publication, messagerie et synchronisation nécessitent une reconnexion. Le service worker conserve uniquement la structure de l'application ; il ne met pas en cache les données privées ou les réponses authentifiées.

Limites explicites : le diagnostic ne réalise pas de test de disponibilité du serveur Supabase, ne certifie pas la sécurité globale du compte et ne remplace ni les tests sur appareils réels, ni l'audit des politiques RLS et des migrations. Les fonctions dépendantes du réseau peuvent rester indisponibles même si le navigateur indique être en ligne.


## Consolidation compte, créations et facturation — novembre 2026

### Connexion et gestion des créations
- Le panneau de connexion initial disparaît après authentification ; les informations de compte et la déconnexion sont regroupées dans Paramètres.
- L'auteur voit une action de suppression sur ses propres publications. Le serveur vérifie la propriété via RLS ; les autres membres conservent l'action de signalement.
- Après suppression de la ligne de publication, l'application tente également de supprimer l'image du bucket `musea-posts`. Les relations de portfolio et de filiation sont liées par des clés étrangères avec suppression en cascade dans leurs migrations respectives.
- Migration requise : `2026-11-06_post_owner_delete.sql`. Elle refuse d'ajouter le droit si RLS n'est pas activé sur `public.posts`, et limite les suppressions Storage au dossier UUID du propriétaire.

### Facturation — protections renforcées
- Le tableau Paramètres affiche l'état de l'abonnement, la confirmation serveur de l'accès Signature et les dernières factures visibles par le compte connecté. Les liens de facture sont acceptés uniquement en HTTPS depuis les domaines Stripe.
- Le portail de facturation vérifie que l'identifiant client Stripe appartient bien au compte MUSEA authentifié.
- La création d'un Checkout est verrouillée par deux variables serveur indépendantes : `MUSEA_BILLING_ENABLED=true` et `MUSEA_MERCHANT_READY=true`. Elles ne doivent être définies qu'après validation du compte marchand par son titulaire légal. Elles ne sont pas configurées dans le dépôt.
- Le Checkout exige une adresse e-mail confirmée, vérifie le prix côté Stripe (actif, mensuel, EUR, montant positif), associe le client Stripe au compte MUSEA et consulte Stripe pour éviter les abonnements simultanés ou les doubles souscriptions.
- La migration `2026-11-06_billing_checkout_lock.sql` ajoute un verrou atomique par compte : une seule préparation Checkout peut être ouverte à la fois. Les sessions sont limitées à 30 minutes et un jeton serveur empêche la libération du verrou par une autre tentative.
- La migration `2026-11-06_billing_hardening.sql` ajoute une réservation atomique des webhooks, un état de traitement, des tentatives et une reprise des événements échoués. Les doublons déjà traités sont acquittés ; un événement toujours en cours n'est pas acquitté prématurément.
- Les accès Signature restent décidés par la fonction SQL serveur `musea_has_signature_access()`, jamais par un drapeau local ou un paramètre d'URL.

### Limites de déploiement
Aucune migration n'a été exécutée sur le projet Supabase, aucune Edge Function n'a été déployée et aucun paiement de test ou réel n'a été lancé. Le Checkout reste verrouillé tant que les deux drapeaux serveur ne sont pas explicitement activés par le titulaire légal autorisé. La gestion d'un compte marchand, les contrats, les vérifications d'identité et la réception de fonds doivent être assumés par le représentant légal ou la structure habilitée selon les règles du prestataire.


## MUSEA IA — assistant créatif (remise à niveau)

Le Studio comprend désormais les points d'entrée pour développer une idée, proposer une légende, traduire un texte et générer un visuel. Les appels passent par l'Edge Function authentifiée `musea-ai` ; la clé OpenAI reste côté serveur et n'est jamais intégrée au navigateur.

- Modèle texte par défaut : `gpt-6-luna` via l'API Responses.
- Modèle image par défaut : `gpt-image-2.5-flare`.
- La migration `2026-11-06_ai_usage_limits.sql` crée des quotas quotidiens côté serveur : 8 requêtes texte et 1 image pour Libre ; 80 requêtes texte et 5 images pour Signature.
- Secrets requis côté Supabase : `OPENAI_API_KEY` et `MUSEA_AI_ENABLED=true`. Modèles configurables via `OPENAI_TEXT_MODEL` et `OPENAI_IMAGE_MODEL`.
- Les quotas sont consommés avant l'appel fournisseur pour empêcher les appels concurrents de dépasser les limites. Une requête fournisseur échouée peut donc consommer une unité.
- Les résultats ne sont jamais publiés automatiquement. Le créateur doit les relire, les modifier et décider de les enregistrer ou de les publier.
- L'API OpenAI est facturée séparément des abonnements ChatGPT ; le coût dépend du modèle, des tokens et des images générées. Les clés doivent être conservées dans les secrets Supabase, jamais dans le code client.
- Le service reste désactivé tant que la migration n'est pas appliquée et que le titulaire du projet n'a pas configuré les secrets et validé les plafonds de dépenses.

### Paiement Signature — environnement de test uniquement

L'interface appelle maintenant `create-signature-checkout`. L'Edge Function refuse explicitement toute clé Stripe autre que `sk_test_`. Les flags serveur `MUSEA_BILLING_ENABLED` et `MUSEA_MERCHANT_READY` doivent aussi être validés pour les tests. Aucun paiement réel ne peut être lancé depuis cette branche. La mise en production nécessitera une revue distincte du compte marchand, des obligations légales, des conditions commerciales, des remboursements et de la résiliation.
