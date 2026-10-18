#!/usr/bin/env bash
# Teste verifier-fuites.sh et verifier-exif.sh sur des fichiers d'essai.
#
# Pourquoi : un garde-fou qui ne sonne jamais ne prouve rien. Ce script crée,
# dans un dossier temporaire (jamais dans le dépôt), des fichiers qui DOIVENT
# être signalés et d'autres qui ne doivent PAS l'être, puis vérifie la réponse
# des deux scripts. À relancer après chaque modification d'une expression
# régulière.
#
# Les faux secrets sont fabriqués par morceaux (« gh""p_ ») : écrits d'un
# bloc, ils feraient sonner la détection de secrets de GitHub sur CE fichier.
#
# Utilisation : bash scripts/tester-garde-fous.sh
# Code de sortie : 0 = tous les cas sont bons, 1 = au moins un cas faux.

set -uo pipefail

racine="$(cd "$(dirname "$0")/.." && pwd)"
essai="$(mktemp -d)"
trap 'rm -rf "$essai"' EXIT

echecs=0
reussites=0

# verifier <description> <condition vraie ?>
ok()    { reussites=$((reussites + 1)); echo "  OK     $1"; }
echec() { echecs=$((echecs + 1));       echo "  ÉCHEC  $1"; }

# Répète un caractère : repeter a 36 -> « aaaa…a » (36 fois).
repeter() { printf "%${2}s" "" | tr ' ' "$1"; }

# ===========================================================================
echo "== verifier-fuites.sh"
# ===========================================================================
mkdir -p "$essai/fuites/doit-sonner" "$essai/fuites/ne-doit-pas-sonner"
d="$essai/fuites/doit-sonner"
n="$essai/fuites/ne-doit-pas-sonner"

# --- Cas qui DOIVENT être signalés (un fichier par cas) --------------------
printf 'Mon serveur répond en 192.168.1.20.\n'            > "$d/ip-privee-192.txt"
printf 'Passerelle : 10.0.0.1\n'                          > "$d/ip-privee-10.txt"
printf 'NAS en 172.20.5.4 sur le VLAN\n'                  > "$d/ip-privee-172.txt"
printf 'Joignable par Tailscale (100.101.102.103)\n'      > "$d/ip-tailscale.txt"
printf 'Mon IP publique est 81.12.34.56\n'                > "$d/ip-publique.txt"
printf 'liste : 192.0.2.1,10.0.0.7\n'                     > "$d/ip-apres-exception.txt"
printf 'url: https://discord.com/api/webhooks/%s/%s\n' "123456789012345678" "$(repeter A 40)" > "$d/webhook-discord.txt"
printf 'https://hooks.slack.com/services/T%s/B%s/%s\n' "0000000" "0000000" "$(repeter x 24)" > "$d/webhook-slack.txt"
printf 'https://entreprise.webhook.office.com/webhookb2/%s\n' "abc-123"                  > "$d/webhook-teams.txt"
printf 'curl https://n8n.exemple.fr/webhook/%s\n' "3f2a9c1e-7b4d-4e2a-9c1e-7b4d4e2a9c1e" > "$d/webhook-generique.txt"
printf -- '-----BEGIN %s PRIVATE KEY-----\n' "OPENSSH"    > "$d/cle-ssh.txt"
printf -- '-----BEGIN PRIVATE %s-----\n' "KEY"            > "$d/cle-pkcs8.txt"
printf -- '-----BEGIN PGP PRIVATE KEY %s-----\n' "BLOCK"  > "$d/cle-pgp.txt"
printf 'jeton %s\n' "gh""p_$(repeter a 36)"               > "$d/jeton-github.txt"
printf 'jeton %s\n' "github""_pat_$(repeter B 60)"        > "$d/jeton-github-fin.txt"
printf 'cle %s\n' "AK""IA$(repeter Z 16)"                 > "$d/cle-aws.txt"
printf 'jeton %s\n' "xox""b-$(repeter 1 12)"              > "$d/jeton-slack.txt"
printf 'tailscale up --authkey=%s\n' "tskey""-auth-$(repeter k 20)" > "$d/cle-tailscale.txt"
printf 'cle %s\n' "AI""za$(repeter q 35)"                 > "$d/cle-google.txt"
printf 'cle %s\n' "sk""_live_$(repeter r 24)"            > "$d/cle-stripe.txt"
printf 'cle %s\n' "sk""-ant-$(repeter s 30)"              > "$d/cle-anthropic.txt"
printf 'cle %s\n' "sk""-$(repeter t 40)"                  > "$d/cle-openai-ancienne.txt"
printf 'bot %s\n' "123456789:$(repeter u 35)"             > "$d/jeton-telegram.txt"
printf 'bot %s\n' "M$(repeter v 25).abcdef.$(repeter w 30)" > "$d/jeton-discord.txt"
printf 'jwt %s\n' "ey""J$(repeter x 10).ey""J$(repeter y 10).$(repeter z 10)" > "$d/jeton-jwt.txt"
printf 'curl -H "Authorization: Bearer %s"\n' "$(repeter b 30)" > "$d/jeton-bearer.txt"
printf 'DB_PASSWORD=%s\n' "Tr0ub4dor3xyz"                 > "$d/secret-motdepasse.txt"
printf '"api_key": "%s"\n' "$(repeter c 20)"              > "$d/secret-json.txt"

# --- Cas qui ne doivent PAS être signalés ---------------------------------
printf 'Exemple : 192.0.2.10 et 203.0.113.5\n'                  > "$n/ip-documentation.txt"
printf 'Masque 255.255.255.0, boucle 127.0.0.1, 0.0.0.0\n'     > "$n/ip-speciales.txt"
printf 'Hugo 0.168.0 et Debian 12.4\n'                           > "$n/numero-version.txt"
printf 'Valeur 1234.1.1.1 (pas une IP)\n'                        > "$n/nombre-long.txt"
printf 'Octets trop grands : 300.1.1.1\n'                        > "$n/ip-invalide.txt"
printf 'token: <votre-jeton>\n'                                  > "$n/exemple-jeton.txt"
printf 'Voir https://docs.github.com/en/webhooks/webhook-events-and-payloads\n' > "$n/doc-webhooks.txt"
printf 'Article : https://exemple.fr/task-management-for-small-teams-guide\n'   > "$n/adresse-sk.txt"
printf 'jeton %s (exemple autorisé)\n' "gh""p_EXEMPLE$(repeter a 30)"           > "$n/exception-texte.txt"
printf 'Un texte tout à fait normal.\n'                          > "$n/texte-normal.txt"

# Fichier d'exceptions d'essai : les vraies exceptions + un « texte ».
exceptions="$essai/exceptions.txt"
cp "$racine/scripts/fuites-exceptions.txt" "$exceptions"
printf "texte  ghp_EXEMPLE   # jeton d'exemple de la documentation\n" >> "$exceptions"

# Lancement sur les deux dossiers d'essai.
sortie="$(FUITES_EXCEPTIONS="$exceptions" bash "$racine/scripts/verifier-fuites.sh" "$d" "$n" 2>&1)"
code=$?

[ "$code" -eq 1 ] && ok "code de sortie 1 quand il y a des fuites" || echec "code de sortie attendu 1, obtenu $code"

for f in "$d"/*; do
  nom="$(basename "$f")"
  if printf '%s\n' "$sortie" | grep -qF "$nom:"; then ok "signalé      : $nom"; else echec "NON signalé  : $nom"; fi
done
for f in "$n"/*; do
  nom="$(basename "$f")"
  if printf '%s\n' "$sortie" | grep -qF "$nom:"; then echec "signalé à tort : $nom"; else ok "ignoré       : $nom"; fi
done

# Cas particuliers sur le contenu de la sortie.
printf '%s\n' "$sortie" | grep -qF "ip-apres-exception.txt:1: [IP privée] 10.0" \
  && ok "deux IP collées : l'exception ne masque pas la seconde" \
  || echec "deux IP collées : la seconde n'est pas trouvée"
printf '%s\n' "$sortie" | grep -qF "ip-publique.txt:1: [IP publique]" \
  && ok "catégorie « IP publique »" || echec "catégorie « IP publique » absente"
printf '%s\n' "$sortie" | grep -qF "ip-tailscale.txt:1: [IP Tailscale]" \
  && ok "catégorie « IP Tailscale »" || echec "catégorie « IP Tailscale » absente"
printf '%s\n' "$sortie" | grep -qF "$(repeter a 36)" \
  && echec "un secret est affiché en entier" || ok "les secrets sont tronqués à l'affichage"

# Dossier propre : code 0.
FUITES_EXCEPTIONS="$exceptions" bash "$racine/scripts/verifier-fuites.sh" "$n" > /dev/null 2>&1
code=$?
[ "$code" -eq 0 ] && ok "code de sortie 0 sur un dossier propre" || echec "code de sortie attendu 0, obtenu $code"

# Exception mal écrite : code 2.
printf 'ip 999.1.1.1/8\n' > "$essai/exceptions-fausses.txt"
FUITES_EXCEPTIONS="$essai/exceptions-fausses.txt" bash "$racine/scripts/verifier-fuites.sh" "$n" > /dev/null 2>&1
code=$?
[ "$code" -eq 2 ] && ok "code de sortie 2 sur une exception invalide" || echec "code de sortie attendu 2, obtenu $code"

# ===========================================================================
echo "== verifier-exif.sh"
# ===========================================================================
mkdir -p "$essai/images/sales" "$essai/images/propres"
s="$essai/images/sales"
p="$essai/images/propres"

# De fausses images : seuls les premiers octets ressemblent au vrai format,
# ce qui suffit pour tester la recherche des signatures.
# JPEG : FF D8 (début d'image), puis segment APP1 (FF E1) contenant « Exif\0\0 ».
printf '\xff\xd8\xff\xe1\x00\x10Exif\x00\x00MM\x00\x2a\xff\xd9'          > "$s/photo-exif.jpg"
# JPEG avec XMP (texte XML dans un segment APP1).
printf '\xff\xd8\xff\xe1\x00\x40<x:xmpmeta xmlns:x="adobe:ns:meta/">\xff\xd9' > "$s/photo-xmp.JPG"
# PNG : signature PNG puis un bloc nommé « eXIf ».
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\x04eXIfMM\x00\x2a'                 > "$s/capture-exif.png"
# PNG : bloc texte compressé « XML:com.adobe.xmp ».
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\x20iTXtXML:com.adobe.xmp\x00\x01\x00' > "$s/capture-xmp.png"
# WebP : en-tête RIFF/WEBP puis un bloc « EXIF ».
printf 'RIFF\x20\x00\x00\x00WEBPVP8X\x0a\x00\x00\x00EXIF\x08\x00\x00\x00'  > "$s/image-exif.webp"
# TIFF : toujours refusé.
printf 'II*\x00\x08\x00\x00\x00'                                           > "$s/scan.tiff"

# Images propres : seulement la structure, sans métadonnées.
printf '\xff\xd8\xff\xdb\x00\x43\x00\xff\xd9'                              > "$p/photo.jpg"
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR\x00\x00\x00\x01'             > "$p/capture.png"
# « Exif » sans les deux octets nuls : simple texte, pas un bloc EXIF.
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\x05tEXtExifs'                        > "$p/mot-exif.png"
# Un nom de fichier avec espaces.
cp "$p/photo.jpg" "$p/ma photo.jpeg"

sortie="$(bash "$racine/scripts/verifier-exif.sh" "$s" "$p" 2>&1)"
code=$?
[ "$code" -eq 1 ] && ok "code de sortie 1 quand il y a des métadonnées" || echec "code de sortie attendu 1, obtenu $code"
for f in "$s"/*; do
  nom="$(basename "$f")"
  if printf '%s\n' "$sortie" | grep -qF "$nom :"; then ok "refusée      : $nom"; else echec "NON refusée  : $nom"; fi
done
for f in "$p"/*; do
  nom="$(basename "$f")"
  if printf '%s\n' "$sortie" | grep -qF "$nom :"; then echec "refusée à tort : $nom"; else ok "acceptée     : $nom"; fi
done
bash "$racine/scripts/verifier-exif.sh" "$p" > /dev/null 2>&1
code=$?
[ "$code" -eq 0 ] && ok "code de sortie 0 sur des images propres" || echec "code de sortie attendu 0, obtenu $code"

# ===========================================================================
echo
if [ "$echecs" -gt 0 ]; then
  echo "RÉSULTAT : $echecs cas faux sur $((echecs + reussites))."
  exit 1
fi
echo "RÉSULTAT : les $reussites cas sont bons."
exit 0
