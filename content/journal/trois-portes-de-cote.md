---
title: "En installant un simple partage de fichiers, j'ai trouvé trois portes de côté"
slug: "trois-portes-de-cote"
date: 2026-10-19T10:00:00+02:00
summary: "Je voulais juste regarder mes vidéos depuis mon Mac. En configurant le partage SMB, j'ai découvert trois accès que je n'avais jamais documentés, dont un qui contournait tout mon durcissement SSH."
tags: ["homelab", "smb", "zimaos", "sécurité", "moindre-privilège"]
---

La veille, j'avais fini de durcir l'accès SSH à mon serveur : connexion par
clé uniquement, mots de passe interdits, un seul compte autorisé. J'en
étais assez fier.

Le lendemain, je voulais quelque chose de beaucoup plus banal : regarder
mes vidéos depuis le Mac et l'iPhone, via un partage de fichiers SMB. En
le configurant proprement, je suis tombé sur **trois portes** que je
n'avais jamais notées nulle part. L'une d'elles rendait mon travail de la
veille inutile.

## Porte n°1 : le partage « admin » qui voyait tout

Mon serveur tourne sous ZimaOS. Son interface crée automatiquement un
partage SMB pour le compte d'administration. Je ne m'en étais jamais
soucié : je l'utilisais pour transférer des fichiers depuis mon PC.

En le regardant de près, j'ai découvert qu'il donnait accès **à tous les
disques, en écriture**, y compris la partition qui contient les données des
conteneurs, les fichiers de configuration… et le fichier `authorized_keys`,
celui qui liste les clés SSH autorisées.

J'ai vérifié en le listant avec `smbclient` et le seul mot de passe du
compte d'administration. Il était bien là, lisible et modifiable.

Autrement dit : quelqu'un qui connaissait ce mot de passe pouvait
**ajouter sa propre clé** par SMB, puis se connecter en SSH. Mon « SSH par
clé uniquement » se contournait par la porte d'à côté.

{{< lecon >}}
Un durcissement ne vaut que si **toutes** les portes vers la même
ressource sont fermées. Protéger SSH ne sert à rien si un autre service
permet de modifier les clés de SSH.
{{< /lecon >}}

## Porte n°2 : les lecteurs réseau toujours branchés

Sur mon PC Windows, deux lecteurs réseau étaient connectés en permanence
avec ce même compte d'administration : l'un vers le disque externe, l'autre
vers la partition de données du serveur.

C'est exactement le scénario qu'exploitent les **rançongiciels** : ils
chiffrent tout ce qu'ils trouvent, y compris les lecteurs réseau. Un
simple fichier piégé ouvert sur le PC aurait pu chiffrer le serveur, et
avec lui… les données de mes sauvegardes.

## Porte n°3 : un deuxième accès distant que je n'avais pas choisi

En nettoyant les identifiants mémorisés sur mon PC, j'en ai trouvé un pour
une adresse que je ne connaissais pas. En remontant la piste : **ZeroTier**,
un réseau privé virtuel installé et activé par ZimaOS pour son application
« Zima Client ».

J'utilisais déjà Tailscale comme unique accès distant, volontairement.
ZeroTier était un **deuxième** chemin vers le serveur, géré par l'éditeur,
que je n'avais jamais décidé d'ouvrir.

## Ce que j'ai fait

**Des comptes dédiés, avec le minimum de droits.** Au lieu du compte
d'administration, deux comptes de partage, sans accès SSH ni shell :

| Compte | Accès | Usage |
|:-------|:------|:------|
| Lecture | un seul dossier (les vidéos), **lecture seule** | mémorisé sur le PC, le Mac et l'iPhone |
| Dépôt | le dossier de sauvegarde, lecture-écriture | connecté **seulement pendant un transfert**, mot de passe jamais mémorisé |

Le compte de lecture peut rester branché en permanence : un rançongiciel
ne peut rien chiffrer avec. Le compte de dépôt, lui, n'existe sur le PC que
quelques minutes à la fois.

**Désactiver le compte SMB d'administration.** Une commande suffit :

```bash
sudo smbpasswd -d admin   # -d : désactive le compte Samba, sans le supprimer
```

Mais ZimaOS **le réactive à chaque redémarrage**. J'ai donc écrit un petit
script, lancé par un timer systemd 3 minutes après le démarrage puis toutes
les 10 minutes. Il redésactive le compte si besoin, vérifie que c'est bien
fait, et me prévient sur Discord quand il a dû intervenir.

{{< attention titre="Les systèmes qui se « réparent » tout seuls" >}}
Sur un système qui régénère sa configuration au démarrage, une correction
faite à la main peut disparaître sans prévenir. Il faut soit la rendre
persistante, soit la réappliquer automatiquement, et surtout le
**vérifier après un redémarrage**.
{{< /attention >}}

**Débrancher les lecteurs du PC**, et ne plus jamais connecter le compte
d'administration depuis un poste.

**Retirer ZeroTier** : le serveur a quitté le réseau, et le service a été
masqué pour qu'il ne puisse plus redémarrer, même par erreur.

## Vérifier, avec des tests écrits

J'ai ensuite déroulé une série de tests, notés un par un : chaque compte
voit-il seulement ce qu'il doit voir ? Le compte de lecture peut-il écrire ?
Les partages sont-ils joignables depuis Internet sans Tailscale ? Le compte
d'administration est-il bien désactivé après un redémarrage ? Tous les
tests sont passés, depuis le PC, le Mac et l'iPhone.

## Ce que j'en retiens

- **Inventorier les accès, pas seulement les sécuriser.** On ne peut pas
  fermer une porte qu'on ne sait pas exister.
- **Le moindre privilège, concrètement :** un compte par usage, et le
  minimum de droits pour cet usage.
- **Se méfier de ce qu'une plateforme active « pour vous ».** Une
  fonctionnalité pratique est aussi une surface d'attaque.
- **Penser comme un attaquant :** « si j'avais ce mot de passe, jusqu'où
  irais-je ? » C'est cette question qui a fait apparaître la porte n°1.
