---
title: "Attaquer mon propre portfolio pour tester ma détection d'intrusion"
slug: "tester-la-detection-sur-mon-portfolio"
date: 2026-11-13T11:00:00+01:00
summary: "Lab sur mon homelab : je joue le robot qui cherche des fichiers sensibles sur mon portfolio, pour vérifier que CrowdSec le repère. Huit requêtes à la main ne déclenchent rien, une rafale de douze, si. Pourquoi : les seaux qui fuient."
tags: ["crowdsec", "détection", "web", "blue-team", "homelab"]
plateforme: "Homelab (mon serveur)"
difficulte: "facile"
---

Ce write-up n'est pas tiré d'une plateforme comme TryHackMe : le lab, c'est
mon propre serveur. Je venais de faire passer mon portfolio par mon reverse
proxy pour que **CrowdSec**, mon outil de détection d'intrusion, analyse
enfin le vrai trafic d'Internet
([le contexte est ici](/journal/une-liste-d-acces-qui-n-aurait-rien-protege/)).

Restait à prouver que ça servait à quelque chose : si un robot venait
fouiller mon site, est-ce que je le saurais ?

{{< attention titre="Uniquement sur ses propres systèmes" >}}
Tout ce qui suit vise **mon** site, sur **mon** serveur. Envoyer ce genre de
requêtes vers un site qui ne vous appartient pas, sans autorisation écrite,
peut constituer une infraction (articles 323-1 et suivants du Code pénal), même « pour tester ».
{{< /attention >}}

## Objectif et règles du jeu

- **Rôle :** un robot qui cherche des fichiers oubliés (`.env`, `.git`,
  pages d'administration…), comme ceux qui passent sur tous les sites
  publics.
- **Position :** Internet, pas la maison. CrowdSec ignore par défaut les
  adresses privées (réseau local, Docker, Tailscale) : une attaque depuis
  chez moi ne prouverait rien. J'ai donc testé depuis une connexion 4G.
- **Succès :** une alerte sur mon salon Discord, avec le nom du scénario
  reconnu.
- **Ménage :** supprimer tout ce que le test a créé.

## Étape 0 : vérifier que la vraie adresse arrive

Avant d'attaquer, il faut s'assurer que CrowdSec verra **l'adresse de
l'attaquant**, pas celle d'un intermédiaire. Le trafic traverse Cloudflare
puis un tunnel : si le reverse proxy écrivait l'adresse du tunnel dans son
journal, toutes les visites sembleraient venir de la même machine interne,
et CrowdSec les ignorerait.

J'ai ouvert le portfolio sur mon téléphone en 4G, puis lu la dernière
ligne du journal d'accès du portfolio :

```bash
sudo tail -n 1 /chemin/vers/logs/proxy-host-1_access.log
```

L'adresse en tête de ligne était bien **l'adresse publique du téléphone**
(remplacée ici par une adresse de documentation) :

```text
[26/Oct/2026:…] - 200 200 - GET https ange-bonkoski.fr "/" [Client 203.0.113.42] …
```

Le prérequis est rempli : CrowdSec reçoit des adresses qu'il peut
analyser.

## Étape 1 : la reconnaissance « à la main »

J'ai ouvert à la main, une par une, huit adresses du genre de celles que
les robots testent sans cesse : des fichiers de configuration, un dossier
`.git`, des pages de connexion de CMS que mon site n'a pas… Par exemple :

```text
/.env
/.git/config
/wp-login.php
/wp-admin/
/phpmyadmin/
/config.php
/backup.zip
/.DS_Store
```

**Résultat : aucune alerte.** Les requêtes étaient bien dans le journal,
CrowdSec les avait bien lues… et n'avait rien déclenché.

Mon premier réflexe a été de croire à une panne. En réalité, c'était le
comportement attendu, et le comprendre est le cœur de ce lab.

## Comprendre : les scénarios sont des seaux qui fuient

Un scénario CrowdSec ne réagit pas à **une** requête suspecte. Il
fonctionne comme un **seau percé** (*leaky bucket*) :

```text
  requête suspecte ─┐  ┌─ requête suspecte
                    v  v
                 ┌────────┐
                 │ ░░░░░░ │  capacité : N requêtes
                 │ ░░░░░░ │
                 └───┬────┘
                     │ fuite : le seau se vide un peu
                     v  à chaque intervalle
```

- Chaque requête suspecte d'une même adresse ajoute une goutte dans **son**
  seau.
- Le seau **fuit** en continu : les gouttes anciennes disparaissent.
- L'alerte ne se déclenche que si le seau **déborde**, c'est-à-dire si
  les requêtes arrivent plus vite qu'il ne se vide.

C'est voulu. Un visiteur humain qui tape une mauvaise adresse ne doit pas
être traité comme un attaquant. Ce qui distingue un robot, c'est le
**rythme** : des dizaines de chemins en quelques secondes.

Mes huit requêtes tapées à la main, espacées de plusieurs secondes,
n'arrivaient jamais assez vite : le seau se vidait entre deux gouttes. Mon
test imitait un humain curieux, pas un robot.

Pour voir la capacité et la vitesse de fuite d'un scénario, CrowdSec
permet de l'inspecter :

```bash
sudo docker exec crowdsec cscli scenarios list
sudo docker exec crowdsec cscli scenarios inspect <nom-du-scénario>
```

## Étape 2 : la rafale

J'ai refait le test en me comportant **comme un robot** : douze requêtes
vers des chemins sensibles, en quelques secondes, toujours depuis la 4G.
Une simple boucle suffit, par exemple :

```bash
# À lancer depuis une connexion extérieure (pas le réseau de la maison).
for chemin in .env .git/config wp-login.php wp-admin/ phpmyadmin/ \
              config.php backup.zip .DS_Store admin/ .htaccess \
              server-status xmlrpc.php; do
  curl -s -o /dev/null -w "%{http_code} /$chemin\n" "https://ange-bonkoski.fr/$chemin"
done
```

**Résultat : l'alerte est arrivée sur Discord**, avec le nom du scénario
reconnu et l'adresse du téléphone. Le seau avait débordé.

Sur le serveur, on retrouve l'alerte et la décision qu'elle a créée :

```bash
sudo docker exec crowdsec cscli alerts list
sudo docker exec crowdsec cscli decisions list
```

Ma configuration crée une décision de quatre heures contre l'adresse
fautive. Comme je n'ai installé aucun composant de blocage (*bouncer*),
cette décision reste une **trace** : elle ne bloque rien. C'est un choix :
sans port ouvert, le gain d'un blocage serait faible, et le risque de me
bloquer moi-même, réel.

## Étape 3 : le ménage

Un test laisse des traces, et une décision contre l'adresse 4G de mon
propre téléphone n'a rien à faire dans l'historique. Je l'ai supprimée :

```bash
sudo docker exec crowdsec cscli decisions delete --ip 203.0.113.42
```

Puis j'ai vérifié qu'il n'en restait aucune avec `cscli decisions list`.

## Ce que j'en retiens

{{< lecon titre="Un test doit imiter la vraie menace" >}}
Mes huit requêtes « à la main » ne prouvaient pas que la détection était
en panne : elles prouvaient qu'elle ne réagit pas à un humain. Pour tester
une détection, il faut reproduire **le comportement** de l'attaque (ici,
son rythme), pas seulement ses requêtes.
{{< /lecon >}}

- **Vérifier le prérequis d'abord.** Sans la vraie adresse du client dans
  le journal, toute la suite aurait été vide de sens.
- **Tester depuis la bonne position.** Depuis la maison, CrowdSec aurait
  tout ignoré, à raison.
- **Comprendre le seuil avant de conclure à une panne.** Les seaux qui
  fuient expliquent le silence du premier test.
- **Faire le ménage après le test.** Décision supprimée, rien ne reste.
- **Limite connue :** CrowdSec ne voit que ce que lisent ses sources (le
  journal SSH et les journaux du reverse proxy). Une attaque sur un autre
  chemin passerait inaperçue.
