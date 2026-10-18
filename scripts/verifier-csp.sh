#!/usr/bin/env bash
# Vérifie que le site construit respecte sa politique de sécurité (CSP).
#
# La CSP (voir layouts/_partials/head.html) interdit au navigateur d'exécuter
# du JavaScript, d'appliquer des styles en ligne et de charger quoi que ce
# soit depuis un autre site. Si le site en contenait quand même, le
# navigateur le bloquerait sans bruit : la page serait cassée sans qu'on le
# sache. Ce script repère ces cas AVANT la mise en ligne.
#
# Il analyse le site déjà construit (dossier public/), donc à lancer après hugo :
#   hugo --gc --minify && bash scripts/verifier-csp.sh
#   bash scripts/verifier-csp.sh autre-dossier      -> analyse ce dossier-là
# Code de sortie : 0 = conforme, 1 = violation(s), 2 = erreur.
#
# Compatibilité : bash, grep, sed, awk (Linux, Git Bash, macOS).

set -uo pipefail

racine="$(cd "$(dirname "$0")/.." && pwd)"
dossier="${1:-$racine/public}"

if [ ! -d "$dossier" ] || [ -z "$(find "$dossier" -name '*.html' -print -quit)" ]; then
  echo "Erreur : aucun fichier HTML dans « $dossier ». Lance d'abord : hugo --gc --minify" >&2
  exit 2
fi

# La CSP attendue : copie exacte de celle de CLAUDE.md (règle n° 4).
csp_attendue="default-src 'none'; style-src 'self'; img-src 'self'; font-src 'self'; base-uri 'none'; form-action 'none'"

# Domaine du blog, lu dans hugo.toml (« baseURL = "https://blog…/" ») :
# les adresses complètes vers ce domaine sont autorisées (même site).
#   .*//       tout jusqu'à « // » compris
#   ([^/]+)    le domaine : tout jusqu'au « / » suivant (capturé, \1)
#   /.*        la fin de la ligne
domaine="$(grep -E '^baseURL' "$racine/hugo.toml" | sed -E 's#.*//([^/]+)/.*#\1#')"
domaine_motif="$(printf '%s' "$domaine" | sed 's/\./\\./g')"   # « . » -> « \. »

resultats="$(mktemp)"
trap 'rm -f "$resultats"' EXIT

# Raccourcit un extrait à 90 caractères pour l'affichage.
couper() {
  if [ "${#1}" -le 90 ]; then printf '%s' "$1"; else printf '%s…' "${1:0:90}"; fi
}

# regle <nom> <expression> <fichiers> [-i]
#   Cherche l'expression dans les fichiers du type donné (ex. « *.html ») et
#   note chaque endroit trouvé. -o : seulement le morceau trouvé (un HTML
#   minifié tient sur une ligne : afficher toute la ligne serait illisible).
regle() {
  local nom="$1" motif="$2" fichiers="$3" options="-rnoE"
  [ "${4:-}" = "-i" ] && options="-rnoEi"
  grep "$options" --include="$fichiers" -- "$motif" "$dossier" | while IFS= read -r ligne; do
    local fichier="${ligne%%:*}" reste="${ligne#*:}"
    printf '%s:%s: [%s] %s\n' "${fichier#"$dossier"/}" "${reste%%:*}" "$nom" "$(couper "${reste#*:}")" >> "$resultats"
  done
}

# Notations communes :
#   <[a-zA-Z][^>]*   le début d'une balise HTML : « < », une lettre, puis tout
#                    sauf « > » (on reste DANS la balise). Le texte d'un
#                    article qui parle de « style= » ne compte pas : dans le
#                    HTML, son « < » est écrit « &lt; ».
#   [[:space:]]      un espace, une tabulation ou un retour à la ligne
#   ["']?            un guillemet facultatif (le HTML minifié les retire souvent)

# --- 1. Ce que « style-src 'self' » interdit : les styles en ligne ---------
# Attribut style="…" sur une balise (SVG compris).
regle "style en ligne" '<[a-zA-Z][^>]*[[:space:]]style[[:space:]]*=' '*.html' -i
# Balise <style>…</style> dans la page.
#   <style([[:space:]]|>)   « <style » suivi d'un espace ou de « > » (et pas
#                           « <styleXYZ »)
regle "balise <style>" '<style([[:space:]]|>)' '*.html' -i

# --- 2. Ce que « default-src 'none' » interdit : tout script --------------
regle "balise <script>" '<script([[:space:]]|>)' '*.html' -i
# Attributs d'événement : onclick=, onload=, onerror=…
#   [[:space:]]on[a-z]+[[:space:]]*=   un espace, « on », des lettres, « = »
regle "attribut on…= (script)" '<[a-zA-Z][^>]*[[:space:]]on[a-z]+[[:space:]]*=' '*.html' -i
# Liens « javascript: » (un script déguisé en adresse).
regle "lien javascript:" '(href|src|action)[[:space:]]*=[[:space:]]*["'"'"']?[[:space:]]*javascript:' '*.html' -i
# Cadres et objets intégrés (iframe, object, embed) : interdits aussi.
regle "cadre ou objet intégré" '<(iframe|frame|object|embed)([[:space:]]|>)' '*.html' -i
# « base-uri 'none' » et « form-action 'none' » : ni <base>, ni formulaire.
regle "balise <base>" '<base([[:space:]]|>)' '*.html' -i
regle "formulaire" '<form([[:space:]]|>)' '*.html' -i

# --- 3. Ce que « img-src / font-src / style-src 'self' » interdit :
#        charger une ressource depuis un autre site, ou une adresse « data: »
# Attributs qui CHARGENT quelque chose (src, srcset, poster), et href des
# balises SVG <image> et <use>, dont la valeur commence par :
#   https?:   http: ou https:
#   //        adresse « sans protocole » (même chose, autre site possible)
#   data:     contenu intégré dans l'adresse (interdit par 'self')
# Les adresses vers notre propre domaine sont retirées ensuite (grep -v).
grep -rnoEi --include='*.html' -- \
  '((src|srcset|poster)|<(image|use)[^>]*[[:space:]](xlink:)?href)[[:space:]]*=[[:space:]]*["'"'"']?[[:space:]]*(https?:|//|data:)[^"'"'"' >]*' "$dossier" \
  | grep -viE "//$domaine_motif(/|[\"' >]|$)" \
  | while IFS= read -r ligne; do
      fichier="${ligne%%:*}"; reste="${ligne#*:}"
      printf '%s:%s: [%s] %s\n' "${fichier#"$dossier"/}" "${reste%%:*}" "ressource externe" "$(couper "${reste#*:}")" >> "$resultats"
    done

# Balises <link> qui chargent un fichier (feuille de style, icône,
# préchargement…) : leur href ne doit pas viser un autre site.
# Les <link> qui ne chargent rien (canonical, alternate, license) sont ignorées.
#   <link[^>]*>                          une balise <link> entière
#   rel=["']?([a-z-]+ )*(stylesheet|…)   l'attribut rel contient un de ces mots
#   href=["']?(https?:)?//               une adresse vers un site (externe ou non)
grep -rnoEi --include='*.html' -- '<link[^>]*>' "$dossier" \
  | grep -iE 'rel=["'"'"']?([a-z-]+ )*(stylesheet|icon|preload|modulepreload|prefetch|preconnect|dns-prefetch|manifest|apple-touch-icon)' \
  | grep -iE 'href=["'"'"']?(https?:)?//|href=["'"'"']?data:' \
  | grep -viE "href=[\"']?(https?:)?//$domaine_motif/" \
  | while IFS= read -r ligne; do
      fichier="${ligne%%:*}"; reste="${ligne#*:}"
      printf '%s:%s: [%s] %s\n' "${fichier#"$dossier"/}" "${reste%%:*}" "<link> externe" "$(couper "${reste#*:}")" >> "$resultats"
    done

# Feuilles de style : pas d'@import (il chargerait un autre fichier sans
# contrôle d'intégrité), et url(…) seulement vers notre site.
#   url\(            « url( » (la parenthèse est « échappée » : \( )
#   [[:space:]]*["']?[[:space:]]*   espaces et guillemet facultatifs
#   (https?:|//|data:)              une adresse externe ou « data: »
regle "@import dans le CSS" '@import' '*.css' -i
regle "url() externe dans le CSS" 'url\([[:space:]]*["'"'"']?[[:space:]]*(https?:|//|data:)[^)]*' '*.css' -i

# --- 4. Fichiers SVG : ouverts directement, ils sont servis SANS notre CSP
#        (GitHub Pages n'envoie pas d'en-tête) : aucun script ne doit s'y trouver.
regle "script dans un SVG" '<script([[:space:]]|>)|[[:space:]]on[a-z]+[[:space:]]*=' '*.svg' -i

# --- 5. Chaque page HTML porte la CSP attendue, AVANT toute feuille de style
#        (une CSP en <meta> ne s'applique qu'à ce qui la suit).
while IFS= read -r -d '' page; do
  nom="${page#"$dossier"/}"
  if ! grep -qiE 'http-equiv=["'"'"']?Content-Security-Policy' "$page"; then
    echo "$nom: [CSP absente] la page n'a pas de balise CSP" >> "$resultats"
    continue
  fi
  if ! grep -qF "content=\"$csp_attendue\"" "$page"; then
    echo "$nom: [CSP différente] la valeur ne correspond pas à CLAUDE.md" >> "$resultats"
  fi
  # grep -b donne la position (en octets) de chaque élément trouvé.
  pos_csp="$(grep -boi 'Content-Security-Policy' "$page" | head -1 | cut -d: -f1)"
  pos_css="$(grep -boiE '<link[^>]*rel=["'"'"']?stylesheet' "$page" | head -1 | cut -d: -f1)"
  if [ -n "$pos_css" ] && [ "$pos_csp" -gt "$pos_css" ]; then
    echo "$nom: [CSP trop tard] une feuille de style est chargée avant la CSP" >> "$resultats"
  fi
done < <(find "$dossier" -name '*.html' -print0)

# --- Bilan --------------------------------------------------------------------
pages="$(find "$dossier" -name '*.html' | wc -l | tr -d ' ')"
if [ -s "$resultats" ]; then
  sort -u "$resultats" >&2
  echo >&2
  echo "ÉCHEC : $(sort -u "$resultats" | wc -l | tr -d ' ') violation(s) de la CSP dans $dossier." >&2
  echo "Le navigateur bloquerait ces éléments. Remplace les styles en ligne par des" >&2
  echo "classes CSS, retire les scripts, et sers les ressources depuis le site." >&2
  exit 1
fi
echo "OK : $pages page(s) HTML conformes à la CSP, aucune ressource externe."
exit 0
