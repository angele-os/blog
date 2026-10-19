# CLAUDE.md — blog (angele-os/blog)

Instructions pour Claude Code. À lire au début de chaque conversation.

## Le projet

Blog statique d'Ange Bonkoski, étudiant en BUT Informatique parcours DACS
(réseaux et cybersécurité), qui cherche un stage. Deux types d'articles :

- **journal** : récits du homelab (serveur ZimaOS auto-hébergé) ;
- **writeups** : write-ups de labs de cybersécurité.

En ligne sur https://journal.ange-bonkoski.fr/ (GitHub Pages, déployé par GitHub Actions).
Langue du site : français uniquement.

## Comment on travaille

- Ange ne sait pas coder : **tu écris le code, il cherche à le comprendre.**
  Commente le code en français, simplement, en expliquant le *pourquoi*.
- **Une étape du plan par conversation**, en Plan Mode. Présente ton plan,
  attends la validation, puis code.
- À la fin de chaque étape, donne : ce qui a changé, comment le tester,
  et un message de commit au format **Conventional Commits** en français
  (ex. `feat: ajoute le gabarit d'article`).
- **Ange fait lui-même les commits et les push.** Ne lance jamais
  `git commit`, `git push` ni aucune commande qui modifie l'historique.
- Il travaille sur un **PC Windows** (PowerShell, VS Code) et parfois sur un
  **Mac**. Précise toujours où lancer une commande.

## Règles techniques (non négociables)

1. **Hugo uniquement** (édition extended). Aucune dépendance npm, pas de
   `package.json`, pas de thème téléchargé : le thème est écrit à la main
   dans `layouts/` et `assets/`.
2. **Zéro JavaScript** dans le site publié. Si une fonction semble en
   exiger, propose d'abord une solution en HTML/CSS et demande avant.
3. **Rien d'externe** : pas de CDN, pas de Google Fonts, pas d'analytics,
   pas de commentaires tiers, pas d'iframe. Polices, images et CSS sont
   servis depuis le site.
4. **CSP stricte** via `<meta http-equiv="Content-Security-Policy">` :
   `default-src 'none'; style-src 'self'; img-src 'self'; font-src 'self';
   base-uri 'none'; form-action 'none'`. Donc **aucun style en ligne**
   (`style="..."`) : la coloration du code utilise des classes CSS
   (`markup.highlight.noClasses = false`), jamais des styles en ligne.
5. **Fins de ligne LF** pour tous les fichiers (voir `.gitattributes`).
   Les scripts shell doivent tourner sous Linux (CI) et Git Bash (Windows).
6. Le site doit rester lisible et accessible : HTML sémantique, contrastes
   AA, navigation au clavier, `prefers-reduced-motion` respecté.

## Confidentialité (le plus important)

Ce dépôt est **public**. Ne mets jamais dans un fichier versionné :

- d'adresse IP privée (192.168.x.x, 10.x.x.x, 172.16-31.x.x) ni d'adresse
  Tailscale (100.64.0.0/10) ;
- d'URL de webhook (Discord ou autre), de jeton, de clé, de mot de passe ;
- de nom d'hôte interne, de nom de compte réel du serveur, de chemin
  système précis du serveur s'il n'apporte rien à l'article.

Les brouillons vivent dans `brouillons/` (ignoré par Git).
La DEX (document d'exploitation du serveur) est interne : ne jamais la
copier dans le dépôt, même en partie, sans version expurgée.
Les images ne doivent contenir aucune métadonnée EXIF.

## Structure visée

```
hugo.toml              configuration du site
content/
  journal/             articles du homelab
  writeups/            write-ups de labs
  a-propos.md
layouts/               gabarits du thème maison
assets/css/            CSS (traité par Hugo, empreinte dans le nom)
static/fonts/          Instrument Sans (woff2, hébergée localement)
static/img/            favicon, image de partage
scripts/               garde-fous (anti-fuite, EXIF)
.github/workflows/     construction, vérifications, déploiement
```

## En-tête d'un article (front matter)

```yaml
title: "Titre de l'article"
date: 2026-10-18
summary: "Une ou deux phrases pour la liste et l'aperçu de partage."
tags: ["docker", "tailscale"]
# writeups uniquement :
plateforme: "TryHackMe"
difficulte: "facile"   # facile | moyen | difficile
```

## Identité visuelle

Reprendre celle du portfolio v2 d'Ange (ange-bonkoski.fr) : couleurs
sobres et épurées, police Instrument Sans, effet « liquid glass » léger
réservé à l'en-tête et aux cartes. Pour un blog, la lisibilité du texte
long passe avant les effets. Mode clair et sombre automatiques.
