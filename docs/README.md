# docs/ — visualiseur 3D publié

`index.html` est une **capture publiée** du visualiseur 3D du projet, mise en
ligne via **GitHub Pages** : <https://St3id.github.io/radar_fw/>.

Ce fichier n'est **pas écrit à la main** : il est **généré par le programme
Ada** (`src/radar_fw.adb`), qui produit `radar_3d.html` à partir du nuage de
points de `Radar_Cloud`. C'est un fichier **autonome** (Three.js chargé depuis
un CDN) : il s'ouvre dans un navigateur sans serveur.

## Mettre à jour la page publiée

    alr run                 # regénère radar_3d.html à la racine
    cp radar_3d.html docs/index.html
    git add docs/index.html
    git commit -m "..."     # puis git push

La sortie `radar_3d.html` à la racine est ignorée par Git ; seule la copie
`docs/index.html` est versionnée, car GitHub Pages ne sert que des fichiers
présents dans le dépôt.
