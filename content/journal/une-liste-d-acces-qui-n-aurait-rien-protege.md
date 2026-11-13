---
title: "La liste d'accès qui n'aurait rien protégé"
slug: "une-liste-d-acces-qui-n-aurait-rien-protege"
date: 2026-11-13T10:00:00+01:00
summary: "Pour que ma détection d'intrusion voie enfin le vrai trafic d'Internet, j'ai fait passer mon portfolio par mon reverse proxy. Avant de basculer, j'ai mesuré, et découvert que mon plan aurait laissé Internet entrer jusqu'à mon coffre."
tags: ["homelab", "reverse-proxy", "docker", "nat", "sécurité", "crowdsec"]
---

Depuis l'installation de [CrowdSec](/journal/crowdsec-le-test-qui-ne-prouvait-rien/),
j'avais un outil de détection d'intrusion… qui ne voyait presque rien. Mon
serveur n'a [aucun port ouvert](/journal/zero-port-ouvert/) : le seul
trafic venu d'Internet est celui de mon portfolio, et il arrivait
directement à son serveur web, sans laisser de journal que CrowdSec puisse
lire.

L'idée était simple : faire passer le portfolio par mon **reverse proxy**
(Nginx Proxy Manager, « NPM »). Ses journaux contiendraient alors les
vraies visites, et CrowdSec pourrait les analyser.

Le problème : ce même reverse proxy sert aussi mon coffre de mots de passe
et Guacamole, deux services qui ne doivent **jamais** être joignables
depuis Internet. Avant de mélanger les deux, il fallait être sûr que NPM
sache les distinguer.

## Le plan de départ

Les services privés sont protégés par une **liste d'accès** sur NPM :
seules les adresses du réseau local et de Tailscale sont autorisées, tout
le reste reçoit `403`.

Mon plan :

```text
Internet ──> Cloudflare ──> tunnel (cloudflared) ──> port publié de NPM ──> portfolio
Tailscale ──> relais Tailscale ──────────────────> port publié de NPM ──> coffre, Guacamole
```

La liste d'accès ferait le tri : le trafic du tunnel ne viendrait pas d'une
adresse autorisée, donc il ne pourrait pas atteindre le coffre. Sur le
papier, c'était propre.

## Mesurer avant de filtrer

Une liste d'accès filtre sur l'adresse **que le proxy voit**, pas sur celle
que je crois qu'il voit. Avant de basculer, j'ai donc lu les journaux
d'accès du coffre et de Guacamole, pour voir d'où arrivaient réellement mes
propres connexions Tailscale.

Toutes les lignes venaient de **la même adresse** : la passerelle du réseau
Docker de NPM. Ni l'adresse Tailscale de mon téléphone, ni celle de mon PC.

### Pourquoi : la traduction d'adresse de Docker

Quand on publie le port d'un conteneur (`ports:` dans un fichier Compose),
Docker ne branche pas directement le monde extérieur sur le conteneur. Il
**traduit** la connexion au passage (c'est de la NAT) : pour le conteneur,
elle semble venir de la passerelle de son réseau.

Le relais Tailscale entrait par le port publié de NPM. Toutes mes
connexions privées prenaient donc la même adresse de passerelle, et ma
liste d'accès devait autoriser cette passerelle, sinon je ne pouvais plus
ouvrir mon propre coffre.

### Ce que ça voulait dire pour mon plan

Mon tunnel public aurait lui aussi visé le port publié de NPM. Il aurait
traversé **la même traduction**, et serait arrivé depuis **la même
passerelle**. Celle que la liste autorisait.

Autrement dit, pour NPM, un visiteur d'Internet et moi sur Tailscale
auraient été **indiscernables**. La liste d'accès aurait laissé passer
tout le monde. Elle n'aurait rien protégé.

{{< attention titre="Supposer l'adresse source, c'est écrire un filtre au hasard" >}}
Derrière un proxy, un tunnel ou Docker, l'adresse vue par un service est
rarement celle du client. Avant d'écrire une règle d'accès, il faut lire
dans les journaux l'adresse **réellement** reçue.
{{< /attention >}}

## La correction : faire entrer le tunnel par une autre porte

Entre deux conteneurs d'un **même réseau Docker**, il n'y a pas de
traduction : chacun garde sa propre adresse. J'ai donc branché le conteneur
du tunnel directement sur le réseau de NPM, au lieu de le faire passer par
le port publié :

```yaml
# Fichier Compose du tunnel (extrait)
services:
  cloudflared:
    networks:
      - default
      - nginxproxymanager_default   # le réseau de NPM

networks:
  nginxproxymanager_default:
    external: true                  # créé par le Compose de NPM, pas par celui-ci
```

Le tunnel vise désormais NPM par son nom de conteneur. Il arrive avec sa
**propre** adresse, que la liste d'accès ne connaît pas. Je l'ai vérifié en
demandant le coffre depuis la position du tunnel : `403`.

## Le deuxième trou : un en-tête que n'importe qui peut écrire

En relisant la configuration de NPM, j'ai trouvé une autre faiblesse. Par
défaut, NPM fait confiance à l'en-tête `X-Real-IP` pour toute requête qui
vient des réseaux Docker. Cet en-tête est censé contenir la vraie adresse
du client… mais c'est **le client** qui l'écrit.

Une requête arrivant par le tunnel avec `X-Real-IP` réglé sur une adresse
du réseau local aurait pu se faire passer pour une machine de la maison, et
passer la liste d'accès.

Sur le coffre et Guacamole, j'ai donc remplacé cette confiance par la plus
stricte possible, dans la configuration avancée de chaque hôte :

```nginx
# Ne croire l'en-tête X-Real-IP que s'il vient de la machine elle-même.
# En pratique : l'adresse retenue est celle de la connexion réelle.
set_real_ip_from 127.0.0.1;
```

Pour le portfolio, c'est l'inverse : je **veux** la vraie adresse du
visiteur, pour que CrowdSec puisse l'analyser. Cloudflare la transmet dans
un en-tête à lui, `CF-Connecting-IP`, et NPM ne le croit que s'il arrive
des réseaux Docker, donc du tunnel.

{{< lecon titre="Un en-tête n'est qu'une déclaration" >}}
Un en-tête HTTP qui annonce une adresse est écrit par celui qui envoie la
requête. On ne le croit que s'il vient d'un intermédiaire **de
confiance**, et seulement de celui-là.
{{< /lecon >}}

## Quatre couches plutôt qu'une

À la fin, le coffre et Guacamole ne reposent plus sur une seule
protection, mais sur quatre, indépendantes :

| Couche | Ce qu'elle empêche |
|:-------|:-------------------|
| Nom d'hôte forcé dans le tunnel | le tunnel n'envoie que les noms du portfolio |
| Site par défaut en « No Response (444) » | un nom inconnu ou l'adresse IP seule ne reçoit aucune réponse |
| Liste d'accès « réseau local + Tailscale » | le tunnel, avec sa propre adresse, reçoit `403` |
| `X-Real-IP` ignoré sur les hôtes privés | impossible de se faire passer pour une adresse autorisée |

Je les ai testées **une par une**, puis j'ai fait une vraie tentative
de bout en bout, depuis Internet. Si l'une d'elles casse un jour, les autres
tiennent encore.

## Basculer avec un retour arrière

Pour la bascule elle-même, je n'ai rien supprimé tout de suite : j'ai
d'abord **désactivé** l'ancienne configuration, et ne l'ai retirée qu'une
fois la nouvelle validée. En cas de problème, un clic
suffisait pour revenir en arrière. Une visite en 4G a ensuite confirmé que
le journal du portfolio contenait bien l'adresse publique du téléphone, et
plus celle d'un conteneur.

La suite, c'est-à-dire vérifier que CrowdSec repère vraiment une attaque
dans ce nouveau trafic, fait l'objet d'un
[write-up à part](/writeups/tester-la-detection-sur-mon-portfolio/).

## Ce que j'en retiens

- **Mesurer avant de filtrer.** L'adresse vue par le proxy n'était pas
  celle que j'imaginais, et mon plan reposait sur une supposition.
- **Un port publié traduit l'adresse source.** Entre deux conteneurs d'un
  même réseau, il n'y a pas de traduction.
- **Ne jamais croire un en-tête d'adresse écrit par le client.**
- **Plusieurs couches indépendantes, testées une par une.** Puis un test
  de bout en bout, depuis Internet.
- **Désactiver avant de supprimer.** Un retour arrière en un clic rend la
  bascule beaucoup moins stressante.
