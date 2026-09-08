# Cap du projet — radar_fw

Document de pilotage unique : le cap à tenir, le périmètre, les règles qui
empêchent la dérive, l'état réel du dépôt, la feuille de route et les
conventions.

Il remplace et absorbe `GUIDE_PROJET.md`, `ANALYSE_REALISME.md` et
`ARCHITECTURE_SYSTEME.md` (leur contenu reste consultable dans l'historique
Git). Le jeu de documents du dépôt est désormais **fixe** :

| Document | Où | Rôle |
| -------- | -- | ---- |
| `CAP_PROJET.md` (ce fichier) | `documentation/` | le cap, les règles, l'état réel, la feuille de route |
| `GUIDE_MATERIEL.md` | `documentation/` | tout ce qui s'achète, se câble et se soude |
| `GUIDE_DEPOT.md` | `documentation/` | la carte du dépôt : où trouver quel fichier |
| `README.md` | racine | la vitrine publique (GitHub) |
| `CLAUDE.md` | racine | la **procédure de session** d'un agent — pas un document projet |

`README.md` et `CLAUDE.md` doivent rester à la racine : GitHub affiche le
premier, Claude Code charge le second automatiquement.

⚠️ Ne pas confondre `documentation/` (les documents du projet) et `docs/`
(le site publié sur GitHub Pages — ce nom est imposé par GitHub).

---

## 1. Le cap

On construit un **capteur qui, posé dans un volume, en rend compte en 3D**.
Deux modes d'exploitation, et leur superposition comme objectif final :

- **Mode cartographie (analyse d'un lieu)** — scan méticuleux de
  l'environnement **statique**, sur une durée donnée : le capteur balaie
  l'espace autour de lui et construit, **point par point**, un nuage 3D dense
  de ce qui l'entoure (murs, meubles, obstacles). On doit pouvoir regarder le
  nuage se remplir pendant le scan, puis explorer **a posteriori** un rendu 3D
  détaillé et figé.
- **Mode veille (temps réel)** — détection et suivi des objets **mobiles** en
  continu, avec affichage live : chaque entité reçoit un identifiant stable,
  une position, un vecteur vitesse et une traînée. C'est le principe d'un
  radar de surveillance : ne pas seulement voir « quelque chose bouge », mais
  suivre **qui** bouge, et ne pas confondre deux cibles qui se croisent.
- **La superposition (l'objectif final)** — les cibles suivies dessinées
  **par-dessus** la carte 3D du lieu, dans la même scène : on voit à la fois
  le décor et ce qui s'y déplace.

> **L'invariant d'architecture qui découle de tout ça :** les deux modes
> diffèrent par le **traitement des balayages** (suivi temps réel contre
> accumulation dense), **pas par la source de données**. C'est ce qui rend la
> superposition possible sans duplication, et c'est ce que la règle R3 protège.

L'expérience visée, aujourd'hui comme le jour du matériel, est la même :
lancer un exécutable, ouvrir un navigateur, regarder. C'est tout l'intérêt
d'avoir construit les modes **avant** le matériel — le jour du flash, seule la
source de données changera.

**Où en est cette vision :** les trois volets existent déjà, sur données
simulées (voir §5). Le mode `live` superpose bien le décor appris et les
pistes dans la même scène 3D. Ce qui manque n'est donc pas la vision, mais le
**matériel réel** et une **vraie base de temps**.

---

## 2. Règle d'arbitrage

> **Ada d'abord. Un radar qui fonctionne comme finalité. SPARK comme un acquis
> qu'on ne perd pas.**

Ce que ça veut dire concrètement, quand il faut trancher :

- **Ada est obligatoire** pour toute la logique. Le projet démontre une
  compétence Ada : détection, pistage, géométrie, protocoles, serveur — tout
  cela s'écrit en Ada, pas ailleurs.
- **Un radar qui marche vraiment** est le but. Entre « une fonctionnalité de
  plus qui rend le capteur utilisable » et « une preuve formelle de plus », on
  choisit la fonctionnalité.
- **La preuve SPARK et Ravenscar restent** : ce sont des atouts réels, déjà
  acquis (85 checks prouvés, profil Ravenscar imposé à la compilation), et on
  ne les sacrifie pas par négligence. Mais ils ne sont **plus un péage** :
  aucune fonctionnalité n'est abandonnée parce qu'elle serait difficile à
  prouver.

*Note historique : ce projet a longtemps été piloté par la règle inverse — « le
radar est un prétexte technique, la finalité est la preuve formelle en vue de
postes défense/aéronautique ». Cette règle a produit l'essentiel de ce qui fait
la valeur du dépôt aujourd'hui (le cœur prouvé, la CI bloquante, la
cross-compilation ARM) et il faut la garder en tête en lisant le code existant.
Elle est remplacée, pas reniée.*

---

## 3. Périmètre

### Dedans

- Un **volume de la taille d'une pièce**, pas nécessairement fermé.
- Les **trous dans le nuage** sont un résultat légitime, pas un défaut : une
  ouverture, une zone hors de portée de l'antenne ou un angle mort laissent un
  vide dans la carte, et c'est l'information correcte. Le nuage doit à terme
  distinguer trois états par direction : *écho reçu*, *balayé sans écho* (le
  trou réel) et *non encore balayé* — voir jalon 2.
- Le capteur est **fixe pendant un scan** : il tourne sur lui-même (tourelle
  azimut/élévation), il ne se déplace pas.
- Une **résolution honnête** : nuage épars, quantifié en distance (cases de
  78 mm), résolution angulaire grossière. Pas une maquette CAO.

### Dehors (jusqu'à nouvel ordre)

- **SLAM** et navigation : le capteur ne se localise pas lui-même.
- **Déplacement du capteur pendant un scan**.
- **Recalage multi-stations** : fusionner les nuages de plusieurs positions.
- **Reconstruction de surfaces** (mesh, triangulation) : on reste au nuage de
  points.
- **Grottes, extérieur longue portée** : hors budget capteur et hors
  contraintes d'alimentation. La « pièce » est la cible.

Ces cinq points ne sont pas interdits pour toujours — ils sont **hors du cap
actuel**. Les rouvrir est une décision explicite, qui se note ici.

---

## 4. Les règles anti-dérive

Numérotées pour pouvoir dire, en une phrase : « attention, ça viole R3 ».

- **R1 — Toute la logique en Ada.** Détection, pistage, géométrie, protocoles,
  serveur : en Ada. Le JavaScript et le HTML des visualiseurs sont du
  **consommable d'affichage** — ils dessinent ce qu'on leur envoie et ne
  prennent **aucune décision métier** (pas de seuil, pas de filtrage, pas
  d'association de pistes dans la page).
- **R2 — La preuve acquise ne régresse pas ; elle ne bloque pas non plus.**
  Les 85 checks prouvés et les deux preuves bloquantes en CI restent. Mais
  pour du code neuf, un `SPARK_Mode => Off` **explicite et commenté** (« pas
  prouvé parce que… ») est une réponse acceptable. Renoncer à la
  fonctionnalité ne l'est pas.
- **R3 — Un seul point d'entrée capteur.** Tout nouveau matériel entre par
  l'interface `Radar_Source` (`src/source/radar_source.ads`) ou par la future
  interface de niveau détection. Aucun mode d'exploitation ne parle au
  matériel en direct.
- **R4 — Le simulateur ne meurt jamais.** `Radar_Sim_Source` (graine fixe 42,
  donc reproductible) reste le banc de test, y compris après l'arrivée du
  matériel. C'est lui qui permet de rejouer un bug sans rebrancher une carte.
- **R5 — Un jalon est fini quand tout est fini.** Le mode tourne, les tests
  passent, la CI est verte, et les documents sont à jour. Pas avant.
- **R6 — Le jeu de documents est fixe.** `README.md` et `CLAUDE.md` à la
  racine, `CAP_PROJET.md`, `GUIDE_MATERIEL.md` et `GUIDE_DEPOT.md` dans
  `documentation/`. Toute nouvelle analyse devient une **section** d'un de
  ces documents, pas un nouveau fichier : c'est exactement la dérive qui
  avait produit six documents contradictoires.
- **R7 — Le cœur reste embarquable.** `src/processing` doit continuer à
  cross-compiler pour Cortex-M4F (garde-fou `radar_core.gpr`, vérifié en CI) :
  pas de `Ada.Text_IO`, pas de `Ada.Calendar`, pas d'exceptions propagées.

---

## 5. État réel du dépôt (2026-09-08)

**Chiffres qui font foi** : **18 tests** AUnit verts · **85 checks SPARK**
prouvés, 0 non prouvé · **4 modes** d'exploitation · **15 paquets/unités**
(~3 600 lignes) · **4 projets GPR** · **aucun matériel** — tout tourne sur le
simulateur.

### Ce qui est fait

- [x] Environnement Ada complet (Alire + VS Code + toolchains native et ARM).
- [x] `Radar_Sweep` : types bornés (`Millimeters`, `Bin_Index`, `Amplitude`,
      `Sweep`), seuil, pic, conversion case → distance, multi-cibles,
      regroupement d'échos voisins, et **CFAR** (`Detect_Adaptive`) — le tout
      sous contrats `Post` et `Loop_Invariant`.
- [x] **Preuve SPARK : 85 checks, 0 non prouvé** (CVC5), avec des contrats
      **fonctionnels non triviaux** (aucune fausse alarme ; `Peak_Distance`
      exacte ; « aucune cible sous son seuil local » pour le CFAR) et la
      terminaison (`Always_Terminates`).
- [x] Pipeline 3D complet : interface abstraite `Radar_Source`, monde simulé
      mobile, détections 3D, regroupement spatial, **pistage** à ID stables.
- [x] **Les quatre modes pilotent la source par l'interface** (`Source'Class`,
      appels dispatchants) : brancher un vrai capteur ne demandera de toucher
      à aucun mode. Garanti par un test, pas par la discipline (voir §8.1,
      dette 8).
- [x] **Pistage robuste** : prédiction + coasting, filtre alpha-beta,
      confirmation M-sur-N, **association globale** (pas de vol de détection),
      **fusion anti-fragmentation**, distance aveugle prouvée (625 mm).
- [x] **MTI par carte de clutter** (`Radar_Clutter`) : décor appris puis
      soustrait, apprentissage de fond et oubli lent.
- [x] **Cibles réalistes** : cibles étendues (4 réflecteurs), Swerling, trous
      de détection, bruit de fond, fantômes multitrajet.
- [x] **Ravenscar réel** : `radar_demo` sous `pragma Profile (Ravenscar)`
      imposé par `ravenscar.adc`, tâche cyclique → objet protégé (entry à
      barrière, **prouvé**) → tâche sporadique.
- [x] **Cross-compilation ARM sans la carte** (`radar_core.gpr`, Cortex-M4F).
- [x] **Serveur HTTP écrit en Ada** (`Radar_Http`, `GNAT.Sockets`), partagé
      par les modes `live` et `scan`.
- [x] **CI GitHub Actions** sur toutes les branches : build, tests, démo
      Ravenscar exécutée, 2 preuves SPARK **bloquantes**, cross-compile ARM.

### Ce qui n'est pas fait

- [ ] Aucun matériel : pas de driver, pas de HAL, pas d'I/O série.
- [ ] Pas de base de temps (les vitesses sont en **mm/tour**, pas en m/s).
- [ ] Pas d'interface de niveau détection (pour le LD2450).
- [ ] La couche 3D est en `Float` hors SPARK.

### Les paquets

| Paquet | Répertoire | Rôle |
| ------ | ---------- | ---- |
| `Radar_Sweep` | `src/processing` | **SPARK.** Types bornés, seuil, pic, distance, multi-cibles, CFAR, distance aveugle |
| `Radar_Clutter` | `src/processing` | Carte de clutter MTI adaptative (grille 120 × 7, confiance 2 bits). Embarquable et cross-compilé ARM, mais **pas encore en SPARK** |
| `Radar_Source` | `src/source` | L'**interface abstraite** de source : `Measurement`, `Next`, `Has_More` |
| `Radar_Sim_Source` | `src/source` | Source simulée (bruit, Swerling, dropouts, fantômes, graine fixe 42) |
| `Radar_World` | `src/source` | Vérité terrain : objets mobiles qui rebondissent dans une pièce |
| `Radar_Detect` | `src/source` | Détections 3D d'un tour, regroupement spatial (`Cluster`, rayon 600 mm) |
| `Radar_Track` | `src/source` | Le pistage : prédiction, association globale, alpha-beta, M-sur-N, fusion |
| `Radar_Geometry` | `src/geometry` | Polaire ↔ cartésien (Arctan 4 quadrants, azimut normalisé, Arcsin borné) |
| `Radar_Cloud` | `src/geometry` | Nuage de points (max 8 192), ajout avec saturation |
| `Radar_Buffer` | `src/tasking` | **SPARK.** Objet protégé `Mailbox` : `Put` + `entry Get` à barrière |
| `Radar_Tasks` | `src/tasking` | Tâche cyclique `Producer` + tâche sporadique `Consumer` |
| `Radar_Http` | `src/app` | Serveur HTTP en Ada pur, mono-thread à selector |
| `Radar_Html` | `src/app` | Helpers de sérialisation (`Img`, `Put_Float`, `F_Img`) |
| `Radar_Fw` (main) | `src/app` | Dispatch `track` / `map` / `live` / `scan` |
| `Radar_Demo` (main) | `src/demo` | Le main Ravenscar |

### Les quatre projets GPR

| Projet | Ce qu'il compile | Pourquoi il existe |
| ------ | ---------------- | ------------------ |
| `radar_fw.gpr` | l'application PC (`app`, `geometry`, `processing`, `source`) | l'exécutable principal |
| `radar_demo.gpr` | `demo`, `tasking`, `processing` sous `ravenscar.adc` | le profil Ravenscar **imposé** (n'importe pas la config AUnit, qui violerait `No_Calendar`) |
| `radar_core.gpr` | `processing` seul, pour `arm-eabi` / `light-cortex-m4f` | le **garde-fou embarqué** (R7) |
| `radar_fw_tests.gpr` | les suites AUnit | les tests |

### Les quatre modes

    alr run                          # track : rejeu du pistage
    alr exec -- ./bin/radar_fw map   # carto figee -> out/radar_3d.html
    alr exec -- ./bin/radar_fw live  # veille temps reel -> localhost:8080
    alr exec -- ./bin/radar_fw scan  # carto progressive -> localhost:8080

- **`track`** — 60 tours d'un monde d'objets mobiles, pistage, vitesses, puis
  un rejeu animé dans `out/radar_tracking_3d.html`.
- **`map`** — un tour méticuleux (180 × 24 directions) d'une pièce sans
  mobiles → `out/radar_3d.html`, nuage dense (~4 300 points) navigable
  (déplacement ZQSD/WASD, clic-détails). C'est la sortie publiée sur
  [GitHub Pages](https://St3id.github.io/radar_fw/).
- **`live`** — le **mode veille** : simulation continue, tour 1 en calibration
  de clutter, puis décor soustrait et seuls les mobiles pistés. La page
  superpose le décor (`/cloud.json`) et les pistes (`/state.json`).
- **`scan`** — le **mode cartographie** : une colonne d'azimut par pas, le
  nuage se construit sous les yeux (~11 s en simulation), puis reste
  explorable.

La chaîne est commune aux quatre : `Radar_Source.Next` → `Detect_Adaptive`
(CFAR prouvé) → `Bin_Distance` → `To_Point` → [`Radar_Clutter.Filter` en
veille] → `Cluster` → `Radar_Track.Update` → sérialisation → Three.js.

---

## 6. Réalisme : où en est le simulateur face au monde réel

Objectif de cette section : mesurer l'écart entre le simulateur et ce que
donneront les essais réels, en s'appuyant sur des projets existants
documentés.

Verdict d'ensemble d'origine : **l'architecture est juste, le monde simulé
était un conte de fées**. Cibles ponctuelles parfaites, amplitude constante,
zéro bruit, zéro fausse alarme, faisceau crayon idéal : chacune de ces
hypothèses casse en réel. La bonne nouvelle, appliquée depuis : chacune peut
être cassée *en simulation*, une par une — et 7 des 8 chantiers listés plus
bas sont faits.

### 6.1 Une cible réelle n'est pas une sphère

- **Cible étendue** : un humain vu par un radar 24/60 GHz, ce sont des
  dizaines de réflecteurs (torse, membres, tête) qui bougent les uns par
  rapport aux autres. Le « centre » mesuré se promène sur le corps (± 20–30 cm
  d'un tour à l'autre) et occupe plusieurs cases de distance à la fois.
- **Fluctuation d'amplitude** (modèles de Swerling) : l'écho varie de
  10–20 dB selon l'orientation de la cible. Concrètement : un tour tu la vois
  fort, le tour suivant elle passe sous le seuil. Les **trous de détection
  sont la norme**, pas l'exception.
- **Multitrajet** : sol et murs créent des **cibles fantômes** (écho rebondi =
  fausse cible derrière la vraie), surtout en intérieur.
- **Micro-Doppler** : pour un radar, un **ventilateur est une cible mobile** —
  artefact documenté par les utilisateurs du LD2450 en domotique (« fan
  flicker », parade : filtres de temporisation).
- **Personne immobile ≈ invisible** pour une détection par mouvement / carte
  de clutter : c'est tout le fond de commerce des capteurs de « présence »
  (LD2410) qui détectent la respiration.

Ce que ces réalités cassaient dans le code d'alors — et la parade retenue :

| Hypothèse d'origine | Réalité | Conséquence et parade |
| ------------------- | ------- | --------------------- |
| Vitesse = différence de positions brutes | jitter ± 20–30 cm par mesure | vitesse inutilisable sans **filtre** (alpha-beta, puis Kalman) |
| `Cluster_Radius` fixe 300 mm | cible étendue + jitter | fragmentation d'une personne en 2–3 pistes, ou fusion de 2 personnes proches |
| Association gloutonne au plus proche | deux personnes qui se croisent | **échanges d'ID** quasi garantis (parade : association globale type hongrois/GNN) |
| Une détection = une piste affichée | dropouts + fantômes fréquents | pistes fantômes clignotantes (parade : cycle de vie **M-sur-N**, piste « tentative » non affichée) |
| Seuil fixe (100) | bruit variable selon distance/scène | fausses alarmes en avalanche OU cibles faibles ratées (parade : **CFAR**) |
| Clutter appris une fois pour toutes | rideaux, ventilateurs, meubles déplacés | carte de clutter à **oubli lent** (moyenne exponentielle) |

### 6.2 Le capteur réel ne balaie pas comme le simulateur

Le simulateur modélise un faisceau crayon de 3° balayé mécaniquement. **Aucun
capteur de la liste d'achats ne fait ça nativement** :

- **HLK-LD2450** : pas de balayage du tout — champ large ± 60°, angle estimé
  par différence de phase entre antennes RX, **10 Hz**, 3 cibles max, en
  **2D** (pas d'élévation), et il sort des cibles **déjà pistées**, avec ses
  propres artefacts (fantômes, accrochages, latence de décrochage) que les
  intégrations domotique compensent par zones et temporisations.
- **Acconeer A121** : le profil d'écho par cases de distance correspond bien à
  notre type `Sweep` (bonne nouvelle), mais le faisceau natif est **large
  (~50–65° selon le plan)** : sur tourelle **sans lentille, le mode
  cartographie serait une bouillie angulaire**. La lentille (kit Acconeer
  HBL/FZP, ou imprimée) ramène à ~10° : elle fait partie du design, pas des
  accessoires. S'ajoutent fuite d'antenne en champ proche, lobes secondaires,
  bruit.
- **BGT60TR13C** : IQ brut, angle par 3 RX — précision de quelques degrés, pas
  3.
- **Cadence** : le scan mécanique réel (servo + temps d'intégration) prendra
  des **minutes** pour une pièce, pas 800 ms. Acceptable pour le mode
  cartographie, mais l'affichage doit être **progressif** (le nuage se remplit
  sous tes yeux), pas « tout à la fin ».

### 6.3 Ce que montrent les projets existants

- **LD2450 + ESPHome / Home Assistant** (composants communautaires, zones
  polygonales, `off_delay`) : la communauté documente précisément les
  artefacts réels — ventilateurs, instabilités d'alimentation en 3,3 V,
  rafraîchissement 10 Hz — et les parades logicielles simples. C'est un aperçu
  fidèle de ce que notre pipeline recevra.
- **Henrik Forstén (hforsten.com)** : LA référence du radar FMCW amateur —
  6 GHz, PCB maison (~350 composants), détection d'un humain à 100 m, puis
  **SAR embarqué sur drone** avec autofocus. Deux leçons : le sommet du
  réalisable en amateur est très haut, et l'essentiel du travail est dans le
  **traitement et la calibration**, pas dans le RF — exactement le pari de ce
  projet.
- **Acconeer** documente la conception de lentilles comme une étape normale
  d'intégration (docs « Lens design »), ce qui confirme le point ci-dessus
  pour le mode cartographie.

### 6.4 Checklist de mise à niveau du réalisme

Numérotation **stable** : plusieurs commentaires du code source y renvoient
(« realisme point N »). Ne pas renuméroter.

1. **Cibles étendues + Swerling** — ✅ **FAIT** : chaque objet est simulé par
   4 réflecteurs (± 150 mm), amplitude retirée au sort à chaque tour (graine
   fixe : reproductible), 15 % d'extinction par réflecteur et 10 %
   d'évanouissement profond par objet. `Cluster_Radius` est passé à 600 mm en
   conséquence (cible étendue + quantification d'élévation : ~520 mm d'écart
   possible entre échos du même objet à 3 m) — revers assumé : deux objets
   réels à moins de 600 mm fusionnent, c'est la résolution réelle du capteur
   simulé.
2. **Bruit de fond + CFAR** — ✅ **FAIT** : bruit aléatoire dans chaque case ;
   seuil CA-CFAR (fenêtre 8, garde 2, facteur 4) **prouvé SPARK**
   (`Detect_Adaptive` : « aucune cible sous son seuil local ») ; c'est lui que
   tout le pipeline utilise.
3. **Cycle de vie M-sur-N** — ✅ **FAIT** : piste tentative invisible avant
   3 détections, tentative jamais revue morte en 2 tours ; l'affichage (veille
   et rejeu) ne montre que les pistes confirmées, le coasting est marqué
   (gris + `*`).
4. **Filtre alpha-beta** — ✅ **FAIT** : prédiction + coasting (une piste non
   revue roule sur son erre) et correction alpha (0,5) / beta (0,3) ; la
   vitesse filtrée converge (testé : 100 mm/tour ± 20 en 10 tours).
5. **Fantômes multitrajet** — ✅ **FAIT** : 5 % de probabilité d'écho miroir
   derrière le mur ; c'est M-sur-N qui les étouffe (testé).
6. **Clutter adaptatif** — ✅ **FAIT** : compteurs de confiance 2 bits,
   confirmation à 2 observations, apprentissage de fond (1 tour sur 4) et
   oubli lent (`Age` tous les 8 tours) : le décor qui apparaît est appris,
   celui qui disparaît est oublié, un mobile qui passe n'empoisonne pas la
   carte — et un mobile qui se gare y fond (réalisme assumé).
   *Limite qui avait été observée : la fragmentation d'une cible étendue
   pouvait confirmer une piste « ombre » (3 pistes pour 2 objets par moments).
   Résolue depuis — voir §8, dette 1.*
7. **Émulateur LD2450** — ❌ **À FAIRE** (jalon 3) : une source de niveau
   détection (x, y, vitesse, 10 Hz, 3 cibles max, jitter réaliste, dropouts,
   fantômes) — le pipeline PC sera prêt **avant** l'arrivée du module, qui
   remplacera l'émulateur trame pour trame.
8. **Mode cartographie progressif** — ✅ **FAIT** : mode `scan` — le serveur
   HTTP (paquet partagé `Radar_Http`) cadence le balayage une colonne d'azimut
   à la fois et la page se remplit au fil de l'eau (progression, compteur de
   points) ; scan terminé, le nuage reste servi et explorable. Sur le vrai
   matériel, seules la cadence et la source changeront.

### 6.5 Ce qui est déjà réaliste (à garder et à revendiquer)

- Le **MTI par carte de clutter** est le vrai principe des radars de veille au
  sol — et l'épisode « cible collée au mur invisible » rencontré pendant le
  développement est un comportement authentique, documenté dans l'historique
  Git.
- La **quantification en distance** (cases de 78 mm) est honnête : le nuage
  « en bandes » du mode cartographie est ce qu'un vrai capteur donne.
- L'architecture à **deux niveaux d'entrée** (balayage brut / détections
  toutes faites) correspond exactement au matériel visé (A121 et BGT60 au
  niveau balayage, LD2450 au niveau détection).
- « Pas de FFT lourde sur le MCU, le PC fait le rendu » : c'est aussi le
  partage des rôles des projets amateurs aboutis (Forstén).

---

## 7. Architecture système

### 7.1 Le montage physique (première phase matérielle : LD2450)

                        ~~~ ondes 24 GHz ~~~>   [cible mobile]
                       <~~~ echos ~~~
       +----------------+
       | HLK-LD2450     |  antennes PCB integrees (1 TX, 2 RX)
       | (radar 24 GHz) |  il calcule lui-meme x, y, vitesse (3 cibles max)
       +-------+--------+
               | UART 256000 bauds (3 fils : TX, RX, GND) + alim 5 V
               v
       +-------+--------+         +------------------+
       | STM32G474      |  UART2  | pont telemetrie  |   WiFi (TCP)
       | Ada/SPARK      +-------->+ ESP32 (possede)  + - - - - - - -> PC
       | Ravenscar      |         +------------------+   autre piece OK
       | pistage, MTI,  |
       | clutter, CFAR  |  ou bien : UART -> USB-UART -> cable USB -> PC
       +-------+--------+
               | GPIO (plus tard : drivers ULN2003)
               v
       [2 moteurs pas-a-pas : tourelle azimut/elevation - phase mecanique]

La décomposition en tâches visée sur la carte (le motif Ravenscar déjà
démontré par `radar_demo`, transposé au matériel) :

    [Capteur] --SPI/UART--> [STM32G474 - Ada bare-metal, profil Ravenscar]
    [Moteur+encodeur] <---> |  tache acquisition  |
                            |  tache moteur/scan  |  --> objet protege
                            |  tache telemetrie   |      (tampon, prouve)
                                     |
                                     +--UART/USB/WiFi--> [PC : rendu 3D]

Phase matérielle suivante (A121) : même schéma, mais le capteur parle **SPI**
et livre un profil d'écho par cases de distance (notre type `Sweep`) — c'est
là que `Detect_Adaptive` (CFAR), `Radar_Clutter` et le pistage, déjà
cross-compilés pour le Cortex-M4F, tournent **sur la carte**.

Répartition des rôles :

- Le **STM32 fait le temps réel et le formatage des données, en Ada** — c'est
  la vitrine embarquée. Pas de FFT lourde sur le MCU.
- Le **PC** fait le traitement lourd et le rendu 3D.
- Le **driver capteur est écrit en Ada**. Nuance apportée depuis : pour l'A121,
  la bibliothèque RSS d'Acconeer étant fermée, ce sera en pratique un
  **binding Ada → C** (`pragma Import`) plutôt qu'un driver SPI intégralement
  écrit à la main (voir `GUIDE_MATERIEL.md`).

### 7.2 Comment les ondes sont émises et captées

Tu ne « touches » jamais l'onde : la puce radar fait tout le RF.

1. La puce génère un signal 24/60 GHz (FMCW : fréquence qui glisse, ou
   impulsions cohérentes pour l'A121) et l'envoie sur son **antenne TX gravée
   sur le circuit** (quelques mm : intégrée, pas remplaçable) ;
2. l'onde part en cône (le « faisceau », large de 40–120° selon le module),
   rebondit sur ce qu'elle rencontre — un corps humain réfléchit bien, le
   plâtre absorbe/traverse partiellement à 24 GHz, bloque à 60 GHz ;
3. l'écho revient sur les **antennes RX** ; la puce mesure le retard
   (→ distance), le glissement de fréquence (→ vitesse Doppler) et la
   différence de phase entre RX (→ angle) ;
4. le module livre le résultat **en numérique** (UART ou SPI). Le travail de ce
   dépôt commence là.

### 7.3 Sur les « plusieurs faisceaux »

Le vrai multi-faisceaux (phased array type **AESA**) n'est pas réalisable au
budget hobby. La version abordable est le **beamforming par balayage
mécanique** (on pointe → on synthétise l'angle), éventuellement complété par du
beamforming numérique. À présenter comme tel, pas comme de l'AESA. Attente
réaliste sur le rendu : nuage de points 3D **épars** (bonne résolution en
distance, résolution angulaire grossière), pas une maquette CAO.

### 7.4 Télémétrie : comment les résultats arrivent jusqu'à toi

| Lien | Portée | Ce que ça demande | Verdict |
| ---- | ------ | ----------------- | ------- |
| UART + câble USB | 1–2 m (PC à côté) | rien (adaptateur 3 €) | **par là qu'on commence** : zéro inconnue, debug facile |
| **UART → ESP32 → WiFi** | toute la maison | l'ESP32 déjà possédé, en pont « bête » | **la cible** : tu es dans une autre pièce, le serveur de veille reçoit du TCP au lieu du simulateur |
| BLE | ~10 m | plus de travail, moins de débit | pas utile ici |

Le point d'architecture qui compte : l'ESP32 reste un **pont transparent**
(UART entrant → TCP sortant, zéro logique radar). Toute l'intelligence reste
dans le STM32 en Ada — la vitrine du projet est intacte (R1), et le pont est un
composant standard de l'industrie (« gateway »).

Débits, pour fixer les idées : des pistes (id, x, y, z, vitesse) à 10 Hz =
**~1 Ko/s** (rien du tout : UART 115200 suffit) ; des profils bruts A121
≈ 10–20 Ko/s (UART 921600 ou WiFi, confortable) ; de l'IQ brut BGT60 = des
Mo/s — là il faudra décimer **à bord**, et c'est un argument de plus pour faire
le traitement sur le STM32.

### 7.5 « Le WiFi perturbe-t-il le radar ? » — Non, et voici pourquoi

- Le WiFi émet à **2,4 / 5 / 6 GHz**. Les radars visés écoutent à **24 GHz**
  (LD2450) ou **60 GHz** (A121, BGT60). Aucun recouvrement : pour le radar, le
  WiFi n'existe pas (ses filtres d'entrée rejettent tout ce qui n'est pas sa
  bande). L'ESP32 peut être collé au module.
- Les **vraies** interférences à connaître :
  - **deux radars 24 GHz face à face** (deux LD2450 dans la même pièce)
    peuvent se polluer mutuellement ;
  - le **ventilateur / rideau** : pas une interférence radio, mais une cible
    mobile bien réelle pour le Doppler (documenté par les utilisateurs
    domotique — c'est la carte de clutter et le M-sur-N qui la gèrent) ;
  - le cas particulier du **coffee-can 2,4 GHz** (projet DIY ultérieur) : lui
    partage la bande WiFi — interférences dans les deux sens, à faire loin des
    points d'accès.
- Sens inverse (le radar perturbe-t-il le WiFi, ou toi ?) : puissance émise de
  l'ordre du **milliwatt**, en bande libre réglementée — sans enjeu.

Conséquence utile : à 60 GHz les ondes **ne traversent pas les cloisons**. Le
radar ne verra jamais la pièce d'à côté (à 24 GHz, une cloison légère est
partiellement transparente — les capteurs domotique sont parfois cachés
derrière un panneau). Le WiFi, lui, traverse : tu peux donc être ailleurs dans
la maison pendant que le radar scanne.

---

### 7.6 Le protocole de télémétrie (spécification)

C'est le livrable du jalon 7. **Rien de tout cela n'existe encore dans le
code** — cette section est la spécification à implémenter, pas un compte rendu.

Trame de longueur variable, **petit-boutiste** (le Cortex-M4, l'ESP32 et le PC
le sont tous — mais on l'écrit, parce que c'est exactement le genre de non-dit
qui coûte une soirée).

| Offset | Taille | Champ | Rôle |
| ------ | ------ | ----- | ---- |
| 0 | 2 | `SYNC` | `0xAA 0x55` — motif de resynchronisation |
| 2 | 1 | `VERSION` | `0x01` — faire évoluer sans casser |
| 3 | 1 | `KIND` | 1 = détections, 2 = pistes, 3 = état carte |
| 4 | 2 | `SEQ` | compteur 16 bits, +1 par trame émise |
| 6 | 4 | `TIMESTAMP` | millisecondes depuis le démarrage de la carte |
| 10 | 1 | `COUNT` | nombre d'éléments dans la charge utile |
| 11 | 1 | `LENGTH` | taille de la charge utile, en octets |
| 12 | N | `PAYLOAD` | les données |
| 12+N | 2 | `CRC16` | CCITT, sur les octets 2 à 11+N |

**Aucun champ n'est décoratif :**

- **`SYNC`** — en se branchant sur un flux déjà en cours, ou après une coupure
  WiFi, on arrive au milieu d'une trame. Sans motif de resynchronisation, on
  lit des octets décalés *pour toujours*. Le parseur cherche `AA 55`, puis
  valide le CRC : si les deux tombent juste, il est recalé.
- **`SEQ`** — le champ le plus important, et le plus souvent oublié. Il permet
  de **savoir** qu'une trame a été perdue. Sans lui, une trame manquante est
  invisible : le filtre alpha-beta prédit comme si de rien n'était et produit
  des vitesses fausses **sans un seul message d'erreur**. C'est le mode de
  défaillance silencieux de la dette 2, et le lien sans fil le rend fréquent.
- **`TIMESTAMP`** — c'est le jalon 1 qui arrive par le câble : le `dt` réel,
  mesuré par la carte, jamais supposé par le PC.
- **`CRC16`** — l'UART se trompe, surtout à 256000 bauds sur de la breadboard.
  Sans CRC, un octet corrompu devient une cible fantôme à douze mètres.

#### Charge utile — une détection ou une piste (15 octets)

| Champ | Taille | Unité |
| ----- | ------ | ----- |
| `ID` | 2 | identifiant de piste (0 pour une détection brute) |
| `X`, `Y`, `Z` | 3 × 2 signés | millimètres |
| `VX`, `VY`, `VZ` | 3 × 2 signés | **mm/s** — plus jamais de mm/tour |
| `FLAGS` | 1 | bit 0 = confirmée, bit 1 = coasting |

Trois cibles LD2450 → 45 octets utiles → **59 octets par trame**. À 10 Hz :
**590 octets/s**. Un UART à 115200 en transporte 11 000 : on occupe 5 % du
lien, et c'est voulu.

#### `KIND` évite un choix prématuré

On n'a pas à décider tout de suite *qui* fait le pistage :

- **`KIND = 1`** — la carte envoie des détections, le PC fait le regroupement
  et le pistage avec `Radar_Detect` et `Radar_Track`, **déjà écrits et
  testés**. C'est par là qu'on commence.
- **`KIND = 2`** — la carte piste elle-même et n'envoie que des conclusions.
  C'est la vitrine embarquée finale.

Le transport ne change pas entre les deux. On bascule quand la carte est
prête, pas avant.

#### La représentation Ada — c'est la vitrine

Pas de décalages calculés à la main, pas de `memcpy` : la structure **est** la
trame. Ce paquet est testable **sans matériel** (fabriquer un tableau d'octets,
le lire, vérifier les champs) — et c'est le test de parsing qui manque
aujourd'hui au dépôt.

    with Interfaces;  use Interfaces;
    with System;

    package Radar_Telemetry is

       --  Le format d'echange carte -> PC. La disposition binaire est
       --  IMPOSEE ici : rien n'est laisse a l'interpretation du
       --  compilateur, donc pas de surprise entre le Cortex-M4 et le x86.
       type Frame_Header is record
          Sync_0    : Unsigned_8;
          Sync_1    : Unsigned_8;
          Version   : Unsigned_8;
          Kind      : Unsigned_8;
          Sequence  : Unsigned_16;
          Timestamp : Unsigned_32;   --  millisecondes depuis le boot
          Count     : Unsigned_8;
          Length    : Unsigned_8;
       end record;

       for Frame_Header use record
          Sync_0    at 0  range 0 .. 7;
          Sync_1    at 1  range 0 .. 7;
          Version   at 2  range 0 .. 7;
          Kind      at 3  range 0 .. 7;
          Sequence  at 4  range 0 .. 15;
          Timestamp at 6  range 0 .. 31;
          Count     at 10 range 0 .. 7;
          Length    at 11 range 0 .. 7;
       end record;

       for Frame_Header'Size use 12 * 8;

       --  Petit-boutiste des deux cotes : on l'ECRIT plutot que de
       --  l'esperer. Si une cible gros-boutiste apparaissait un jour, c'est
       --  le compilateur qui ferait la conversion, pas nous.
       for Frame_Header'Bit_Order use System.Low_Order_First;
       for Frame_Header'Scalar_Storage_Order use System.Low_Order_First;

    end Radar_Telemetry;

#### Que faire quand ça casse

| Symptôme | Cause probable | Réaction du code |
| -------- | -------------- | ---------------- |
| CRC faux | bruit UART, débit trop haut | compter, jeter la trame, continuer |
| `SEQ` saute | trame perdue (WiFi, tampon plein) | **signaler au pistage** : le `dt` est plus grand |
| Pas de `SYNC` | flux décalé, capteur redémarré | rechercher `AA 55` octet par octet |
| Rien du tout | masse commune absente, TX/RX inversés | vérifier le câblage **avant** le code |

Ces compteurs (trames reçues, CRC faux, trames perdues) doivent être
**visibles dans la page** — c'est le rôle de `/health.json` au jalon 2bis.
C'est la différence entre un démonstrateur et un instrument : quand la qualité
du lien se dégrade, il faut le voir **avant** que les pistes deviennent
farfelues.

---

## 8. Dettes connues et enseignements

### 8.1 Dettes d'implémentation

Priorité réévaluée selon la règle d'arbitrage (§2) : ce qui rapproche d'un
radar fonctionnel passe devant ce qui rapproche d'une preuve.

1. **Fragmentation de pistes** — ✅ **résolue** en deux temps : association
   GLOBALE (paire piste/détection la plus proche au monde, plus de « vol » de
   détection) + FUSION des pistes à moins de 400 mm. La traque du fantôme
   restant a révélé un phénomène radar authentique : les fausses alarmes CFAR
   des premières cases de distance se concentrent géométriquement près de
   l'origine (tous les azimuts y convergent) et fabriquaient une piste fantôme
   persistante au pied du radar — parade réelle appliquée : **distance
   aveugle** de 625 mm (`Blind_Bins`), sous contrat prouvé, comme sur un vrai
   module dont la fuite TX→RX sature les premières cases.
2. **Vitesses en mm/tour** — **priorité haute** (jalon 1) : toujours pas de
   vraie base de temps (m/s). À faire avant le matériel — le LD2450 fournira
   des horodatages réels.
3. **Couplage implicite de grille** — priorité moyenne : la grille de
   `Radar_Clutter` (120 × 7) doit correspondre à celle de la source,
   convention non vérifiée par le compilateur. À terme : passer la grille en
   paramètre (générique ou discriminant).
4. **HTTP par sondage (250 ms)** — priorité moyenne : simple et suffisant à
   0,8 s/tour ; si la cadence monte (LD2450 : 10 Hz), passer aux Server-Sent
   Events (plus simple que WebSocket, toujours sans dépendance).
5. **Serveur mono-thread** — priorité basse : si un tour de traitement
   dépassait la période, les requêtes attendraient. Sans enjeu sur PC ; à
   surveiller.
6. **Serveur en 127.0.0.1 sans authentification** — **volontaire** (démo
   locale). Pour consulter depuis le téléphone : écouter sur 0.0.0.0 — et
   assumer que c'est du LAN de confiance.
7. **La couche 3D reste en `Float` non SPARK** — **priorité basse désormais**
   (jalon 10) : c'était un chantier bloquant sous l'ancienne règle
   d'arbitrage ; sous la nouvelle (§2), c'est un bonus opportuniste. Une piste
   si on le fait : millimètres entiers bornés ou virgule fixe, plus proches des
   usages « défense » et plus simples à prouver.
8. **L'interface `Source` était contournée par trois modes sur quatre** —
   ✅ **résolue.** `live`, `map` et `scan` déclaraient `Simulated_Source`
   (le type **concret**) : leurs appels étaient liés statiquement au
   simulateur, et la promesse « le jour du matériel, seule la source
   change » était fausse pour eux. Seul `track` faisait les choses
   correctement, via `Process (Radar : in out Source'Class)`.
   *La cause n'était pas de la négligence, et c'est l'enseignement :*
   l'interface était **incomplète**. `live` et `scan` ont besoin de
   `Per_Turn` (combien de mesures font un tour) pour cadencer et afficher
   une progression — une opération qui n'existait que sur le type concret.
   Ils n'avaient donc **pas le choix** que de le nommer. Parade : `Per_Turn`
   est entré dans le contrat de `Radar_Source`, et les trois modes sont
   passés en `Source'Class`. Un test (« Source pilotée à travers
   l'interface ») garde la porte fermée : si une opération nécessaire
   quittait l'interface, il cesserait de compiler.
9. **La géométrie vivait en double, dont une moitié non testée** —
   ✅ **résolue.** Les pages de `map` et `scan` recalculaient en JavaScript
   la distance, l'azimut et l'élévation d'un point cliqué — c'est-à-dire
   `Radar_Geometry.To_Polar`, réécrit à la main, avec ses propres cas
   limites (`Math.max(1,d)` là où la version Ada a un bornage d'Arcsin
   couvert par un test). Violation directe de R1, et surtout : corriger un
   bug de géométrie en Ada laissait le bug dans la page. Parade : `To_Polar`
   est appelée en Ada, ses trois valeurs partent avec chaque point, la page
   ne fait plus que les afficher.
10. **Trois saturations silencieuses** — priorité moyenne. Quand une borne est
    atteinte, la donnée est jetée **sans un mot** :
    `Radar_Cloud.Append` au-delà de 8 192 points, `Radar_Track` quand les 16
    pistes sont actives et qu'une détection orpheline arrive,
    `Radar_Detect` au-delà de 32 détections par tour.
    Les bornes elles-mêmes sont le **bon choix** — mémoire statique, jamais de
    débordement, c'est ce qu'un embarqué exige. C'est leur **mutisme** qui ne
    l'est pas : en radar, un nuage tronqué ressemble à une pièce plus petite,
    et c'est un mensonge parfaitement crédible.
    Le jalon 2 supprime le cas du nuage par construction (grille à mémoire
    fixe, plus de liste qui déborde). Restent les deux autres, qui doivent au
    minimum **compter** ce qu'elles jettent et le publier dans `/health.json`
    (jalon 2bis).

   *Effet de bord instructif :* transporter six nombres au lieu de trois a
   fait passer la page publiée de 172 à 328 Ko. La cause n'était pas le
   volume de données mais le **format** — `Float'Image` écrit
   `1.96155E+03`, soit onze caractères pour une valeur qu'on connaît à
   78 mm près. Un format compact à une décimale (`Radar_Html.F_Img`) ramène
   la page à 177 Ko **avec deux fois plus de données**, et rend le JSON du
   mode `live` lisible à l'œil (`"x":2302.8`).

### 8.2 Enseignements (du vécu, coûteux à réapprendre)

- **Crates `a0b`** (BSP communautaire STM32) : ne compilent pas avec la
  toolchain récente — elles sont épinglées à `gnat_arm_elf=14.2` /
  `gprbuild=22`, d'où l'erreur `Runtime_Ada is not a single string` avec
  gnat 15.2 / gprbuild 25. → Pour la cible STM32, utiliser le runtime
  **maintenu par AdaCore** (`embedded_stm32g4xx`), pas ces crates.
- **Le blinky a besoin du matériel** : le brochage LED se vérifie sur la carte
  réelle. La cross-compilation peut se préparer sans carte, mais la validation
  finale (flash) attend le STM32.
- **ESP32** : Ada possible (toolchain `gnat_xtensa_esp32_elf` présente) mais
  moins documenté, et le rôle utile de l'ESP32 ici est le pont télémétrie →
  on reste sur STM32 pour la logique.
- **Alire est épinglé à 2.1.0 en CI** : la version 2.0.2 casse la résolution
  d'AUnit (le commentaire détaillé est dans `.github/workflows/ci.yml`).
- **`radar_demo.gpr` n'importe volontairement pas `radar_fw_config.gpr`** :
  la configuration AUnit violerait la restriction Ravenscar `No_Calendar`.

---

## 9. Feuille de route

### 9.1 Le matériel de référence

Détail des achats, des prix et des alternatives : `GUIDE_MATERIEL.md`. Ici,
seulement ce qui conditionne les jalons.

| Matériel | Statut | Rôle |
| -------- | ------ | ---- |
| ESP32 | possédé | **pont télémétrie** UART → WiFi (pas de logique radar dessus) |
| PIC | possédé | hors cible (pas de support Ada) |
| WeAct **STM32G474** | à acheter | le cerveau Ada (Cortex-M4 + FPU) |
| ST-Link V2 (clone) | à acheter | programmateur / débogueur |
| USB-UART (CP2102 / FT232) | à acheter | la liaison de départ, PC à côté |
| **HLK-LD2450** (24 GHz) | à acheter | le premier vrai radar (niveau détection) |
| Moteurs pas-à-pas + ULN2003 | à acheter | la tourelle de balayage |
| Acconeer A121 / Infineon BGT60 | plus tard | le niveau balayage (vrai `Sweep`) |

**Pourquoi le STM32G474 et pas autre chose** : c'est la famille proprement
supportée par la toolchain Ada (`gnat_arm_elf`) et par les runtimes publiés
(`light`, `light-tasking`, Ravenscar). Le `light-tasking` est indispensable
pour porter la démonstration Ravenscar sur la carte — c'est lui qui décide.

**Budget** : ~150–200 € pour le chemin complet, dans l'enveloppe 100–300 €
fixée à l'origine.

### 9.2 Les jalons

Une seule liste, qui remplace les deux feuilles de route concurrentes qui
existaient auparavant. Un jalon n'est terminé que quand son critère de sortie
est vérifiable **et** que R5 est honorée.

| # | Jalon | Coût | Critère de sortie |
| - | ----- | ---- | ----------------- |
| 1 | **Base de temps réelle** : horodatage porté par `Measurement`, vitesses en m/s au lieu de mm/tour | 0 € | une vitesse en m/s vérifiée par un test |
| 2 | **Carte vivante** : `Radar_Cloud` passe d'une liste saturable à une **grille par direction avec âge** — trois états (*jamais balayé* / *balayé sans écho* / *écho daté*), oubli en secondes, mémoire bornée à la compilation | 0 € | le mode `scan` distingue un trou d'une zone non explorée, et un objet déplacé disparaît de la carte tout seul |
| 2bis | **Poste de contrôle** : le serveur accepte des commandes, la page devient pilotage (recalibrer, démarrer/arrêter, effacer, santé du lien, export) | 0 € | recalibrer le clutter **sans relancer le programme** |
| 3 | **Interface de niveau détection + émulateur LD2450** émettant de **vraies trames binaires** (10 Hz, 3 cibles, 2D, jitter, dropouts, fantômes) | 0 € | `radar_fw live` tourne sur l'émulateur sans modifier le pistage, et le parseur du jalon 5 se teste contre lui |
| 4 | **Achat du premier lot** : WeAct STM32G474CEU6, ST-Link V2, USB-UART, HLK-LD2450, breadboard, fer à souder | ~55 € | matériel reçu (détails dans `GUIDE_MATERIEL.md`) |
| 5 | **`Radar_Serial_Source`** : parsing des trames LD2450 en Ada (clauses de représentation) | — | des pistes **réelles** s'affichent dans le navigateur, sur données câblées |
| 6 | **Portage sur carte** : blinky STM32G474, puis `radar_demo` sous runtime `light-tasking` | — | Ravenscar tourne sur le matériel |
| 7 | **Traitement embarqué** : parsing LD2450 sur la carte + protocole de télémétrie (en-tête, compteur, CRC) spécifié dans ce document | — | le PC reçoit des pistes calculées **par la carte** |
| 8 | **Tourelle motorisée** azimut/élévation (28BYJ-48 + ULN2003) | ~15 € | un vrai scan de pièce : nuage 3D réel, avec ses trous |
| 9 | **Capteur de niveau balayage** (Acconeer A121 ou Infineon BGT60TR13C) : le `Sweep` devient réel | 60–120 € | `Detect_Adaptive` (CFAR prouvé) tourne sur de vraies données |
| 10 | **Bonus opportunistes** : SPARK sur la couche 3D, paquet `Radar_Array` (PESA logicielle), traçabilité exigences ↔ code ↔ tests | 0 € | jamais bloquants (R2) |

Les jalons 1 à 3 ne demandent **aucun matériel** : ils préparent le terrain
pour que le jour de la livraison, il ne reste qu'à changer la source (R3).

**Conseil d'ordonnancement :** commander le lot du jalon 4 **dès maintenant**,
en parallèle des jalons 1 à 3. Un colis met deux à trois semaines ; c'est à peu
près le temps de faire la base de temps, la carte vivante et l'émulateur.
Commander après avoir fini le logiciel, c'est attendre pour rien.

**Dépendances à ne pas inverser :**

- Le jalon 2 a besoin du jalon 1 : une durée de vie se compte en **secondes**,
  pas en tours. Un tour de cartographie réel durera des minutes — vieillir
  « tous les 8 tours » n'y voudrait plus rien dire.
- Le jalon 5 a besoin du jalon 3 : si l'émulateur émet de vrais octets, le
  parseur binaire s'écrit et se **teste avant** que le capteur arrive. Sinon on
  débogue du parsing et de l'électronique en même temps, ce qui est la pire
  configuration possible.

---

## 10. Conventions

- **Cycle Git** : `git add .` → `git commit -m "..."` → `git push`, à chaque
  jalon. Messages clairs et en **français sans accents**, avec les préfixes du
  dépôt (`docs :`, `tests :`, `CI :`, `fix :`, `perf :`, `feat :`) ou un sujet
  direct (`Mode scan : ...`). Un recruteur lit l'historique.
- **Types bornés + contrats** : pas d'entier nu pour une grandeur physique ;
  préconditions et postconditions sur les interfaces.
- **SPARK** : `SPARK_Mode => On` là où c'est raisonnable, et **on ne perd
  jamais ce qui est déjà prouvé** (R2). Pour du code neuf, un
  `SPARK_Mode => Off` explicite et commenté est acceptable. Reprouver après
  chaque ajout touchant du code prouvé (`alr exec -- gnatprove`, viser 0
  unproved).
- **Contrats non triviaux** : une postcondition déjà garantie par un sous-type
  (ex. `Count <= Max`) ne prouve rien ; viser des propriétés fonctionnelles
  (ex. « toute cible rapportée dépasse son seuil local »).
- **Commentaires Ada** : en français **sans accents** (ASCII pur, par
  sécurité), denses, et qui expliquent le **pourquoi** — surtout la
  justification physique d'une constante.
- **Style GNAT strict** : `-gnaty3aAbBcefhiIklmnOprStux`, zéro warning
  (`-gnatwa`). `pragma Style_Checks ("M300")` reste local aux seuls fichiers
  qui génèrent du HTML.
- **Documents à jour** : `README.md` et ce fichier reflètent l'état réel. La
  procédure de mise à jour est dans `CLAUDE.md`.
- **Langue** : les documents sont en français. Un passage des commentaires de
  code en anglais reste envisagé pour la visibilité GitHub — décision non
  prise, à trancher explicitement (ce serait un chantier à part entière).
