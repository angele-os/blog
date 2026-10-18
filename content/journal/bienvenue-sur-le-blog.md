---
title: "Bienvenue sur le blog"
date: 2026-10-18
summary: "Premier article : pourquoi ce blog existe et ce que vous y trouverez."
tags: ["hugo", "homelab"]
---

Ce premier article sert d'exemple : il permet de vérifier que le site
s'affiche correctement, des titres jusqu'aux blocs de code.

## Ce que vous trouverez ici

- **Le journal** : les étapes de mon homelab, réussites comme erreurs ;
- **Les write-ups** : mes solutions commentées de labs de cybersécurité.

## Comment le blog est construit

Le site est généré par [Hugo](https://gohugo.io/), sans thème téléchargé
ni JavaScript. Pour le lancer en local :

```bash
hugo server
```

Puis on ouvre l'adresse affichée dans le terminal. La commande `hugo`
seule construit le site final dans le dossier `public/`.

> Le site ne charge rien depuis un autre serveur : polices, styles et
> images sont tous servis par le blog lui-même.

### Un script un peu plus long

Pour vérifier la coloration du code, voici un petit script de sauvegarde.
Les lignes 4 et 5 sont mises en évidence :

```bash {hl_lines=[4,5]}
#!/usr/bin/env bash
# Sauvegarde d'un dossier dans une archive datée
set -euo pipefail
source="$HOME/documents"
archive="sauvegarde-$(date +%F).tar.gz"
tar -czf "$archive" "$source"
echo "Archive créée : $archive ($(du -h "$archive" | cut -f1))"
```

{{< lecon >}}
Une sauvegarde qu'on n'a jamais **restaurée** n'est pas une sauvegarde :
tester la restauration fait partie du travail.
{{< /lecon >}}

{{< attention titre="Avant de lancer une commande trouvée en ligne" >}}
Lisez-la jusqu'au bout. Une commande comme `rm -rf` ne demande aucune
confirmation.
{{< /attention >}}

## Les deux types d'articles

| Type      | Contenu                           | Exemple            |
|:----------|:----------------------------------|-------------------:|
| Journal   | récit d'une étape du homelab      | installer Docker   |
| Write-up  | solution commentée d'un lab       | une box TryHackMe  |
