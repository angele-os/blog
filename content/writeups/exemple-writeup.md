---
# Article d'EXEMPLE pour tester le gabarit des write-ups.
# draft: true = brouillon : jamais publié sur le site en ligne,
# visible seulement en local avec « hugo server -D ».
draft: true
title: "Exemple de write-up"
date: 2026-10-18
summary: "Write-up fictif qui sert à vérifier l'affichage de la plateforme et de la difficulté."
tags: ["exemple"]
plateforme: "TryHackMe"
difficulte: "facile"   # facile | moyen | difficile
---

Ce write-up n'existe que pour tester l'affichage : plateforme, pastille de
difficulté et sommaire.

## Reconnaissance

On commence par lister les services ouverts :

```bash
nmap -sV -p- cible.exemple
```

## Exploitation

Étape fictive.

## Ce que j'en retiens

{{< lecon >}}
Toujours commencer par une reconnaissance complète avant d'attaquer
le premier service trouvé.
{{< /lecon >}}
