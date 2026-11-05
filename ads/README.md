# MUSEA — préparation publicitaire (annonces désactivées)

État actuel : **OFF**. Aucun emplacement publicitaire ne doit charger une annonce,
initialiser un SDK publicitaire ou effectuer de requête publicitaire.

## Configuration
- Fichier : `ads/ads-config.js`
- `enabled: false`
- Mode : `disabled`
- Emplacements prévus : fil natif, Explorer natif, vidéo récompensée.
- Identifiants publicitaires volontairement vides.

Le fichier est un contrat de configuration et n'est pas inclus dans le chargement
de la PWA actuelle : il n'a donc aucun effet sur l'application en production.

## Point d'architecture à résoudre avant l'intégration réelle

Le dépôt contient actuellement une PWA hébergée sur GitHub Pages, pas un projet
Android Gradle natif. Le SDK Google Mobile Ads / AdMob est un SDK Android natif ;
il ne suffit pas d'ajouter un script à `index.html`. Il faudra décider et vérifier
l'architecture du paquet Android (TWA ou application native/hybride) avant de
choisir la méthode d'affichage des annonces.

Si l'application Android utilise le SDK natif AdMob :
1. Créer/valider l'application dans le compte éditeur AdMob et récupérer l'App ID.
2. Ajouter la dépendance Google Mobile Ads au projet Android et déclarer l'App ID
   dans AndroidManifest.xml.
3. Intégrer Google UMP et traiter le consentement avant toute initialisation ou
   demande publicitaire, notamment pour l'EEE.
4. Utiliser exclusivement des annonces de test pendant le développement.
5. N'activer les annonces de production qu'après validation des politiques,
   de la confidentialité, du public visé et des tests.

## Règle d'activation future

Ne pas passer `enabled` à `true` avant que :
- l'architecture Android et la méthode publicitaire soient validées ;
- les identifiants d'application et d'emplacements soient attribués ;
- le consentement et les réglages de protection du public soient testés ;
- la politique de confidentialité et les déclarations de la boutique soient à jour ;
- une validation explicite du lancement publicitaire ait été donnée.

Ne jamais utiliser de vrais identifiants publicitaires dans les tests. Ne jamais
cliquer sur ses propres annonces. Les annonces récompensées ne doivent créditer
des points qu'après confirmation fiable de la récompense par le SDK/serveur.
