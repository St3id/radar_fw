# docs/ — visualiseur 3D publié

`index.html` est une **capture publiée** du visualiseur 3D du projet, mise en
ligne via **GitHub Pages** : <https://St3id.github.io/radar_fw/>.

Ce fichier n'est **pas écrit à la main** : il est **généré par le programme
Ada** en mode cartographie (`radar_fw map`), qui scanne la pièce simulée à
travers la chaîne de détection prouvée et produit `out/radar_3d.html`. C'est un
fichier **autonome** (Three.js chargé depuis un CDN) : il s'ouvre dans un
navigateur sans serveur.

## Mettre à jour la page publiée

    alr build
    alr exec -- ./bin/radar_fw map   # regenere out/radar_3d.html
    cp out/radar_3d.html docs/index.html
    git add docs/index.html
    git commit -m "..."              # puis git push

La sortie `out/radar_3d.html` est ignorée par Git ; seule la copie
`docs/index.html` est versionnée, car GitHub Pages ne sert que des fichiers
présents dans le dépôt.
