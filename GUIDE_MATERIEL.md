# Guide matériel & feuille de route capteurs — radar_fw

Réponses aux questions : *que dois-je commander ? pas d'antenne ? comment
passer du simulateur à un vrai radar qui détecte des cibles mobiles, avec ou
sans scan de pièce ?* — et la marche à suivre, phase par phase.

---

## 1. Réponse courte

**Non, tu n'achètes pas d'antenne — et tu n'en construiras pas.** Aux
fréquences radar accessibles en hobby (24 GHz et 60 GHz), la longueur d'onde
fait 5 à 12 mm : les antennes sont des **pastilles gravées sur le PCB du
module** (patch array) ou intégrées dans le boîtier même de la puce
(*antenna-in-package*, cas de l'Acconeer A121). Tout module radar du commerce
arrive donc antennes comprises, prêt à émettre.

**À commander maintenant (≈ 50–60 €) :**

| Quoi | Prix ~ | Pourquoi |
| ---- | ------ | -------- |
| WeAct STM32G474CEU6 | 12–18 € | le cerveau Ada (déjà prévu) |
| ST-Link V2 clone (ou STLINK-V3MINIE) | 5–12 € | flash + debug SWD |
| Adaptateur USB-UART (CP2102/FT232) | 3 € | télémétrie + **brancher le radar au PC sans attendre le STM32** |
| **Hi-Link HLK-LD2450** | 10–15 € | **le premier vrai radar** : 24 GHz, suit jusqu'à 3 cibles mobiles, sort x, y, vitesse en UART |
| Breadboard + jumpers Dupont | 8 € | câblage |
| (si pas déjà) fer à souder basique | 15–20 € | les headers des cartes arrivent souvent non soudés |

Le LD2450 + l'adaptateur USB-UART se branchent **directement sur le PC** :
tu peux avoir de la détection de cibles mobiles **réelles** dans ton
pipeline Ada actuel *avant même que le STM32 n'arrive*.

---

## 2. La réalité RF en deux paragraphes

Un « radar fait maison » au sens *je soude l'émetteur et l'antenne* n'existe
pratiquement pas à ces fréquences : le front-end RF (VCO, mixeur, LNA) est
une puce millimétrique, et l'antenne est co-conçue avec elle. Le travail
d'ingénieur radar amateur, c'est **tout ce qu'il y a après l'antenne** :
acquisition, traitement (FFT distance, Doppler, CFAR, MTI), pistage,
visualisation — exactement ce que ce dépôt construit déjà en simulé.

*Exception pédagogique si un jour tu veux vraiment toucher le RF :* le
« coffee-can radar » du MIT (FMCW 2,4 GHz, antennes = deux boîtes de
conserve, ~150 €). Mémorable en entretien, mais sortie audio vers PC — ça
ne met pas en valeur la chaîne STM32/Ada. À garder comme projet annexe,
pas comme chemin principal.

---

## 3. Les capteurs, par étage de maturité

| Étage | Module | Prix ~ | Interface | Ce qu'il donne | Rôle dans le projet |
| ----- | ------ | ------ | --------- | -------------- | ------------------- |
| 1 | **HLK-LD2450** (24 GHz FMCW) | 10–15 € | UART 256000 bauds, trames binaires | jusqu'à 3 cibles : x, y (mm), vitesse (cm/s), ~10 Hz, ±60° d'azimut, ~6 m | cibles mobiles réelles tout de suite ; il fait la détection, TON code fait pistage/fusion/affichage |
| 2 | Acconeer **A121** (module XM125) | 60–80 € | SPI (via lib C d'Acconeer) | profil d'écho par cases de distance (comme ton type `Sweep` !), très précis | scan de pièce fin sur tourelle ; distance mm |
| 3 | Infineon **BGT60TR13C** (60 GHz FMCW) | 60–120 € | SPI, données IQ **brutes**, 1 TX / 3 RX | les échantillons bruts : FFT distance, FFT Doppler, CFAR, angle par 3 antennes RX — le vrai boulot de radariste | la consécration : TA chaîne de traitement de bout en bout |

Points de vigilance honnêtes :

- **A121** : la puce ne se pilote pas registre par registre ; elle exige la
  bibliothèque C fermée d'Acconeer (RSS). Le « driver SPI 100 % Ada » promis
  par le GUIDE_PROJET sera en réalité un **binding Ada→C** (pragma Import) +
  le port bas niveau SPI en Ada. C'est un très bon exercice quand même, mais
  il faut le savoir avant d'acheter.
- **LD2450** : il sort des cibles déjà détectées (pas d'écho brut) et en 2D
  (pas d'élévation). C'est sa force (résultats immédiats) et sa limite.
- **BGT60TR13C** : le plus formateur, mais le plus difficile (débits SPI,
  buffers IQ, DSP). À garder pour la phase où le reste tourne.

---

## 3 bis. Fabriquer soi-même : ce qui est réaliste (et l'antenne)

La physique décide de ce qui est fabricable à la main :

- la précision en **distance** vient de la **bande passante** du signal —
  fixée par la puce et la réglementation : pas de levier DIY ;
- la précision **angulaire** vient de la **taille de l'antenne**
  (ouverture) : largeur de faisceau ≈ 70 × λ / D degrés. Doubler le
  diamètre = faisceau deux fois plus fin. **C'est LE levier DIY** ;
- la **portée** vient du gain d'antenne (qui compte au carré :
  aller-retour). Autre levier DIY.

Ce que ça donne, capteur par capteur :

| Capteur | Antenne modifiable ? | Levier « je fabrique » |
| ------- | -------------------- | ---------------------- |
| LD2450, BGT60 (24/60 GHz) | non : patchs gravés sur PCB, aucun connecteur RF | logiciel + mécanique seulement |
| A121 (60 GHz) | non, MAIS une **lentille diélectrique** posée devant focalise réellement à λ = 5 mm | kit lentille Acconeer (~15 €) ou lentille **imprimée en 3D** |
| **HB100** (10,525 GHz, 3–5 €) | oui, indirectement : on construit un cornet ou une parabole **autour** du module | **le terrain de jeu antenne** |
| Coffee-can 2,4 GHz | antennes 100 % construites main | le radar entier fait main |

### Le projet antenne qui a du sens tout de suite (~10 €)

**HB100 + cornet fait main + ADC du STM32.** Le HB100 est un module
Doppler à 10,5 GHz qui sort son signal de battement **en bande audio** :
l'ADC du STM32G474 l'échantillonne, ta FFT en Ada sort la vitesse de la
cible — un radar Doppler dont **tout** le traitement est à toi. Et à
λ = 2,85 cm, un cornet de 6–10 cm en tôle (ou carton + aluminium) se
construit à la règle et au cutter.

Surtout, ça se **mesure** — c'est ça qui a de la valeur : cible fixe
(plaque métallique), moteur qui balaie l'angle, amplitude Doppler relevée
point par point → **diagramme de rayonnement avant/après cornet**, tracé
par ton code. Un mini-mémoire d'antenniste, quantifié, sans VNA ni labo.
Variante spectaculaire : parabole de récupération (tête d'antenne satellite,
voire passoire métallique) avec le HB100 au foyer → ~6° de faisceau pour
30 cm de diamètre.

### Le vrai « j'ai construit mon radar » (~150 €, plus tard)

Le **coffee-can radar du MIT** (FMCW 2,4 GHz) : blocs RF connectorisés
SMA (VCO, séparateur, LNA, mixeur) et **deux antennes-boîtes de conserve
construites main**. Version modernisée pour CE projet : remplacer la
carte son du design d'origine par l'ADC du STM32G474 → la mesure de
distance FMCW passe dans ta chaîne Ada. RF fait main + Ada embarqué
prouvé : combinaison rarissime dans un portfolio. À faire quand la
chaîne STM32 tourne, pas avant.

### Grille de décision acheter / fabriquer

- **≥ 24 GHz** : acheter le module ; « fabriquer » = lentille (A121),
  mécanique de balayage, et logiciel ;
- **10 GHz (HB100)** : acheter le module à 3 €, **fabriquer l'antenne
  autour** — le meilleur ratio apprentissage/prix du projet ;
- **2,4 GHz** : fabriquer le radar entier (coffee-can) — le badge ultime.

→ Ajouter un **HB100 (~4 €)** à la commande de la section 1 : c'est le
seul achat qui ouvre un vrai chantier « antenne faite main ».

---

## 4. Architecture cible révisée

```text
ETAGE CAPTEUR (au choix, interchangeable)
  [LD2450 : cibles x,y,v  @ UART]          <- phase 1 : detection toute faite
  [A121   : profil d'echo @ SPI+lib C]     <- phase 2 : distance fine, tourelle
  [BGT60  : IQ brut       @ SPI]           <- phase 3 : DSP maison complet
        |
  STM32G474 - Ada, profil Ravenscar (radar_demo = deja la bonne ossature)
     tache acquisition  --\
     tache scan moteur  ---> objets proteges (prouves SPARK) -> tache fusion/track
     tache telemetrie  <---/
        |  UART/USB : trames binaires (en-tete, compteur, CRC)
  PC : visualisation live + enregistrement (rejeu = les HTML actuels)
```

Le point clé logiciel : ton pipeline a **deux niveaux d'entrée naturels**,
et l'interface abstraite doit refléter ça :

- **niveau balayage** (`Radar_Source` actuel : un `Sweep` par direction) —
  c'est là que se branchent A121 et BGT60, et ton simulateur ;
- **niveau détection** (une `Frame` de positions 3D) — c'est là que se
  branche le LD2450, qui court-circuite `Radar_Detect` puisqu'il détecte
  lui-même. Le pistage, le clutter, l'affichage restent identiques.

Concevoir cette seconde interface (`Detection_Source` ?) est le premier
chantier d'architecture — faisable dès maintenant, en simulé.

---

## 5. Marche à suivre

### Phase A — 0 €, tout de suite (sans matériel)

1. **Horodatage** : ajouter un temps (`dt`) aux mesures et passer les
   vitesses de « mm/tour » à « mm/s ». Une heure maintenant, une refonte
   plus tard si tu attends.
2. **Carte de clutter (MTI)** : c'est LA brique qui unifie tes deux modes —
   « détection de cible en mouvement avec scan de pièce ou non » :
   le mode `map` mémorise l'écho statique par direction (les murs) ; le
   mode `track` supprime tout écho à ±2 cases de cette référence → seuls
   les objets MOBILES deviennent des pistes. Testable en simulation en
   activant murs **et** objets mobiles en même temps (`See_Room => True`
   avec `Initial_World`) : aujourd'hui le tracking se noierait dans les
   murs ; avec la carte de clutter, il voit à travers. C'est le
   fonctionnement réel d'un radar de veille au sol.
3. **CFAR** : remplacer le seuil fixe (100) par un seuil adaptatif
   CA-CFAR (moyenne glissante des cases voisines × facteur) dans
   `Radar_Sweep` — arithmétique entière, prouvable SPARK, très « radar ».
4. **Bruit réaliste** : rapatrier le générateur de bruit de la branche
   `experiment-simulateur` dans la source simulée (puis fermer cette
   branche). CFAR + bruit se valident l'un l'autre.
5. **Dé-risquer la cible** : vérifier dès maintenant qu'un main vide
   compile avec le runtime STM32G474 d'AdaCore (`embedded_stm32g4xx` /
   `light-tasking-stm32g4xx` via Alire). Si ça coince, on le sait avant
   de dépendre du colis.

### Phase B — ≈ 55 €, dès la commande reçue (sans STM32 !)

6. LD2450 branché au PC via USB-UART. Écrire `Radar_Serial_Source` en Ada
   (GNAT fournit `GNAT.Serial_Communications`, ça marche sous Windows) :
   parser les trames binaires du LD2450 — champs 16 bits, signe porté par
   le bit de poids fort (pas du complément à deux !), footer fixe : un
   exercice parfait pour les **clauses de représentation** Ada.
7. Brancher ces détections réelles sur `Radar_Track` → **cibles mobiles
   réelles, pistées par ton code**. Toi qui marches dans la pièce, avec
   ID et vecteur vitesse.
8. **Visualiseur temps réel vrai** : les HTML actuels sont des rejeux.
   Pour du live : mini serveur HTTP en Ada (`GNAT.Sockets`) qui sert la
   page + les frames JSON ; la page se rafraîchit en continu. 100 % Ada,
   pas de dépendance.

### Phase C — le STM32 arrive

9. Blinky Ada, puis **porter `radar_demo` tel quel** sur la carte (runtime
   `light-tasking`) : c'est déjà l'ossature Ravenscar qu'il faut.
10. Déplacer le parsing LD2450 sur le STM32 (driver UART Ada) ; le STM32
    pousse des trames télémétrie (protocole à toi : en-tête, compteur,
    CRC — spécifie-le dans un .md, c'est de la traçabilité gratuite) ;
    le PC ne fait plus qu'afficher.

### Phase D — la mécanique (≈ +15 €)

11. Deux steppers 28BYJ-48 + ULN2003 (ou tourelle pan-tilt SG90) pilotés
    par le STM32 : balayage azimut/élévation réel. Monter d'abord le
    LD2450 dessus (couverture élargie), puis l'A121 (scan de pièce fin →
    ton mode `map` avec de vrais murs).

### Phase E — le radar « brut » (≈ +60–120 €)

12. A121 (binding RSS) ou BGT60TR13C (registres + IQ) : la détection sort
    de TON code — FFT distance sur le G474 (170 MHz + FPU : une FFT 256
    points est confortable), Doppler et CFAR à toi, le simulateur devient
    un banc de validation croisée.

### Phase F — l'avion, sur le papier (0 €)

13. Dossier d'étude « portage aéroporté » : tes deux modes se généralisent
    exactement — surveillance → **GMTI** (cibles mobiles au sol vues du
    ciel), cartographie → **SAR** (imagerie par synthèse d'ouverture).
    Le cœur du dossier : pourquoi ta carte de clutter casse dès que la
    plateforme bouge (le clutter n'est plus à Doppler nul, il s'étale
    proportionnellement à la vitesse et à l'ouverture du faisceau), et
    quelles parades existent (DPCA, STAP) ; bilan de liaison ; choix de
    PRF et ambiguïtés distance/vitesse. Aucun matériel, et c'est un
    document en or pour un entretien défense/aéro.

---

## 6. Risques à garder en tête

- **Runtime G474** : à valider en phase A.5 (avant réception).
- **Lib C fermée d'Acconeer** : le driver A121 sera un binding, pas du
  pur Ada — l'assumer dans le discours.
- **Soudure** : headers à souder sur la plupart des cartes.
- **Alimentation** : tout fonctionne en USB 5 V ; le LD2450 pique des
  pointes de courant — l'alimenter du 5 V (pas du 3,3 V du STM32),
  niveaux UART en 3,3 V (compatibles).
- **Budget total** du chemin complet : ~150–200 €, dans l'enveloppe
  100–300 € du GUIDE_PROJET.
