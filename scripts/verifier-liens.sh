#!/usr/bin/env bash
# Vérifie que tous les liens INTERNES du site construit mènent quelque part.
#
# Pourquoi : un lien cassé (article renommé, faute de frappe dans une
# adresse, titre modifié qui change une ancre #…) donne une page d'erreur au
# lecteur. Ce script parcourt toutes les pages de public/ et vérifie que
# chaque lien vers le blog lui-même correspond à un fichier existant, et
# que chaque ancre (#titre) existe dans la page visée.
# Les liens vers d'autres sites ne sont pas vérifiés (cela demanderait
# d'accéder à Internet, et un site externe peut être en panne un instant).
#
# Utilisation (après hugo) :
#   hugo --gc --minify && bash scripts/verifier-liens.sh
#   bash scripts/verifier-liens.sh autre-dossier
# Code de sortie : 0 = tous les liens fonctionnent, 1 = lien(s) cassé(s), 2 = erreur.

set -uo pipefail

racine="$(cd "$(dirname "$0")/.." && pwd)"
dossier="${1:-$racine/public}"

if [ ! -d "$dossier" ] || [ -z "$(find "$dossier" -name '*.html' -print -quit)" ]; then
  echo "Erreur : aucun fichier HTML dans « $dossier ». Lance d'abord : hugo --gc --minify" >&2
  exit 2
fi
dossier="$(cd "$dossier" && pwd)"

# Domaine du blog, lu dans hugo.toml : une adresse complète vers ce domaine
# (lien canonique, liens des pages de redirection…) est un lien interne.
#   .*//([^/]+)/.*   tout jusqu'à « // », puis le domaine (capturé), puis la suite
domaine="$(grep -E '^baseURL' "$racine/hugo.toml" | sed -E 's#.*//([^/]+)/.*#\1#')"

resultats="$(mktemp)"
trap 'rm -f "$resultats"' EXIT

# Décode les caractères écrits en « %XX » dans une adresse : un tag
# « sécurité » apparaît dans le HTML sous la forme « s%C3%A9curit%C3%A9 »,
# alors que le dossier sur le disque s'appelle bien « sécurité ».
# ${1//%/\\x} remplace chaque « % » par « \x », et printf '%b' interprète
# « \xC3 » comme l'octet C3.
decoder() { printf '%b' "${1//%/\\x}"; }

# Vrai si la page $1 contient un élément d'identifiant $2 (id="…").
#   id=[^"' >]+   un id sans guillemets (HTML minifié), jusqu'à l'espace ou « > »
ancre_existe() {
  grep -qF "id=\"$2\"" "$1" || grep -qF "id='$2'" "$1" \
    || grep -oE 'id=[^"'"'"' >]+' "$1" | grep -qxF "id=$2"
}

liens=0
while IFS= read -r -d '' page; do
  dossier_page="$(dirname "$page")"
  nom_page="${page#"$dossier"/}"

  # Tous les attributs href= et src= de la page. Trois formes possibles :
  #   "…"           valeur entre guillemets doubles
  #   '…'           valeur entre guillemets simples
  #   [^"' >]+      valeur sans guillemets (le minifieur les retire quand il peut)
  while IFS= read -r attribut; do
    valeur="${attribut#*=}"
    valeur="${valeur#[\"\']}"; valeur="${valeur%[\"\']}"   # retire les guillemets
    valeur="${valeur//&amp;/&}"                           # « &amp; » dans le HTML = « & »

    # Adresse complète : interne seulement si c'est notre domaine.
    case "$valeur" in
      ""|mailto:*|tel:*|javascript:*|data:*) continue ;;
      "https://$domaine"/*|"http://$domaine"/*|"//$domaine"/*)
        valeur="/${valeur#*//"$domaine"/}" ;;
      http://*|https://*|//*) continue ;;                 # autre site : non vérifié
    esac
    liens=$((liens + 1))

    # Séparer l'ancre (#…) et retirer les paramètres (?…).
    chemin="${valeur%%#*}"
    ancre=""
    case "$valeur" in *"#"*) ancre="${valeur#*#}" ;; esac
    chemin="${chemin%%\?*}"

    # Fichier visé sur le disque.
    if [ -z "$chemin" ]; then
      cible="$page"                                       # « #ancre » : même page
    elif [ "${chemin:0:1}" = "/" ]; then
      cible="$dossier$(decoder "$chemin")"                # depuis la racine du site
    else
      cible="$dossier_page/$(decoder "$chemin")"          # relatif à la page
    fi
    # Une adresse de dossier (« /journal/ ») sert son index.html. GitHub Pages
    # accepte aussi « /journal » sans « / » final s'il y a un dossier.
    if [ -d "$cible" ]; then cible="${cible%/}/index.html"; fi

    if [ ! -f "$cible" ]; then
      printf '%s: [lien cassé] %s\n' "$nom_page" "$valeur" >> "$resultats"
    elif [ -n "$ancre" ] && ! ancre_existe "$cible" "$(decoder "$ancre")"; then
      printf '%s: [ancre absente] %s\n' "$nom_page" "$valeur" >> "$resultats"
    fi
  done < <(grep -oE '(href|src)=("[^"]*"|'"'"'[^'"'"']*'"'"'|[^"'"'"' >]+)' "$page")
done < <(find "$dossier" -name '*.html' -print0)

if [ -s "$resultats" ]; then
  sort -u "$resultats" >&2
  echo >&2
  echo "ÉCHEC : $(sort -u "$resultats" | wc -l | tr -d ' ') lien(s) interne(s) cassé(s)." >&2
  exit 1
fi
echo "OK : $liens lien(s) interne(s) vérifié(s), tous valides."
exit 0
