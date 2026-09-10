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

La documentation technique vit dans **`documentation/public/`** :
**`ARCHITECTURE.md`** explique la physique radar que le logiciel doit
affronter et l'architecture matérielle visée ; **`GUIDE_DEPOT.md`** est la
carte du dépôt.

## État d'avancement

- [x] Traitement d'un balayage : seuil de détection, pic, conversion en
      distance, multi-cibles (`Detect_All`) et regroupement des échos
      voisins (`Detect_Clustered`)
- [x] Vérification formelle SPARK : **85 checks prouvés, 0 non prouvé**,
      avec des **contrats fonctionnels** — dont le **CFAR** (seuil
      adaptatif au bruit local : « aucune cible rapportée sous son seuil
      local », prouvé) — et la terminaison (`Always_Terminates`)
- [x] Pipeline 3D complet sur source simulée : interface abstraite
      (`Radar_Source`), monde simulé mobile, détections 3D, regroupement
      spatial (`Cluster`), **pistage** avec ID stables et vitesses
      (`Radar_Track`), visualiseur Three.js généré (`out/radar_tracking_3d.html`)
- [x] Concurrence **Ravenscar réelle** : exécutable `radar_demo` sous
      `pragma Profile (Ravenscar)` imposé à la compilation, tâche cyclique →
      objet protégé (entry à barrière) → tâche sporadique, objet protégé
      `Mailbox` **prouvé SPARK**
- [x] **Cross-compilation embarquée sans la carte** : le cœur prouvé
      (`src/processing`) compile pour Cortex-M4F (runtime `light`), vérifié
      en CI (`radar_core.gpr`)
- [x] **Quatre modes d'exploitation** partageant la même source et la même
      chaîne prouvée : `radar_fw track` (rejeu du pistage), `radar_fw map`
      (cartographie 3D navigable, fichier), `radar_fw live` (surveillance
      **temps réel** dans le navigateur) et `radar_fw scan` (cartographie
      **progressive** : le nuage se construit sous vos yeux)
- [x] **MTI par carte de clutter** (`Radar_Clutter`, embarquable et
      cross-compilé ARM en CI) : le décor statique appris au premier tour
      est soustrait, seuls les objets **mobiles** deviennent des pistes —
      avec ou sans pièce autour
- [x] **Cibles réalistes** : cibles **étendues** (4 réflecteurs), écho
      **fluctuant** (Swerling), trous de détection, bruit de fond et
      **fantômes multitrajet** — le pipeline est éprouvé contre des
      données imparfaites (voir `documentation/public/ARCHITECTURE.md` §1)
- [x] **Pistage robuste** : prédiction + coasting, filtre **alpha-beta**,
      confirmation **M-sur-N** (les tentatives et les fantômes ne sont
      jamais affichés), **association globale** (pas de vol de détection),
      **fusion anti-fragmentation**, clutter **adaptatif** (apprentissage
      de fond, oubli lent), **distance aveugle** prouvée (625 mm)
- [x] **Serveur HTTP écrit en Ada** (`GNAT.Sockets`, mono-thread à
      selector) : la page 3D live interroge `/state.json` en continu
- [x] Tests unitaires **AUnit** : 18 tests verts (balayage, CFAR,
      géométrie, regroupement 3D, cycle de vie du pistage, association
      globale, fusion, murs, clutter adaptatif, pilotage de la source
      **par l'interface**, format de sérialisation)
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

## Quatre modes d'exploitation

Les modes partagent la même source de données (`Radar_Source`) et la
même chaîne de détection prouvée ; seul le **traitement des balayages**
change :

    alr run                          # rejeu du pistage (defaut)
    alr exec -- ./bin/radar_fw map   # cartographie -> out/radar_3d.html
    alr exec -- ./bin/radar_fw live  # temps reel -> http://localhost:8080
    alr exec -- ./bin/radar_fw scan  # carto progressive -> meme adresse

- **`track` — rejeu du pistage** : 60 tours d'un monde d'objets mobiles,
  pistage, vitesses → `out/radar_tracking_3d.html`, un rejeu animé (lissage
  et vitesse réglables) ;
- **`map` — cartographie statique** : un tour méticuleux (180 × 24
  directions) d'une pièce sans objets mobiles → `out/radar_3d.html`, un nuage
  dense (~4 300 points) **navigable** : déplacement ZQSD/WASD, clic sur un
  point pour ses détails (position, distance, angles) — c'est cette sortie
  qui alimente la page [GitHub Pages](https://St3id.github.io/radar_fw/) ;
- **`live` — surveillance temps réel** : un serveur HTTP **écrit en Ada**
  fait tourner la simulation en continu (murs + objets mobiles qui
  rebondissent). Le tour 1 calibre la **carte de clutter** ; ensuite le
  décor est soustrait et seuls les mobiles sont pistés. La page 3D
  (overlay : cibles numérotées, distance, vitesse en m/s, traînées) se
  met à jour seule. Le jour du matériel, seule la source change (UART au
  lieu du simulateur) ;
- **`scan` — cartographie progressive** : le scan est cadencé (une
  colonne d'azimut à la fois, ~11 s en simulation — le vrai prendra des
  minutes) et **le nuage se construit sous vos yeux** dans le navigateur
  (progression, compteur) ; à la fin il reste explorable (déplacement,
  clic-détails). Les modes `live` et `scan` partagent le serveur HTTP
  Ada (`Radar_Http`).

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
**85 checks, 0 non prouvé** :

- absence d'erreur d'exécution (débordements, indices hors bornes) ;
- contrats fonctionnels : `Peak_Bin` renvoie bien le maximum,
  `Peak_Distance` vaut exactement `Bin_Distance (Peak_Bin (S))`,
  `Detect_All` / `Detect_Clustered` ne rapportent **aucune fausse
  alarme**, et `Detect_Adaptive` (CFAR) ne rapporte **aucune cible sous
  son seuil local** (adaptatif au bruit) ;
- terminaison des sous-programmes (aspect implicite `Always_Terminates`) ;
- l'objet protégé `Mailbox` est prouvé dans le contexte Ravenscar
  (projet `radar_demo.gpr`).

Reproduire les deux preuves :

    alr exec -- gnatprove -P radar_fw.gpr   --report=all --checks-as-errors=on
    alr exec -- gnatprove -P radar_demo.gpr --report=all --checks-as-errors=on

## Tests

18 tests AUnit en deux suites : traitement du balayage (pic, seuil,
multi-cibles, regroupement) et pipeline 3D (CFAR, aller-retour
géométrique, normalisation d'azimut, zénith, regroupement, cycle de vie
du pistage — filtre, M-sur-N, coasting, mort des tentatives —, deux
échos sur un même rayon, murs, clutter adaptatif) :

    alr exec -- gprbuild -p -P radar_fw_tests.gpr
    alr exec -- ./bin/run_tests

## Compilation et exécution

    alr build
    alr run                          # tracking -> out/radar_tracking_3d.html
    alr exec -- ./bin/radar_fw map   # cartographie -> out/radar_3d.html
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
