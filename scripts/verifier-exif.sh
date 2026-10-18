#!/usr/bin/env bash
# Refuse toute image contenant des métadonnées EXIF ou XMP.
#
# Pourquoi : un appareil photo ou un téléphone ajoute dans l'image des
# informations invisibles : position GPS (souvent l'adresse du domicile),
# modèle de l'appareil, date et heure, parfois le nom du propriétaire.
# Elles partent en ligne avec l'image. EXIF est le format le plus courant ;
# XMP (Photoshop, Lightroom, certains téléphones) peut contenir les mêmes.
#
# Utilisation (Git Bash sous Windows, Terminal sous Mac/Linux, ou la CI) :
#   bash scripts/verifier-exif.sh                 -> content/, static/ et assets/
#   bash scripts/verifier-exif.sh dossier1 …      -> ces dossiers-là
# Code de sortie : 0 = images propres, 1 = métadonnées trouvées, 2 = erreur.
#
# Comment : aucun outil à installer. « od » (présent partout) affiche les
# octets du fichier en hexadécimal ; on y cherche les « signatures » qui
# annoncent un bloc de métadonnées dans chaque format d'image.

set -uo pipefail

racine="$(cd "$(dirname "$0")/.." && pwd)"

if [ "$#" -gt 0 ]; then
  dossiers=("$@")
else
  cd "$racine" || exit 2
  dossiers=()
  for d in content static assets; do [ -d "$d" ] && dossiers+=("$d"); done
fi
for d in "${dossiers[@]}"; do
  if [ ! -d "$d" ]; then
    echo "Erreur : le dossier « $d » n'existe pas." >&2
    exit 2
  fi
done

# Convertit un texte en sa suite d'octets hexadécimaux, au format de la
# sortie de od ci-dessous : « Exif » -> « 45 78 69 66 ».
en_hexa() {
  printf '%s' "$1" | od -An -tx1 -v | tr -s ' \n' '  ' | sed 's/^ *//; s/ *$//'
}

# Signatures recherchées (en hexadécimal, encadrées d'espaces pour ne
# trouver que des octets entiers, jamais un « demi-octet » à cheval) :
#
# Tous formats :
#   « Exif » suivi de deux octets nuls (00 00) : l'en-tête d'un bloc EXIF dans
#   un JPEG (segment APP1), un HEIC/AVIF ou un WebP.
sig_exif=" $(en_hexa Exif) 00 00 "
#   « <x:xmpmeta » : la balise qui ouvre un paquet XMP (c'est du texte XML).
sig_xmp=" $(en_hexa '<x:xmpmeta') "
# PNG :
#   « eXIf » : nom du bloc (« chunk ») qui contient l'EXIF d'un PNG.
sig_png_exif=" $(en_hexa eXIf) "
#   « XML:com.adobe.xmp » : mot-clé du bloc texte qui contient le XMP d'un PNG
#   (utile quand ce bloc est compressé et que « <x:xmpmeta » n'est pas lisible).
sig_png_xmp=" $(en_hexa 'XML:com.adobe.xmp') "
#   « Raw profile type exif » : EXIF rangé dans un bloc texte par ImageMagick.
sig_png_brut=" $(en_hexa 'Raw profile type exif') "
# WebP :
#   « EXIF » et « XMP » suivi d'un espace : noms des blocs de métadonnées.
sig_webp_exif=" $(en_hexa EXIF) "
sig_webp_xmp=" $(en_hexa 'XMP ') "

problemes=0
images=0

# find : toutes les images, quelle que soit la casse de l'extension (-iname).
# -print0 et read -d '' : les noms de fichiers peuvent contenir des espaces.
while IFS= read -r -d '' image; do
  images=$((images + 1))
  trouve=""

  # Extension en minuscules (tr : compatible avec le vieux Bash de macOS).
  extension="$(printf '%s' "${image##*.}" | tr '[:upper:]' '[:lower:]')"

  case "$extension" in
    tif|tiff)
      # Dans un TIFF, l'EXIF fait partie de la structure même du fichier :
      # impossible de le garantir propre. Format inutile sur le web.
      trouve="format TIFF refusé (convertir en PNG, JPEG ou WebP)" ;;
    *)
      # Le fichier entier en hexadécimal, sur UNE ligne, octets séparés par
      # un espace : « 89 50 4e 47 0d 0a … ». Espaces ajoutés aux deux bouts.
      hexa=" $(od -An -tx1 -v "$image" | tr -s ' \n' '  ') "

      # Signatures à chercher selon le format.
      signatures=("EXIF|$sig_exif" "XMP|$sig_xmp")
      case "$extension" in
        png) signatures+=("EXIF (bloc eXIf)|$sig_png_exif" "XMP (bloc texte)|$sig_png_xmp" "EXIF (bloc texte ImageMagick)|$sig_png_brut") ;;
        webp) signatures+=("EXIF (bloc EXIF)|$sig_webp_exif" "XMP (bloc XMP)|$sig_webp_xmp") ;;
      esac

      for s in "${signatures[@]}"; do
        nom="${s%%|*}"
        motif="${s#*|}"
        # case … *motif* : vrai si le motif apparaît quelque part.
        case "$hexa" in
          *"$motif"*) trouve="${trouve:+$trouve, }$nom" ;;
        esac
      done ;;
  esac

  if [ -n "$trouve" ]; then
    echo "$image : $trouve" >&2
    problemes=$((problemes + 1))
  fi
done < <(find "${dossiers[@]}" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
  -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.avif' -o -iname '*.heic' -o -iname '*.heif' \
  -o -iname '*.tif' -o -iname '*.tiff' \) -print0)

if [ "$problemes" -gt 0 ]; then
  echo >&2
  echo "ÉCHEC : $problemes image(s) sur $images contiennent des métadonnées." >&2
  echo "Pour les retirer :" >&2
  echo "  - avec ExifTool : exiftool -all= -overwrite_original <image>" >&2
  echo "  - ou réexporter l'image depuis un logiciel avec l'option « sans métadonnées »" >&2
  echo "    (GIMP : Exporter > décocher EXIF et XMP)." >&2
  exit 1
fi

echo "OK : $images image(s) vérifiée(s), aucune métadonnée EXIF ou XMP."
exit 0
