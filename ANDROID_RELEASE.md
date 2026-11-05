# MUSEA Android — état de préparation

Le dépôt contient maintenant une configuration Capacitor et un workflow GitHub Actions
qui génère un projet Android, compile un APK de test et un bundle AAB.

- Application ID conservé : `io.github.raydaakhbech2_maker.twa`
- Nom : MUSEA
- Cible : Android 16 / API 36
- Technologie : Capacitor 8
- Publicités : désactivées ; aucun SDK publicitaire n'est inclus.
- Paiements : désactivés.
- Le code web est copié localement dans l'application via `scripts/prepare-web.mjs`.

## Compilation

Le workflow `.github/workflows/android-build.yml` se lance sur les changements concernés
ou manuellement depuis l'onglet Actions de GitHub. Il publie un artefact APK de test et AAB.

## Signature de publication

Sans clé de téléversement, le AAB produit n'est pas prêt à être envoyé sur Google Play.
La personne légalement autorisée à gérer l'éditeur doit créer et conserver une clé de
téléversement privée, puis configurer les secrets GitHub suivants dans Settings > Secrets
and variables > Actions :

- `MUSEA_ANDROID_KEYSTORE_BASE64` : contenu Base64 du fichier keystore
- `MUSEA_ANDROID_KEY_ALIAS`
- `MUSEA_ANDROID_KEYSTORE_PASSWORD`
- `MUSEA_ANDROID_KEY_PASSWORD`

Ne jamais committer le keystore, ses mots de passe ou les secrets dans le dépôt.
Ne jamais envoyer ces valeurs dans une conversation.

## Vérifications obligatoires avant publication

La compilation ne vaut pas validation Play Store. Il faut tester l'installation,
authentification, navigation, téléversements, autorisations, liens externes, suppression
de compte, signalement/blocage, comportement hors-ligne et appareils réels. Vérifier
également le formulaire de sécurité des données, la classification du contenu, la
politique de confidentialité et les informations de l'éditeur dans Play Console.

L'ID d'application doit rester identique après publication pour les mises à jour.
