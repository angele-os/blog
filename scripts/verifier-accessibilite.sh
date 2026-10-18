#!/usr/bin/env bash
# Vérifie les règles d'accessibilité de base sur le site construit.
#
# Pourquoi : une personne aveugle navigue avec un lecteur d'écran, qui lit la
# page à voix haute et permet de sauter de titre en titre ; d'autres
# naviguent uniquement au clavier. Ces règles leur rendent le site utilisable.
# Lighthouse les vérifie aussi, mais à la main et page par page ; ce script
# les vérifie sur TOUTES les pages à chaque construction (dans la CI).
#
# Pour chaque page HTML de public/ :
#   - la langue est indiquée (<html lang="fr">) : le lecteur d'écran prend
#     la bonne voix et la bonne prononciation ;
#   - la page a un titre (<title>) : c'est ce qui est annoncé en premier ;
#   - exactement UN titre principal <h1> ;
#   - les titres se suivent sans sauter de niveau (pas de <h1> puis <h3>) ;
#   - chaque image a un attribut alt (vide autorisé pour une image décorative) ;
#   - chaque lien a un texte (un lien vide est annoncé « lien » sans plus) ;
#   - le lien d'évitement « Aller au contenu » et sa cible id="contenu" existent.
#
# Utilisation (après hugo) :
#   hugo --gc --minify && bash scripts/verifier-accessibilite.sh
#   bash scripts/verifier-accessibilite.sh autre-dossier
# Code de sortie : 0 = conforme, 1 = problème(s), 2 = erreur.

set -uo pipefail

racine="$(cd "$(dirname "$0")/.." && pwd)"
dossier="${1:-$racine/public}"

if [ ! -d "$dossier" ] || [ -z "$(find "$dossier" -name '*.html' -print -quit)" ]; then
  echo "Erreur : aucun fichier HTML dans « $dossier ». Lance d'abord : hugo --gc --minify" >&2
  exit 2
fi

resultats="$(mktemp)"
trap 'rm -f "$resultats"' EXIT

signaler() {  # $1 = page, $2 = règle, $3 = détail
  printf '%s: [%s] %s\n' "$1" "$2" "$3" >> "$resultats"
}

# Notation commune : ([[:space:]]|>) = un espace ou « > » juste après le nom
# de la balise, pour que « <h1 » ne trouve pas aussi « <h1x ».
pages=0
while IFS= read -r -d '' fichier; do
  nom="${fichier#"$dossier"/}"

  # Les pages de redirection de Hugo (layouts/alias.html) n'ont pas de
  # contenu : elles renvoient tout de suite ailleurs. On les ignore.
  #   http-equiv=["']?refresh   la balise <meta> qui fait la redirection
  if grep -qiE 'http-equiv=["'"'"']?refresh' "$fichier"; then continue; fi
  pages=$((pages + 1))

  # Langue : <html … lang="fr"…>
  #   <html[^>]*      la balise <html>, jusqu'à la fin de ses attributs
  #   lang=["']?[a-z] un attribut lang, guillemet facultatif, puis une lettre
  grep -qiE '<html[^>]*[[:space:]]lang=["'"'"']?[a-z]' "$fichier" \
    || signaler "$nom" "langue" "<html> n'a pas d'attribut lang"

  # Titre de la page : <title> suivi d'au moins un caractère avant </title>.
  #   [^<]+   un ou plusieurs caractères qui ne sont pas « < »
  grep -qiE '<title>[^<]+</title>' "$fichier" \
    || signaler "$nom" "titre de page" "<title> absent ou vide"

  # Titres : on extrait leur niveau, dans l'ordre de la page.
  #   <h([1-6])([[:space:]]|>)   « <h » suivi d'un chiffre de 1 à 6
  # Le sed garde seulement le chiffre : « <h2 id=… » -> « 2 ».
  niveaux="$(grep -oiE '<h[1-6]([[:space:]]|>)' "$fichier" | sed -E 's/<[hH]([1-6]).*/\1/' | tr '\n' ' ')"
  nb_h1="$(printf '%s' "$niveaux" | tr ' ' '\n' | grep -c '^1$')"
  [ "$nb_h1" -eq 1 ] || signaler "$nom" "titre principal" "$nb_h1 <h1> au lieu d'un seul"
  # Ordre : chaque titre peut descendre d'UN niveau au plus (h2 -> h3),
  # remonter librement (h3 -> h2), et le premier doit être un h1.
  saut="$(printf '%s' "$niveaux" | awk '{
      prec = 0
      for (i = 1; i <= NF; i++) {
        if ($i > prec + 1) { printf "h%d puis h%d", prec, $i; exit }
        prec = $i
      }
    }')"
  [ -z "$saut" ] || signaler "$nom" "ordre des titres" "niveau sauté : ${saut/h0 puis/début de page puis}"

  # Images sans alt : on liste les balises <img …>, puis on garde celles où
  # « alt » n'apparaît pas comme attribut.
  #   <img[^>]*>                    une balise <img> entière
  #   [[:space:]]alt([[:space:]]|=|>)   l'attribut alt (avec ou sans valeur)
  grep -oiE '<img[^>]*>' "$fichier" | grep -viE '[[:space:]]alt([[:space:]]|=|>)' | while IFS= read -r img; do
    signaler "$nom" "image sans alt" "${img:0:90}"
  done

  # Liens sans texte : <a …> suivi directement de </a> (espaces permis).
  # Un lien avec aria-label est accepté (son nom vient de là).
  #   <a([[:space:]][^>]*)?>   la balise ouvrante <a> avec ou sans attributs
  #   [[:space:]]*</a>         rien d'autre que des espaces avant </a>
  grep -oiE '<a([[:space:]][^>]*)?>[[:space:]]*</a>' "$fichier" | grep -viE 'aria-label=' | while IFS= read -r lien; do
    signaler "$nom" "lien sans texte" "${lien:0:90}"
  done

  # Lien d'évitement et sa cible.
  #   href=["']?#contenu   un lien vers l'ancre #contenu
  #   id=["']?contenu      l'élément qui porte cet identifiant
  grep -qiE 'href=["'"'"']?#contenu' "$fichier" || signaler "$nom" "lien d'évitement" "lien « Aller au contenu » absent"
  grep -qiE '[[:space:]]id=["'"'"']?contenu([[:space:]"'"'"'>])' "$fichier" || signaler "$nom" "lien d'évitement" "cible id=\"contenu\" absente"
done < <(find "$dossier" -name '*.html' -print0)

if [ -s "$resultats" ]; then
  sort "$resultats" >&2
  echo >&2
  echo "ÉCHEC : $(wc -l < "$resultats" | tr -d ' ') problème(s) d'accessibilité." >&2
  exit 1
fi
echo "OK : $pages page(s) HTML vérifiées, règles d'accessibilité de base respectées."
exit 0
