#!/usr/bin/env bash
# Fabrique console/dist/ : la console et tout ce que GTK charge a l'execution,
# pour la lancer sur un PC sans Alire ni MSYS2.
#
#     bash console/empaqueter.sh

set -eu
cd "$(dirname "$0")"

M="${LOCALAPPDATA//\\//}/alire/cache/msys64/mingw64"
[ -d "$M/bin" ] || { echo "MSYS2 d'Alire introuvable : $M" >&2; exit 2; }

alr -n build --release

rm -rf dist
mkdir -p dist/share/glib-2.0/schemas dist/share/icons dist/lib/gdk-pixbuf-2.0
cp bin/radar_console.exe dist/

# Le selecteur de fichiers plante sans schemas. Sans icones ni lecteur SVG,
# GTK s'arrete des qu'il doit dessiner la fleche d'une liste deroulante.
cp "$M"/share/glib-2.0/schemas/gschemas.compiled dist/share/glib-2.0/schemas/
cp -r "$M/share/icons/Adwaita" dist/share/icons/
cp -r "$M/share/icons/hicolor" dist/share/icons/ 2>/dev/null || true
cp -r "$M/lib/gdk-pixbuf-2.0/2.10.0" dist/lib/gdk-pixbuf-2.0/
rm -f dist/lib/gdk-pixbuf-2.0/2.10.0/loaders/*.dll.a

# Les DLL, de proche en proche : objdump ne liste que les dependances directes,
# et les modules charges a l'execution (lecteur SVG) ont les leurs.
a_voir=(dist/radar_console.exe dist/lib/gdk-pixbuf-2.0/2.10.0/loaders/*.dll)
while [ "${#a_voir[@]}" -gt 0 ]; do
   courant="${a_voir[0]}"
   a_voir=("${a_voir[@]:1}")
   for dll in $(alr -n exec -- objdump -p "$courant" 2>/dev/null \
                | sed -n 's/.*DLL Name: //p' | tr -d '\r'); do
      if [ -f "$M/bin/$dll" ] && [ ! -f "dist/$dll" ]; then
         cp "$M/bin/$dll" dist/
         a_voir+=("dist/$dll")
      fi
   done
done

echo "Paquet : $(pwd)/dist ($(du -sh dist | cut -f1))"
