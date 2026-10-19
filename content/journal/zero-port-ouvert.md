---
title: "Zéro port ouvert : Cloudflare Tunnel pour le public, Tailscale pour le privé"
slug: "zero-port-ouvert"
date: 2026-10-18T10:00:00+02:00
summary: "Comment j'ai fermé toutes les redirections de ma box sans rien perdre : mon portfolio reste public grâce à un tunnel sortant, et tout le reste passe par un réseau privé."
tags: ["homelab", "réseau", "cloudflare", "tailscale", "sécurité"]
---

Pendant des semaines, mon serveur maison était joignable depuis Internet
de la façon la plus classique qui soit : deux redirections de ports sur ma
box, le 80 et le 443, vers un reverse proxy. Ça marchait. Et c'est
justement le problème : ça marchait **pour tout le monde**.

Aujourd'hui, ma box n'a plus **aucune** redirection. Mon portfolio est
toujours en ligne, et j'accède toujours à mes services privés depuis mon
téléphone en 4G. Voici comment, et surtout pourquoi.

## Le point de départ

Mon homelab est un vieux PC portable sous ZimaOS, qui fait tourner une
dizaine de services dans des conteneurs Docker : mon portfolio, un
gestionnaire de mots de passe (Vaultwarden), de la supervision, un filtre
DNS…

Pour les rendre accessibles de l'extérieur, j'avais fait ce que font la
plupart des tutoriels :

1. un enregistrement DNS qui pointe vers l'**IP publique** de ma box ;
2. une redirection des ports 80 et 443 de la box vers le serveur ;
3. un reverse proxy (Nginx Proxy Manager) qui répartit les requêtes entre
   les services selon le nom de domaine demandé.

## Pourquoi ce n'était pas acceptable

Un port ouvert, c'est une porte d'entrée que n'importe qui peut essayer de
pousser. Et sur Internet, quelqu'un essaie **en permanence** : des robots
balayent toutes les adresses IPv4 en continu, à la recherche d'un service
mal configuré ou pas à jour.

Trois choses me gênaient en particulier :

- **mon coffre de mots de passe était joignable par le monde entier.** Il
  était protégé par un mot de passe maître et une double authentification,
  mais une seule faille dans Vaultwarden aurait suffi ;
- **mon IP publique apparaissait dans mon DNS.** N'importe qui pouvait
  savoir où se trouve mon serveur, et donc ma connexion personnelle ;
- **toute la sécurité reposait sur un seul logiciel**, le reverse proxy,
  en première ligne face à Internet.

Je me suis fixé une règle simple : **ce qui doit être public l'est ; tout le
reste ne doit même pas être visible.**

## L'idée : inverser le sens de la connexion

Une redirection de port, c'est la box qui **accepte** des connexions
entrantes. Le pare-feu de la box, lui, bloque déjà tout ce qui entre sans
avoir été demandé. Il suffit donc de ne rien lui demander d'accepter.

Le principe est le suivant : c'est le **serveur** qui ouvre lui-même une
connexion **sortante** vers un service extérieur, et c'est par ce tuyau
déjà ouvert que les visiteurs arrivent. Vu de la box, il n'y a qu'une
connexion sortante, comme quand vous ouvrez un site web. Rien n'entre.

J'ai utilisé deux outils construits sur cette idée, un pour chaque usage.

## Le chemin public : Cloudflare Tunnel

Mon portfolio doit rester accessible à n'importe quel recruteur, sans
logiciel à installer. Pour lui, j'utilise **Cloudflare Tunnel**.

Un petit conteneur, `cloudflared`, tourne sur le serveur. Au démarrage, il
ouvre une connexion chiffrée vers Cloudflare et la garde ouverte. Le
domaine pointe vers Cloudflare, plus vers ma box :

```text
Visiteur → DNS → Cloudflare (pare-feu applicatif, cache)
         → tunnel (connexion sortante ouverte par le serveur)
         → cloudflared → serveur web du portfolio
```

Le fichier Compose tient en quelques lignes. Le jeton qui identifie le
tunnel n'y est pas écrit : il est lu dans un fichier `.env` séparé, lisible
seulement par son propriétaire.

```yaml
services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    restart: unless-stopped
    command: tunnel --no-autoupdate run
    environment:
      - TUNNEL_TOKEN=${TUNNEL_TOKEN}   # lu dans .env, jamais en clair ici
```

Au passage, mon IP publique a disparu du DNS : on ne voit plus que celles
de Cloudflare.

{{< attention titre="Le prix de ce confort" >}}
Cloudflare termine le chiffrement TLS : il voit passer le trafic du site
en clair avant de le renvoyer dans le tunnel. Pour un portfolio public, ça
ne me dérange pas. Pour un service qui manipule des données sensibles,
c'est une vraie question de confiance. C'est d'ailleurs pour ça que mon
coffre de mots de passe n'emprunte **pas** ce chemin.
{{< /attention >}}

## Les chemins privés : Tailscale

Pour tout le reste (coffre de mots de passe, administration, partage de
fichiers, SSH), il n'y a qu'un seul public : moi. Pas besoin de les
exposer au monde ; il suffit que **mes appareils** puissent les joindre.

**Tailscale** crée un réseau privé chiffré (basé sur WireGuard) entre mon
serveur, mon PC, mon Mac et mon iPhone. Chaque appareil reçoit une adresse
dans une plage réservée, qui n'a de sens que sur ce réseau.
Et là encore, chaque appareil n'ouvre que des connexions sortantes : aucune
redirection n'est nécessaire.

Restait un détail : je voulais garder une vraie adresse, avec un vrai
certificat HTTPS, pour que les applications de mon gestionnaire de mots de
passe fonctionnent comme avant. La solution tient en trois morceaux.

**1. Un DNS qui pointe vers une adresse privée.** Le sous-domaine du coffre
renvoie l'adresse Tailscale du serveur. Tout le monde peut lire cet
enregistrement, mais cette adresse ne mène nulle part si l'on n'est pas
dans mon réseau Tailscale.

**2. Un certificat obtenu sans port ouvert.** Let's Encrypt doit vérifier
que je contrôle bien le domaine avant de délivrer un certificat. La méthode
habituelle (le *défi HTTP*) consiste à venir chercher un fichier sur mon
serveur… ce qui est impossible, puisque plus rien n'est joignable. J'utilise
donc le **défi DNS** : le reverse proxy crée lui-même un enregistrement
temporaire dans ma zone DNS, grâce à un jeton d'API Cloudflare limité à
cette seule zone.

**3. Un relais pour le port 443.** Sur mon serveur, l'interface de ZimaOS
occupe déjà le port 80, et le reverse proxy écoute sur d'autres ports. C'est
Tailscale qui reçoit le 443 sur son interface et le relaie vers le reverse
proxy :

```bash
tailscale serve --bg --tcp 443 tcp://localhost:<port-https-du-proxy>
```

{{< attention titre="La commande à ne jamais lancer" >}}
`tailscale serve reset` efface **tous** les relais configurés. Je l'ai
appris en la lançant : mon coffre est devenu injoignable jusqu'à ce que je
recrée le relais.
{{< /attention >}}

## Vérifier, plutôt que supposer

Une fois les redirections supprimées dans l'interface de la box, je n'ai
pas considéré que c'était fini. J'ai vérifié chaque promesse depuis
l'**extérieur**, avec mon iPhone en 4G (donc hors de mon réseau local) :

| Test | Tailscale coupé | Tailscale actif |
|:-----|:---------------:|:---------------:|
| Portfolio | accessible | accessible |
| Coffre de mots de passe | **injoignable** | accessible |
| IP publique de la box | aucune réponse | — |
| Partages de fichiers | **injoignables** | accessibles |

J'ai aussi balayé l'adresse **IPv6** publique du serveur. Contrairement à
l'IPv4, une adresse IPv6 désigne directement la machine, sans traduction
d'adresse par la box : c'est un oubli classique. Résultat : tous les ports
testés fermés ou filtrés.

{{< lecon titre="L'échec qui prouve que ça marche" >}}
Plus tard, en ajoutant un nouveau service, j'ai oublié de cocher le défi
DNS : la demande de certificat en défi HTTP a échoué. Let's Encrypt n'avait
pas pu joindre mon serveur depuis Internet. Cette erreur était la
meilleure preuve possible que l'isolement tenait.
{{< /lecon >}}

## Ce que j'en retiens

- **Ne pas confondre « accessible » et « exposé ».** Mes services privés
  sont accessibles partout où je vais, mais ne sont exposés à personne.
- **Séparer les chemins selon le public.** Un visiteur anonyme et moi
  n'avons pas besoin d'emprunter la même porte.
- **Tester depuis l'extérieur.** Depuis le Wi-Fi de la maison, tout semble
  toujours fonctionner. C'est en 4G qu'on voit ce qui est vraiment exposé.
- **Chaque choix a un coût.** Le tunnel me rend dépendant de Cloudflare :
  si le conteneur `cloudflared` s'arrête, le portfolio tombe. Ma
  supervision me prévient dans ce cas.

Il reste une limite que j'assume : à l'intérieur de mon réseau local, les
services écoutent encore sur toutes les interfaces. La prochaine étape est
de réduire aussi cette surface-là.
