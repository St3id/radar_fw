# radar_fw

[![Build, Test & Prove](https://github.com/St3id/radar_fw/actions/workflows/ci.yml/badge.svg)](https://github.com/St3id/radar_fw/actions/workflows/ci.yml)

Firmware de radar de scan 3D développé en **Ada/SPARK**, ciblant un microcontrôleur **STM32 (ARM Cortex-M)**.

Ce projet sert de démonstrateur de programmation embarquée haute-intégrité :
conception en Ada, concurrence déterministe (profil Ravenscar) et
**vérification formelle avec SPARK**.

## Objectif

Acquérir un balayage radar, en extraire les cibles (distance, angle), les
suivre dans le temps et reconstruire une représentation 3D de la scène. Le
radar est ici un support technique pour démontrer une chaîne embarquée
rigoureuse, applicable au domaine défense / aéronautique.

## État d'avancement

- [x] Traitement d'un balayage : seuil de détection, pic, conversion en
      distance, multi-cibles (`Detect_All`) et regroupement des échos
      voisins (`Detect_Clustered`)
- [x] Vérification formelle SPARK : **35 checks prouvés, 0 non prouvé**,
      avec des **contrats fonctionnels** (aucune fausse alarme : toute
      cible rapportée dépasse réellement le seuil) et la terminaison
      prouvée automatiquement (`Always_Terminates`)
- [x] Pipeline 3D complet sur source simulée : interface abstraite
      (`Radar_Source`), monde simulé mobile, détections 3D, regroupement
      spatial (`Cluster`), **pistage** avec ID stables et vitesses
      (`Radar_Track`), visualiseur Three.js généré (`radar_tracking_3d.html`)
- [x] Concurrence **Ravenscar réelle** : exécutable `radar_demo` sous
      `pragma Profile (Ravenscar)` imposé à la compilation, tâche cyclique →
      objet protégé (entry à barrière) → tâche sporadique, objet protégé
      `Mailbox` **prouvé SPARK**
- [x] **Cross-compilation embarquée sans la carte** : le cœur prouvé
      (`src/processing`) compile pour Cortex-M4F (runtime `light`), vérifié
      en CI (`radar_core.gpr`)
- [x] **Trois modes d'exploitation** partageant la même source et la même
      chaîne prouvée : `radar_fw track` (rejeu du pistage), `radar_fw map`
      (cartographie 3D navigable d'une pièce) et `radar_fw live`
      (surveillance **temps réel** dans le navigateur)
- [x] **MTI par carte de clutter** (`Radar_Clutter`, embarquable et
      cross-compilé ARM en CI) : le décor statique appris au premier tour
      est soustrait, seuls les objets **mobiles** deviennent des pistes —
      avec ou sans pièce autour
- [x] **Cibles réalistes** : chaque objet simulé est une cible **étendue**
      (4 réflecteurs) à l'écho **fluctuant** (type Swerling) avec de vrais
      trous de détection — le pistage est éprouvé contre des données
      imparfaites (voir `ANALYSE_REALISME.md`)
- [x] **Serveur HTTP écrit en Ada** (`GNAT.Sockets`, mono-thread à
      selector) : la page 3D live interroge `/state.json` en continu
- [x] Tests unitaires **AUnit** : 12 tests verts (traitement du balayage +
      géométrie, regroupement 3D, pistage, murs, clutter)
- [x] Intégration continue **GitHub Actions** sur **toutes les branches** :
      build, tests, démo Ravenscar exécutée, 2 preuves SPARK bloquantes,
      cross-compilation ARM
- [ ] Driver capteur A121 en Ada sur STM32 (matériel requis)
- [ ] Balayage motorisé réel (matériel requis)

## Chaîne de traitement

Le paquet `Radar_Sweep` (SPARK, prouvé) transforme un balayage brut en
cibles : seuil de détection, pic (`Peak_Bin`), conversion case → distance
(`Bin_Distance`), détection multi-cibles et regroupement d'échos voisins.

Au-dessus, le pipeline de perception 3D (branche `tracking-3d`) :

1. `Radar_Source` : interface abstraite — la source simulée
   (`Radar_Sim_Source`) et, plus tard, le vrai capteur sont
   interchangeables ;
2. `Radar_Detect` : chaque mesure passe par `Detect_Clustered` (la
   fonction **prouvée**) — deux objets alignés sur un même rayon donnent
   bien deux détections ;
3. `Cluster` : fusion spatiale des détections d'un même tour ;
4. `Radar_Track` : association par proximité, ID stables, vecteurs
   vitesse (corrigés du nombre de tours écoulés en cas d'occultation).

## Trois modes d'exploitation

Les modes partagent la même source de données (`Radar_Source`) et la
même chaîne de détection prouvée ; seul le **traitement des balayages**
change (c'est le point 9 de la feuille de route) :

    alr run                          # rejeu du pistage (defaut)
    alr exec -- ./bin/radar_fw map   # cartographie -> radar_3d.html
    alr exec -- ./bin/radar_fw live  # temps reel -> http://localhost:8080

- **`track` — rejeu du pistage** : 60 tours d'un monde d'objets mobiles,
  pistage, vitesses → `radar_tracking_3d.html`, un rejeu animé (lissage
  et vitesse réglables) ;
- **`map` — cartographie statique** : un tour méticuleux (180 × 24
  directions) d'une pièce sans objets mobiles → `radar_3d.html`, un nuage
  dense (~4 300 points) **navigable** : déplacement ZQSD/WASD, clic sur un
  point pour ses détails (position, distance, angles) — c'est cette sortie
  qui alimente la page [GitHub Pages](https://St3id.github.io/radar_fw/) ;
- **`live` — surveillance temps réel** : un serveur HTTP **écrit en Ada**
  fait tourner la simulation en continu (murs + objets mobiles qui
  rebondissent). Le tour 1 calibre la **carte de clutter** ; ensuite le
  décor est soustrait et seuls les mobiles sont pistés. La page 3D
  (overlay : cibles numérotées, distance, vitesse en m/s, traînées) se
  met à jour seule. Le jour du matériel, seule la source change (UART au
  lieu du simulateur).

## Architecture concurrente (Ravenscar)

L'exécutable `radar_demo` (projet `radar_demo.gpr`) fait tourner le motif
Ravenscar canonique — et le profil est **imposé à la compilation** par
`ravenscar.adc` (`pragma Profile (Ravenscar)` + élaboration séquentielle),
pas seulement annoncé :

- `Producer` (tâche **cyclique**) : cadencée par `delay until`, dépose un
  balayage toutes les 250 ms dans l'objet protégé ;
- `Mailbox` (objet protégé, **prouvé SPARK**) : `entry Get` à barrière
  simple — le consommateur est suspendu par le noyau tant qu'il n'y a
  rien à lire, zéro polling ;
- `Consumer` (tâche **sporadique**) : réveillée par la barrière, traite le
  balayage avec les fonctions prouvées de `Radar_Sweep` ;
- fin de démo signalée par un **objet de suspension**
  (`Ada.Synchronous_Task_Control`), l'autre primitive de synchronisation
  autorisée par Ravenscar.

    alr exec -- gprbuild -p -P radar_demo.gpr
    alr exec -- ./bin/radar_demo

## Cible embarquée (sans la carte)

`radar_core.gpr` compile le cœur algorithmique pour **arm-eabi /
Cortex-M4F** avec le runtime réduit `light` — le processeur du STM32G474
visé. La CI rejoue cette compilation à chaque commit : tout ajout au cœur
qui dépendrait du PC (`Text_IO`, `Calendar`, exceptions propagées…) casse
le build immédiatement.

## Vérification formelle

Le code en `SPARK_Mode` est prouvé avec SPARK (prouveur CVC5) :
**35 checks, 0 non prouvé** :

- absence d'erreur d'exécution (débordements, indices hors bornes) ;
- contrats fonctionnels : `Peak_Bin` renvoie bien le maximum,
  `Peak_Distance` vaut exactement `Bin_Distance (Peak_Bin (S))`, et
  `Detect_All` / `Detect_Clustered` ne rapportent **aucune fausse
  alarme** (toute cible retournée dépasse le seuil) ;
- terminaison des sous-programmes (aspect implicite `Always_Terminates`) ;
- l'objet protégé `Mailbox` est prouvé dans le contexte Ravenscar
  (projet `radar_demo.gpr`).

Reproduire les deux preuves :

    alr exec -- gnatprove -P radar_fw.gpr   --report=all --checks-as-errors=on
    alr exec -- gnatprove -P radar_demo.gpr --report=all --checks-as-errors=on

## Tests

12 tests AUnit en deux suites : traitement du balayage (pic, seuil,
multi-cibles, regroupement) et pipeline 3D (aller-retour géométrique,
normalisation d'azimut, zénith, regroupement 3D, vitesse de piste après
occultation, deux échos sur un même rayon, distance aux murs, carte de
clutter) :

    alr exec -- gprbuild -p -P radar_fw_tests.gpr
    alr exec -- ./bin/run_tests

## Compilation et exécution

    alr build
    alr run                          # tracking -> radar_tracking_3d.html
    alr exec -- ./bin/radar_fw map   # cartographie -> radar_3d.html
    alr exec -- ./bin/radar_fw live  # temps reel -> http://localhost:8080

Pour `track` et `map`, ouvrez le fichier HTML généré dans un navigateur ;
pour `live`, ouvrez l'URL pendant que le programme tourne.

## Intégration continue

Le workflow GitHub Actions (`.github/workflows/ci.yml`) se déclenche à
chaque push sur **toutes les branches** : compilation, tests AUnit,
exécution du démonstrateur Ravenscar, preuves SPARK des deux projets
(**bloquantes** : `--checks-as-errors=on`) et cross-compilation du cœur
pour la cible ARM.

## Outils

Ada 2022, SPARK, Alire, GNAT (natif et `gnat_arm_elf` pour la cible STM32).

## Licence

MIT.
