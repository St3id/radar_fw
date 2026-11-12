#!/usr/bin/env bash
# Fabrique out/radar_console/ : la console et tout ce que GTK charge a l'execution,
# pour la lancer sur un PC sans Alire ni MSYS2.
#
#     bash console/empaqueter.sh

set -eu
cd "$(dirname "$0")"

# Hors de console/ : un second radar_console.exe dans la crate fait refuser
# `alr run` ("Too many candidates").
D=../out/radar_console

M="${LOCALAPPDATA//\\//}/alire/cache/msys64/mingw64"
[ -d "$M/bin" ] || { echo "MSYS2 d'Alire introuvable : $M" >&2; exit 2; }

alr -n build --release

rm -rf "$D" dist
mkdir -p "$D"/share/glib-2.0/schemas "$D"/share/icons "$D"/lib/gdk-pixbuf-2.0
cp bin/radar_console.exe "$D"/

# Le selecteur de fichiers plante sans schemas. Sans icones ni lecteur SVG,
# GTK s'arrete des qu'il doit dessiner la fleche d'une liste deroulante.
cp "$M"/share/glib-2.0/schemas/gschemas.compiled "$D"/share/glib-2.0/schemas/
cp -r "$M/share/icons/Adwaita" "$D"/share/icons/
cp -r "$M/share/icons/hicolor" "$D"/share/icons/ 2>/dev/null || true
cp -r "$M/lib/gdk-pixbuf-2.0/2.10.0" "$D"/lib/gdk-pixbuf-2.0/
rm -f "$D"/lib/gdk-pixbuf-2.0/2.10.0/loaders/*.dll.a

# Cache d'icones refait ici, apres la copie : GTK l'ignore des qu'un dossier
# du theme est plus recent que lui, et relit alors les 825 fichiers. 3,8 s
# au demarrage (mesure du 2026-11-12) ; deja le cas dans le MSYS2 d'Alire.
for theme in "$D"/share/icons/*/; do
   "$M/bin/gtk-update-icon-cache.exe" -f -t -q "$theme"
done

# Les DLL, de proche en proche : objdump ne liste que les dependances directes,
# et les modules charges a l'execution (lecteur SVG) ont les leurs.
a_voir=("$D"/radar_console.exe "$D"/lib/gdk-pixbuf-2.0/2.10.0/loaders/*.dll)
while [ "${#a_voir[@]}" -gt 0 ]; do
   courant="${a_voir[0]}"
   a_voir=("${a_voir[@]:1}")
   for dll in $(alr -n exec -- objdump -p "$courant" 2>/dev/null \
                | sed -n 's/.*DLL Name: //p' | tr -d '\r'); do
      if [ -f "$M/bin/$dll" ] && [ ! -f "$D/$dll" ]; then
         cp "$M/bin/$dll" "$D"/
         a_voir+=("$D/$dll")
      fi
   done
done

echo "Paquet : $(cd "$D" && pwd) ($(du -sh "$D" | cut -f1))"
