---
title: "Mon coffre de mots de passe ne répondait plus, et le réseau n'y était pour rien"
slug: "le-reseau-n-y-etait-pour-rien"
date: 2026-10-19T09:00:00+02:00
summary: "Extension et application refusaient de se connecter à mon Vaultwarden, alors que le site web marchait. J'ai accusé Cloudflare pendant des heures. La vraie cause : un contrat de version rompu, et une image Docker figée sans que je le sache."
tags: ["homelab", "vaultwarden", "docker", "diagnostic"]
---

Le 20 septembre, mon gestionnaire de mots de passe auto-hébergé a
cessé de fonctionner… à moitié. Le coffre s'ouvrait parfaitement dans le
navigateur. Mais l'extension Firefox affichait une erreur obscure, et
l'application iPhone refusait de se connecter.

J'ai passé des heures à chercher dans la mauvaise direction. Cet article
raconte comment j'en suis sorti, et surtout la petite expérience qui a
tout débloqué.

## Le contexte

J'héberge **Vaultwarden** sur mon serveur maison. C'est une réécriture
légère du serveur de **Bitwarden** : on garde les applications officielles
de Bitwarden (extension, application mobile), mais elles parlent à mon
serveur plutôt qu'à celui de l'éditeur.

À l'époque, le trafic passait par Cloudflare, puis par un reverse proxy,
avant d'arriver au conteneur.

## Le symptôme

- **Le coffre web** : fonctionne.
- **L'extension Firefox** : `KDF config response does not contain a valid KDF type`.
- **L'application iOS** : « Nous ne sommes pas en mesure de traiter votre demande ».

Le KDF (*key derivation function*) est la fonction qui transforme le mot de
passe maître en clé de chiffrement. Le client demande au serveur quels
paramètres utiliser, puis fait le calcul lui-même. L'erreur disait donc :
« la réponse du serveur ne ressemble pas à ce que j'attends ».

## Pourquoi j'ai accusé le réseau

Ma première intuition : quelque chose entre le client et le serveur
abîmait la réponse. C'était plausible, car proxys et CDN modifient parfois
le trafic au passage. J'ai donc testé, une par une :

| Piste testée | Résultat |
|:-------------|:---------|
| Désactiver les protections anti-robots de Cloudflare | Aucun effet |
| Règle de pare-feu applicatif pour laisser tout passer | Aucun effet |
| Purger le cache Cloudflare | Aucun effet |
| Désactiver HTTP/3 et le 0-RTT | Aucun effet |
| Vérifier la compression de la réponse | JSON propre une fois décompressé |
| Corriger l'adresse publique déclarée dans la configuration | Vrai défaut, mais pas suffisant |

Chaque test prenait du temps, et aucun ne changeait rien.

## Le *friend test*

J'ai fini par emprunter le téléphone d'un proche. Il n'avait jamais été
connecté à mon réseau, ni à mon compte iCloud, ni à mon Firefox. J'y ai
installé l'application Bitwarden, je l'ai pointée vers mon serveur…

**Même erreur, exactement.**

Ce test a éliminé d'un coup toutes mes hypothèses réseau. Un problème
propre à mon infrastructure, à mon cache ou à mes appareils n'aurait pas
touché un téléphone neuf. Le problème venait de ce que **tous** les clients
avaient en commun : la version de l'application.

{{< lecon titre="Le friend test" >}}
Quand tout semble suspect, reproduisez le problème sur un appareil qui ne
partage **rien** avec les vôtres. S'il plante pareil, ce n'est ni votre
réseau, ni votre configuration locale.
{{< /lecon >}}

## La vraie cause : un contrat de version rompu

Pourquoi le coffre web, lui, fonctionnait-il ? Parce que Vaultwarden sert
**sa propre** interface web, compilée avec lui, à la même version. Elle
comprend forcément ses réponses. C'était le pire témoin possible.

L'extension et l'application, elles, sont publiées par Bitwarden et mises à
jour automatiquement par les magasins d'applications, sans aucun lien avec
mon serveur. Bitwarden avait fait évoluer la structure de la réponse KDF.
Les clients avaient adopté le nouveau format ; mon serveur ne le parlait
pas encore. Il fallait une version plus récente de Vaultwarden.

## Pourquoi la mise à jour n'a pas marché du premier coup

J'ai lancé la mise à jour du conteneur… et rien n'a changé. En relisant
mon fichier Compose, j'ai trouvé ceci :

```yaml
image: vaultwarden/server:1.36.0@sha256:<empreinte>
```

Docker peut désigner une image de deux façons :

- par une **étiquette** (`1.36.0`, `latest`) : un nom qui peut pointer vers
  une autre image demain ;
- par une **empreinte** (`sha256:…`) : l'identifiant exact d'une image,
  qui ne change jamais.

Quand les deux sont présentes, **l'empreinte l'emporte**. J'avais beau
télécharger de nouvelles versions, Docker relançait toujours la même image
figée. Une fois l'empreinte retirée et une version récente demandée,
l'extension et l'application se sont reconnectées immédiatement.

{{< attention titre="Épingler n'est pas une erreur, l'oublier si" >}}
Figer une image par son empreinte est une bonne pratique de sécurité : on
sait exactement ce qui tourne. Le piège, c'est de l'avoir fait sans s'en
souvenir. Depuis, chaque service a une politique d'image écrite : figé (et
mis à jour à la main) ou suivi automatiquement.
{{< /attention >}}

## Ce que j'en retiens

- **Vérifier la compatibilité client/serveur avant de chercher dans le
  réseau.** Quand des clients mis à jour automatiquement cassent, la version
  est le premier suspect.
- **Choisir un bon témoin.** Un client livré avec le serveur ne prouve rien
  sur les autres.
- **Lire le fichier réel avant de mettre à jour.** Ce que je croyais avoir
  configuré et ce qui était écrit n'étaient pas la même chose.
- **Changer une seule chose à la fois.** C'est ce qui m'a permis de repérer
  le seul vrai défaut parmi mes essais.
