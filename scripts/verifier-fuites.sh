#!/usr/bin/env bash
# Vérifie qu'aucune information sensible n'est publiée sur le blog.
#
# Le dépôt est PUBLIC : tout fichier de content/ ou static/ finit en ligne.
# Ce script parcourt ces dossiers et échoue s'il trouve :
#   - une adresse IPv4 (privée, Tailscale ou publique), sauf exceptions ;
#   - une URL de webhook (Discord, Slack, Teams ou autre) ;
#   - une clé privée (-----BEGIN … PRIVATE KEY-----) ;
#   - un jeton (« token ») d'un format courant, ou un mot de passe écrit en clair.
# Les exceptions autorisées sont dans scripts/fuites-exceptions.txt.
#
# Utilisation (Git Bash sous Windows, Terminal sous Mac/Linux, ou la CI) :
#   bash scripts/verifier-fuites.sh                 -> vérifie content/ et static/
#   bash scripts/verifier-fuites.sh dossier1 …      -> vérifie ces dossiers-là
# Code de sortie : 0 = rien trouvé, 1 = fuite(s) trouvée(s), 2 = erreur.
#
# Affichage : « fichier:ligne: [catégorie] début… ». La valeur trouvée est
# volontairement tronquée : les journaux de la CI sont publics, il ne faut
# pas y recopier un secret en entier.
#
# Compatibilité : uniquement bash, grep, sed, sort, awk, présents sous Linux,
# Git Bash et macOS. Les expressions régulières sont « étendues » (grep -E),
# la syntaxe commune à toutes ces versions de grep.

# -u : erreur si on utilise une variable jamais définie (faute de frappe).
# -o pipefail : une commande qui échoue au milieu d'un « | » est signalée.
# Pas de -e : grep renvoie 1 quand il ne trouve rien, ce qui est normal ici.
set -uo pipefail

# Dossier racine du dépôt (le parent du dossier scripts/).
racine="$(cd "$(dirname "$0")/.." && pwd)"

# Fichier d'exceptions. La variable FUITES_EXCEPTIONS permet d'en utiliser un
# autre (c'est ce que fait scripts/tester-garde-fous.sh).
fichier_exceptions="${FUITES_EXCEPTIONS:-$racine/scripts/fuites-exceptions.txt}"

# Dossiers à vérifier : ceux donnés en arguments, sinon content/ et static/.
if [ "$#" -gt 0 ]; then
  dossiers=("$@")
else
  cd "$racine" || exit 2
  dossiers=(content static)
fi
for d in "${dossiers[@]}"; do
  if [ ! -d "$d" ]; then
    echo "Erreur : le dossier « $d » n'existe pas." >&2
    exit 2
  fi
done

# Les détections sont écrites dans un fichier temporaire, supprimé à la fin
# (trap … EXIT : même si le script s'arrête sur une erreur).
resultats="$(mktemp)"
trap 'rm -f "$resultats"' EXIT

# ---------------------------------------------------------------------------
# Outils pour les adresses IP
# ---------------------------------------------------------------------------

# Transforme « 192.168.1.20 » en un seul nombre (comme le fait un routeur) :
# 192×256³ + 168×256² + 1×256 + 20. Comparer des plages devient alors une
# simple comparaison de nombres. « 10# » force la base 10 : sans lui, Bash
# lirait « 010 » comme un nombre octal (en base 8).
ip_vers_nombre() {
  local a b c d
  IFS=. read -r a b c d <<< "$1"
  echo $(( (10#$a << 24) + (10#$b << 16) + (10#$c << 8) + 10#$d ))
}

# Vrai si chaque octet de l'adresse vaut au plus 255 (« 300.1.1.1 » n'est
# pas une IP, mais ressemble à une IP pour l'expression régulière).
ip_valide() {
  local a b c d
  IFS=. read -r a b c d <<< "$1"
  [ $((10#$a)) -le 255 ] && [ $((10#$b)) -le 255 ] && [ $((10#$c)) -le 255 ] && [ $((10#$d)) -le 255 ]
}

# Vrai si l'adresse $1 est dans la plage CIDR $2 (ex. « 10.0.0.0/8 »).
# Le préfixe (/8) dit combien de bits de gauche sont fixes : on compare
# seulement ces bits-là, grâce à un masque (des 1 à gauche, des 0 à droite).
dans_plage() {
  local ip="$1" reseau="${2%/*}" prefixe=32
  case "$2" in */*) prefixe="${2#*/}" ;; esac
  local masque=$(( (0xFFFFFFFF << (32 - prefixe)) & 0xFFFFFFFF ))
  [ $(( $(ip_vers_nombre "$ip") & masque )) -eq $(( $(ip_vers_nombre "$reseau") & masque )) ]
}

# ---------------------------------------------------------------------------
# Lecture des exceptions
# ---------------------------------------------------------------------------
plages_autorisees=()
textes_autorises=()
if [ -f "$fichier_exceptions" ]; then
  numero=0
  while IFS= read -r ligne || [ -n "$ligne" ]; do
    numero=$((numero + 1))
    ligne="${ligne%$'\r'}"          # fin de ligne Windows éventuelle
    ligne="${ligne%%#*}"            # retire le commentaire
    read -r type valeur <<< "$ligne"
    # Retire les espaces en fin de valeur.
    valeur="$(printf '%s' "${valeur:-}" | sed 's/[[:space:]]*$//')"
    case "${type:-}" in
      "") ;;                        # ligne vide ou commentaire seul
      ip)
        # Vérifie le format « a.b.c.d » ou « a.b.c.d/préfixe ».
        if ! printf '%s' "$valeur" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}(/([0-9]|[12][0-9]|3[0-2]))?$' \
           || ! ip_valide "${valeur%/*}"; then
          echo "Erreur : $fichier_exceptions, ligne $numero : plage IP invalide « $valeur »." >&2
          exit 2
        fi
        plages_autorisees+=("$valeur") ;;
      texte)
        if [ -z "$valeur" ]; then
          echo "Erreur : $fichier_exceptions, ligne $numero : texte vide." >&2
          exit 2
        fi
        textes_autorises+=("$valeur") ;;
      *)
        echo "Erreur : $fichier_exceptions, ligne $numero : type « $type » inconnu (attendu : ip ou texte)." >&2
        exit 2 ;;
    esac
  done < "$fichier_exceptions"
fi

# Vrai si la détection $1 contient un des textes autorisés.
texte_autorise() {
  local t
  for t in ${textes_autorises[@]+"${textes_autorises[@]}"}; do
    case "$1" in *"$t"*) return 0 ;; esac
  done
  return 1
}

# Vrai si l'IP $1 est dans une des plages autorisées.
ip_autorisee() {
  local plage
  for plage in ${plages_autorisees[@]+"${plages_autorisees[@]}"}; do
    dans_plage "$1" "$plage" && return 0
  done
  return 1
}

# Tronque une valeur trouvée avant de l'afficher : les 8 premiers caractères
# suffisent pour la reconnaître, sans recopier le secret dans les journaux.
# Pour une adresse web, on garde le nom du site (pas secret) et on coupe
# juste après : « https://discord.com/… ».
#   ^(https?://[^/]+/)   le début : protocole, puis tout jusqu'au premier « / »
#   .*                   le reste (le secret), remplacé par « … »
tronquer() {
  case "$1" in
    http://*|https://*) printf '%s' "$1" | sed -E 's#^(https?://[^/]+/).*#\1…#' ;;
    *) if [ "${#1}" -le 8 ]; then printf '%s' "$1"; else printf '%s…' "${1:0:8}"; fi ;;
  esac
}

# Enregistre une détection. Séparateur : tabulation (voir le bilan plus bas).
signaler() {  # $1 = fichier, $2 = ligne, $3 = catégorie, $4 = valeur affichée
  printf '%s:%s:\t[%s] %s\n' "$1" "$2" "$3" "$4" >> "$resultats"
}

# ---------------------------------------------------------------------------
# 1. Adresses IPv4
# ---------------------------------------------------------------------------
# Méthode en deux temps :
#  a) sed remplace chaque caractère qui n'est ni un chiffre ni un point par
#     DEUX espaces. Il ne reste que des groupes « chiffres et points »
#     séparés par au moins deux espaces. Pourquoi deux ? grep -o « consomme »
#     l'espace qui suit une IP ; avec deux espaces, l'IP suivante a encore le
#     sien devant elle (« 10.0.0.1,10.0.0.2 » : les deux sont trouvées).
#     Les numéros de ligne ne changent pas : sed garde chaque ligne en place.
#  b) grep cherche ce qui a la forme d'une IPv4 :
#
#     (^| )([0-9]{1,3}\.){3}[0-9]{1,3}(\.? |\.?$)
#
#     (^| )            début de ligne ou espace : l'IP commence là, et pas au
#                      milieu d'un nombre (« 1234.1.1.1 » ne donne pas
#                      « 234.1.1.1 »).
#     [0-9]{1,3}\.     un nombre de 1 à 3 chiffres suivi d'un point (\. : un
#                      point « vrai » ; seul, « . » voudrait dire « n'importe
#                      quel caractère ») ;
#     ( … ){3}         … répété 3 fois : « 192.168.1. » ;
#     [0-9]{1,3}       le 4e nombre : « 20 » ;
#     (\.? |\.?$)      puis un espace ou la fin de ligne, éventuellement après
#                      un point (une IP en fin de phrase : « … en 10.0.0.5. »).
#
#  Puis Bash vérifie que chaque nombre vaut au plus 255, et classe l'adresse.
motif_ip='(^| )([0-9]{1,3}\.){3}[0-9]{1,3}(\.? |\.?$)'

# grep -rlIE : liste (-l) récursivement (-r) les fichiers texte (-I ignore les
# fichiers binaires : polices, images) contenant quelque chose comme une IP.
grep -rlIE '([0-9]{1,3}\.){3}[0-9]{1,3}' "${dossiers[@]}" | while IFS= read -r fichier; do
  sed 's/[^0-9.]/  /g' "$fichier" | grep -noE "$motif_ip" | while IFS=: read -r num trouve; do
    # Retire les espaces et le point final capturés autour de l'adresse.
    ip="${trouve// /}"
    ip="${ip%.}"
    ip_valide "$ip" || continue
    ip_autorisee "$ip" && continue
    # Classement. Les adresses privées (RFC 1918) ne circulent pas sur
    # Internet mais révèlent l'organisation du réseau ; 100.64.0.0/10 est
    # la plage utilisée par Tailscale (et par le « CGNAT » des opérateurs).
    if dans_plage "$ip" 10.0.0.0/8 || dans_plage "$ip" 172.16.0.0/12 || dans_plage "$ip" 192.168.0.0/16; then
      categorie="IP privée"
    elif dans_plage "$ip" 100.64.0.0/10; then
      categorie="IP Tailscale"
    else
      categorie="IP publique"
    fi
    # On n'affiche que les deux premiers nombres de l'adresse.
    signaler "$fichier" "$num" "$categorie" "$(printf '%s' "$ip" | cut -d. -f1-2).…"
  done
done

# ---------------------------------------------------------------------------
# 2. Webhooks, clés privées, jetons : une expression régulière par format
# ---------------------------------------------------------------------------
# chercher <catégorie> <expression> [-i]
#   grep -r : récursif, -n : numéro de ligne, -o : seulement le morceau trouvé,
#   -I : ignore les fichiers binaires, -E : expression régulière étendue,
#   -i (si 3e argument) : sans distinguer majuscules et minuscules.
#   Le « -- » indique à grep que l'expression suit, même si elle commence par « - ».
chercher() {
  local categorie="$1" motif="$2" options="-rnoIE"
  [ "${3:-}" = "-i" ] && options="-rnoIEi"
  grep "$options" -- "$motif" "${dossiers[@]}" | while IFS= read -r ligne; do
    # Une ligne de grep : « fichier:numéro:texte trouvé ».
    local fichier="${ligne%%:*}" reste="${ligne#*:}"
    local num="${reste%%:*}" trouve="${reste#*:}"
    texte_autorise "$trouve" && continue
    signaler "$fichier" "$num" "$categorie" "$(tronquer "$trouve")"
  done
}

# Notations communes à plusieurs expressions :
#   https?://        « http:// » ou « https:// » (le ? rend le s facultatif)
#   [A-Za-z0-9_-]    une lettre, un chiffre, « _ » ou « - » (le « - » placé
#                    en dernier est un vrai tiret, pas un intervalle)
#   {20,}            au moins 20 fois ; {35} : exactement 35 fois
#   (a|b)            « a » ou « b »

# --- Webhooks : une adresse qui, à elle seule, permet de poster des messages.
# Discord : https://discord.com/api/webhooks/<numéro>/<jeton>
#   ([a-z]+\.)?      sous-domaine facultatif (ptb., canary.)
#   discord(app)?    discord.com ou l'ancien discordapp.com
chercher "Webhook Discord" 'https?://([a-z]+\.)?discord(app)?\.com/api/webhooks/[0-9]+/[A-Za-z0-9_-]+'
# Slack : https://hooks.slack.com/services/T…/B…/… (ou workflows/, triggers/)
chercher "Webhook Slack" 'https?://hooks\.slack\.com/(services|workflows|triggers)/[A-Za-z0-9/_-]+'
# Microsoft Teams : https://<entreprise>.webhook.office.com/webhookb2/…
chercher "Webhook Teams" 'https?://[A-Za-z0-9.-]+\.webhook\.office\.com/[A-Za-z0-9/@._-]+'
# Tout autre service (n8n, Home Assistant, Gotify…) : un chemin « /webhook/ »,
# « /webhooks/ » ou « /hooks/ » suivi d'un identifiant qui contient au moins
# 4 chiffres. Un identifiant secret est aléatoire, donc plein de chiffres ;
# une page de documentation (« /webhooks/webhook-events-and-payloads ») n'en
# a pas, et n'est donc pas signalée.
#   [^[:space:]"'<>)]+          l'adresse jusque-là : tout sauf espace,
#                               guillemets, chevrons et parenthèse (qui
#                               terminent une URL en Markdown)
#   ([A-Za-z0-9_-]*[0-9]){4}    4 fois : des caractères quelconques puis un
#                               chiffre -> au moins 4 chiffres au total
#   [A-Za-z0-9_/-]*             la suite de l'identifiant
chercher "Webhook" "https?://[^[:space:]\"'<>)]+/(webhooks?|hooks)/([A-Za-z0-9_-]*[0-9]){4}[A-Za-z0-9_/-]*"

# --- Clés privées (SSH, TLS, PGP…) : l'en-tête suffit à les reconnaître.
#   -----BEGIN       cinq tirets puis BEGIN
#   ([A-Z0-9]+ )*    zéro, un ou plusieurs mots : « RSA », « OPENSSH »,
#                    « EC », « ENCRYPTED », « PGP »…
#   PRIVATE KEY      le cœur de l'en-tête
#   ( BLOCK)?        « BLOCK » pour les clés PGP
chercher "Clé privée" '-----BEGIN ([A-Z0-9]+ )*PRIVATE KEY( BLOCK)?-----'

# --- Jetons : chaque service a un préfixe reconnaissable.
# GitHub : ghp_ (personnel), gho_, ghu_, ghs_, ghr_ + 36 caractères ou plus.
#   gh[pousr]_       « gh », une lettre parmi p o u s r, « _ »
chercher "Jeton GitHub" 'gh[pousr]_[A-Za-z0-9]{36,}'
# GitHub, jeton « fine-grained » : github_pat_ + ~80 caractères.
chercher "Jeton GitHub" 'github_pat_[A-Za-z0-9_]{50,}'
# AWS : clé d'accès AKIA (permanente) ou ASIA (temporaire) + 16 majuscules/chiffres.
chercher "Clé AWS" '(AKIA|ASIA)[A-Z0-9]{16}'
# Slack : xoxb- (bot), xoxp- (utilisateur), xoxa-, xoxo-, xoxs-, xoxr-.
chercher "Jeton Slack" 'xox[abposr]-[A-Za-z0-9-]{10,}'
# Tailscale : clé d'authentification ou d'API « tskey-… » (homelab !).
chercher "Clé Tailscale" 'tskey-[A-Za-z0-9-]{16,}'
# Google : clés d'API « AIza » + exactement 35 caractères.
chercher "Clé Google" 'AIza[A-Za-z0-9_-]{35}'
# Stripe : clés secrètes de production sk_live_ / rk_live_.
#   [sr]k_live_      « s » ou « r », puis « k_live_ »
chercher "Clé Stripe" '[sr]k_live_[A-Za-z0-9]{20,}'
# Anthropic, OpenAI… : deux familles de clés commençant par « sk- » :
#   - récentes : « sk-ant- », « sk-proj- » ou « sk-svcacct- » + 20 caractères ;
#   - anciennes : « sk- » + 32 lettres ou chiffres, SANS tiret.
#   (^|[^A-Za-z0-9_-])   « sk- » doit commencer un mot : sinon l'adresse
#                        « task-management-… » contiendrait une fausse clé.
chercher "Clé d'API (sk-)" '(^|[^A-Za-z0-9_-])sk-((ant|proj|svcacct)-[A-Za-z0-9_-]{20,}|[A-Za-z0-9]{32,})'
# Telegram : jeton de bot « <numéro du bot>:<35 caractères> ».
#   [0-9]{8,10}:     8 à 10 chiffres puis deux-points
chercher "Jeton Telegram" '[0-9]{8,10}:[A-Za-z0-9_-]{35}'
# Discord : jeton de bot, trois morceaux séparés par des points ; le premier
# commence par M, N ou O (l'identifiant du bot encodé en base64).
chercher "Jeton Discord" '[MNO][A-Za-z0-9_-]{23,27}\.[A-Za-z0-9_-]{6}\.[A-Za-z0-9_-]{27,40}'
# JWT (jetons de session de nombreux services) : trois morceaux base64 séparés
# par des points ; les deux premiers commencent par « eyJ » (« {" » encodé).
chercher "Jeton JWT" 'eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}'
# En-tête HTTP « Authorization: Bearer <jeton> », fréquent dans les exemples curl.
#   [A-Za-z0-9._~+/-]{20,}=*   les caractères autorisés d'un jeton « Bearer »,
#                              puis d'éventuels « = » de remplissage
chercher "Jeton Bearer" 'Bearer [A-Za-z0-9._~+/-]{20,}=*'
# Affectation générique, sans tenir compte des majuscules (-i) :
# « password = … », « API_KEY: "…" », « token=… », « mot_de_passe: … »
#   (password|…)        le nom de la variable
#   ["']?               un guillemet facultatif après le nom (JSON : "token": …)
#   [[:space:]]*[:=]    des espaces facultatifs puis « : » ou « = »
#   [[:space:]]*["']?   des espaces facultatifs, un guillemet facultatif
#   [A-Za-z0-9_+/=.-]{12,}   une valeur d'au moins 12 caractères « de secret ».
# Un exemple écrit « <votre-jeton> » n'est pas signalé (« < » n'en fait pas
# partie) : c'est la bonne façon d'écrire un exemple dans un article.
chercher "Secret en clair" "(password|passwd|pwd|mot_de_passe|secret|token|api[_-]?key|access[_-]?key)[\"']?[[:space:]]*[:=][[:space:]]*[\"']?[A-Za-z0-9_+/=.-]{12,}" -i

# ---------------------------------------------------------------------------
# Bilan
# ---------------------------------------------------------------------------
# Une même valeur peut être trouvée par deux expressions (une adresse Discord
# est aussi un « Webhook » générique) : awk ne garde qu'une détection par
# couple « fichier:ligne » + valeur. Puis tri par fichier et numéro de ligne,
# et la tabulation redevient un espace pour l'affichage.
if [ -s "$resultats" ]; then
  nombre="$(awk -F'\t' '{ split($2, p, "] "); if (!vu[$1 p[2]]++) print }' "$resultats" \
    | sort -t: -k1,1 -k2,2n | tr '\t' ' ' | tee /dev/stderr | wc -l | tr -d ' ')"
  echo >&2
  echo "ÉCHEC : $nombre information(s) sensible(s) trouvée(s)." >&2
  echo "Retire-les, remplace-les par un exemple (192.0.2.10, <votre-jeton>…)," >&2
  echo "ou, si c'est sans danger, ajoute une exception documentée dans" >&2
  echo "scripts/fuites-exceptions.txt." >&2
  exit 1
fi

echo "OK : aucune information sensible trouvée dans ${dossiers[*]}."
exit 0
