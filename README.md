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
```

## Sécurité

Pour signaler un problème, voir [SECURITY.md](SECURITY.md).

## Licences

- **Articles** (textes et images de `content/`) : [CC BY 4.0](LICENSE-CONTENU)
- **Code** : [MIT](LICENSE)
- **Police** Instrument Sans : [SIL OFL 1.1](static/fonts/OFL.txt)
- **Logo, favicon et image de partage** : tous droits réservés

Le détail est en tête du fichier [LICENSE-CONTENU](LICENSE-CONTENU).
