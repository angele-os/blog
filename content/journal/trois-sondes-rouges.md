---
title: "Trois sondes rouges pendant deux jours, et aucun service en panne"
slug: "trois-sondes-rouges"
date: 2026-11-13T09:00:00+01:00
summary: "Ma supervision affichait le coffre et le bastion hors ligne depuis deux jours, alors que tout fonctionnait. C'était la supervision elle-même qui était en panne. Diagnostic, correction… et la porte que cette correction a rouverte."
tags: ["homelab", "supervision", "uptime-kuma", "tailscale", "docker", "diagnostic"]
---

Le 5 novembre au soir, j'ouvre Uptime Kuma, mon outil de supervision, pour
une tâche sans rapport. Trois sondes sont rouges **depuis deux jours** : le
coffre de mots de passe (deux sondes) et Guacamole, mon bastion d'accès web.

Pourtant, le coffre s'ouvrait parfaitement depuis mon PC. Aucun service
n'avait jamais été coupé. C'était la **supervision** qui était en panne.

## Pourquoi j'étais dans Kuma ce soir-là

J'étais en train de remplacer l'adresse de mon webhook Discord, celle qui
permet à mes outils de m'envoyer des alertes. Je l'avais laissée fuiter le
jour même, d'une façon à laquelle je ne m'attendais pas.

{{< attention titre="Un secret affiché par une page d'aide" >}}
Pour connaître la version de Watchtower (l'outil qui met à jour mes
conteneurs), j'ai lancé une commande avec une option qui n'existe pas.
Watchtower a affiché son aide complète. Or cette aide montre la **valeur
actuelle** de chaque option, dont l'adresse du webhook, en clair. J'ai
collé cette sortie dans une conversation avant de la relire.

Avec cette adresse, n'importe qui peut écrire dans mon salon d'alertes :
fausses alertes, liens piégés. J'ai supprimé le webhook dans Discord, créé
un nouveau, puis cherché avec `grep` **tous** les fichiers où l'ancienne
adresse était écrite pour la remplacer, et testé chaque envoi.
{{< /attention >}}

## La chronologie

| Moment | Ce qui s'est passé |
|:-------|:-------------------|
| 3 nov., 19 h 31 | Le conteneur Tailscale est recréé. **À la même minute**, les trois sondes passent au rouge : `connect ECONNREFUSED`. Les alertes partent sur Discord. |
| 3 → 5 nov. | Personne ne les lit. |
| 5 nov., 18 h 43 | Je remarque les sondes rouges. |
| 5 nov., 18 h 44 | Début du diagnostic. |
| 5 nov., 18 h 58 | Sondes vertes. |

Deux jours d'alerte sans réaction : la première leçon est là, avant même le
diagnostic. Une alerte qui n'est pas lue ne sert à rien. Les notifications
de mon téléphone font partie de ma supervision, au même titre que Kuma.

## Le bon premier réflexe : vérifier par le vrai chemin

Une sonde rouge ne veut pas dire un service en panne. Elle veut dire : « la
sonde n'arrive pas à joindre le service ». Avant de toucher à quoi que ce
soit, j'ai donc ouvert le coffre comme un utilisateur normal : depuis mon
PC, Tailscale actif. Il s'est ouvert.

La question a alors changé. Ce n'était plus « pourquoi le coffre est en
panne ? », mais **« pourquoi Kuma ne voit-il pas ce que je vois ? »**.

## Comparer depuis plusieurs positions

Pour rappel, le coffre et Guacamole ne sont joignables que par mon réseau
privé Tailscale. Le chemin normal ressemble à ceci :

```text
Appareil ──Tailscale──> relais Tailscale (port 443 du serveur)
                              │
                              v
                      reverse proxy (NPM) ──> coffre / Guacamole
```

Kuma tourne dans un conteneur sur ce même serveur, et ses sondes
empruntaient ce même chemin. J'ai testé chaque maillon, en changeant
**d'où** je testais :

| Test | Résultat | Ce que j'en déduis |
|:-----|:---------|:-------------------|
| État des conteneurs | tous démarrés | aucun service arrêté |
| État du relais Tailscale | connecté, relais présent | le relais n'a pas sauté |
| Décisions de CrowdSec | aucune | personne n'a été bloqué |
| `curl` depuis le serveur vers le reverse proxy | `200` | le proxy et le coffre fonctionnent |
| `curl` depuis le serveur vers le relais Tailscale | `200` | le relais accepte le serveur |
| **Même `curl`, depuis le conteneur de Kuma** | **`000` (refusé)** | **seuls les conteneurs sont refusés** |
| Règles du pare-feu | rien qui vise les conteneurs | ce n'est pas le pare-feu |
| Qui écoute sur le port 443 ? | le démon Tailscale lui-même | c'est lui qui refuse |

Une seule ligne différait. Le relais acceptait le serveur, mon PC, mon
téléphone… mais refusait les connexions venant d'un conteneur.

Pourquoi ce changement le 3 novembre ? Le conteneur Tailscale avait été
recréé avec une version plus récente, et mon hypothèse est que cette
version est plus stricte sur l'origine des connexions. **Je ne l'ai pas
prouvé**, et je préfère l'écrire tel quel : la cause exacte reste une
hypothèse, le mécanisme (seuls les conteneurs sont refusés), lui, est
mesuré.

{{< lecon titre="La seule différence désigne la cause" >}}
Quand quelque chose marche d'un endroit et pas d'un autre, refaire le
**même** test depuis plusieurs positions (l'hôte, un conteneur, un
appareil) est souvent plus rapide que de chercher dans la configuration.
{{< /lecon >}}

## La correction : un chemin court pour la supervision

Plutôt que de dépendre du relais, j'ai donné à Kuma un chemin direct vers
le reverse proxy, **sans changer ses sondes**.

Le reverse proxy vit dans un réseau Docker. Docker permet de donner à un
conteneur des **alias** sur ce réseau : des noms supplémentaires, que seuls
les conteneurs du même réseau peuvent résoudre. J'ai déclaré comme alias
les noms du coffre et de Guacamole, puis branché Kuma sur ce réseau :

```yaml
# Fichier Compose du reverse proxy (extrait, noms d'exemple)
services:
  app:
    networks:
      default:
        aliases:
          - coffre.example.com
          - bastion.example.com
```

Pour Kuma, `coffre.example.com` désigne désormais directement le reverse
proxy. Ses sondes gardent la même adresse, et vérifient toujours le
certificat HTTPS.

### Premier résultat : 403, et c'était une bonne nouvelle

La première réponse a été `403 Forbidden`. Le coffre et Guacamole sont
protégés par une **liste d'accès** sur le reverse proxy : seuls le réseau
local et Tailscale sont autorisés. En arrivant par le réseau Docker, Kuma
avait sa propre adresse interne, inconnue de la liste. La protection a
fait exactement son travail.

J'ai donc ajouté le réseau Docker du proxy à la liste… et obtenu encore un
`403`. J'avais écrit l'adresse du réseau **sans son masque**. Dans une
règle d'accès, une adresse sans masque ne désigne qu'**elle-même**, pas la
plage. Avec le masque (`/16`), la réponse est passée à `200`, et les sondes
au vert.

## Le piège : ce qu'un contournement rouvre

En relisant la correction, j'ai compris qu'elle avait un coût.
Autoriser **tout** le réseau Docker du proxy, c'est autoriser tous les
conteneurs branchés dessus, pas seulement Kuma. Or l'un d'eux est
justement un conteneur que j'avais fait **refuser** par cette liste trois
semaines plus tôt ([je raconte pourquoi ici](/journal/une-liste-d-acces-qui-n-aurait-rien-protege/)).

D'autres protections, indépendantes de la liste d'accès, bloquent
toujours ce chemin. Mais une couche de défense en moins reste une couche
en moins. La bonne version est plus précise : donner une **adresse fixe**
à Kuma et n'autoriser que celle-là. C'est la prochaine correction de ma
liste.

{{< lecon titre="Relire un contournement comme un changement de sécurité" >}}
Une correction faite pour réparer la supervision peut affaiblir la
sécurité. Après chaque contournement, se demander : « qui d'autre que
moi passe maintenant par cette porte ? »
{{< /lecon >}}

## Ce qu'on contourne doit rester surveillé

Kuma ne passe plus par le relais Tailscale. Mais le relais, c'est le chemin
que **j'utilise** tous les jours. S'il tombait, plus aucune sonde ne le
verrait.

J'ai donc ajouté une sonde d'un autre type : une sonde **Push**. Au lieu
que Kuma aille vérifier un service, c'est un script qui vient lui dire
« tout va bien » à intervalle régulier. Si Kuma n'a pas de nouvelles
pendant 90 secondes, il m'alerte.

Le script tourne sur le serveur lui-même (que le relais accepte), et teste
le vrai chemin Tailscale. Dans son principe :

```bash
#!/usr/bin/env bash
# Teste le chemin Tailscale vers le coffre, puis rend compte à Uptime Kuma.
# Le jeton de la sonde est un secret : il est lu dans un fichier protégé.
JETON="$(cat /chemin/vers/jeton-sonde)"

code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
  https://coffre.example.com/alive)

if [ "$code" = "200" ]; then
  curl -s "http://127.0.0.1:3001/api/push/$JETON?status=up&msg=OK" > /dev/null
else
  curl -s "http://127.0.0.1:3001/api/push/$JETON?status=down&msg=HTTP%20$code" > /dev/null
fi
```

Un timer systemd le lance deux minutes après le démarrage, puis chaque
minute :

```ini
[Timer]
OnBootSec=2min
OnUnitActiveSec=1min
```

Petit rappel de ZimaOS au passage : le premier `systemctl enable` a
répondu `Unit check-tailscale.timer does not exist`. Sur ce système, une
unité systemd ajoutée à la main doit être écrite dans
`/etc/systemd/system`, la seule zone de configuration conservée (j'en
avais déjà fait les frais avec [ma sauvegarde](/journal/la-sauvegarde-qui-sest-evaporee/)).

## Ce que j'en retiens

- **Une sonde rouge n'est pas une panne.** Vérifier d'abord par le chemin
  réel des utilisateurs.
- **Comparer depuis plusieurs positions.** La seule différence trouvée
  désigne la cause.
- **Écrire ce qui est prouvé et ce qui ne l'est pas.** Le mécanisme est
  mesuré ; la raison du changement reste une hypothèse.
- **Relire un contournement sous l'angle de la sécurité.** Celui-ci a
  réparé la supervision et élargi une liste d'accès.
- **Ce qu'on contourne doit rester surveillé.** D'où la sonde Push.
- **Lire une sortie avant de la coller.** Une page d'aide peut contenir un
  secret.
