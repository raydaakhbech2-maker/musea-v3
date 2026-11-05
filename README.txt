# MUSEA V3 — application web progressive

MUSEA V3 est une application web progressive sociale et créative en préparation de publication. Le dépôt contient une PWA hébergée sur GitHub Pages et connectée à un projet Supabase.

## Fichiers principaux

- `index.html` : interface, navigation et logique cliente.
- `manifest.webmanifest` : métadonnées d’installation PWA.
- `sw.js` : cache hors ligne minimal.
- `icon-192.png` et `icon-512.png` : icônes de l’application.
- `privacy.html`, `delete-account.html`, `community-guidelines.html` : informations publiques de confidentialité, suppression de compte et règles communautaires.
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
- L'assistant IA, les idées créatives et les légendes appellent l'Edge Function Supabase `bright-api` (OpenAI). La disponibilité effective dépend du secret serveur OPENAI_API_KEY, des crédits fournisseur et d'une session utilisateur valide ; un test authentifié de bout en bout reste nécessaire.
- Les abonnements et paiements sont désactivés dans l'interface et les fonctions de paiement côté serveur sont verrouillées pour cette version. Aucun achat ne doit être proposé avant une mise à jour distincte.
- Les notifications sont dans l'application ; les notifications push lorsque l'application est fermée ne sont pas garanties.
- Les appels audio/vidéo et les pièces jointes personnelles dans les messages ne sont pas implémentés.
- Les stories textuelles sont synchronisées dans public.stories, limitées à 24 heures et filtrées par les règles de confidentialité et de blocage. Les médias de stories et leur lecture avancée ne sont pas encore intégrés à l'interface.
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

Le dépôt ne contient pas d'APK Android ni d'IPA iOS natif. Les pages publiques sont disponibles : `privacy.html`, `delete-account.html` et `community-guidelines.html`. La demande de suppression de compte est actuellement reçue par e-mail et doit être traitée manuellement après vérification ; ce n'est pas une suppression instantanée depuis l'application. Une publication sur les stores exige encore un emballage Android signé et testé, les informations juridiques complètes de l'éditeur, les comptes développeur, les déclarations Play Console et les tests de conformité.

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

Cette formule est une piste produit future et n'est pas présentée comme disponible dans l'interface de lancement. Aucun abonnement n'est vendu, aucun paiement n'est collecté et les fonctions de paiement sont verrouillées. Les avantages listés sont une proposition de produit à implémenter et à vérifier avant commercialisation.

## MUSEA Encaissement — reporté après le lancement

Une étape distincte est réservée à l'intégration d'un prestataire de paiement et au véritable cycle de facturation. Elle devra inclure au minimum : création de session de paiement côté serveur, confirmation exclusivement par webhook signé, gestion des abonnements et de leur état, droits Premium contrôlés côté serveur, factures/reçus, annulation et remboursement, journal de transactions, suivi des frais et des virements, protection contre les doubles événements et tests en environnement sandbox. Aucune clé secrète de paiement ne devra être exposée dans le fichier client.

L'activation commerciale dépendra de la structure juridique, des conditions du prestataire, de la vérification du titulaire du compte et des obligations fiscales applicables. Pour un créateur mineur, le représentant légal devra intervenir selon les règles du prestataire ; aucun contrôle d'âge ou d'identité ne doit être contourné.


## MUSEA Encaissement — architecture technique existante, non activée

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


**Validation réalisée pour l'étape 23 :** revue statique des chemins d'authentification, contrôle de l'origine, validation du prix mensuel en EUR, vérification de signature du webhook sur le corps brut, synchronisation serveur et politiques RLS. Les migrations de facturation ont été appliquées au schéma Supabase, mais aucune Edge Function Stripe n'a été déployée, aucun secret marchand n'a été configuré et aucun paiement de test ou réel n'a été effectué. Le verrou de Checkout reste fermé.


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
Les migrations SQL du socle social, des notifications, de la découverte, de la messagerie, de la modération, du portfolio, du Studio, de la filiation, de la suppression propriétaire et de la facturation sont maintenant appliquées au projet Supabase. L'Edge Function musea-ai est active. Stripe reste désactivé et n'a fait l'objet d'aucun paiement de test ou réel. Le Checkout reste verrouillé tant que les deux drapeaux serveur ne sont pas explicitement activés par le titulaire légal autorisé. La gestion d'un compte marchand, les contrats, les vérifications d'identité et la réception de fonds doivent être assumés par le représentant légal ou la structure habilitée selon les règles du prestataire.


## État réel du déploiement — 5 novembre 2026

- Projet Supabase Musea : actif, région eu-west-2.
- Edge Function musea-ai : active avec JWT obligatoire ; le code utilise OpenAI gpt-4.1-mini. Le test authentifié de bout en bout dépend de la présence et de la validité du secret serveur OPENAI_API_KEY et d'un compte utilisateur de test.
- Migrations appliquées : social_graph_compat, notifications, creative_discovery, discovery_controls, messaging_collaboration, moderation_trust, fair_moderation, creator_profiles_portfolio, creator_studio, creative_lineage, post_owner_delete, billing_core, billing_checkout_lock, billing_hardening, trigger_function_privileges et follow_graph_privacy.
- Stories : le schéma réel utilise caption et media_path ; l'interface a été alignée sur ce schéma. Les demandes d'abonnement privées et les abonnements publics utilisent user_follows.
- Stockage : les buckets musea-posts (public), musea-drafts (privé) et musea-stories (privé) existent.
- La PWA Android/iOS est installable depuis un navigateur compatible. Aucun APK natif signé ni IPA n'est produit par ce dépôt.
- Les contrôles Supabase signalent encore des avertissements de performance RLS et plusieurs fonctions SECURITY DEFINER accessibles aux utilisateurs authentifiés. Les fonctions de trigger-only ont été retirées des rôles API ; les autres fonctions privilégiées restent à auditer individuellement avant ouverture publique.
- Les migrations n'ont pas toutes été exécutées sur une base vierge : le projet contenait déjà un schéma préexistant sans historique de migrations. Les opérations ont été appliquées en mode compatible avec les tables et données déjà présentes.


## Paiements — état au 5 novembre 2026

Les fonctions `create-checkout-session`, `create-billing-portal` et `stripe-webhook` sont déployées dans Supabase. Checkout est strictement limité à une clé Stripe de test (`sk_test_`) et à un compte explicitement validé par un titulaire majeur dans la table serveur `billing_checkout_eligibility`. Cette table n'est pas modifiable par les comptes utilisateurs. Sans cette validation, sans les secrets serveur et sans le prix Stripe de test, Checkout refuse la demande.

Secrets serveur attendus, à saisir par le titulaire majeur dans le gestionnaire de secrets Supabase (ne jamais les placer dans le dépôt GitHub ni dans le navigateur) :
- `STRIPE_SECRET_KEY` : clé secrète Stripe de test, commençant par `sk_test_`.
- `STRIPE_WEBHOOK_SIGNING_SECRET` : secret de signature du webhook Stripe de test.
- `STRIPE_PRICE_SIGNATURE_MONTHLY` : identifiant du prix mensuel Stripe de test.
- `MUSEA_BILLING_ENABLED` : valeur `true` uniquement après validation de la configuration de test.

Le webhook Stripe doit écouter : `checkout.session.completed`, `checkout.session.expired`, `customer.subscription.created`, `customer.subscription.updated`, `customer.subscription.deleted`, `invoice.paid` et `invoice.payment_failed`. L'URL est l'endpoint Supabase de la fonction `stripe-webhook`. Le portail et Checkout exigent un JWT valide. Aucun secret marchand n'a été configuré par cette mise à jour ; aucun paiement réel n'est possible.


### Mise à jour du parcours de paiement

- Migration `billing_adult_eligibility` appliquée au projet Supabase.
- `create-checkout-session` déployée en version 2, JWT obligatoire ; uniquement une clé Stripe test `sk_test_`, un prix de test configuré et le drapeau serveur `MUSEA_BILLING_ENABLED=true` peuvent l'activer.
- La table `billing_checkout_eligibility` est inaccessible à `anon` et `authenticated`. Seul `service_role` peut y lire/écrire. L'accès au Checkout est refusé par défaut, jusqu'à une validation adulte effectuée hors du navigateur.
- Le verrou de Checkout est conservé jusqu'à la réception d'un webhook `checkout.session.completed` ou `checkout.session.expired`.
- `create-billing-portal` déployée avec JWT obligatoire ; `stripe-webhook` déployée sans JWT Supabase, mais avec vérification cryptographique de la signature Stripe.
- Le bouton Signature appelle désormais le Checkout de test et valide strictement le domaine de redirection.
- Les secrets Stripe, le prix Stripe de test et la configuration du webhook ne sont pas encore renseignés. Aucun paiement réel ne peut être déclenché.


## Stripe — environnement sandbox isolé (mise à jour du 5 novembre 2026)

L'environnement choisi pour MUSEA V3 est le compte séparé **« environnement de test Musea »** (`acct_1UYNbP0CmLAIBoiD`). Toutes les opérations réalisées dans cette étape ont été faites avec `livemode=false`. Aucun produit, prix, client, abonnement, webhook ou paiement n'a été créé dans le compte réel.

Catalogue de test créé :
- Produit : **MUSEA Signature** — `prod_VZZ9fHcMjUUCYI`.
- Tarif : **5,99 EUR par mois** — `price_1UYQ1B0CmLAIBoiDXKzhou3g`.
- Portail client : configuration par défaut **MUSEA Signature — portail test** — `bpc_1UYQ1H0CmLAIBoiDHzWxSoed`. Le client peut modifier ses coordonnées, mettre à jour son moyen de paiement, consulter ses factures et résilier à la fin de la période. Les changements d'offre sont désactivés tant qu'une deuxième formule n'existe pas.

Les trois Edge Functions de facturation sont actives et renforcées :
- `create-checkout-session` : JWT obligatoire, clé `sk_test_` uniquement, vérification du prix actif (EUR, mensuel, montant positif), verrou atomique et validation adulte préalable.
- `create-billing-portal` : JWT obligatoire et refus des clés Stripe live.
- `stripe-webhook` : JWT Supabase désactivé pour permettre l'appel Stripe, mais signature cryptographique obligatoire et clé Stripe test uniquement.

Secrets et variables encore à configurer côté Supabase par le titulaire majeur du compte marchand :
- `STRIPE_SECRET_KEY` : clé secrète de test `sk_test_...`.
- `STRIPE_WEBHOOK_SIGNING_SECRET` : secret de signature du webhook de test.
- `STRIPE_PRICE_SIGNATURE_MONTHLY` : `price_1UYQ1B0CmLAIBoiDXKzhou3g`.
- `MUSEA_BILLING_ENABLED=true` et `MUSEA_MERCHANT_READY=true` uniquement après validation de la configuration de test par le titulaire majeur.
- Les variables Supabase natives doivent rester configurées par Supabase ; aucune clé privilégiée ne doit être publiée dans GitHub.

Le webhook Stripe n'est pas encore créé, car son secret de signature doit être enregistré immédiatement et de façon sécurisée dans Supabase. Il devra écouter `checkout.session.completed`, `checkout.session.expired`, `customer.subscription.created`, `customer.subscription.updated`, `customer.subscription.deleted`, `invoice.paid` et `invoice.payment_failed`, sur `https://dujargvriuxwczkgsyua.supabase.co/functions/v1/stripe-webhook`.

**État :** le catalogue Stripe et le portail test sont créés ; les fonctions sont déployées en versions renforcées. Les secrets, le webhook, le test authentifié de bout en bout et la validation adulte restent à faire. Le Checkout demeure fermé par défaut. Aucun paiement réel n'est possible depuis cette configuration.
