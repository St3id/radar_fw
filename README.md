# radar_fw

[![Build, Test & Prove](https://github.com/St3id/radar_fw/actions/workflows/ci.yml/badge.svg)](https://github.com/St3id/radar_fw/actions/workflows/ci.yml)

Chaîne de traitement radar 3D écrite en **Ada 2022 / SPARK** : détection
prouvée formellement, pistage multi-cibles, restitution 3D dans le
navigateur.

Le cœur algorithmique est embarquable — il cross-compile pour ARM
Cortex-M4F et l'intégration continue le vérifie à chaque commit — mais
aucun matériel n'est encore branché : tout ce qui suit tourne sur une
source simulée, derrière l'interface qui accueillera le capteur réel.

**[Voir la démonstration en ligne](https://St3id.github.io/radar_fw/)** —
une pièce cartographiée par la chaîne de détection prouvée, explorable
dans le navigateur.

## En bref

| | |
| --- | --- |
| Langage | Ada 2022 ; `SPARK_Mode` sur le cœur de traitement |
| Vérification formelle | **85 checks prouvés, 0 non prouvé** (prouveur CVC5) |
| Tests | **22 tests AUnit**, rejoués à chaque commit |
| Modes d'exploitation | 4 : `track`, `map`, `live`, `scan` |
| Concurrence | profil **Ravenscar** imposé à la compilation |
| Cible embarquée | ARM Cortex-M4F, runtime `light` (STM32G474 visé) |
| Source de données | simulateur reproductible — aucun matériel à ce jour |

## Ce que fait le programme

Les modes de cartographie et le mode `live` basé sur balayages utilisent
`Radar_Source` et gardent le passage simulation → source réelle. Les capteurs
qui livrent des positions 3D déjà calculées ont un contrat distinct,
`Radar_Target_Source`. Aucun adaptateur matériel ne l'utilise encore. Un
capteur qui ne donne que x/y, comme le LD2450 décrit ici, attend un type de
piste planaire ; on ne lui invente pas une altitude.

    alr run                          # track : rejeu du pistage (defaut)
    alr exec -- ./bin/radar_fw map   # cartographie -> out/radar_3d.html
    alr exec -- ./bin/radar_fw live  # temps reel -> http://localhost:8080
    alr exec -- ./bin/radar_fw scan  # carto progressive -> meme adresse

- **`track` — rejeu du pistage.** 60 tours d'un monde d'objets mobiles :
  détection, pistage, vitesses, puis un rejeu animé dans
  `out/radar_tracking_3d.html` (lissage et vitesse de rejeu réglables).
- **`map` — cartographie statique.** Un tour méticuleux de 180 × 24
  directions sur une pièce sans objets mobiles, rendu en un nuage
  d'environ 4 300 points dans `out/radar_3d.html` : navigation au clavier
  (ZQSD/WASD), clic sur un point pour sa position, sa distance et ses
  angles. C'est la sortie qui alimente la
  [page publiée](https://St3id.github.io/radar_fw/).
- **`live` — surveillance temps réel.** Un serveur HTTP écrit en Ada fait
  tourner la simulation en continu (murs et objets mobiles). Les huit
  premiers tours calibrent la carte de clutter ; ensuite le décor est
  soustrait et seuls les mobiles sont pistés. La page 3D se met à jour
  seule, le serveur lui poussant chaque nouvel état (Server-Sent Events,
  sans sondage) : cibles numérotées, distance, vitesse en m/s, traînées.
- **`scan` — cartographie progressive.** Une passe globale rapide (60 × 8)
  apparaît d'abord, puis une passe de détail (180 × 24) l'enrichit. Dans la
  démonstration, la première passe prend environ 1,5 s et le détail 10,8 s ;
  ce sont des cadences d'animation, pas des mesures du moteur ou du capteur.
  Les nouveaux points sont transmis par lots, sans renvoyer tout le nuage à
  chaque rafraîchissement.

Les modes `live` et `scan` partagent le même serveur HTTP Ada
(`Radar_Http`). Pour `track` et `map`, ouvrez le fichier HTML produit
dans `out/` ; pour `live` et `scan`, ouvrez l'URL pendant que le
programme tourne.

## La chaîne de traitement

Le paquet `Radar_Sweep` (SPARK, prouvé) transforme un balayage brut en
cibles : seuil de détection, pic (`Peak_Bin`), conversion case → distance
(`Bin_Distance`), détection multi-cibles, regroupement des échos voisins
et seuil adaptatif CFAR (`Detect_Adaptive`, la fonction qu'utilise tout
le pipeline).

Au-dessus vient la perception 3D :

1. `Radar_Source` — le contrat de profil de balayage, utilisé pour
   développer sur simulation puis remplacer la source sans réécrire le
   traitement. `Radar_Target_Source` est le contrat séparé pour les sources
   qui livrent des positions 3D calculées. Le parseur matériel et l'adaptateur
   LD2450 planaire restent à faire ;
2. `Radar_Detect` — chaque mesure passe par la détection prouvée puis
   devient un point 3D ; deux objets alignés sur un même rayon donnent
   bien deux détections ;
3. `Cluster` — fusion spatiale des détections d'un même tour ;
4. `Radar_Clutter` — en surveillance par profils, le décor appris est
   soustrait (MTI) : ne restent que les objets mobiles ;
5. `Radar_Track` — association globale, identifiants stables, filtre
   alpha-beta, confirmation M-sur-N, fusion des pistes fragmentées. Il reçoit
   des frames horodatées, quel que soit le contrat d'entrée.

## État d'avancement

Acquis :

- [x] Traitement d'un balayage : seuil de détection, pic, conversion en
      distance, multi-cibles (`Detect_All`) et regroupement des échos
      voisins (`Detect_Clustered`).
- [x] Vérification formelle SPARK à contrats **fonctionnels** — dont le
      CFAR, seuil adaptatif au bruit local — et terminaison prouvée.
- [x] Pipeline 3D complet sur source simulée : interface abstraite, monde
      simulé mobile, détections 3D, regroupement spatial, pistage à
      identifiants stables et vitesses.
- [x] **Base de temps réelle** : chaque mesure est horodatée, les vitesses
      sont en mm/s et ne dépendent plus de la cadence de balayage ; la
      fenêtre d'association et la durée de coasting se comptent en temps.
- [x] Pistage robuste : prédiction et coasting, filtre **alpha-beta**,
      confirmation **M-sur-N** (ni les tentatives ni les fantômes ne sont
      affichés), association globale, fusion anti-fragmentation, exclusion
      logicielle des 8 premières cases simulées (625 mm).
- [x] **MTI** par carte de clutter adaptative — apprentissage de fond et
      oubli lent — embarquable et cross-compilée pour ARM en CI.
- [x] Cibles simulées imparfaites : 4 réflecteurs, fading uniforme inspiré
      des modèles de Swerling (sans en reprendre la loi statistique), trous de
      détection, bruit de fond et fantômes multitrajet.
      Le pipeline est éprouvé contre des données imparfaites, voir
      `documentation/public/ARCHITECTURE.md` §1.
- [x] Concurrence **Ravenscar** réelle : profil imposé à la compilation,
      tâche cyclique, objet protégé prouvé, tâche sporadique.
- [x] Cross-compilation du cœur prouvé pour Cortex-M4F, sans la carte.
- [x] Serveur HTTP écrit en Ada (`GNAT.Sockets`), partagé par `live` et
      `scan`.
- [x] Intégration continue sur toutes les branches : build, tests, démo
      Ravenscar exécutée, deux preuves SPARK bloquantes, cross-compilation
      ARM.

Reste à faire :

- [ ] Type de rapport planaire, pistage 2D, puis adaptateur simulation et
      matériel du LD2450. Garder le type 3D pour les mesures qui ont réellement
      une altitude ; fusionner ensuite avec horloges et poses calibrées.
- [ ] Raffinement sélectif des seuls secteurs utiles après la passe rapide ;
      le mode `scan` actuel refait encore toute la grille en détail.
- [ ] Driver capteur en Ada sur STM32 (matériel requis).
- [ ] Balayage motorisé réel (matériel requis).

## Vérification formelle

Le code en `SPARK_Mode` est prouvé avec SPARK (prouveur CVC5) :
**85 checks, 0 non prouvé**. Ce qui est établi :

- l'absence d'erreur d'exécution : débordements, indices hors bornes ;
- des contrats **fonctionnels**, et non des tautologies : `Peak_Bin`
  renvoie bien le maximum du balayage, `Peak_Distance` vaut exactement
  `Bin_Distance (Peak_Bin (S))`, et les détecteurs ne rapportent que des
  cases au-dessus de leur seuil logiciel. Cela ne prouve pas un taux de fausse
  alarme réel ni qu'un écho provient d'une cible ;
- la terminaison des sous-programmes (aspect implicite
  `Always_Terminates`) ;
- l'objet protégé `Mailbox`, prouvé dans le contexte Ravenscar (projet
  `radar_demo.gpr`).

Reproduire les deux preuves :

    alr exec -- gnatprove -P radar_fw.gpr   --report=all --checks-as-errors=on
    alr exec -- gnatprove -P radar_demo.gpr --report=all --checks-as-errors=on

## Concurrence Ravenscar

L'exécutable `radar_demo` (projet `radar_demo.gpr`) met en œuvre le motif
Ravenscar canonique. Le profil n'est pas seulement annoncé : il est
**imposé à la compilation** par `ravenscar.adc` (`pragma Profile
(Ravenscar)` et élaboration séquentielle).

- `Producer`, tâche **cyclique** cadencée par `delay until`, dépose un
  balayage toutes les 250 ms dans l'objet protégé ;
- `Mailbox`, objet protégé **prouvé SPARK**, expose une `entry Get` à
  barrière simple : le consommateur est suspendu par le noyau tant qu'il
  n'y a rien à lire, sans aucun sondage ;
- `Consumer`, tâche **sporadique**, est réveillée par la barrière et
  traite le balayage avec les fonctions prouvées de `Radar_Sweep` ;
- la fin de la démonstration est signalée par un objet de suspension
  (`Ada.Synchronous_Task_Control`), l'autre primitive de synchronisation
  autorisée par le profil.

Compiler puis exécuter la démonstration :

    alr exec -- gprbuild -p -P radar_demo.gpr
    alr exec -- ./bin/radar_demo

## Le cœur embarquable, sans la carte

`radar_core.gpr` compile le cœur algorithmique pour **arm-eabi /
Cortex-M4F** avec le runtime réduit `light` — le processeur du STM32G474
visé. La CI rejoue cette compilation à chaque commit : tout ajout au cœur
qui dépendrait du PC (`Ada.Text_IO`, `Ada.Calendar`, exceptions
propagées) casse le build immédiatement, longtemps avant qu'une carte
soit branchée.

## Tests

**22 tests AUnit** répartis en deux suites :

- traitement du balayage : pic, seuil, multi-cibles, regroupement ;
- pipeline 3D : CFAR, aller-retour géométrique, normalisation d'azimut,
  zénith, regroupement spatial, cycle de vie du pistage (filtre,
  M-sur-N, coasting, mort des tentatives), deux échos sur un même rayon,
  murs (distance, incidence, écho spéculaire ou diffus), clutter adaptatif,
  pilotage de la source par l'interface,
  format de sérialisation, vitesse en mm/s indépendante de la cadence de
  balayage, cycle de vie des pistes compté en temps.

Compiler puis lancer les suites :

    alr exec -- gprbuild -p -P radar_fw_tests.gpr
    alr exec -- ./bin/run_tests

## Compilation et exécution

    alr build
    alr run                          # track -> out/radar_tracking_3d.html
    alr exec -- ./bin/radar_fw map   # cartographie -> out/radar_3d.html
    alr exec -- ./bin/radar_fw live  # temps reel -> http://localhost:8080
    alr exec -- ./bin/radar_fw scan  # carto progressive -> meme adresse

## Intégration continue

Le workflow GitHub Actions (`.github/workflows/ci.yml`) se déclenche à
chaque push, sur **toutes les branches** : compilation, tests AUnit,
exécution du démonstrateur Ravenscar, preuves SPARK des deux projets —
**bloquantes**, grâce à `--checks-as-errors=on` — et cross-compilation du
cœur pour la cible ARM.

## Documentation

- `documentation/public/ARCHITECTURE.md` — pourquoi le code fait ce qu'il
  fait : la physique radar que le simulateur doit affronter,
  l'architecture matérielle visée et la spécification du protocole de
  télémétrie.
- `documentation/public/GUIDE_DEPOT.md` — la carte du dépôt : où trouver
  quel fichier, et pourquoi il existe quatre projets de compilation.

## Outils

Ada 2022, SPARK, Alire, GNAT — natif et `gnat_arm_elf` pour la cible
STM32.

## Remerciements

Merci à [Stevee87](https://github.com/Stevee87) pour ses projets publics de
fusion LiDAR + radar mmWave sur ESP32
([Lidar-Radar-combination-Raspberry](https://github.com/Stevee87/Lidar-Radar-combination-Raspberry),
[Tactical-Radar-System-ESP32-P4](https://github.com/Stevee87/Tactical-Radar-System-ESP32-P4-elcrow-Display),
MIT). Leur lecture a fait gagner du temps sur trois points précis :

- l'encodage des coordonnées du protocole Hi-Link, en **binaire décalé** et
  non en complément à deux — de quoi inverser tous les signes sans que rien
  ne plante ;
- la **configuration du module, qu'il faut réaffirmer** périodiquement parce
  qu'il y retombe tout seul ;
- la **cécité au mouvement tangentiel** d'un capteur Doppler, une limite
  physique qu'une couronne de capteurs ne lève pas et que le pistage doit
  absorber.

Ces trois points sont détaillés dans
[`documentation/public/ARCHITECTURE.md`](documentation/public/ARCHITECTURE.md)
§1.1 et §2.6. Aucun code n'a été repris — seules les leçons.

## Licence

MIT, voir [`LICENSE`](LICENSE).
