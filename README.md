# radar_fw

[![Build, Test & Prove](https://github.com/St3id/radar_fw/actions/workflows/ci.yml/badge.svg)](https://github.com/St3id/radar_fw/actions/workflows/ci.yml)

Firmware de radar de scan 3D développé en **Ada/SPARK**, ciblant un microcontrôleur **STM32 (ARM Cortex-M)**.

Ce projet sert de démonstrateur de programmation embarquée haute-intégrité :
conception en Ada, concurrence déterministe (profil Ravenscar) et
**vérification formelle avec SPARK**.

## Objectif

Acquérir un balayage radar, en extraire les cibles (distance, angle), et
reconstruire une représentation 3D de la scène. Le radar est ici un support
technique pour démontrer une chaîne embarquée rigoureuse, applicable au
domaine défense / aéronautique.

## État d'avancement

- [x] Traitement d'un balayage : seuil de détection, détection du pic et
      conversion en distance
- [x] Détection multi-cibles (`Detect_All`) et regroupement des échos voisins
      en une seule cible (`Detect_Clustered`)
- [x] Types bornés et contrats (conception « correct par construction »)
- [x] Vérification formelle SPARK : **23 checks prouvés, 0 non prouvé**
- [x] Tests unitaires **AUnit** : 4 tests verts
- [x] Architecture concurrente **Ravenscar** : tâches `Producer` / `Consumer`
      et objet protégé `Mailbox`
- [x] Intégration continue **GitHub Actions** : build + tests + preuve SPARK,
      bloquante en cas d'échec
- [x] Reconstruction 3D : géométrie, scan de pièce simulé et visualiseur
      **Three.js** (`radar_3d.html`)
- [ ] Driver capteur en Ada sur STM32 (matériel requis)
- [ ] Balayage motorisé réel (matériel requis)

## Chaîne de traitement

Le paquet `Radar_Sweep` transforme un balayage brut en cibles :

- **Seuil de détection** : un écho sous le seuil est considéré comme du bruit
  (cas « aucune cible »).
- **Détection du pic** : la case d'amplitude maximale.
- **`Detect_All`** : toutes les cases dont l'écho dépasse le seuil.
- **`Detect_Clustered`** : regroupe les cases voisines au-dessus du seuil en
  une seule cible (un objet étalé sur plusieurs cases = une cible, pas
  plusieurs).

## Architecture concurrente (Ravenscar)

Deux tâches déclarées au niveau bibliothèque communiquent par un objet
protégé, comme l'impose le profil Ravenscar (concurrence déterministe, sans
interblocage) :

- `Producer` dépose un balayage dans l'objet protégé `Mailbox` ;
- `Consumer` le récupère et le traite ;
- `Mailbox` garantit l'exclusion mutuelle entre les deux tâches.

## Reconstruction 3D

Le paquet `Radar_Cloud` simule un scan complet d'une pièce (azimut × élévation)
et produit un nuage de points 3D, à partir de la géométrie de `Radar_Geometry`
(conversion distance + angles → point cartésien). Le programme principal génère
`radar_3d.html`, un visualiseur **autonome** : Three.js est chargé depuis un
CDN, le fichier s'ouvre directement dans un navigateur (rotation à la souris,
zoom à la molette), sans serveur.

## Vérification formelle

Le code en `SPARK_Mode` (principalement le paquet `Radar_Sweep`) est prouvé
avec SPARK (prouveur CVC5) : **23 checks, 0 non prouvé**.

- absence d'erreur d'exécution (débordements, indices hors bornes) ;
- contrats fonctionnels (par ex. la détection de pic renvoie bien le maximum) ;
- terminaison des sous-programmes.

Reproduire la preuve :

    alr gnatprove

## Tests

Tests unitaires AUnit (4 tests : absence de cible, détection du pic,
multi-cibles, regroupement) :

    alr exec -- gprbuild -p -P radar_fw_tests.gpr
    ./bin/run_tests

## Compilation et exécution

    alr build
    alr run

`alr run` génère `radar_3d.html` ; ouvrez-le dans un navigateur.

## Intégration continue

Le workflow GitHub Actions (`.github/workflows/ci.yml`) se déclenche à chaque
push et pull request : compilation, tests AUnit et preuve SPARK. La preuve est
**bloquante** (`--checks-as-errors=on`) : un seul check non prouvé fait échouer
la CI.

## Outils

Ada 2022, SPARK, Alire, GNAT (natif et `gnat_arm_elf` pour la cible STM32).

## Licence

MIT.
