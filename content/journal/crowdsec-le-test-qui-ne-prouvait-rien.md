---
title: "CrowdSec, et le test qui ne prouvait rien"
slug: "crowdsec-le-test-qui-ne-prouvait-rien"
date: 2026-10-18T12:00:00+02:00
summary: "J'ai installé CrowdSec pour détecter les attaques sur mon serveur. Tout fonctionnait, sauf les alertes Discord, et la commande de test ne disait rien. Diagnostic couche par couche."
tags: ["homelab", "crowdsec", "détection", "docker", "discord"]
---

J'ai installé **CrowdSec** sur mon homelab pour une raison simple : je
voulais savoir si quelqu'un s'en prenait à mon serveur. L'installation
s'est bien passée. Les alertes, elles, n'arrivaient pas sur Discord. Et la
commande censée les tester me répondait… rien. Ni succès, ni erreur.

Cet article raconte comment j'ai trouvé la panne, et pourquoi la leçon
dépasse largement CrowdSec.

## CrowdSec en deux minutes

CrowdSec est un outil de détection d'intrusion. Il fonctionne comme une
chaîne :

```text
journaux  →  analyseurs  →  scénarios  →  alerte  →  notification
(SSH, web)   (lisent         (reconnaissent   (décision)   (Discord)
              chaque ligne)   une attaque)
```

1. Il **lit les journaux** du serveur : ici, les connexions SSH et les
   accès au reverse proxy.
2. Des **analyseurs** découpent chaque ligne (adresse IP, utilisateur,
   résultat).
3. Des **scénarios** reconnaissent un comportement suspect, par exemple
   une rafale d'échecs de connexion SSH depuis la même adresse en
   quelques secondes : une attaque par force brute.
4. Une **alerte** est créée, et un **plugin** l'envoie ailleurs, ici vers
   un salon Discord privé.

CrowdSec peut aussi **bloquer** les adresses fautives, grâce à un composant
séparé (un *bouncer*). Je ne l'ai pas installé, volontairement : mon
serveur n'a aucun port ouvert sur Internet, donc aucune attaque extérieure
ne peut l'atteindre. Mon but était d'apprendre la chaîne de détection et de
surveiller ce qui se passe, pas de risquer de me bloquer moi-même.

## Le symptôme

CrowdSec propose une commande pour tester une notification :

```bash
cscli notifications test http_default
```

Elle s'exécutait sans erreur. Sa sortie montrait le plugin qui démarre,
puis qui s'arrête. Et sur Discord : rien. J'ai relancé plusieurs fois, en
modifiant la configuration entre deux essais. Toujours rien.

## Séparer les couches

Quand une chaîne de plusieurs maillons ne fonctionne pas, deviner ne sert à
rien. J'ai testé chaque maillon **seul**, en partant du bout.

### Maillon 1 : Discord reçoit-il quoi que ce soit ?

Un webhook Discord est une simple adresse à laquelle on envoie un message.
On peut donc le tester sans CrowdSec. Problème : l'image de CrowdSec ne
contient pas `curl`. Plutôt que d'installer quoi que ce soit, j'ai utilisé
un **conteneur jetable** qui ne contient que `curl` et disparaît après
usage :

```bash
docker run --rm --env-file .env curlimages/curl \
  sh -c 'curl -s -o /dev/null -w "%{http_code}\n" \
    -H "Content-Type: application/json" \
    -d "{\"content\":\"Test du webhook\"}" "$DISCORD_WEBHOOK"'
```

Réponse : `204`, et le message est apparu sur Discord. Le webhook
fonctionnait. Le problème était donc **en amont**.

### Maillon 2 : CrowdSec lit-il le bon fichier ?

`cscli notifications list` indiquait bien `http_default` comme actif. Mais
« actif » voulait seulement dire qu'**un** fichier portait ce nom. En
regardant le fichier réellement présent **dans le conteneur**, sa date et
sa taille, j'ai compris : c'était le fichier **par défaut** livré avec
l'image, pas le mien. Ma configuration n'avait jamais été chargée.

{{< lecon titre="« Actif » n'est pas « chargé »" >}}
Une commande qui liste une configuration ne prouve pas que c'est **la
vôtre**. Allez voir le fichier réellement utilisé par le programme : sa
date de modification et sa taille disent la vérité.
{{< /lecon >}}

### Maillon 3 : la commande de test teste-t-elle vraiment quelque chose ?

En corrigeant le fichier, j'ai aussi compris pourquoi le test restait
muet. La commande démarre le plugin, lui confie le message… et s'arrête
avant que l'envoi ait eu le temps de se faire. Ma configuration ajoutait
en plus un délai de regroupement de 60 secondes avant chaque envoi : le
test ne pouvait **jamais** aboutir. J'ai retiré ce délai, et j'ai cessé de
me fier à cette commande.

## La vraie preuve : une vraie alerte

Pour prouver que toute la chaîne fonctionne, il faut un test qui la
**traverse** entièrement, comme le ferait une vraie attaque. J'ai donc
créé une décision manuelle contre une adresse fictive :

```bash
cscli decisions add --ip 203.0.113.99 --reason "test de bout en bout"
```

L'alerte est arrivée sur Discord en quelques secondes. Puis j'ai supprimé
cette décision de test.

Pourquoi `203.0.113.99` ? Parce que cette plage (`203.0.113.0/24`) est
**réservée à la documentation** : elle n'appartient à personne. C'est une
bonne habitude, dans un test comme dans un article, pour ne jamais viser
l'adresse de quelqu'un par erreur.

## Le piège suivant : les adresses privées

J'ai voulu aller plus loin et simuler une vraie attaque par force brute
SSH depuis mon propre PC. Rien ne s'est déclenché. Normal : par défaut,
CrowdSec **ignore** les adresses privées (le réseau local, Docker,
Tailscale). Une attaque venant de l'intérieur passe donc sous ses radars.

Pour vérifier qu'un scénario reconnaît bien une ligne de journal, CrowdSec
propose `cscli explain`. On lui donne une fausse ligne avec une adresse de
documentation, et il montre chaque étape : quel analyseur l'a lue, quels
scénarios se sont activés.

```bash
cscli explain --type syslog \
  --log "Oct 18 10:00:00 serveur sshd[1234]: Failed password for invalid user test from 203.0.113.5 port 4242 ssh2"
```

## Ce que j'en retiens

- **Un test qui ne dit rien ne prouve rien.** Ni succès ni erreur, ce
  n'est pas « ça marche ».
- **Tester chaque maillon seul, en partant du bout.** Le webhook, puis le
  fichier, puis le plugin : chaque étape élimine une hypothèse.
- **Préférer une vraie alerte à une commande de test.** Elle emprunte le
  même chemin qu'une attaque réelle.
- **Connaître les angles morts de son outil.** Ignorer les adresses
  privées est un choix raisonnable, mais il faut le savoir.
- **Un secret peut fuiter par un message d'erreur.** Une erreur d'envoi
  peut afficher l'adresse complète du webhook, qui suffit à quiconque pour
  écrire dans mon salon Discord. Avant de partager un journal, je masque
  toujours ce genre d'information.
