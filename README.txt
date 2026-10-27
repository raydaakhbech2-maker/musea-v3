# MUSEA — prototype PWA

## Contenu
- `index.html` : prototype interactif autonome
- `manifest.webmanifest` : métadonnées PWA
- `sw.js` : cache hors ligne minimal
- `README.txt` : instructions

## Tester rapidement
Ouvrir `index.html` dans un navigateur récent. Les interactions et réglages sont enregistrés localement dans le navigateur (localStorage). Aucun backend, compte réel, paiement ou service IA n'est connecté.

## Installer comme une application
Le mode PWA exige normalement une URL HTTPS. Héberge les fichiers à la racine d'un site HTTPS, puis :
- Android/Chrome : menu du navigateur > Installer l'application ou Ajouter à l'écran d'accueil.
- iPhone/iPad/Safari : bouton Partager > Sur l'écran d'accueil.

Cette archive ne contient pas d'APK Android ni d'IPA iOS. Pour publier sur Google Play/App Store, il faudra une vraie application native ou un wrapper testé, les comptes développeur, les politiques de confidentialité, la modération et les tests de conformité.

## À propos du navigateur intégré
L'écran « Web » est un prototype qui ouvre les URL dans le navigateur système. Il ne remplace pas Chrome/Opera GX et n'intègre pas un moteur de navigateur complet. Une vraie intégration mobile utiliserait Android WebView et iOS WKWebView, avec une UI d'onglets/favoris et une politique de sécurité spécifique. iOS impose WebKit dans les configurations ordinaires ; il n'est pas réaliste d'embarquer Opera GX complet dans une PWA.

## Points et certification
Les points, offres, thèmes et vérification sont des règles de démonstration. Le badge certifié doit être accordé uniquement après une vérification indépendante ; il ne peut pas s'acheter et les points ne garantissent pas son obtention.
