# Analyse de réalisme — radar_fw face au monde réel

Objectif : mesurer l'écart entre le simulateur actuel et ce que donneront
les essais réels, en s'appuyant sur des projets existants documentés.
Verdict d'ensemble : **l'architecture est juste, le monde simulé est un
conte de fées**. Cibles ponctuelles parfaites, amplitude constante, zéro
bruit, zéro fausse alarme, faisceau crayon idéal : chacune de ces
hypothèses casse en réel. La bonne nouvelle : chacune peut être cassée
*dès maintenant, en simulation*, une par une.

---

## 1. Une cible réelle n'est pas une sphère

- **Cible étendue** : un humain vu par un radar 24/60 GHz, ce sont des
  dizaines de réflecteurs (torse, membres, tête) qui bougent les uns par
  rapport aux autres. Le « centre » mesuré se promène sur le corps
  (± 20–30 cm d'un tour à l'autre) et occupe plusieurs cases de distance
  à la fois.
- **Fluctuation d'amplitude** (modèles de Swerling) : l'écho varie de
  10–20 dB selon l'orientation de la cible. Concrètement : un tour tu la
  vois fort, le tour suivant elle passe sous le seuil. Les **trous de
  détection sont la norme**, pas l'exception.
- **Multitrajet** : sol et murs créent des **cibles fantômes** (écho
  rebondi = fausse cible derrière la vraie), surtout en intérieur.
- **Micro-Doppler** : pour un radar, un **ventilateur est une cible
  mobile** — artefact documenté par les utilisateurs du LD2450 en
  domotique (« fan flicker », parade : filtres de temporisation).
- **Personne immobile ≈ invisible** pour une détection par mouvement /
  carte de clutter : c'est tout le fond de commerce des capteurs de
  « présence » (LD2410) qui détectent la respiration.

### Ce que ça casse dans notre code actuel

| Hypothèse actuelle | Réalité | Conséquence |
| ------------------ | ------- | ----------- |
| Vitesse = différence de positions brutes | jitter ± 20–30 cm par mesure | vitesse inutilisable sans **filtre** (alpha-beta, puis Kalman) |
| `Cluster_Radius` fixe 300 mm | cible étendue + jitter | fragmentation d'une personne en 2–3 pistes, ou fusion de 2 personnes proches |
| Association gloutonne au plus proche | deux personnes qui se croisent | **échanges d'ID** quasi garantis (parade : association globale type hongrois/GNN) |
| Une détection = une piste affichée | dropouts + fantômes fréquents | pistes fantômes qui clignotent (parade : cycle de vie **M-sur-N** : piste « tentative » non affichée avant confirmation) |
| Seuil fixe (100) | bruit variable selon distance/scène | avalanche de fausses alarmes OU cibles faibles ratées (parade : **CFAR**) |
| Clutter appris une fois pour toutes | rideaux, ventilateurs, meubles déplacés | carte de clutter à **oubli lent** (moyenne exponentielle) |

---

## 2. Le capteur réel ne balaie pas comme le simulateur

Le simulateur modélise un faisceau crayon de 3° balayé mécaniquement.
**Aucun capteur de la liste d'achats ne fait ça nativement** :

- **HLK-LD2450** : pas de balayage du tout — champ large ± 60°, angle
  estimé par différence de phase entre antennes RX, **10 Hz**, 3 cibles
  max, en **2D** (pas d'élévation), et il sort des cibles **déjà
  pistées**, avec ses propres artefacts (fantômes, accrochages, latence
  de décrochage) que les intégrations domotiques compensent par zones et
  temporisations.
- **Acconeer A121** : le profil d'écho par cases de distance correspond
  bien à notre type `Sweep` (bonne nouvelle), mais le faisceau natif est
  **large (~50–65° selon le plan)** : sur tourelle **sans lentille, le
  mode cartographie serait une bouillie angulaire**. La lentille
  (kit Acconeer HBL/FZP, ou imprimée) ramène à ~10° : elle fait partie
  du design, pas des accessoires. S'ajoutent fuite d'antenne en champ
  proche, lobes secondaires, bruit.
- **BGT60TR13C** : IQ brut, angle par 3 RX — précision de quelques
  degrés, pas 3.
- **Cadence** : le scan mécanique réel (servo + temps d'intégration)
  prendra des **minutes** pour une pièce, pas 800 ms. Acceptable pour le
  mode « analyse », mais l'affichage devra être **progressif** (le nuage
  se remplit sous tes yeux), pas « tout à la fin ».

---

## 3. Ce que montrent les projets existants

- **LD2450 + ESPHome/Home Assistant** (composants communautaires,
  zones polygonales, `off_delay`) : la communauté documente précisément
  les artefacts réels — ventilateurs, instabilités d'alimentation en
  3,3 V, rafraîchissement 10 Hz — et les parades logicielles simples.
  C'est un aperçu fidèle de ce que notre pipeline recevra.
- **Henrik Forstén (hforsten.com)** : LA référence du radar FMCW
  amateur — 6 GHz, PCB maison (~350 composants), détection d'un humain
  à 100 m, puis **SAR embarqué sur drone** avec autofocus. Deux leçons :
  le sommet du réalisable en amateur est très haut, et l'essentiel du
  travail est dans le **traitement et la calibration**, pas dans le RF —
  exactement le pari de ce projet.
- **Acconeer** documente la conception de lentilles comme une étape
  normale d'intégration (docs « Lens design »), confirmant le point
  ci-dessus pour le mode cartographie.

---

## 4. Plan de mise à niveau du réalisme (tout en simulation, par priorité)

1. **Cibles étendues + Swerling** — ✅ **FAIT** : chaque objet est simulé
   par 4 réflecteurs (± 150 mm), amplitude retirée au sort à chaque tour
   (graine fixe : reproductible), 15 % d'extinction par réflecteur et
   10 % d'évanouissement profond par objet. `Cluster_Radius` est passé à
   600 mm en conséquence (cible étendue + quantification d'élévation :
   ~520 mm d'écart possible entre échos du même objet à 3 m) — revers
   assumé : deux objets réels à moins de 600 mm fusionnent, c'est la
   résolution réelle du capteur simulé.
2. **Bruit de fond + CFAR** — ✅ **FAIT** : bruit aléatoire dans chaque
   case ; seuil CA-CFAR (fenêtre 8, garde 2, facteur 4) **prouvé SPARK**
   (`Detect_Adaptive` : « aucune cible sous son seuil local », 83 checks
   au total) ; c'est lui que tout le pipeline utilise.
3. **Cycle de vie M-sur-N** — ✅ **FAIT** : piste tentative invisible
   avant 3 détections, tentative jamais revue morte en 2 tours ;
   l'affichage (live et rejeu) ne montre que les pistes confirmées, le
   coasting est marqué (gris + `*`).
4. **Filtre alpha-beta** — ✅ **FAIT** : prédiction + coasting (une piste
   non revue roule sur son erre) et correction alpha (0,5) / beta (0,3) ;
   la vitesse filtrée converge (testé : 100 mm/tour ± 20 en 10 tours).
5. **Fantômes multitrajet** — ✅ **FAIT** : 5 % de probabilité d'écho
   miroir derrière le mur ; c'est M-sur-N qui les étouffe (testé).
6. **Clutter adaptatif** — ✅ **FAIT** : compteurs de confiance 2 bits,
   confirmation à 2 observations, apprentissage de fond (1 tour sur 4)
   et oubli lent (`Age` tous les 8 tours) : le décor qui apparaît est
   appris, celui qui disparaît est oublié, un mobile qui passe
   n'empoisonne pas la carte — et un mobile qui se gare y fond
   (réalisme assumé).
   *Limite connue observée : la fragmentation d'une cible étendue peut
   confirmer une piste « ombre » (3 pistes pour 2 objets par moments) —
   parade au chantier suivant : association globale + fusion de pistes
   (voir `ARCHITECTURE_SYSTEME.md` §5).*
7. **Émulateur LD2450** : une source de niveau détection (x, y, vitesse,
   10 Hz, 3 cibles max, jitter réaliste, dropouts, fantômes) — le
   pipeline PC sera prêt **avant** l'arrivée du module, qui remplacera
   l'émulateur trame pour trame.
8. **Mode map progressif** — ✅ **FAIT** : mode `scan` — le serveur HTTP
   (extrait en paquet partagé `Radar_Http`) cadence le balayage une
   colonne d'azimut à la fois et la page se remplit au fil de l'eau
   (progression, compteur de points) ; scan terminé, le nuage reste
   servi et explorable (déplacement, clic-détails). Sur le vrai
   matériel, seule la cadence et la source changeront.

## 5. Ce qui est déjà réaliste (à garder et à revendiquer)

- Le **MTI par carte de clutter** est le vrai principe des radars de
  veille au sol — et l'épisode « cible collée au mur invisible »
  rencontré pendant le développement est un comportement authentique,
  documenté dans l'historique Git.
- La **quantification en distance** (cases de 78 mm) est honnête : le
  nuage « en bandes » du mode map est ce qu'un vrai capteur donne.
- L'architecture à **deux niveaux d'entrée** (balayage brut / détections
  toutes faites) correspond exactement au matériel visé (A121/BGT60 au
  niveau balayage, LD2450 au niveau détection).
- « Pas de FFT lourde sur le MCU, le PC fait le rendu » : c'est aussi le
  partage des rôles des projets amateurs aboutis (Forstén).
