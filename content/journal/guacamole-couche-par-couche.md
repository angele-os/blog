---
title: "Quatre blocages en une journée : diagnostiquer couche par couche"
slug: "guacamole-couche-par-couche"
date: 2026-10-19T11:00:00+02:00
summary: "En installant Guacamole, un bastion d'accès web, je suis tombé sur quatre pannes successives. Aucune n'a été résolue en devinant : à chaque fois, la réponse était dans un journal, souvent celui de l'autre côté."
tags: ["homelab", "guacamole", "ssh", "vnc", "diagnostic"]
---

Je voulais pouvoir administrer mon serveur et prendre la main sur mon PC
fixe depuis **n'importe quel navigateur**, même sur un téléphone, sans rien
installer. C'est le rôle d'**Apache Guacamole** : un bastion d'accès web.

L'installation m'a pris une journée, et j'ai buté quatre fois. Ce n'est pas
le nombre de blocages qui m'a appris le plus, c'est la méthode qui a permis
de tous les résoudre.

## Comment Guacamole fonctionne

```text
Navigateur ──HTTPS──> Guacamole (interface web)
                          │
                          v
                        guacd ──SSH──> serveur
                              └─VNC──> PC fixe
```

Le navigateur ne parle qu'en HTTPS avec l'interface web. C'est `guacd`, un
petit moteur qui tourne sur le serveur, qui ouvre réellement les connexions
SSH ou VNC vers les machines cibles, puis renvoie l'image au navigateur.
Une base PostgreSQL garde les comptes et les connexions. Les trois tournent
dans des conteneurs Docker, et aucun ne publie de port : on y accède
seulement par mon réseau privé Tailscale, avec double authentification.

## Blocage n°1 : le certificat qui refusait de se faire

**Symptôme :** « Internal Error » en enregistrant le nom de domaine dans le
reverse proxy.

**Le journal :** `docker logs` du reverse proxy montrait la commande de
Let's Encrypt avec `--preferred-challenges http`, puis
`Some challenges have failed`.

**La cause :** j'avais oublié de cocher « Use a DNS Challenge ». Le défi
HTTP demande à Let's Encrypt de venir chercher un fichier sur mon serveur
depuis Internet… alors qu'aucun port n'est ouvert. Il ne pouvait
**qu'échouer**. Avec le défi DNS, le certificat est arrivé en une minute.

Cet échec avait un bon côté : il prouvait que mon serveur est vraiment
injoignable depuis Internet.

## Blocage n°2 : la clé SSH « au format inconnu »

**Symptôme :** la connexion SSH vers le serveur échoue.

**Le journal, côté client** (`guacd`) :
`Unable to extract public key from private key file: Unsupported private key file format`.

**Le journal, côté serveur** (`sshd`) : une connexion fermée avant
authentification, puis une pénalité de 10 secondes pour cette adresse.

**La cause :** j'avais collé la clé privée **sans** ses lignes
`-----BEGIN …` et `-----END …`. Sans elles, impossible de reconnaître le
format. Elles font partie de la clé.

Le journal du serveur m'a aussi appris quelque chose : les versions
récentes de `sshd` **pénalisent** une adresse qui se connecte sans
s'authentifier. Pendant le diagnostic, les reconnexions automatiques de
Guacamole aggravaient la situation. J'ai dû les couper.

## Blocage n°3 : le Bureau à distance… qui n'existait pas

**Symptôme :** impossible de joindre mon PC fixe en RDP.

**La vérification :** « À propos de Windows » → **Windows 11 Famille**.

**La cause :** l'édition Famille ne peut pas **recevoir** de connexion
Bureau à distance, c'est réservé aux éditions Pro. Plutôt que de payer une
licence, je suis passé à **VNC** avec TightVNC (gratuit), verrouillé par
deux protections indépendantes : TightVNC n'accepte que l'adresse du
serveur, et le pare-feu Windows aussi.

{{< attention titre="L'installateur qui ouvre une porte sans le dire" >}}
En vérifiant le pare-feu après coup, j'ai trouvé une règle créée par
l'installateur de TightVNC : elle autorisait **tout le monde** à se
connecter. Je l'ai désactivée. Toujours relire le pare-feu après avoir
installé un logiciel serveur.
{{< /attention >}}

## Blocage n°4 : « Unable to connect to VNC server »

C'est le blocage le plus instructif, parce que je l'ai résolu en
remontant les couches une par une :

| Couche | Test | Résultat |
|:-------|:-----|:---------|
| Réseau (TCP) | le port 5900 du PC répond-il depuis le serveur ? | oui |
| Service | le PC renvoie-t-il une bannière VNC (`RFB 003.008`) ? | oui, même depuis le conteneur de `guacd` |
| Authentification | que dit le journal de TightVNC ? | `Authentication failed` |

Le réseau et le service étaient bons. Le problème était à la dernière
couche : le mot de passe VNC enregistré dans Guacamole et celui de
TightVNC **n'étaient pas les mêmes**. Je les ai redéfinis des deux côtés à
partir de mon gestionnaire de mots de passe, et tout a fonctionné.

{{< lecon titre="Un port ouvert ne prouve qu'une chose" >}}
« Le port répond » valide la couche réseau, et rien d'autre. Il faut
tester chaque couche : la connexion TCP, puis le service (sa bannière),
puis l'authentification.
{{< /lecon >}}

## Le détail qui m'a fait comprendre la NAT de Docker

En configurant les deux connexions, j'ai remarqué que les cibles ne
voyaient pas arriver la même adresse :

- **vers le serveur lui-même**, `sshd` voyait l'adresse **interne** du
  conteneur `guacd`. J'ai donc limité la clé SSH de Guacamole aux réseaux
  internes de Docker (option `from=` dans `authorized_keys`) ;
- **vers le PC**, TightVNC voyait l'adresse **du serveur** : en sortant vers
  le réseau local, Docker remplace l'adresse du conteneur par celle de
  l'hôte (c'est de la NAT). La règle de TightVNC autorise donc le serveur.

Comprendre ce comportement était indispensable pour écrire des règles
d'accès qui marchent, et qui restent strictes.

## Ce que j'en retiens

- **Lire les journaux des deux côtés.** Le client dit ce qu'il a tenté ; le
  serveur dit pourquoi il a refusé. Pour SSH comme pour VNC, c'est le
  serveur qui a donné la cause.
- **Tester couche par couche**, du réseau à l'authentification, au lieu de
  tout changer en même temps.
- **Un bloc de clé se copie en entier**, lignes BEGIN et END comprises.
- **Les outils de diagnostic sont temporaires** : niveau de journalisation
  maximal, conteneurs de test… tout a été retiré une fois la cause trouvée.
