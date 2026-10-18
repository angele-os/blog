#!/usr/bin/env bash
# Génère les feuilles de style de la coloration du code.
#
# Pourquoi : Hugo colore le code en posant des classes CSS (par ex. « k »
# pour un mot-clé) au lieu de styles en ligne, interdits par notre CSP
# (voir markup.highlight.noClasses = false dans hugo.toml). Il faut donc
# une feuille de style qui donne une couleur à chaque classe : Hugo sait la
# fabriquer avec « hugo gen chromastyles ».
#
# Thèmes choisis : modus-operandi (clair) et modus-vivendi (sombre). Ils sont
# conçus pour l'accessibilité : toutes leurs couleurs restent lisibles
# (contraste AA) sur nos fonds de code. Seuls leurs numéros de ligne sont
# trop pâles : on les remplace par le gris « --ink-3 » du site. Et leur fond
# de ligne surlignée (option hl_lines) se confondait avec notre fond de code :
# on le fonce un peu (clair) ou on l'éclaircit (sombre).
#
# Quand le relancer : seulement si on change de thème. Les fichiers produits
# sont versionnés, le site n'a pas besoin de ce script pour se construire.
#
# Utilisation (Git Bash sous Windows, ou Terminal sous Mac/Linux),
# depuis la racine du dépôt :
#   bash scripts/generer-styles-code.sh

# Arrête le script à la première erreur, au lieu de continuer à moitié.
set -euo pipefail

# Se place à la racine du dépôt, d'où que le script soit lancé.
cd "$(dirname "$0")/.."

destination="assets/css"

# Une fonction pour éviter d'écrire deux fois la même longue commande.
# $1 = thème Chroma, $2 = couleur des numéros de ligne,
# $3 = fond des lignes surlignées, $4 = fichier de sortie
generer() {
  hugo gen chromastyles \
    --style="$1" \
    --omitClassComments \
    --lineNumbersInlineStyle="$2" \
    --lineNumbersTableStyle="$2" \
    --highlightStyle="bg:$3" \
    > "$destination/$4"
  echo "Écrit : $destination/$4 (thème $1)"
}

generer modus-operandi "#59636D" "#D8E0E3" code-clair.css
generer modus-vivendi  "#95A1AB" "#26323B" code-sombre.css
