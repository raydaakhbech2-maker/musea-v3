/**
 * MUSEA — configuration publicitaire centralisée.
 *
 * IMPORTANT :
 * - Les annonces sont volontairement désactivées.
 * - Ne pas initialiser de SDK publicitaire ni envoyer de requête publicitaire
 *   tant que ENABLED reste à false.
 * - Ne jamais placer de clé privée ou de secret dans ce fichier.
 * - Les identifiants AdMob seront ajoutés uniquement après choix/validation
 *   de l'architecture Android native et création du compte éditeur.
 */
(function (root) {
  "use strict";

  const ADS_CONFIG = Object.freeze({
    enabled: false,
    provider: "admob",
    mode: "disabled",
    placements: Object.freeze({
      feedNative: Object.freeze({ enabled: false, adUnitId: "" }),
      exploreNative: Object.freeze({ enabled: false, adUnitId: "" }),
      rewardedPoints: Object.freeze({ enabled: false, adUnitId: "" })
    }),
    privacy: Object.freeze({
      consentRequiredBeforeAdRequests: true,
      consentPlatform: "google-ump",
      personalizedAdsDefault: false
    })
  });

  root.MUSEA_ADS_CONFIG = ADS_CONFIG;
  root.MUSEA_ADS = Object.freeze({
    isEnabled: function () {
      return ADS_CONFIG.enabled === true &&
        ADS_CONFIG.mode === "production";
    },
    canRequestAds: function (consentGranted) {
      return this.isEnabled() && consentGranted === true;
    }
  });
})(typeof globalThis !== "undefined" ? globalThis : window);
