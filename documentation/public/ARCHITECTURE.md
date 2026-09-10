# Architecture radar — radar_fw

Documentation d'ingénierie : **pourquoi le code fait ce qu'il fait**. Deux
volets, l'un sur la physique radar que le logiciel doit affronter, l'autre sur
l'architecture matérielle visée et son protocole d'échange.

C'est le document que citent les commentaires du code source (« realisme
point N » renvoie à la checklist de la section 1.4, dont la numérotation est
stable).

Voir aussi le `README.md` pour l'état d'avancement et
`documentation/public/GUIDE_DEPOT.md` pour la carte du dépôt.

---

## 1. Réalisme : où en est le simulateur face au monde réel

Objectif de cette section : mesurer l'écart entre le simulateur et ce que
donneront les essais réels, en s'appuyant sur des projets existants
documentés.

Point de départ : **l'architecture était juste, le monde simulé beaucoup trop
docile**. Cibles ponctuelles parfaites, amplitude constante, zéro bruit, zéro
fausse alarme, faisceau crayon idéal — chacune de ces hypothèses tombe en
conditions réelles. Chacune peut en revanche être levée *en simulation*, une
par une, sans attendre le capteur : c'est l'objet de la checklist de la
section 1.4.

### 1.1 Une cible réelle n'est pas une sphère

- **Cible étendue** : un humain vu par un radar 24/60 GHz, ce sont des
  dizaines de réflecteurs (torse, membres, tête) qui bougent les uns par
  rapport aux autres. Le « centre » mesuré se promène sur le corps (± 20–30 cm
  d'un tour à l'autre) et occupe plusieurs cases de distance à la fois.
- **Fluctuation d'amplitude** (modèles de Swerling) : l'écho varie de
  10–20 dB selon l'orientation de la cible. Concrètement : un tour elle est vue
  nettement, le tour suivant elle passe sous le seuil. Les **trous de détection
  sont la norme**, pas l'exception.
- **Multitrajet** : sol et murs créent des **cibles fantômes** (écho rebondi =
  fausse cible derrière la vraie), surtout en intérieur.
- **Micro-Doppler** : pour un radar, un **ventilateur est une cible mobile** —
  artefact documenté par les utilisateurs du LD2450 en domotique (« fan
  flicker », parade : filtres de temporisation).
- **Personne immobile ≈ invisible** pour une détection par mouvement / carte
  de clutter : c'est tout le fond de commerce des capteurs de « présence »
  (LD2410) qui détectent la respiration.

Ce que ces réalités mettent en défaut dans une conception naïve, et la
parade retenue :

| Hypothèse naïve | Réalité | Conséquence et parade |
| --------------- | ------- | --------------------- |
| Vitesse = différence de positions brutes | jitter ± 20–30 cm par mesure | vitesse inutilisable sans **filtre** (alpha-beta, puis Kalman) |
| `Cluster_Radius` fixe 300 mm | cible étendue + jitter | fragmentation d'une personne en 2–3 pistes, ou fusion de 2 personnes proches |
| Association gloutonne au plus proche | deux personnes qui se croisent | **échanges d'ID** quasi garantis (parade : association globale type hongrois/GNN) |
| Une détection = une piste affichée | dropouts + fantômes fréquents | pistes fantômes clignotantes (parade : cycle de vie **M-sur-N**, piste « tentative » non affichée) |
| Seuil fixe (100) | bruit variable selon distance/scène | fausses alarmes en avalanche OU cibles faibles ratées (parade : **CFAR**) |
| Clutter appris une fois pour toutes | rideaux, ventilateurs, meubles déplacés | carte de clutter à **oubli lent** (moyenne exponentielle) |

### 1.2 Le capteur réel ne balaie pas comme le simulateur

Le simulateur modélise un faisceau crayon de 3° balayé mécaniquement. **Aucun
capteur envisagé ne fait ça nativement** :

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
  au fil de l'eau), pas « tout à la fin ».

### 1.3 Ce que montrent les projets existants

- **LD2450 + ESPHome / Home Assistant** (composants communautaires, zones
  polygonales, `off_delay`) : la communauté documente précisément les
  artefacts réels — ventilateurs, instabilités d'alimentation en 3,3 V,
  rafraîchissement 10 Hz — et les parades logicielles simples. C'est un aperçu
  fidèle de ce que notre pipeline recevra.
- **Henrik Forstén (hforsten.com)** : la référence du radar FMCW amateur —
  6 GHz, PCB maison (~350 composants), détection d'un humain à 100 m, puis
  **SAR embarqué sur drone** avec autofocus. Deux leçons : le sommet du
  réalisable en amateur est très haut, et l'essentiel du travail est dans le
  **traitement et la calibration**, pas dans le RF — exactement le pari de ce
  projet.
- **Acconeer** documente la conception de lentilles comme une étape normale
  d'intégration (docs « Lens design »), ce qui confirme le point ci-dessus
  pour le mode cartographie.

### 1.4 Checklist de mise à niveau du réalisme

Numérotation **stable** : plusieurs commentaires du code source y renvoient
(« realisme point N »). Ne pas renuméroter.

1. **Cibles étendues et Swerling** — **mis en œuvre.** Chaque objet est
   simulé par 4 réflecteurs (± 150 mm), dont l'amplitude est tirée au sort à
   chaque tour (graine fixe, donc reproductible), avec 15 % d'extinction par
   réflecteur et 10 % d'évanouissement profond par objet. `Cluster_Radius`
   est porté à 600 mm en conséquence : une cible étendue vue à travers une
   quantification d'élévation peut écarter deux échos du même objet
   d'environ 520 mm à 3 m. Revers assumé : deux objets réels à moins de
   600 mm fusionnent — c'est la résolution réelle du capteur simulé.
2. **Bruit de fond et CFAR** — **mis en œuvre.** Bruit aléatoire dans chaque
   case et seuil CA-CFAR (fenêtre 8, garde 2, facteur 4) **prouvé SPARK**
   (`Detect_Adaptive` : « aucune cible sous son seuil local »). C'est cette
   détection qu'utilise tout le pipeline.
3. **Cycle de vie M-sur-N** — **mis en œuvre.** Une piste tentative reste
   invisible avant 3 détections, et une tentative non revue meurt en
   2 tours ; l'affichage, en veille comme en rejeu, ne montre que les pistes
   confirmées, et le coasting y est marqué (gris et `*`).
4. **Filtre alpha-beta** — **mis en œuvre.** Prédiction et coasting — une
   piste non revue roule sur son erre — puis correction alpha (0,5) et beta
   (0,3). La prédiction avance de `v × dt` et le gain beta est divisé par
   `dt`, si bien que la vitesse estimée ne dépend **pas** de la cadence de
   balayage : la même cible vue à 1 ou 2 tours par seconde donne la même
   valeur en mm/s (vérifié par un test).

   La fenêtre d'association suit la même logique : `600 mm + v × dt`. Le
   terme fixe couvre le bruit de mesure et l'étalement de la cible, le terme
   proportionnel couvre la manœuvre — si la cible change de cap pendant
   `dt`, la prédiction se trompe d'environ `v × dt`. Avec un balayage
   mécanique, `dt` varie d'une fraction de seconde à des dizaines de
   secondes selon la direction : un rayon figé serait aussitôt trop large,
   puis très vite trop étroit.
5. **Fantômes multitrajet** — **mis en œuvre.** 5 % de probabilité d'écho
   miroir derrière le mur ; c'est la règle M-sur-N qui les étouffe, ce que
   vérifie un test.
6. **Clutter adaptatif** — **mis en œuvre.** Compteurs de confiance sur
   2 bits, confirmation à 2 observations, apprentissage de fond (1 tour sur
   4) et oubli lent (`Age` tous les 8 tours) : le décor qui apparaît est
   appris, celui qui disparaît est oublié, et un mobile qui ne fait que
   passer n'empoisonne pas la carte — tandis qu'un mobile qui se gare y fond,
   réalisme assumé. Limite connue du mécanisme : la fragmentation d'une cible
   étendue peut confirmer une piste « ombre » ; ce sont l'association globale
   et la fusion de pistes, dans `Radar_Track`, qui l'écartent.
7. **Émulateur LD2450** — **non implémenté.** Il s'agirait d'une source de
   niveau détection (x, y, vitesse, 10 Hz, 3 cibles au plus, jitter
   réaliste, dropouts, fantômes), afin que le pipeline PC soit prêt **avant**
   l'arrivée du module, qui remplacerait alors l'émulateur trame pour trame.
8. **Cartographie progressive** — **mise en œuvre.** Le mode `scan` : le
   serveur HTTP (paquet partagé `Radar_Http`) cadence le balayage une colonne
   d'azimut à la fois et la page se remplit au fil de l'eau, avec sa
   progression et son compteur de points ; le scan terminé, le nuage reste
   servi et explorable. Sur du matériel réel, seules la cadence et la source
   changeront.

### 1.5 Ce qui est déjà réaliste (à conserver)

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

## 2. Architecture système

### 2.1 Le montage physique (première phase matérielle : LD2450)

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
  la part embarquée du traitement. Pas de FFT lourde sur le MCU.
- Le **PC** fait le traitement lourd et le rendu 3D.
- Le **driver capteur est écrit en Ada**. Nuance : pour l'A121, la
  bibliothèque RSS d'Acconeer étant fermée, ce sera en pratique un
  **binding Ada → C** (`pragma Import`) plutôt qu'un driver SPI intégralement
  écrit à la main.

### 2.2 Comment les ondes sont émises et captées

On ne « touche » jamais l'onde : la puce radar fait tout le RF.

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

### 2.3 Sur les « plusieurs faisceaux »

Le vrai multi-faisceaux (phased array type **AESA**) n'est pas réalisable au
budget hobby. La version abordable est le **beamforming par balayage
mécanique** (on pointe → on synthétise l'angle), éventuellement complété par du
beamforming numérique : c'est de cela qu'il s'agit ici, et non d'une antenne
AESA. Attente réaliste sur le rendu : un nuage de points 3D **épars** — bonne
résolution en distance, résolution angulaire grossière — et non une maquette
CAO.

### 2.4 Télémétrie : comment les résultats remontent jusqu'au PC

| Lien | Portée | Ce que ça demande | Verdict |
| ---- | ------ | ----------------- | ------- |
| UART + câble USB | 1–2 m (PC à côté) | un adaptateur USB-UART | **par là qu'on commence** : zéro inconnue, debug facile |
| **UART → ESP32 → WiFi** | toute la maison | un ESP32 en pont « bête » | **la cible** : l'opérateur est dans une autre pièce, le serveur de veille reçoit du TCP au lieu du simulateur |
| BLE | ~10 m | plus de travail, moins de débit | pas utile ici |

Le point d'architecture qui compte : l'ESP32 reste un **pont transparent**
(UART entrant → TCP sortant, zéro logique radar). Toute l'intelligence reste
dans le STM32 en Ada, et le pont reste un composant standard de l'industrie
(« gateway »).

Débits, pour fixer les idées : des pistes (id, x, y, z, vitesse) à 10 Hz =
**~1 Ko/s** (rien du tout : UART 115200 suffit) ; des profils bruts A121
≈ 10–20 Ko/s (UART 921600 ou WiFi, confortable) ; de l'IQ brut BGT60 = des
Mo/s — là il faudra décimer **à bord**, et c'est un argument de plus pour faire
le traitement sur le STM32.

### 2.5 « Le WiFi perturbe-t-il le radar ? » — Non, et voici pourquoi

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
- Sens inverse (le radar perturbe-t-il le WiFi, ou les personnes présentes ?) :
  puissance émise de l'ordre du **milliwatt**, en bande libre réglementée —
  sans enjeu.

Conséquence utile : à 60 GHz les ondes **ne traversent pas les cloisons**. Le
radar ne verra jamais la pièce d'à côté (à 24 GHz, une cloison légère est
partiellement transparente — les capteurs domotique sont parfois cachés
derrière un panneau). Le WiFi, lui, traverse : on peut donc être ailleurs dans
la maison pendant que le radar scanne.

### 2.6 Le protocole de télémétrie (spécification)

**Rien de tout cela n'existe encore dans le
code** — cette section est la spécification à implémenter, pas un compte rendu.

Trame de longueur variable, **petit-boutiste** (le Cortex-M4, l'ESP32 et le PC
le sont tous — mais on l'écrit, parce qu'un tel non-dit se paie au moment du
débogage, quand plus rien ne permet de dire qui des deux bouts a tort).

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
  défaillance silencieux le plus courant, et le lien sans fil le rend fréquent.
- **`TIMESTAMP`** — la base de temps arrive par le câble : le `dt` réel,
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
  C'est la cible finale du portage embarqué.

Le transport ne change pas entre les deux. On bascule quand la carte est
prête, pas avant.

#### La représentation Ada : la trame est la structure

Pas de décalages calculés à la main, pas de `memcpy` : la structure **est** la
trame. Un tel paquet se teste **sans matériel** — fabriquer un tableau
d'octets, le donner à lire, vérifier les champs obtenus — et c'est la seule
manière raisonnable de mettre au point un parseur binaire avant que le
capteur existe.

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
**visibles dans la page**, via une route `/health.json`.
C'est la différence entre un démonstrateur et un instrument : quand la qualité
du lien se dégrade, il faut le voir **avant** que les pistes deviennent
farfelues.
