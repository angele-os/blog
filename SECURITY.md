# Politique de sécurité

Merci de prendre le temps de signaler un problème. Ce blog est un projet
personnel, maintenu par une seule personne, mais chaque signalement est lu
et traité.

## Ce qui est concerné

- le site <https://journal.ange-bonkoski.fr/> et le code de ce dépôt (gabarits,
  scripts, configuration, workflows GitHub Actions) ;
- **une information sensible publiée par erreur** dans un article : adresse IP,
  nom de machine, capture d'écran révélant une configuration, métadonnées
  d'une image, etc. C'est le cas le plus probable sur un blog de homelab, et
  il est tout aussi bienvenu.

Hors périmètre : GitHub Pages lui-même, les sites vers lesquels le blog fait
un lien (merci de les contacter directement), et les rapports produits
uniquement par un outil automatique sans démonstration d'un risque réel.

## Comment signaler

**N'ouvrez pas d'issue publique** : elle serait visible par tous avant
la correction.

Utilisez le signalement privé de GitHub :

1. onglet **Security** du dépôt, puis **Report a vulnerability** ;
   lien direct : <https://github.com/angele-os/blog/security/advisories/new>
2. décrivez :
   - ce que vous avez trouvé et où (adresse de la page, fichier, ligne) ;
   - comment le reproduire ;
   - l'impact possible selon vous.

Le message n'est visible que par vous et par moi.

## Ce qui se passe ensuite

- **sous 7 jours** : une première réponse pour confirmer la réception ;
- dès que possible : la correction ou le retrait de l'information, puis une
  réponse pour vous en informer ;
- si vous le souhaitez, vous êtes remercié(e) dans la note de correction.

Merci de ne pas divulguer le problème publiquement avant sa correction.

## Ce que le site fait déjà pour limiter les risques

- aucun JavaScript, aucune ressource externe, aucun formulaire, aucun cookie ;
- une politique de sécurité du contenu (CSP) stricte et une politique de
  référent `no-referrer` ;
- avant chaque publication, des vérifications automatiques refusent les
  adresses IP, jetons, clés, webhooks et métadonnées d'images
  (`scripts/verifier-fuites.sh`, `scripts/verifier-exif.sh`,
  `scripts/verifier-csp.sh`).
