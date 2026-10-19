---
title: "La sauvegarde qui s'est évaporée"
slug: "la-sauvegarde-qui-sest-evaporee"
date: 2026-10-18T11:00:00+02:00
summary: "Une nuit, ma sauvegarde ne s'est pas lancée, et aucune alerte ne m'a prévenu. La cause : un simple redémarrage, et un dossier qui s'efface tout seul."
tags: ["homelab", "sauvegarde", "systemd", "zimaos", "supervision"]
---

Le 9 octobre, en cherchant où ajouter une nouvelle tâche planifiée sur mon
serveur, j'ai tapé `crontab -l`. La réponse était vide. Ma sauvegarde
nocturne, celle qui protège mon coffre de mots de passe, n'existait plus.

Elle ne s'était pas lancée la nuit précédente. Et aucune de mes alertes
n'avait sonné.

## Le dispositif de sauvegarde

Chaque nuit à 3 h 30, un script sauvegarde les données importantes du
serveur avec **restic**, un outil qui produit des sauvegardes chiffrées,
dédupliquées et versionnées. Le script :

1. fait une copie cohérente de la base de données du coffre, sans
   l'arrêter ;
2. l'envoie dans le dépôt restic, sur un disque séparé ;
3. supprime les anciennes versions selon une règle de rétention ;
4. vérifie un échantillon des données ;
5. signale « tout va bien » à ma supervision (Uptime Kuma), **seulement si
   toutes les étapes ont réussi**.

Uptime Kuma attend ce signal. S'il ne reçoit rien pendant 26 heures, il
m'envoie une alerte sur Discord. Sur le papier, une sauvegarde manquée ne
pouvait donc pas passer inaperçue.

## La chronologie

| Moment | Ce qui s'est passé |
|:-------|:-------------------|
| 8 oct., 3 h 30 | Dernière sauvegarde réussie. |
| 8 oct., 17 h 40 | Je redémarre le serveur pour valider un changement de configuration SSH, sans aucun rapport avec les sauvegardes. |
| 9 oct., 3 h 30 | Aucune sauvegarde. Aucun message. |
| 9 oct., après-midi | Plusieurs redémarrages pour d'autres travaux. Uptime Kuma affiche toujours « en ligne ». |
| 9 oct., 17 h 40 | Je découvre par hasard que la tâche planifiée a disparu. |

## Première énigme : où est passée la tâche ?

Mon serveur tourne sous **ZimaOS**, un système conçu pour faire tourner des
conteneurs. Pour être robuste, il ne ressemble pas à une distribution
Linux classique :

| Zone | Comportement |
|:-----|:-------------|
| `/` (le système) | en lecture seule |
| `/etc` (la configuration) | modifiable et conservée |
| `/var` | **en mémoire vive (tmpfs) : vidée à chaque démarrage** |
| la partition de données | modifiable et conservée |

Or, quand on crée une tâche avec `crontab -e`, cron l'enregistre dans
`/var/spool/cron/`. Sur ZimaOS, ma tâche vivait donc dans la mémoire vive.
Elle a fonctionné parfaitement **jusqu'au premier redémarrage**, qui l'a
effacée sans un bruit.

{{< attention >}}
Sur un système dont `/var` est en tmpfs, `crontab -e` semble fonctionner :
la tâche s'affiche, elle se lance, tout a l'air normal. Le problème
n'apparaît qu'au redémarrage suivant, parfois des semaines plus tard.
{{< /attention >}}

## Deuxième énigme : pourquoi aucune alerte ?

C'est la question qui m'a le plus appris. Deux défauts se sont cumulés.

**Un script qui ne se lance pas ne peut rien signaler.** Mon script envoie
« échec » quand une étape échoue. Mais là, il n'a jamais démarré. Il ne
restait que le délai de 26 heures pour me prévenir.

**Le chien de garde redémarrait avec ce qu'il surveillait.** Uptime Kuma
tourne sur le même serveur. À chaque redémarrage de l'après-midi, son
compte à rebours de 26 heures repartait de zéro. Il aurait fini par
m'alerter… si j'avais arrêté de redémarrer.

{{< lecon >}}
Un chien de garde doit vivre ailleurs que ce qu'il garde. Quand le
serveur tombe, la supervision qui tourne dessus tombe avec lui.
{{< /lecon >}}

## La correction : un timer systemd

Puisque `/etc` est conservé, la tâche doit être déclarée là. J'ai remplacé
la ligne cron par un **timer systemd** : un couple de deux petits fichiers.

Le service dit **quoi** lancer :

```ini
# /etc/systemd/system/sauvegarde.service
[Unit]
Description=Sauvegarde restic nocturne

[Service]
Type=oneshot
ExecStart=/chemin/vers/sauvegarde.sh
```

Le timer dit **quand** le lancer :

```ini
# /etc/systemd/system/sauvegarde.timer
[Unit]
Description=Lance la sauvegarde chaque nuit à 3 h 30

[Timer]
OnCalendar=*-*-* 03:30:00
Persistent=true

[Install]
WantedBy=timers.target
```

La ligne `Persistent=true` est le vrai gain par rapport à cron : si le
serveur était éteint à 3 h 30, la sauvegarde est lancée dès le démarrage
suivant au lieu d'être simplement sautée.

On active le timer, puis on vérifie la date du prochain lancement :

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now sauvegarde.timer
systemctl list-timers sauvegarde.timer
```

Je n'ai pas considéré le problème réglé avant de l'avoir **prouvé** : un
redémarrage, puis `systemctl list-timers` à nouveau. Le timer était
toujours là.

## L'erreur pendant la correction

J'ai aussi fait une erreur en corrigeant. J'ai deux scripts aux noms
proches : celui qui fait la sauvegarde complète, et un petit outil qui
transmet ses arguments à restic. Mon premier service lançait… le second.
Résultat : le journal ne contenait que l'aide de restic.

Depuis, ma documentation distingue clairement les deux, avec une phrase
pour chacun : ce qu'il fait, et quand on l'utilise.

## Ce que j'en retiens

- **Un changement peut casser quelque chose qui n'a rien à voir avec
  lui.** J'avais redémarré pour tester SSH, pas les sauvegardes.
- **Connaître son système avant d'y appliquer ses habitudes.** `crontab -e`
  est un bon réflexe sur une Debian, un piège sur ZimaOS.
- **Une absence de nouvelles n'est pas une bonne nouvelle.** Le silence
  peut vouloir dire « tout va bien » comme « rien ne s'est lancé ».
- **Vérifier les tâches planifiées après chaque redémarrage**, au moins
  tant qu'on n'a pas prouvé qu'elles survivent.

Il me reste un chantier ouvert : déplacer ce chien de garde hors du
serveur, pour qu'une panne complète déclenche enfin une alerte.
