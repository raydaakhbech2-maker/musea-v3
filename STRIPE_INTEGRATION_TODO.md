# Stripe Checkout — MUSEA

## État vérifié au 5 novembre 2026

La fonction Supabase `create-checkout-session` est déployée en version 8. Le parcours reste volontairement limité au mode test et verrouillé tant que les contrôles du compte marchand et l'éligibilité du titulaire ne sont pas validés.

## Paramètres Checkout déployés

- `ui_mode`: `hosted` (page Checkout hébergée par Stripe)
- `integration_identifier`: `musea_web_aBcdEfGh` (paramètre de premier niveau)
- `mode`: `subscription`
- `line_items`: tarif mensuel lu depuis `STRIPE_PRICE_SIGNATURE_MONTHLY`, quantité 1
- `success_url`: `https://raydaakhbech2-maker.github.io/musea-v3/?billing=success&session_id={CHECKOUT_SESSION_ID}`
- `cancel_url`: `https://raydaakhbech2-maker.github.io/musea-v3/?billing=cancelled`
- `billing_address_collection`: `auto`
- `phone_number_collection.enabled`: `false`
- `automatic_tax.enabled`: `false` (ne pas activer sans avoir vérifié les immatriculations fiscales requises)
- `allow_promotion_codes`: `false`
- `payment_method_collection`: `always`
- Aucun `payment_method_types` forcé : Stripe conserve les moyens de paiement dynamiques.

Les contrôles existants ont été conservés : session Supabase authentifiée, vérification d'éligibilité adulte côté serveur, absence d'abonnement en cours, verrou anti-doublon, vérification du prix et du client Stripe, idempotence.

## Fonctions Supabase

| Fonction | Version | Contrôle |
|---|---:|---|
| `create-checkout-session` | 8 | JWT requis, clé Stripe test uniquement, double verrou marchand/éligibilité |
| `create-billing-portal` | 5 | JWT requis, clé Stripe test uniquement, client Stripe lié à l'utilisateur |
| `stripe-webhook` | 6 | JWT désactivé pour Stripe, signature vérifiée, clé test uniquement |

## Webhooks et limites actuelles

Le webhook traite actuellement les événements de cycle de vie suivants : `checkout.session.completed`, `checkout.session.expired`, `customer.subscription.*`, `invoice.paid` et `invoice.payment_failed`. Il vérifie la signature, gère l'idempotence et synchronise abonnements/factures.

**Avant un lancement commercial**, il reste nécessaire d'ajouter et de traiter explicitement les événements de risque pertinents (`charge.dispute.created`, `charge.refunded`, `radar.early_fraud_warning.created`), de vérifier le comportement de résiliation et de réconciliation, puis de tester tout le cycle de vie avec des événements Stripe de test. Ils ne doivent pas être activés dans le Dashboard tant que leur traitement applicatif n'est pas prêt.

Le portail client dépend également de la configuration du Customer Portal dans Stripe. Il n'a pas encore été validé par une session de bout en bout.

## Tests non réalisés

Aucun paiement Checkout de test complet n'a encore été réalisé. Les drapeaux `MUSEA_BILLING_ENABLED` et `MUSEA_MERCHANT_READY` restent désactivés et aucune ligne d'éligibilité adulte n'est enregistrée. C'est intentionnel : ne pas créer de faux justificatif ni contourner ces contrôles.

Une fois le parcours de test autorisé par le représentant responsable, tester au minimum :
1. création de session Checkout et retour vers MUSEA ;
2. abonnement créé puis synchronisé par webhook ;
3. facture payée et facture échouée ;
4. annulation depuis le Customer Portal et mise à jour du statut ;
5. événements dupliqués, reçus dans le désordre et signatures invalides ;
6. absence d'accès Premium avant confirmation serveur de l'abonnement.

Cartes de test Stripe uniquement : succès `4242 4242 4242 4242`, refus `4000 0000 0000 0002`, avec date future et CVC à 3 chiffres.

## Conditions préalables à toute mise en production

- Le représentant légalement autorisé doit confirmer auprès de Stripe que l'entité, le représentant et l'activité sont correctement déclarés et autorisés.
- Vérifier les conditions applicables à la vente d'abonnements, aux renouvellements, à la résiliation, aux remboursements, à la confidentialité et à la fiscalité.
- Préparer un tarif et un webhook distincts en environnement live, puis effectuer une revue de sécurité et des tests de bout en bout avant toute activation.
- Examiner les événements de risque et le mécanisme d'attribution/révocation des droits Premium.
- Envisager une clé API restreinte avec le minimum de permissions nécessaires ; conserver les secrets exclusivement dans le coffre Supabase.

**Sécurité :** cette version reste bloquée en mode test. Ne pas retirer le contrôle `sk_test_`, ne pas activer les interrupteurs et ne pas inscrire artificiellement un utilisateur comme adulte vérifié. Le fait que Stripe affiche certaines capacités actives ne remplace pas la validation légale du titulaire ni la revue de mise en production.

## Références

- [Stripe Checkout](https://docs.stripe.com/checkout)
- [Stripe Billing et abonnements](https://docs.stripe.com/billing/subscriptions)
- [Webhooks Stripe](https://docs.stripe.com/webhooks)
- [Stripe Tax — abonnements](https://docs.stripe.com/billing/taxes/collect-taxes)
- [Tableau de bord Stripe](https://dashboard.stripe.com/)
