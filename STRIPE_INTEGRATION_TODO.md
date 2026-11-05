# Stripe Checkout — MUSEA

## Values to Replace

Aucun placeholder de Checkout n'a été trouvé dans l'appel existant.

Les valeurs existantes ont été conservées :
- `mode` : `subscription` (abonnement récurrent)
- `success_url` : `https://raydaakhbech2-maker.github.io/musea-v3/?billing=success`
- `cancel_url` : `https://raydaakhbech2-maker.github.io/musea-v3/?billing=cancelled`
- `line_items[].price` : récupéré depuis le secret Supabase `STRIPE_PRICE_SIGNATURE_MONTHLY` ; aucun identifiant fictif n'a été introduit.

## Configured Parameters

**Fichier serveur :** fonction Supabase `create-checkout-session` (Edge Function, version 7).

| Paramètre | Valeur configurée |
|---|---|
| `ui_mode` | `hosted_page` |
| `billing_address_collection` | `auto` |
| `phone_number_collection.enabled` | `false` |
| `automatic_tax.enabled` | `false` |
| `allow_promotion_codes` | `false` |
| `payment_method_collection` | `always` |
| `submit_type` | `auto` |
| `integration_identifier` | `hosted_web_0001` (conservé dans les métadonnées de session) |
| `origin_context` | `web` (conservé dans les métadonnées de session) |

Les paramètres techniques existants nécessaires au fonctionnement de MUSEA (`customer`, `client_reference_id`, métadonnées d'identification et clé d'idempotence) ont été conservés.

## Setup et prérequis

Les secrets sont gérés côté serveur dans Supabase — ne les placez jamais dans le code du navigateur et ne les partagez pas dans un message.

La fonction utilise :
- `STRIPE_SECRET_KEY` : clé secrète Stripe de test (`sk_test_...`)
- `STRIPE_PRICE_SIGNATURE_MONTHLY` : identifiant du tarif mensuel Stripe de test
- `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`
- `MUSEA_BILLING_ENABLED` et `MUSEA_MERCHANT_READY` : interrupteurs de mise en service

Le SDK Stripe est importé dans la fonction avec `npm:stripe@^22`. Aucun SDK navigateur ni nouvelle dépendance n'a été ajouté.

## Fonctionnement

1. L'utilisateur connecté demande l'abonnement depuis MUSEA.
2. La fonction vérifie sa session, son adresse e-mail, les verrous de paiement et l'éligibilité enregistrée.
3. Elle récupère ou crée le client Stripe associé à l'utilisateur.
4. Elle crée une Checkout Session d'abonnement et renvoie l'URL Stripe hébergée.
5. Les webhooks Stripe existants synchronisent l'abonnement et les factures dans Supabase.

## Tests

Effectuer les essais uniquement en mode test, avec une carte Stripe de test :
- Paiement réussi : `4242 4242 4242 4242`
- Date d'expiration future quelconque et CVC à 3 chiffres
- Paiement refusé : `4000 0000 0000 0002`

Utiliser une adresse e-mail de test et ne saisir aucune vraie carte bancaire en mode test. Vérifier ensuite le Checkout, l'événement `checkout.session.completed`, la création de l'abonnement et l'activation des droits Premium. Tester également annulation, renouvellement simulé et échec de paiement via les outils de test Stripe.

## Prochaines étapes avant toute mise en production

- Faire confirmer par le titulaire légalement autorisé que l'activité MUSEA et le représentant sont correctement déclarés auprès de Stripe.
- Vérifier avec Stripe les obligations applicables à l'activité, à la vente d'abonnements et aux informations consommateurs.
- Vérifier le tarif et le produit dans le compte Stripe de test, puis préparer leurs équivalents en mode réel seulement après autorisation.
- Faire contrôler les clés, le webhook, les événements et le parcours complet par le représentant autorisé.
- Réaliser une revue juridique et opérationnelle des conditions d'abonnement, renouvellement, résiliation, remboursements, confidentialité et fiscalité.

**Important :** cette fonction reste volontairement limitée au mode test. Elle refuse les clés live et conserve les contrôles d'éligibilité du titulaire majeur. Les interrupteurs de paiement et le contrôle d'éligibilité ne doivent pas être contournés. Le déploiement de cette configuration ne signifie pas que MUSEA est prêt à encaisser en réel.

## Structure du projet

Aucun nouveau fichier serveur ni nouvelle route n'a été ajouté. Le seul document créé par cette tâche est `STRIPE_INTEGRATION_TODO.md`.

## Ressources

- [Tableau de bord Stripe](https://dashboard.stripe.com/)
- [Documentation Stripe Checkout](https://docs.stripe.com/checkout)
- [Assistance Stripe](https://support.stripe.com/)
- [Documentation Stripe MCP](https://docs.stripe.com/mcp)
