# blog

Code source de <https://blog.ange-bonkoski.fr/> : le journal de mon homelab et
mes write-ups de labs de cybersécurité.

Site statique construit avec [Hugo](https://gohugo.io/) (édition extended),
avec un thème écrit à la main : aucun JavaScript, aucune ressource externe,
une politique de sécurité du contenu (CSP) stricte.

## Lancer le site en local

```bash
hugo server        # puis ouvrir http://localhost:1313/
hugo server -D     # en affichant aussi les brouillons
```

## Vérifications avant publication

À lancer depuis Git Bash (Windows) ou un terminal (Linux, macOS) :

```bash
bash scripts/verifier-fuites.sh   # IP, jetons, clés, webhooks
bash scripts/verifier-exif.sh     # métadonnées EXIF / XMP des images
hugo --gc --minify && bash scripts/verifier-csp.sh   # respect de la CSP
bash scripts/verifier-accessibilite.sh               # titres, alt, langue… (après hugo)
bash scripts/verifier-liens.sh                       # liens internes (après hugo)
```

## Publication

Le workflow [.github/workflows/site.yml](.github/workflows/site.yml) tourne à
chaque push et pull request : il installe Hugo extended et gitleaks (versions
épinglées, sommes de contrôle vérifiées), lance tous les garde-fous, construit
le site et vérifie la CSP, l'accessibilité et les liens. Sur `main`, si tout
est vert, il publie le site sur GitHub Pages.

Les actions sont épinglées par SHA et mises à jour par Dependabot
([.github/dependabot.yml](.github/dependabot.yml)). Hugo et gitleaks se
mettent à jour à la main, dans les variables en tête du workflow.

Réglages GitHub (une seule fois) :

- **Settings → Pages** : Source « GitHub Actions » ; domaine personnalisé
  `blog.ange-bonkoski.fr` ; « Enforce HTTPS ».
- **DNS** du domaine : enregistrement `CNAME` de `blog` vers `angele-os.github.io`.
- **Settings → Environments → github-pages** : déploiement limité à la branche `main`.
- **Settings → Rules** : sur `main`, exiger que « Construire et vérifier » réussisse.

## Sécurité

Pour signaler un problème, voir [SECURITY.md](SECURITY.md).

## Licences

- **Articles** (textes et images de `content/`) : [CC BY 4.0](LICENSE-CONTENU)
- **Code** : [MIT](LICENSE)
- **Police** Instrument Sans : [SIL OFL 1.1](static/fonts/OFL.txt)
- **Logo, favicon et image de partage** : tous droits réservés

Le détail est en tête du fichier [LICENSE-CONTENU](LICENSE-CONTENU).
