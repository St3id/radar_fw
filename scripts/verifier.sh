#!/usr/bin/env bash
# Verification complete du depot, en une commande et en serie :
#
#     bash scripts/verifier.sh
#
# Elle repart d'un obj/ neuf : une preuve ou un build incremental peut afficher
# des totaux venus d'artefacts perimes. Les totaux lus sont compares aux valeurs
# attendues ci-dessous : un chiffre different fait echouer le script, meme si
# l'outil a rendu le code 0. Journaux detailles dans out/verifier/.
#
# Un chiffre qui change legitimement (test ou code prouve ajoute) se corrige ici.

set -u -o pipefail
cd "$(dirname "$0")/.." || exit 2

ATTENDU_TESTS=71
ATTENDU_PREUVE_PRINCIPALE=187
ATTENDU_PREUVE_LD2450=214
ATTENDU_PREUVE_PARSEUR=354
ATTENDU_PREUVE_DEMO=89

JOURNAUX=out/verifier
PREUVE_FW=obj/development/gnatprove/gnatprove.out
PREUVE_DEMO=obj/demo/gnatprove/gnatprove.out

# Jamais deux gnatprove en parallele : ils partagent le cache Alire et les memes
# fichiers de resultat, y compris depuis un autre worktree. mkdir est atomique,
# et le dossier commun de git est le meme pour tous les worktrees.
VERROU="$(git rev-parse --git-common-dir)/radar_verifier.lock"
if ! mkdir "$VERROU" 2> /dev/null; then
   echo "Une verification tourne deja ($VERROU)."
   echo "Si elle a ete tuee, supprimer ce dossier puis relancer."
   exit 2
fi
trap 'rmdir "$VERROU"' EXIT

rm -rf obj "$JOURNAUX"
mkdir -p "$JOURNAUX"

RESUME=""
ECHEC=0

note () {
   RESUME="$RESUME$(printf '  %-34s %s' "$1" "$2")"$'\n'
}

# Arrete tout au premier echec, comme la procedure : la suite n'aurait pas de sens.
arret () {
   note "$1" "ECHEC : $2"
   printf '\nEchec de "%s" : %s\n' "$1" "$2"
   [ -f "$JOURNAUX/$1.log" ] && tail -n 30 "$JOURNAUX/$1.log"
   printf '\nResume :\n%s' "$RESUME"
   exit 1
}

etape () {
   local nom="$1"
   shift
   echo "... $nom"
   "$@" > "$JOURNAUX/$nom.log" 2>&1 || arret "$nom" "code de sortie non nul"
}

# Les builds doivent rester sans aucun warning (style GNAT strict).
compile () {
   local nom="$1"
   shift
   etape "$nom" "$@"
   if grep -qE 'warning:|\(style\)' "$JOURNAUX/$nom.log"; then
      arret "$nom" "warning de compilation"
   fi
   note "$nom" "ok"
}

execute () {
   local nom="$1"
   shift
   etape "$nom" "$@"
   note "$nom" "ok"
}

# Lit le total de la ligne "Total" du rapport, jamais la sortie de l'outil.
prouve () {
   local nom="$1" rapport="$2" attendu="$3"
   shift 3
   etape "$nom" "$@"
   local ligne total
   ligne=$(grep -E '^Total' "$rapport") || arret "$nom" "rapport sans total"
   total=$(echo "$ligne" | awk '{print $2}')
   [ "$total" = "$attendu" ] ||
      arret "$nom" "$total checks au lieu de $attendu"
   echo "$ligne" | grep -qE '\.[[:space:]]*$' ||
      arret "$nom" "des checks ne sont pas prouves : $ligne"
   note "$nom" "$total checks, 0 non prouve"
}

compile build alr build
compile build_tests alr exec -- gprbuild -p -P radar_fw_tests.gpr

etape tests alr exec -- ./bin/run_tests
total_tests=$(grep -E 'Total Tests Run' "$JOURNAUX/tests.log" | awk '{print $NF}')
[ "$total_tests" = "$ATTENDU_TESTS" ] ||
   arret tests "${total_tests:-aucun} tests au lieu de $ATTENDU_TESTS"
for compteur in 'Failed Assertions' 'Unexpected Errors'; do
   grep -E "$compteur" "$JOURNAUX/tests.log" | grep -qE ':[[:space:]]*0[[:space:]]*$' ||
      arret tests "$compteur non nul"
done
note tests "$total_tests verts"

execute mode_map alr exec -- ./bin/radar_fw map
execute mode_track alr exec -- ./bin/radar_fw
execute mode_sar alr exec -- ./bin/radar_fw sar

compile contrats alr exec -- gprbuild -c -u -P radar_fw.gpr radar_planar_source.ads radar_target_source.ads
compile enregistreur alr exec -- gprbuild -p -P radar_ld2450_record.gpr

compile build_demo alr exec -- gprbuild -p -P radar_demo.gpr
execute demo alr exec -- ./bin/radar_demo

prouve preuve_principale "$PREUVE_FW" "$ATTENDU_PREUVE_PRINCIPALE" \
   alr exec -- gnatprove -P radar_fw.gpr --report=all --checks-as-errors=on
prouve preuve_ld2450 "$PREUVE_FW" "$ATTENDU_PREUVE_LD2450" \
   alr exec -- gnatprove -P radar_fw.gpr -u radar_ld2450.adb --report=all --checks-as-errors=on
prouve preuve_parseur "$PREUVE_FW" "$ATTENDU_PREUVE_PARSEUR" \
   alr exec -- gnatprove -P radar_fw.gpr -u radar_ld2450_stream.adb radar_ld2450_plausibility.adb --report=all --checks-as-errors=on
prouve preuve_demo "$PREUVE_DEMO" "$ATTENDU_PREUVE_DEMO" \
   alr exec -- gnatprove -P radar_demo.gpr --report=all --checks-as-errors=on

# Le compilateur croise vit dans le cache Alire, hors du PATH de alr exec.
if ! command -v arm-eabi-gcc > /dev/null; then
   CACHE="${LOCALAPPDATA:-$HOME/.local/share}/alire/cache/toolchains"
   ARM=$(find "$CACHE" -maxdepth 1 -name 'gnat_arm_elf*' 2> /dev/null | head -n 1)
   [ -n "$ARM" ] || arret garde_fou_arm "gnat_arm_elf absent du cache Alire"
   PATH="$ARM/bin:$PATH"
fi
compile garde_fou_arm alr exec -- gprbuild -p -P radar_core.gpr

printf '\nResume :\n%s\nTout est vert.\n' "$RESUME"
