# Stripe Checkout — MUSEA

## État vérifié au 5 novembre 2026

Le dépôt contient déjà un appel Stripe Checkout dans la fonction Supabase `create-checkout-session` : scénario A. Le code utilise `npm:stripe@^22` ; selon la règle de version du SDK, `ui_mode` attendu est `hosted_page`.

**État d'exécution :** la version actuellement déployée est la version 8. Une tentative de déploiement de la mise à jour demandée a été bloquée par un contrôle de sécurité de la plateforme. Les paramètres listés ci-dessous sont donc les paramètres à appliquer, et non une confirmation qu'ils sont déjà actifs en production.

## Valeurs conservées (scénario A)

Les valeurs réelles déjà présentes dans le code sont conservées :
- `mode`: `subscription` (abonnement mensuel MUSEA Signature)
- `line_items`: tarif lu depuis `STRIPE_PRICE_SIGNATURE_MONTHLY`, quantité 1
- `success_url`: `https://raydaakhbech2-maker.github.io/musea-v3/?billing=success&session_id={CHECKOUT_SESSION_ID}`
- `cancel_url`: `https://raydaakhbech2-maker.github.io/musea-v3/?billing=cancelled`

Aucun de ces paramètres n'est un placeholder. Aucun identifiant de prix ou secret ne doit être codé en dur.

## Paramètres Checkout Studio à appliquer

Fichier : `supabase/functions/create-checkout-session/index.ts` (fonction déployée via Supabase Edge Functions).

| Paramètre | Valeur attendue |
|---|---|
| `ui_mode` | `hosted_page` (SDK Stripe ^22) |
| `billing_address_collection` | `auto` |
| `phone_number_collection` | `{ enabled: false }` |
| `automatic_tax` | `{ enabled: false }` |
| `allow_promotion_codes` | `false` |
| `payment_method_collection` | `always` (car `mode=subscription`) |
| `submit_type` | `auto` |
| `integration_identifier` | `hosted_web_0002` |
| `origin_context` | `web` |

## Configuration et fonctionnement

- Les secrets serveur restent dans le coffre Supabase : `STRIPE_SECRET_KEY`, `STRIPE_PRICE_SIGNATURE_MONTHLY`, `SUPABASE_SERVICE_ROLE_KEY` et les autres variables Supabase nécessaires.
- Ne jamais exposer `STRIPE_SECRET_KEY` dans le frontend ni utiliser un préfixe `VITE_` pour ce secret.
- Le frontend authentifié appelle `create-checkout-session`; la fonction vérifie l'utilisateur, l'éligibilité, le tarif mensuel et l'existence d'un abonnement, puis crée une session Checkout hébergée par Stripe.
- Le webhook synchronise les abonnements et factures dans Supabase. Le portail client est fourni par `create-billing-portal`.

## Tests et étapes restantes

1. Appliquer les paramètres attendus ci-dessus à l'appel existant puis redéployer la fonction.
2. Garder le mode test et les verrous d'éligibilité existants ; ne pas activer de paiements réels ni contourner une validation du titulaire.
3. Faire valider l'éligibilité du compte marchand par la personne légalement autorisée, puis tester le cycle complet avec des cartes de test Stripe : succès `4242 4242 4242 4242`, refus `4000 0000 0000 0002`, date future et CVC à 3 chiffres.
4. Vérifier la création d'abonnement, les webhooks, l'attribution Premium uniquement après confirmation serveur, les échecs, annulations, remboursements et litiges.
5. Le webhook actuel traite `checkout.session.completed`, `checkout.session.expired`, `customer.subscription.*`, `invoice.paid` et `invoice.payment_failed`. Les traitements de remboursement, litige et alerte de fraude restent à ajouter et tester avant d'abonner ces événements au webhook.
6. Configurer et tester le Customer Portal dans Stripe.

## Sécurité et mise en production

Le déploiement existant reste limité aux clés Stripe de test et les interrupteurs de facturation/validation marchand restent verrouillés. Ne retire pas ces protections. La mise en production exige une revue juridique/fiscale, une validation du compte marchand par son titulaire autorisé, des clés/prix/webhooks live distincts et des tests complets.

## Ressources

- [Stripe Checkout](https://docs.stripe.com/checkout)
- [Stripe Billing et abonnements](https://docs.stripe.com/billing/subscriptions)
- [Webhooks Stripe](https://docs.stripe.com/webhooks)
- [Clés API Stripe](https://dashboard.stripe.com/apikeys)
- [Support Stripe](https://support.stripe.com)
- [Documentation Stripe MCP](https://docs.stripe.com/mcp)
