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
- **Mouvement tangentiel ≈ invisible aussi.** Un capteur Doppler mesure une
  vitesse **radiale** : la composante du déplacement le long de la ligne de
  visée. Une cible qui décrit un cercle autour du capteur, à distance
  constante, produit un signal quasi nul — elle disparaît alors même qu'elle
  bouge franchement. C'est une limite de physique, pas de traitement, et les
  intégrateurs de ces modules la rapportent explicitement.

  *Ce qu'une couronne de capteurs ne corrige pas :* la vitesse radiale se
  mesure le long de la ligne **capteur → cible**, et non selon l'axe vers
  lequel pointe le capteur. Dans une couronne, les capteurs sont à quelques
  centimètres les uns des autres : vus d'une cible à 3 m, ils partagent
  pratiquement la même ligne de visée. Une cible qui tourne autour du boîtier
  reste donc tangentielle **pour tous les capteurs à la fois** — l'orientation
  de chacun change son gain d'antenne, pas le Doppler qu'il mesure. La
  couronne apporte la couverture sur 360°, pas la diversité de point de vue.

  Les parades réelles :

  - **par le pistage** : une piste confirmée survit 2,5 s sans détection
    (coasting, voir §1.4 point 4), ce qui franchit les phases tangentielles,
    le plus souvent brèves pour une personne qui marche ;
  - **par la géométrie** : un second capteur **éloigné de plusieurs mètres**
    du premier. Une trajectoire tangentielle pour l'un devient alors radiale
    pour l'autre, sauf quand la cible est alignée avec les deux capteurs.
    Cela suppose de connaître la position de chaque capteur dans la pièce, ce
    qui sort de l'architecture à boîtier unique décrite ici.

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

### 1.2 Les faisceaux et les données ne sont pas interchangeables

Le simulateur ne reproduit pas encore un diagramme d'antenne : son test accepte
une cible à moins de 3° en azimut et 5° en élévation. Cela représente une fenêtre
rectangulaire à seuil dur de 6° × 10° au total, sans lobes ni pondération de
gain. La différence est importante : une largeur de faisceau constructeur est
habituellement mesurée à un niveau donné, elle ne définit pas une frontière
angulaire nette.

- **HLK-LD2450** : ce n'est pas un scanner d'angle. Hi-Link décrit un radar FMCW
  24 GHz à une antenne TX et deux RX, avec un traitement intégré qui envoie des
  données de détection par liaison série. La fiche annonce une portée maximale
  de 6 m, des angles de ±60° en azimut et ±35° en inclinaison, et annonce
  10 trames/s. Les coordonnées exposées sont x/y et la vitesse : le champ de
  vision vertical n'est donc pas une mesure d'altitude. Cette cadence nominale
  doit être chronométrée avec le firmware et le transport choisis.
  Les sorties sont des cibles déjà calculées ; le module ne fournit pas au
  programme Ada le profil brut de 256 cases attendu par `Radar_Source`.
  [Fiche officielle Hi-Link du LD2450](https://www.hlktech.com/en/Goods-352.html).
- **Acconeer A121** : c'est un radar à impulsions cohérentes (PCR) à 60,5 GHz,
  pas un FMCW. Son unique canal TX/RX mesure une distance et une phase, pas un
  angle ; obtenir la direction demande une mécanique d'azimut/élévation ou un
  autre capteur angulaire. Le service Sparse IQ fournit des trames de balayages
  et des échantillons de distance complexes. La plage, le profil d'impulsion,
  l'espacement des échantillons, le nombre de balayages par trame et le réglage
  HWAAS font partie de la configuration. Une frame peut regrouper plusieurs
  balayages ; Acconeer indique des cadences typiques de 1 à 100 frames/s selon
  les réglages, limitées par le nombre et la cadence des balayages. Cela ne
  garantit pas cette fréquence dans le montage visé. [Frames, sweeps et
  cadence A121](https://docs.acconeer.com/en/latest/radar_data_and_control/a121/sweeps_and_frames.html).
  La capacité générale annoncée jusqu'à
  20 m ne signifie pas qu'une configuration XM125 donnée couvre cette plage :
  le PRF fixe aussi la distance maximale mesurable et non ambiguë. Le guide de
  configuration recommande de limiter la plage au besoin et de choisir le pas
  selon la trueness, le profil et les angles morts. Un pas d'échantillonnage
  réglable jusqu'à environ 2,5 mm ne signifie pas que deux cibles séparées de
  2,5 mm sont résolues : la résolution radiale dépend du profil et se mesure
  séparément. [A121](https://developer.acconeer.com/a121/),
  [principe PCR et mesure sans angle](https://docs.acconeer.com/en/latest/pcr_tech/overview.html),
  [plage, pas et limites PRF](https://docs.acconeer.com/en/latest/radar_data_and_control/a121/measurement_range.html),
  [résolution radiale](https://docs.acconeer.com/en/latest/figure_of_merits/a121.html),
  [configuration A121](https://docs.acconeer.com/en/latest/radar_data_and_control/a121/how_to_configure.html).
- **XM125** : c'est un module avec son propre microcontrôleur ; il peut exécuter
  une application embarquée ou communiquer avec un hôte par un protocole de
  registres. La forme des données reçues dépend donc du logiciel chargé. Ne pas
  supposer qu'un XM125 sous son application I²C livre automatiquement les
  profils IQ nécessaires à la cartographie. [Documentation XM125](https://developer.acconeer.com/home/a121-docs-software/xm125-xe125/).
- **La géométrie angulaire limite la carte.** Pour une largeur mesurée β,
  l'empreinte transversale vaut environ `2 R tan(β/2)`. Dans une configuration
  Acconeer XE121 + LH120 + lentille hyperbolique à D1, le guide donne 16,8° à
  mi-puissance dans le plan H ; à 3 m, cela correspond à environ 0,89 m
  d'empreinte. Ce chiffre illustre une configuration précise, il ne caractérise
  pas le XM125 prévu. Une cible isolée peut être localisée plus finement que
  cette empreinte ; deux objets proches ne sont pas pour autant séparables.
  Un couvercle placé devant le capteur peut aussi modifier fortement le
  diagramme. Pour l'A121, Acconeer recommande d'optimiser l'épaisseur du
  radome diélectrique selon sa permittivité (cas idéal : multiple de λ/2 dans
  le matériau) et sa distance au capteur ; une lentille peut remplacer un
  radome séparé. Mesurer l'empilement complet. [Radome et mécanique A121](https://docs.acconeer.com/en/latest/hw_integration/a121/radome_and_mechanical_design.html).
- **Pas angulaire et durée.** Le pas de balayage se choisit après mesure du
  diagramme et de la précision mécanique, selon la résolution spatiale utile.
  Un pas beaucoup plus fin augmente les données et le temps sans créer
  automatiquement une résolution équivalente. Pour un balayage mécanique,
  ajouter temps d'acquisition, déplacement, stabilisation et retour sans
  mesure ; ne déduire aucune cadence du simulateur.

### 1.3 Ce que montrent les projets existants

- **LD2450 + ESPHome / Home Assistant** (composants communautaires, zones
  polygonales, `off_delay`) : les intégrations rapportent des artefacts réels
  — ventilateurs et instabilités d'alimentation — à vérifier sur l'assemblage.
  La fiche Hi-Link annonce 10 trames/s ; c'est une cadence nominale, pas une
  mesure de latence de bout en bout.
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

1. **Cibles étendues et fading** — **modèle simplifié dans le simulateur.**
   Chaque objet est simulé par 4 réflecteurs (± 150 mm), dont le niveau est
   tiré uniformément à chaque tour (graine fixe, donc reproductible), avec 15 %
   d'extinction par réflecteur et 10 % d'évanouissement profond par objet.
   Cela imite des variations d'écho, mais ce n'est pas une loi statistique
   Swerling calibrée : les niveaux sont combinés par maximum, sans somme
   cohérente de phase. `Cluster_Radius` est porté à 600 mm en conséquence :
   une cible étendue vue à travers une
   quantification d'élévation peut écarter deux échos du même objet
   d'environ 520 mm à 3 m. Revers assumé : deux objets réels à moins de
   600 mm fusionnent ; ce rayon est un réglage de regroupement simulé, pas une
   résolution physique mesurée.
2. **Bruit de fond et CFAR** — **mis en œuvre.** Bruit aléatoire dans chaque
   case et seuil CA-CFAR (fenêtre 8, garde 2, facteur 4). SPARK prouve ici que
   toute case rapportée dépasse le seuil calculé par le code ; cela ne prouve
   ni un taux de fausse alarme physique, ni qu'une case au-dessus du seuil
   correspond à une cible réelle. Le bruit simulé et les amplitudes doivent
   être recalés sur les données du profil choisi.
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

   Le délai de survie dépend de ce que l'absence d'écho **prouve**. Dans le
   champ du capteur, une piste confirmée survit 2,5 s : au-delà, le silence
   signifie probablement que l'objet est parti. Dans la **zone aveugle**, le
   silence ne prouve rien : le capteur ne pouvait pas voir. Chaque frame
   porte donc la portée minimale de son capteur (`Frame.Min_Range`, 625 mm
   pour la chaîne à profils, dérivée de `Blind_Bins` dans le cœur prouvé),
   et une piste dont la position prédite s'y trouve survit 10 s. La zone est
   élargie de la demi-taille d'une cible (200 mm) : l'écho d'une cible
   étendue s'effondre dès que son **bord** y entre, avant son centre. Mesure
   en veille simulée sur 254 tours : les deux traversées de la zone aveugle
   changeaient l'identifiant de l'objet, elles le conservent désormais
   (6 changements d'identifiant → 4). La portée minimale voyage avec la
   frame, et non comme une constante du pistage, parce qu'elle est propre à
   chaque capteur. Les quatre changements restants ont d'autres causes : deux
   croisements d'objets à moins de 600 mm (`Cluster_Radius`, point 1), un
   objet au-dessus du faisceau près du radar, dont l'élévation mesurée
   dérive, et une perte encore inexpliquée.
5. **Fantômes multitrajet** — **mis en œuvre.** 5 % de probabilité d'écho
   miroir derrière le mur ; c'est la règle M-sur-N qui les étouffe, ce que
   vérifie un test.
6. **Clutter adaptatif** — **mis en œuvre.** Compteurs de confiance sur
   2 bits, confirmation à 2 observations, calibration sur 8 tours,
   apprentissage de fond (1 tour sur 4) et oubli lent (`Age` tous les
   32 tours) : le décor qui apparaît est appris, celui qui disparaît est
   oublié, et un mobile qui ne fait que passer n'empoisonne pas la carte —
   tandis qu'un mobile qui se gare y fond, réalisme assumé. Limite connue du
   mécanisme : la fragmentation d'une cible étendue peut confirmer une piste
   « ombre » ; ce sont l'association globale et la fusion de pistes, dans
   `Radar_Track`, qui l'écartent.

   *Le réglage de l'oubli se calcule.* Une case détectée avec la
   probabilité p gagne en moyenne `p × N / 4` crans par période d'oubli de
   N tours, et en perd un : elle n'est apprise que si `p > 4 / N`. Les murs
   vus de biais (point 9) renvoient un écho proche du seuil, détecté par
   intermittence. Avec N = 8, seules les cases vues plus d'une fois sur deux
   étaient apprises, et le mode `live` affichait 8 à 11 pistes fantômes sur
   les murs. Avec N = 32, le seuil tombe à 12,5 % : il reste 0 à 1 fantôme
   bref (mesuré sur 120 s). En contrepartie, un meuble retiré met environ
   30 s à sortir de la carte. Une carte qui apprendrait le **niveau** d'écho
   plutôt que le nombre de détections (carte de clutter de type MTD)
   supprimerait la cause, mais au prix d'une mémoire que la cible embarquée
   ne peut pas offrir sans réduire la plage utile.
7. **Émulateur LD2450** — **non implémenté.** Il s'agirait d'une source de
   niveau détection (x, y, vitesse, cadence et nombre de cibles à confirmer sur
   la version de trame utilisée, jitter, dropouts, fantômes), afin que le
   pipeline PC soit prêt avant l'arrivée du module. Il remplacerait
   l'émulateur trame pour trame, sous réserve de la géométrie par capteur.
8. **Cartographie progressive** — **mise en œuvre en deux résolutions.** Le
   mode `scan` commence par une couverture globale de 60 × 8 directions, puis
   ajoute une passe détaillée de 180 × 24. Dans la démo, une colonne prend
   respectivement 25 ms et 60 ms : environ 1,5 s avant la première carte
   grossière, puis 10,8 s pour compléter le détail. Les points sont envoyés
   par lots et ajoutés à une géométrie GPU persistante ; le navigateur ne
   retélécharge ni ne reconstruit le nuage complet à chaque sondage. Ces durées
   règlent l'animation de la simulation et ne prédisent pas le moteur ni le
   temps d'intégration RF. Le détail couvre encore tout le champ ; le
   raffinement sélectif par secteur reste à faire.
9. **Murs et coins** — **modèle simplifié ajouté au simulateur.** L'écho d'un
   mur dépend maintenant de l'angle d'incidence et les coins verticaux peuvent
   produire un écho fort. Les niveaux diffus/spéculaire et la géométrie des
   coins restent des hypothèses, pas une loi de rétrodiffusion validée. Les
   réflexions sur sol/plafond, les trajets cohérents et l'interférence entre
   radars ne sont pas simulés ; le CFAR ne représente donc pas encore un
   comportement matériel mesuré.

### 1.5 Ce qui est déjà réaliste (à conserver)

- Le **MTI par carte de clutter** est le vrai principe des radars de veille au
  sol — et l'épisode « cible collée au mur invisible » rencontré pendant le
  développement est un comportement authentique, documenté dans l'historique
  Git.
- La **quantification en distance** de la simulation vaut 78,125 mm par case
  sur une plage théorique de 20 m. Ce pas logiciel n'est ni la résolution
  physique, ni l'espacement d'échantillons garanti par l'A121.
- Les deux familles d'entrée sont séparées : `Radar_Source` transporte les
  profils ; `Radar_Target_Source` transporte des frames déjà calculées en
  3D. Le LD2450 ne fournit qu'une position planaire dans le contrat étudié :
  il lui manque encore un rapport 2D et un pistage 2D explicites.
- « Pas de FFT lourde sur le MCU, le PC fait le rendu » : c'est aussi le
  partage des rôles des projets amateurs aboutis (Forstén).

### 1.6 Propagation en intérieur : réflexion et diffusion dépendent des surfaces

La réflexion d'une onde millimétrique dépend de la permittivité et de la
conductivité du matériau, de son épaisseur, de la polarisation et de l'angle
d'incidence. La rugosité par rapport à la longueur d'onde partage
approximativement les surfaces lisses (composante spéculaire dominante) et
rugueuses (diffusion plus importante) ; le critère de Rayleigh est un repère,
pas une séparation binaire entre « miroir » et « diffuseur ». À 24 GHz,
λ ≈ 12,5 mm ; à 60,5 GHz, λ ≈ 5 mm. Les propriétés électriques des matériaux
de construction et leurs coefficients de réflexion/transmission sont traités
par la [recommandation ITU-R P.2040](https://www.itu.int/rec/R-REC-P.2040/en).

Un mur, une porte ou une vitre ne peut donc pas être qualifié de miroir sur le
seul fait qu'il est peint ou lisse à l'œil. Les mesures publiées à 60 GHz
montrent que la rugosité change la part spéculaire et diffusée. Les coins
peuvent donner des retours forts par réflexions multiples, mais leur amplitude
dépend de leur matériau, de leur forme et de leur orientation. Des trajets
indirects peuvent produire des images derrière les parois ; un point estimé
sous le plancher est suspect, mais pas une preuve universelle de fantôme sans
connaître le repère et la géométrie.

Le simulateur emploie désormais une loi angulaire simple et des échos de coin.
Son bruit uniforme, ses amplitudes de cible indépendantes de la portée, la
combinaison par maximum, le mur rectangulaire idéal et l'absence de phase, de
Doppler RF et de trajets multiples cohérents en font un scénario de
développement, pas une validation de propagation. Il faut relever la réponse
de l'A121 face à des matériaux connus et à plusieurs angles avant d'en tirer
une carte attendue.

### 1.7 Vérification physique et compatibilité des interfaces

La revue des fiches, des contrats et du code établit un écart bloquant avant
tout branchement direct :

| Élément | Ce que le système fournit ou suppose | Ce qu'il faut pour le capteur réel |
| ------- | ------------------------------------ | ---------------------------------- |
| `Radar_Sweep.Sweep` | 256 valeurs d'amplitude 0..4095, plage linéaire fixe de 20 m | A121 : profil et plage sélectionnés, pas de distance, points IQ complexes ; conversion et calibration explicites |
| `Radar_Source.Measurement` | azimut, élévation, heure, un seul `Sweep` ; pas d'identifiant ni de pose capteur | capteur, horodatage de capture et extrinsèques par module ; angle mesuré par index/encodeur pour le scanner |
| LD2450 | format de trame codé (`Radar_Ld2450`) et contrat 2D (`Radar_Planar_Source`) ; pas encore de décodeur série | décodage série vers des rapports 2D horodatés ; ne pas fabriquer un `Sweep` ni une altitude |
| A121/XM125 | aucun pilote matériel dans le dépôt | choisir le firmware XM125 ou le chemin A121 qui expose les données requises, puis mapper plage/étape/IQ/calibration |

Le principe de `Radar_Source` reste central : développer et éprouver le
traitement de profils sur simulation, puis remplacer le producteur A121 sans
réécrire le pipeline. `Radar_Target_Source` est la frontière séparée pour
les rapports déjà calculés, à condition qu'ils soient honnêtement
représentables en 3D. Le LD2450 reste une source planaire : son type
d'observation 2D existe (`Radar_Planar_Source`), mais avant de l'utiliser pour
le suivi rapide, il faut encore un filtre de piste 2D. Poser `z = 0` dans
`Frame` ferait passer une convention
de dessin pour une mesure d'altitude. Chaque flux matériel devra avoir un
équivalent simulé avec le même sens physique ; la fusion se fera ensuite dans
un repère commun, après calibration des poses et des horloges.

La transformation 3D actuelle suppose le radar à l'origine. Une couronne de
LD2450 exige, pour chaque module, une rotation et une translation vers le repère
global ; la fusion demande aussi des horloges comparables. Le timestamp unique
d'une `Frame` ne suffit pas à corriger le déplacement d'une cible pendant un
scan mécanique long. Ces éléments doivent entrer dans les contrats Ada, sans
logique de décision dans la page HTML.

La base de temps actuelle est un entier de 31 bits en millisecondes
(`0 .. 2**31 - 1`), soit environ 24,9 jours. La source simulée l'incrémente
sans retour circulaire ; le pistage suppose des timestamps strictement
croissants et calcule zéro durée quand un timestamp régresse. Avant un usage
continu, il faut définir le calcul wrap-safe des écarts ou étendre l'époque,
ainsi que le traitement d'un redémarrage et de trames hors ordre. Pour plusieurs
capteurs, leurs horloges doivent d'abord être ramenées sur une base commune.

**Contrat de temps recommandé avant le multi-capteur :** séparer le temps
interne du champ `TIMESTAMP` v1. Le pipeline et `Radar_Track` devraient porter
un temps monotone interne sur 64 bits ; le champ 32 bits du protocole reste une
représentation de transport, avec son origine et son comportement au rebouclage
définis séparément. La source simulée garde son horloge virtuelle déterministe,
ce qui préserve le rejeu identique. Chaque adaptateur réel étend son compteur de
capture et le ramène à une époque commune. Une trame ancienne ou issue d'un
redémarrage doit être rejetée ou provoquer une remise à zéro explicite du
pistage ; la convertir silencieusement en `dt = 0` masque la rupture temporelle.
Cette recommandation n'est pas encore implémentée.

**Cadence de la tourelle à vérifier avant de figer le rapport.** Le croquis
actuel place le rayon moyen de couronne à `80/2 + 4/2 = 42 mm`, le rayon dessiné
du pignon à `4 mm` et l'axe moteur à `46 mm` : ces trois valeurs décrivent un
engrènement géométrique cohérent dans le modèle, mais pas une denture fabriquée.
Le rapport extérieur représenté est `42/4 = 10,5:1`. Combiné au réducteur
nominal `64:1` et aux `4096` demi-pas/tour annoncés pour le 28BYJ-48 5 V, cela
donne `672:1` et environ `43 008` demi-pas par tour de tourelle. À une cadence
commandée de 100 demi-pas/s, un tour prendrait environ **430 s** ; le retour
complet à l'index à la même vitesse porterait le mouvement seul à environ
**14 min 20 s**, avant les acquisitions et les accélérations. Sans l'étage
extérieur, l'estimation serait 41 s par tour, mais avec moins de couple et une
granularité angulaire différente. C'est un compromis à trancher à partir du
temps de cycle acceptable, de l'inertie, du frottement et du couple requis ; le
nombre de 48 dents visibles dans les maquettes est un motif graphique, pas un
nombre de dents choisi. Les valeurs du 28BYJ-48 sont celles d'une fiche 5 V
particulière, pas une garantie pour tout moteur vendu sous ce nom. [Fiche
28BYJ-48 5 V](https://www.mouser.com/datasheet/2/758/stepd-01-data-sheet-1143075.pdf).

Le moteur reste en boucle ouverte : l'index corrige l'origine après le retour,
mais ne révèle pas un pas perdu au milieu du balayage. Garder un seul sens de
mesure puis revenir sans mesurer limite l'effet du jeu, déjà présent dans la
conception. Avant d'augmenter la réduction, mesurer sur le moteur réel les
demi-pas par tour, le jeu, les pas perdus et le temps d'un cycle complet. Le
rapport de couple idéal ne doit pas être déduit du seul chiffre de couple de la
fiche sans savoir à quel arbre il se rapporte ni tenir compte des pertes.

Le choix de transmission reste ouvert. Une couronne dentée donne un entraînement
positif et compact sans tendre de courroie, mais demande de fixer le module, le
nombre de dents, le jeu et la précision d'impression. Une courroie crantée rend
le rapport plus facile à changer et pardonne un léger défaut d'entraxe ; elle
ajoute tension, support de galet et élasticité. Entraîner directement le plateau
retire la réduction extérieure et accélère le balayage, mais demande davantage
de couple au moteur et augmente l'angle par pas. Un moteur plus rapide avec
encodeur détecterait les pas perdus pendant le scan, au prix du volume, du
driver et du logiciel de retour. Le palier indépendant, l'axe central ouvert,
le moteur fixe et l'index restent de bons invariants : ils séparent charge,
transmission, câblage et mesure. Le rapport et le type d'entraînement ne peuvent
être choisis sérieusement qu'après avoir posé le temps de scan accepté, la
masse/inertie du plateau et l'erreur angulaire tolérée.

**Choix retenu : rotation continue dans un seul sens.** Le temps de scan est
désormais posé : un plan à 360° en environ 2 s, un volume de six rangées en
environ 12 s, sans arrêt ni inversion de la tête. Il en découle :

- **un moteur pas-à-pas de type NEMA 17** avec un driver à micropas
  interpolés (TMC2209), par **courroie crantée de rapport 3:1**. Le moteur
  reste en périphérie et l'axe central libre. À 0,5 tr/s au plateau, le
  moteur tourne à 1,5 tr/s, loin de ses limites ;
- **un collecteur tournant** dans le passage central, à la place de la boucle
  de câble. Il permet une rotation illimitée. Le module XM125 communique par
  UART ou I²C, des liaisons lentes qui traversent un collecteur sans
  difficulté ;
- **un recalage à chaque tour** : l'index est franchi à chaque révolution, si
  bien qu'un pas perdu ne se propage jamais au-delà d'un tour ;
- **plus de jeu à l'inversion** : en tournant toujours dans le même sens, la
  transmission reste appuyée du même côté ;
- **une acquisition au vol** : chaque profil est horodaté, et l'angle est
  interpolé à l'instant de la trame. Le faisceau défile alors de 180°/s :
  une trame doit durer moins d'environ 12 ms pour que l'étalement reste sous
  le quart d'un faisceau de 9°. C'est à vérifier sur le module réel.

La cadence est bornée par le lien du capteur, pas par le moteur : un profil
tous les 3° représente 60 profils/s, soit quelques dizaines de ko/s selon la
plage et le pas configurés. Les mesures du montage (pas par tour, répétabilité
de l'index, bruit du collecteur sur la liaison série) restent à faire.

Le bloc ULN2003 de `30 x 22 mm` dans la maquette est lui aussi une enveloppe à
mesurer avec les borniers et les câbles. La fiche du 28BYJ-48 donne `5 V` et
`50 Ω` par phase : environ `100 mA` par phase par simple calcul résistif avant
la chute du driver, avec deux phases parfois alimentées ensemble. Prévoir la
branche moteur et son retour de masse selon la mesure réelle ; le calibre
`500 mA` d'une sortie ULN2003 ne dimensionne pas à lui seul la puissance
thermique lorsque plusieurs voies commutent. [Fiche ULN2003A de TI](https://www.ti.com/lit/ds/symlink/uln2003a.pdf).

La maquette actuelle représente cinq LD2450 fonctionnant en FMCW dans la même
bande 24 GHz ; quatre reste l'option plus légère à caractériser avant de figer
le nombre. La documentation de recherche sur les radars FMCW montre que les
paramètres de chirp influent sur l'interférence entre radars ; le comportement
des LD2450 côte à côte reste à mesurer, car Hi-Link ne publie pas ces
paramètres sur sa fiche. Quatre modules espacés de 90° donneraient 30° de
recouvrement géométrique théorique avec des secteurs annoncés de ±60° ; cinq à
72° en donnent 48°. Quatre réduisent la consommation, les câbles et le nombre
d'émetteurs, mais offrent moins de marge angulaire. Ce calcul ne décrit pas la
sensibilité réelle aux bords du faisceau. [Étude d'interférence FMCW](https://doi.org/10.1049/joe.2019.0167).

Le nombre de capteurs a aussi une borne électronique : le STM32G474 dispose de
USART1 à USART3, UART4 et UART5, plus LPUART1. Dans le routage candidat, LPUART1
sert au pont ESP32 et les cinq autres voies peuvent recevoir chacune un LD2450.
Quatre radars laissent donc une voie UART pour l'A121 si son firmware utilise
ce transport ; cinq consomment les cinq voies capteur. Une sixième entrée radar
exigerait un concentrateur ou une autre architecture. Ce décompte porte sur les
périphériques du microcontrôleur, pas sur les broches effectivement exposées :
leur multiplexage et leur présence sur la carte WeAct restent à vérifier.
[Fiche STM32G474](https://www.st.com/resource/en/datasheet/stm32g474qb.pdf).

Le diagnostic physique reste donc **analytique**, faute de modules montés et
de mesures RF. Les essais de validation sont : cartographier portée/angle d'un
LD2450 seul puis en groupe ; comparer détections manquées et fausses avec un,
quatre puis cinq émetteurs actifs ; mesurer le motif A121 avec la lentille,
coque et support finaux ; refaire les acquisitions moteur arrêté et en
mouvement ; puis calibrer les poses et le biais d'angle sur des cibles aux
positions mesurées. La transmission mécanique et le routage moteur restent
des hypothèses tant que ces essais ne sont pas faits.

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
       [azimut : rotation continue, collecteur, index + elevation]

Ce schéma décrit la **première phase** : un capteur unique, pour valider la
chaîne. La cible est une **couronne** de capteurs fixes orientés dans des
directions différentes (voir §1.1) plus un capteur de balayage sur tourelle ;
le microcontrôleur reste le même, seul le nombre de liaisons série change.

La décomposition en tâches visée sur la carte (le motif Ravenscar déjà
démontré par `radar_demo`, transposé au matériel) :

                       +-------------------------+
    [Capteur] <-bus--> |  tache acquisition      |
      (UART, I2C       |                         |
       ou SPI)         |                         |
    [Moteurs]  <-GPIO- |  tache moteur / scan    | --> objet protege
                       |                         |     (tampon, prouve)
    [PC] <-UART/WiFi-- |  tache telemetrie       |
                       +-------------------------+
                          STM32G474 - Ada bare-metal
                              profil Ravenscar

Le moteur d'azimut n'a pas d'encodeur : un capteur d'index fixe donne l'origine,
puis le contrôleur compte les pas. La tête tourne en continu, toujours dans le
même sens (voir le choix de transmission en §1.7). L'index, franchi à chaque
révolution, recale donc le compte à chaque tour : un pas perdu n'est pas
détecté sur-le-champ, mais il ne survit pas au tour suivant. Un collecteur
tournant relie la tête au reste du montage.

Phase matérielle suivante (XM125/A121) : un service configuré peut exposer des
profils Sparse IQ via l'Exploration Server ; les registres I²C peuvent exposer
des résultats de détection selon le micrologiciel. Aucun de ces chemins ne doit
être assimilé d'avance au `Sweep` fixe du simulateur. Choisir d'abord le
micrologiciel, la plage, le pas, le format complexe et le transport ; le SPI
concerne le pilotage direct de la puce A121 ou d'autres capteurs comme le
BGT60. CFAR, clutter et pistage ne peuvent rester côté carte qu'après avoir
défini et calibré la conversion des données reçues.

Répartition des rôles :

- Le **STM32 fait le temps réel et le formatage des données, en Ada** — c'est
  la part embarquée du traitement. Pas de FFT lourde sur le MCU.
- Le **PC** fait le traitement lourd et le rendu 3D.
- Le **driver XM125 est écrit en Ada** pour le lien configuré (UART ou I²C).
  La bibliothèque RSS fermée ne s'intègre au STM32 que si l'on abandonne le
  module et pilote directement la puce A121 ; ce choix demanderait alors un
  binding Ada → C (`pragma Import`).

### 2.2 Ce que mesurent les capteurs visés

Le chemin RF et la sortie logicielle dépendent du capteur ; il n'existe pas un
format de mesure commun implicite :

1. Le **LD2450** émet en FMCW autour de 24 GHz et possède deux voies de
   réception. Son traitement embarqué produit des détections de cible et les
   transmet en série. Le programme hôte ne reçoit pas son profil RF brut.
2. L'**A121** fonctionne en radar à impulsions cohérentes (PCR) autour de
   60,5 GHz. Le service Sparse IQ peut fournir des échantillons complexes par
   distance, selon le profil et la configuration. Une voie TX/RX ne donne pas
   à elle seule un angle d'arrivée ; la tourelle ou un autre instrument doit
   fournir la direction.
3. La scène renvoie une combinaison de réflexions, transmissions et diffusion.
   Leur importance dépend du matériau, de l'épaisseur, de l'humidité, de la
   rugosité à l'échelle de la longueur d'onde, de la polarisation et de
   l'incidence. Une cloison ne peut pas être déclarée opaque ou transparente
   sur la seule fréquence ; voir §1.6 et [ITU-R P.2040](https://www.itu.int/rec/R-REC-P.2040/en).
4. Chaque module transforme le signal selon son propre traitement puis expose
   ses données par une interface définie par le fabricant. Le firmware doit
   respecter cette représentation au lieu de fabriquer un profil commun qui
   n'est pas fourni par le capteur.

### 2.3 Balayage mécanique et résolution angulaire

La tourelle prévue **déplace physiquement un capteur** et associe chaque
mesure à une direction et une heure. Elle ne synthétise pas une antenne à
réseau phasé (AESA) et ne crée pas de faisceau plus étroit. Un véritable
beamforming demanderait plusieurs voies cohérentes, une géométrie d'antennes
connue et des données de phase calibrées ; les interfaces des modules retenus
ne fournissent pas aujourd'hui un tel flux commun. Une piste différente est
étudiée au §2.9 : la synthèse d'ouverture en arc affine l'azimut avec un seul
capteur cohérent décentré, sans réseau d'antennes ; elle n'existe pour
l'instant qu'en simulation.

Le balayage mécanique est le choix le plus direct pour donner une direction à
l'A121, qui possède un seul canal TX/RX. Il évite de concevoir un réseau RF,
mais échange cette simplicité contre un scan lent, du jeu mécanique, des
erreurs de pointage et une scène non instantanée. Le LD2450 estime ses cibles
avec ses deux voies RX, puis ne livre que des détections traitées. Attente
réaliste : un nuage 3D **épars** — résolution en distance dépendant du profil,
résolution angulaire limitée par le diagramme mesuré et la mécanique — et non
une maquette CAO.

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

Le débit doit être calculé à partir de la sortie réellement configurée. Pour
Sparse IQ, une estimation de charge utile est
`échantillons complexes par trame × octets par échantillon × trames par seconde`,
à laquelle s'ajoutent en-têtes et transport. Profil, plage, nombre de balayages
et cadence changent ce résultat ; une estimation générique en Ko/s ne doit pas
servir à choisir le lien ou le processeur.

### 2.5 Compatibilité électromagnétique (CEM)

La CEM pose trois questions : les éléments du système se gênent-ils entre
eux, le système gêne-t-il son environnement, supporte-t-il son
environnement. Ici la première domine : trois familles de radars, deux
moteurs, des convertisseurs et un émetteur Wi-Fi tiennent dans une tour
d'une vingtaine de centimètres. Les chiffres viennent des fiches
constructeur quand elles existent ; les autres sont des ordres de grandeur,
signalés comme tels, que les essais du point 8 confirment ou corrigent.

**Inventaire : qui émet, qui subit.**

| Élément | Rôle | Ce qui compte pour la CEM |
| ------- | ---- | ------------------------- |
| LD2450 (couronne) | émetteur et victime | FMCW 24,00–24,25 GHz (250 MHz de balayage) ; 5 V, 120 mA en moyenne, source d'au moins 200 mA ; aucune exigence d'ondulation publiée |
| LD6004 | émetteur et victime | FMCW 58–64 GHz, 12 dBm (en sortie selon le manuel, en PIRE selon la page produit : point 7) et 4 dBi d'antenne ; 3,1–3,5 V, 135 à 600 mA, source d'au moins 1 A, **ondulation ≤ 50 mV, découpage ≥ 2 MHz** si l'alimentation est à découpage |
| A121 (XM125) | émetteur et victime | impulsions cohérentes 57–64 GHz, PIRE 11 dBm ; **ondulation ≤ 25 mV crête à crête de 10 kHz à 4 MHz** sur son 1,8 V numérique ; appel de ~3 à ~75 mA au passage en mesure |
| TMC2209 + NEMA 17 | source | découpage à 23, 35 (défaut), 47 ou 59 kHz (2/1024 à 2/410 de son horloge de 12 MHz) ; ~1 A par phase, fronts rapides |
| ULN2003 + 28BYJ-48 | source | commutation inductive au rythme des pas, ~100 mA par phase |
| Convertisseurs | source | de 150 kHz (LM2596) à 1,5 MHz au plus (MP1584) pour les modules courants |
| ESP32 | source et victime | 2,4 GHz jusqu'à ~20 dBm ; appels de ~240 mA à l'émission |
| Liaisons série | victimes | LD2450 à 256 000 bauds **sans somme de contrôle** ; LD6004 avec deux sommes de contrôle ; XM125 par USB (CRC) |

**1. Les radars entre eux.** Un voisin arrive par un seul trajet, en `1/d²`,
alors que l'écho d'une cible fait l'aller-retour, en `1/R⁴`. Pour deux
modules identiques distants de `d`, face à une cible de surface équivalente
`σ` à la distance `R` :

    I/S = (Gl_e x Gl_r) x 4 pi R^4 / (sigma d^2)

où `Gl_e` et `Gl_r` sont les gains d'émission et de réception dans la
direction de l'autre module, rapportés aux gains dans l'axe (lobes
latéraux). Couronne de LD2450 : `d` = 5 cm, personne de 1 m² à 5 m, le terme
`4π R⁴ / (σ d²)` vaut 65 dB ; avec des lobes latéraux de −20, −25 ou
−30 dB de chaque côté, le voisin arrive **25, 15 ou 5 dB au-dessus de
l'écho**. Son effet dépend des chirps : deux rampes qui se croisent laissent
une salve brève (du bruit) ; deux rampes presque parallèles laissent un
battement stable, donc une cible fantôme à distance fixe qui dérive avec les
horloges. Hi-Link ne publie pas ses chirps : seule la mesure tranche. Ses
consignes vont dans le même sens : ne jamais orienter deux radars 24 GHz
l'un vers l'autre, les éloigner autant que possible, et une plaque
métallique à l'arrière du module coupe ce qui vient de derrière. Dans la
couronne, un noyau métallique au centre (tôle ou ruban de cuivre) applique
cette dernière consigne.

À 60 GHz, le LD6004 et l'A121 partagent la bande 57–64 GHz. Même calcul,
LD6004 à 10 cm (1 ou 5 dB de PIRE de plus que l'A121, selon la valeur du
fabricant retenue : point 7), personne à 3 m : le brouilleur arrive entre
−9 et +35 dB par rapport à l'écho pour des lobes de −30 à −10 dB de chaque
côté. L'intégration cohérente de l'A121 rabat une partie de ce signal
non corrélé, dans une proportion qu'on ne peut pas chiffrer sans mesure.
D'où une règle de conception : **réserver la bande 60 GHz à l'A121**, avec
une couronne tout en 24 GHz ; un LD6004 près de la tête de cartographie ne
s'envisage qu'après l'essai A121 seul / A121 + LD6004. Entre les deux
bandes, pas de chemin direct : les harmoniques du 24 GHz tombent à 48 et
72 GHz, hors de 57–64 GHz.

**2. L'alimentation vers les radars (perturbations conduites).** Un radar
FMCW traduit une fréquence de battement `f` en distance, `R = c f / (2 S)`,
où `S` est la pente du chirp. Une ondulation qui atteint sa chaîne de
réception dans cette bande devient une raie : une fausse cible à distance
fixe, ou un plancher de bruit relevé. Pour un chirp hypothétique de 250 MHz
en 100 µs (`S` = 2,5 MHz/µs), 0 à 6 m correspondent à 0–100 kHz : le
découpage du TMC2209 à 35 kHz tomberait à 2,1 m, son harmonique 2 à 4,2 m.
C'est l'interprétation la plus simple de l'exigence du LD6004 : au-dessus de
2 MHz, le découpage sort de la bande utile. Les modules abaisseurs courants
(LM2596 à 150 kHz, Mini-360 à 340 kHz, MP1584 à 1,5 MHz au plus) restent en
dessous. Conséquences :

- **LD6004 : régulateur linéaire** (3,3 V, au moins 1 A) depuis un 5 V
  propre. Il dissipe `(5 − 3,3) × I` : 0,23 W à 135 mA, 1,0 W aux pointes de
  600 mA ; c'est le courant moyen mesuré qui fixe le refroidissement.
- **A121** : la carte SparkFun XM125 enchaîne deux régulateurs linéaires
  (5 V → 3,3 V → 1,8 V, Richtek RT9080). Alimentée par un port USB ordinaire,
  elle tient a priori les 25 mV ; le risque apparaît sur un 5 V partagé avec
  les moteurs.
- **Tour** : distribution en étoile depuis l'entrée, en trois branches :
  moteur (12 V, au moins 100 µF au plus près du TMC2209), radars (5 V
  filtré), logique (STM32, ESP32). Le filtre des radars est un LC amorti
  dont la coupure tombe sous les fréquences de découpage : 10 µH et 100 µF
  donnent `f0` = 5 kHz, soit en théorie −34 dB à 35 kHz et −59 dB à
  150 kHz ; les éléments parasites limitent l'atténuation réelle au-delà de
  quelques centaines de kHz. La résistance série d'un condensateur
  électrolytique amortit la résonance ; Acconeer décrit la même méthode pour
  l'A121 (LC à 30 kHz, résistance de 250 mΩ).
- **28BYJ-48** : bobines sur la branche moteur, pas sur le 5 V des radars
  (sa version 12 V s'y prête directement), et coupées pendant les balayages
  de l'A121.

**3. Les moteurs vers les câbles (couplage proche).** Les phases du NEMA 17
basculent de 12 V en un temps de l'ordre de 100 ns (ordre de grandeur, à
mesurer), soit ~120 V/µs. Par couplage capacitif, 10 pF entre un fil de
phase et une ligne série injectent `C dV/dt` ≈ 1,2 mA pendant le front :
60 mV sur une ligne tenue par une sortie de 50 Ω, plus d'un volt sur une
entrée à haute impédance. Parades : fils de phase torsadés deux à deux et
courts ; lignes série torsadées avec leur masse, éloignées des fils moteur ;
filtre RC à l'entrée de réception (1 kΩ et 100 pF, soit 100 ns, l'échelle
des fronts à filtrer, encore invisible devant les 3,9 µs d'un bit à
256 000 bauds) ; vote à trois échantillons de l'USART du STM32 et comptage
de ses erreurs de bruit et de trame. La broche COM du ULN2003 doit être
reliée à l'alimentation des bobines : ce sont ses diodes internes qui
écrêtent les surtensions de coupure.

**4. Le Wi-Fi vers les radars.** 2,4 GHz est loin de 24 et 60 GHz, et les
antennes des radars le filtrent. Restent deux chemins : le champ proche d'un
émetteur à ~20 dBm, redressé par les amplificateurs basse fréquence des
radars (l'enveloppe des paquets devient une perturbation impulsionnelle), et
les appels de courant d'environ 240 mA sur une alimentation partagée. La
dixième harmonique du canal 1 (10 × 2,412 = 24,12 GHz) tombe en outre dans
la bande du LD2450, à un niveau non spécifié et sans doute très faible.
Parades : antenne de l'ESP32 tournée à l'opposé des radars et aussi loin que
la tour le permet, puissance d'émission réduite (une pièce ne demande pas
20 dBm), ESP32 sur la branche logique.

**5. L'intégrité des trames : l'immunité passe aussi par le logiciel.** Une
trame LD2450 n'a pas de somme de contrôle : en-tête `AA FF 03 00`,
24 octets de cibles, fin `55 CC`. Un octet corrompu entre les deux passe
inaperçu et peut déplacer une cible de plusieurs mètres. Le décodeur Ada
devra donc vérifier la plausibilité de chaque cible : `y` positif (devant le
capteur), distance dans la portée, vitesse bornée, champ de résolution
constant (le manuel le dit fixe ; il vaut 360 dans les trois exemples de sa
FAQ, 320 dans celui du §2.6 : la valeur se relève sur le module réel). Le
fenêtrage d'association du pistage rejette ensuite les sauts restants.
Trames rejetées et erreurs d'USART seront comptées et publiées. Un module
qui se tait ou redémarre (baisse de tension, décharge électrostatique)
devra être détecté et reconfiguré si besoin : le mode multi-cible est une
commande de l'hôte, dont la persistance après redémarrage reste à vérifier.
Le LD6004 (deux sommes de contrôle), le XM125 (USB) et la télémétrie vers
le PC (§2.7, CRC) sont protégés par leur transport. L'émulateur du capteur
(`Radar_Ld2450_Sim`, §2.6) injecte déjà ces défauts, pour que le décodeur
soit éprouvé avant le matériel.

**6. Masses, décharges électrostatiques et collecteur.**

- Dans la configuration visée, la tête (XM125 sur l'USB du PC) et le
  boîtier (sur sa batterie, données par Wi-Fi) n'ont aucune liaison
  galvanique : pas de boucle de masse. Pendant les essais câblés au PC,
  l'adaptateur USB-série et une alimentation 5 V séparée relient les
  masses ; un chargeur secteur de classe II y injecte alors un courant de
  fuite à 50 Hz et son bruit de découpage. Une batterie USB évite la question
  et sert de référence.
- L'A121 tient 2 kV (modèle du corps humain) et 1 kV (modèle CDM) ; la carte
  SparkFun protège son USB par un réseau de diodes. Les LD2450 et LD6004 ne
  publient pas de tenue. Un corps humain atteint couramment plusieurs kV par
  temps sec : boîtier imprimé isolant, aucune pièce métallique touchable
  reliée à l'électronique, connecteurs en retrait.
- Si un collecteur tournant est ajouté, il ne porte que l'alimentation ; les
  données de la tête passent par radio. Chaque variation de résistance de
  contact devient un creux de tension : condensateur de réserve et diode de
  protection (TVS) côté tournant.

**7. Émissions et réglementation (France).**

- Convertisseurs et driver pas-à-pas sont ceux d'une imprimante 3D, avec des
  câbles courts : une gêne pour la radio domestique est peu probable.
- 24 GHz, ERC 70-03 (édition de 2024) : 100 mW PIRE en annexe 1 bande m
  (appareils non spécifiques, 24,00–24,25 GHz) comme en annexe 6 bande m
  (radiorepérage, 24,05–24,25 GHz). Restrictions françaises : en annexe 6,
  aucune pour une installation fixe, sinon 0,1 mW PIRE entre 24,10 et
  24,15 GHz et, en FMCW, 20 mW moyens et 50 mW crête avec un balayage d'au
  moins 5 MHz/ms ; en annexe 1, 0,1 mW PIRE entre 24,10 et 24,15 GHz. Le
  LD2450 balaie dès 24,00 GHz, sous le bas de la bande de l'annexe 6, et sa
  PIRE n'est pas publiée : le cadre qui le couvre se lit dans sa déclaration
  de conformité.
- 57–64 GHz, annexe 1 bande n1 : 100 mW PIRE et 10 mW en sortie
  d'émetteur. L'A121 (11 dBm PIRE) est déclaré conforme à la directive
  2014/53/UE. Pour le LD6004, les deux documents du fabricant se
  contredisent : 12 dBm en sortie selon le manuel (16 mW, plus que les
  10 mW), 12 dBm de PIRE selon la page produit, soit 8 dBm en sortie avec
  l'antenne de 4 dBi (6,3 mW, conforme). Aucune déclaration de conformité
  n'est publiée : c'est elle qui tranchera.
- Une lentille augmente la PIRE : ramener le plan E de l'A121 de 53 à 12°
  ajoute ~6,5 dB (~17,5 dBm crête, sous 20 dBm) ; une lentille ronde à 17°
  ajouterait ~11 dB (~22 dBm crête, au-dessus). L'agrément FCC de l'A121 ne
  couvre d'ailleurs que les lentilles qui n'augmentent pas la PIRE.

**8. Essais sans instrument : les radars se mesurent eux-mêmes.** Chaque
couplage se teste en A/B, pièce vide, quelques minutes par configuration, en
comptant ce que les capteurs produisent déjà : détections et fantômes des
LD2450 et du LD6004, plancher de bruit de l'A121 sur des cases vides,
erreurs d'USART et trames rejetées.

| Bascule | Couplage visé |
| ------- | ------------- |
| moteur arrêté / en rotation | points 2 et 3 (les vibrations, qui ne sont pas de la CEM, se voient aussi) |
| Wi-Fi au repos / en émission continue | point 4 |
| batterie USB / chargeur secteur / convertisseur | points 2 et 6 |
| 1, puis 2, 3 et 4 LD2450 actifs | point 1, 24 GHz |
| A121 seul / A121 + LD6004 | point 1, 60 GHz |

Seuils proposés : une configuration est acceptée si les fantômes augmentent
de moins de 5 % et si le plancher de l'A121 monte de moins de 1 dB. Un
oscilloscope, s'il est disponible, vérifie directement les 25 et 50 mV
d'ondulation sur les rails.

### 2.6 Décoder les trames du capteur — trois pièges

À ne pas confondre avec le protocole de télémétrie de la section suivante :
ici il s'agit de lire ce que le **module radar** envoie, un format imposé par
son fabricant. Le codage des champs et la cadence ci-dessous sont vérifiés sur
l'exemple chiffré et la FAQ du manuel Hi-Link du LD2450, et recoupés avec
l'implémentation LD2450 d'ESPHome ; le comportement de la configuration vient
d'implémentations tierces (famille LD2450 / RD-03D) et reste à mesurer sur le
module retenu.

**Structure de trame** — en-tête `AA FF 03 00`, trois blocs cible de 8 octets,
queue `55 CC`, soit **30 octets** au total. Chaque bloc porte, en
petit-boutiste : X (2 octets), Y (2), vitesse (2), résolution de distance (2).
Trois cibles sont toujours transmises : les emplacements inutilisés sont
simplement nuls.

**Cadence : 10 trames par seconde** selon le manuel. C'est la borne haute du
rafraîchissement : rien en aval ne produira plus de dix positions nouvelles
par seconde et par cible. La liaison n'est pas le goulot — à 256 000 bauds,
une trame de 30 octets occupe 1,2 ms de ligne, et le module accepte jusqu'à
460 800 bauds.

**Piège 1 — ni complément à deux, ni binaire décalé : un bit de signe.**
Le bit 15 porte le signe (1 = positif, 0 = négatif), les bits 0 à 14 la valeur
absolue. L'exemple du manuel, à reprendre tel quel comme vecteur de test :

    AA FF 03 00   0E 03 B1 86 10 00 40 01   8 x 00   8 x 00   55 CC

| Champ | Octets | Brut | Bit 15 | Valeur |
| ----- | ------ | ---- | ------ | ------ |
| X | `0E 03` | 782 | 0 | 0 − 782 = **−782 mm** |
| Y | `B1 86` | 34 481 | 1 | 34 481 − 2¹⁵ = **1 713 mm** |
| Vitesse | `10 00` | 16 | 0 | 0 − 16 = **−16 cm/s** |
| Résolution de distance | `40 01` | 320 | — | **320 mm**, non signée |

    Magnitude : constant Natural := Natural (Raw and 16#7FFF#);
    Value     : constant Integer :=
      (if (Raw and 16#8000#) /= 0 then Magnitude else -Magnitude);

Deux lectures fausses circulent, et chacune reste plausible sur la moitié du
champ. L'entier signé 16 bits (complément à deux) rend les valeurs
**positives** absurdes : `B1 86` donne −31 055. Le binaire décalé
(`raw - 16#8000#`) rend les positives justes mais les **négatives**
absurdes : `0E 03` donne −31 986 mm, qu'un filtre de portée efface sans
bruit — toute la moitié gauche du champ disparaît. Une version antérieure de
ce document recommandait le binaire décalé, recopié d'une implémentation
tierce dont le code contredisait son propre commentaire ; elle est corrigée
d'après l'exemple du constructeur. Corollaire pour les tests : un émulateur de
trames et un décodeur écrits avec la même erreur se valident l'un l'autre. Le
vecteur de test doit venir du manuel, jamais de l'émulateur.

**Zéro garde le bit de signe à 0.** Une capture de la FAQ du manuel montre
une vitesse nulle codée `00 00`, et non `00 80` : le bit 15 ne vaut 1 que
pour une valeur strictement positive. Le décodage n'en dépend pas (les deux
formes se lisent 0), l'encodage d'un émulateur si. Le format est codé dans
`Radar_Ld2450`, dans le cœur embarquable : l'aller-retour entre codage et
décodage y est prouvé pour toutes les valeurs, et ses tests reproduisent
octet pour octet les quatre trames du manuel, l'exemple ci-dessus et les
trois captures de la FAQ.

**L'émulateur remplace le port série, pas le décodeur.** `Radar_Ld2450_Sim`
produit, dix fois par seconde, les octets qu'un module enverrait pour la
scène simulée ; le décodeur les lira comme ceux d'un vrai port, puis livrera
des rapports planaires (`Radar_Planar_Source`). Son modèle de mesure est
celui d'un capteur à deux antennes de réception horizontales : une distance
oblique et un angle, d'où `x = R sin θ` et `y = R cos θ`. Une cible plus
haute ou plus basse que le module paraît donc plus loin : à 1 m devant et
0,6 m de dénivelé, `y` vaut 1 166 mm. Le champ couvre ±60° sur ±35°, la
portée suit des relevés d'utilisateurs (8 m dans l'axe, 6 m à 30°, 5 m à
45°, 1 m à 60°), et seules les trois cibles les plus proches sont
rapportées. Bruit, pertes, fantômes et défauts de liaison (octet abîmé,
module muet, redémarrage qui retombe en mono-cible) sont réglables ou
déclenchés à la demande. Chaque trame porte aussi ce que le module voulait
envoyer : c'est la vérité à laquelle le décodeur sera comparé. Le hasard
vient d'un générateur congruentiel écrit dans le paquet, et non de
`Ada.Numerics.Float_Random`, dont la suite peut changer avec le
compilateur : la même graine donne les mêmes octets partout. Le côté du `x`
positif (droite ou gauche), le sens de la vitesse et le comportement après
un redémarrage restent à vérifier sur un module réel.

**La vitesse est en cm/s**, pas en mm/s : elle se multiplie par 10 avant
d'entrer dans le pistage, qui travaille en mm/s. Une implémentation tierce la
divise par 1000 comme des mm/s, et l'affiche dix fois trop petite.

**Piège 2 — réaffirmer la configuration a un prix.** Le mode multi-cible se
demande par une séquence de trames de commande (en-tête `FD FC FB FA`,
longueur, mot de commande, queue `04 03 02 01`) : ouverture du mode
configuration (`0x00FF`), commande multi-cible (`0x0090`), fermeture
(`0x00FE`). Une implémentation tierce la **réaffirme chaque minute**, au cas
où le module retomberait dans un autre mode. Ce retour spontané n'est pas
documenté par le constructeur, et ESPHome ne le suppose pas : il lit le mode
(`0x0091`) au démarrage. Or chaque séquence occupe la liaison et le module :
environ 0,45 s avec des attentes fixes de 50, 200 et 200 ms, contre une
cinquantaine de millisecondes chez ESPHome, qui ne marque une pause qu'après
la commande elle-même. Qu'il retombe ou non, et qu'il continue ou non
d'émettre des cibles pendant la séquence, se mesure sur le module retenu avant
de payer ce prix toutes les minutes.

**Piège 3 — la configuration ne doit rien bloquer.** Implémentées par des
pauses bloquantes, ces attentes figeaient la boucle d'une implémentation
tierce pendant environ 650 ms : liaison série et réseau affamés, un trou
garanti par minute. En Ada sous profil Ravenscar, cela s'écrit naturellement
comme une **tâche périodique** et le problème ne se pose pas ; c'est un des
endroits où la concurrence déterministe paie comptant.

---

### 2.7 Le protocole de télémétrie (spécification)

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

### 2.8 Priorités d'exploitation : aperçu, détail, suivi

Les trois résultats demandés n'ont pas la même contrainte temporelle. Le
logiciel doit conserver trois chemins, puis les réunir dans l'affichage avec
des horodatages et des niveaux de confiance :

1. **Vue globale rapidement** — le mode `scan` commence par 60 × 8 directions
   pour donner une carte grossière, puis garde ces points visibles pendant
   qu'il ajoute le balayage 180 × 24. Dans la simulation, cela donne un aperçu
   en environ 1,5 s et le détail complet en environ 12,3 s au total. Le second
   passage couvre encore toute la pièce ; le prochain raffinement utile est de
   revisiter seulement les secteurs intéressants, mais uniquement quand le
   scanner sait atteindre un angle demandé et mesurer cet angle.
2. **Suivre une cible avec peu de délai** — `Radar_Track.Update` travaille
   déjà sur des frames datées : sa confirmation M-sur-N de trois observations
   ajoute environ deux intervalles de rapport après la première observation.
   La fiche officielle LD2450 annonce 10 trames/s, soit environ 200 ms pour ces
   deux intervalles avant le transport ; cette latence reste à mesurer sur le
   montage complet. Avec les frames de 840 ms du balayage simulé actuel, la
   confirmation ajoute environ 1,68 s. Les pertes de détection allongent ce
   délai. Réduire globalement le seuil de confirmation
   rendrait les fantômes plus visibles ; il vaut mieux garder ce filtre pour
   les profils incertains et régler le compromis selon la source et sa qualité.
3. **Faire les deux en parallèle** — le flux de cibles doit être traité dès
   son arrivée, avec priorité et horodatage de capture. Le scan A121 peut
   continuer en tâche de fond pour affiner la géométrie. Il ne faut pas attendre
   la fin d'un tour mécanique pour publier une cible issue d'un autre capteur.

Le choix matériel suit ces contraintes : un module qui livre des cibles
directement convient au suivi, mais ne fournit pas les profils nécessaires à
une carte dense des murs ; le profil A121 donne la matière pour cartographier,
mais son axe mécanique ne peut pas suivre une personne avec une cadence
comparable. Les réunir dans un faux format `Sweep` ferait perdre les
différences de dimension, de vitesse et de confiance. Les positions LD2450
sont planaires et ont leur propre contrat (`Radar_Planar_Source`) : leur
suivi rapide demande encore un filtre de piste 2D, sans altitude inventée.
Une couronne de modules peut couvrir plus
large, mais le chevauchement en 24 GHz et la fusion des repères restent à
mesurer avant de figer leur nombre.

La boîte protégée `Radar_Buffer.Mailbox` a une politique différente de celle
de la carte : elle remplace volontairement une mesure non consommée par la
plus fraîche. C'est cohérent avec le suivi, où une vieille observation ajoute
de la latence ; ce serait mauvais pour la cartographie. `Radar_Cloud` conserve
les points jusqu'à sa capacité fixe et compte ceux qu'il rejette ; `map` et
`scan` signalent alors explicitement que le résultat est incomplet. Cette
borne protège la mémoire, mais ne garantit pas une collecte sans perte : une
configuration réelle devra dimensionner la capacité et traiter tout rejet
comme une carte incomplète. Garder une voie « dernière mesure » pour le
pistage et un accumulateur distinct pour la carte évite de sacrifier l'un des
deux usages en partageant un même tampon.

`Radar_Track.Update` reçoit une frame logique et mémorise un seul
`Last_Stamp`. Une intégration multi-capteurs devra donc convertir les positions
dans le même repère, regrouper les observations d'un même instant avant
l'appel au pistage, et retarder ou rejeter une frame arrivée en retard. Des
appels successifs pour deux capteurs au même instant compteraient deux fois la
confirmation M-sur-N ; une frame plus ancienne ferait reculer l'horloge du
tracker. La synchronisation et la fusion sont une étape d'orchestration, pas
une propriété déjà fournie par les deux contrats de source.

**Limite actuelle :** le mode `scan` et le mode `live` restent deux
démonstrations séparées, sans capteurs réels ni ordonnanceur commun. Le mode
`live`, fondé sur des profils, simule un tour toutes les 840 ms et met à jour
les pistes à la fin du tour ; il ne démontre donc pas un suivi rapide matériel. La
prochaine intégration doit raccorder le flux planaire à un filtre 2D, garder
`Radar_Target_Source` pour les rapports réellement 3D, puis faire tourner le
suivi prioritaire et le scan de détail en parallèle.

### 2.9 Synthèse d'ouverture en arc (simulée)

Un capteur à un seul canal TX/RX, comme l'A121, mesure la distance mais pas
l'angle. Sur une tourelle, l'angle vient de la direction visée, avec la
finesse du faisceau : ~65° à mi-puissance pour l'A121 nu (plan H, datasheet
v1.3), ~17° avec la lentille hyperbolique citée au §1.2. Mais l'A121 est
**cohérent** : il mesure aussi la phase de l'écho. Monté **décentré**, à la
distance `r` de l'axe, il décrit un arc ; d'un balayage à l'autre, la phase
de l'écho d'un point fixe change selon `4π d / λ`. En compensant cette phase
pour chaque position supposée du point, puis en sommant les balayages, les
échos s'ajoutent en phase au bon endroit et s'annulent ailleurs : c'est une
antenne synthétique de la taille de la corde de l'arc, `2 r sin(β/2)` pour
une ouverture traitée `β`.

    finesse en azimut (premier zero)   ~ lambda / (4 r sin(beta/2))
    pas maximal le long de l'arc       ~ lambda / (4 sin(beta/2))
    lambda = 4,96 mm a 60,5 GHz

`Radar_Sar` forme l'image par **rétroprojection** (pour chaque pixel, somme
cohérente des balayages qui le voient, sans approximation de champ lointain) ;
`Radar_Sar_Sim` simule des échos complexes (faisceau gaussien, enveloppe du
profil, phase `−4π d/λ`, amplitude en `1/d²`) et injecte des erreurs
mécaniques balayage par balayage. Résultats du mode `sar`, **en simulation**
(une mire ponctuelle à 3 m, profil 2, `r` = 60 mm, un balayage tous les
1,5°). Les pertes dues aux erreurs aléatoires sont des moyennes sur 30
tirages, le pire tirage entre parenthèses : un tirage isolé peut être
chanceux.

| Grandeur | Résultat simulé |
| -------- | --------------- |
| Largeur à −3 dB, ouverture traitée 60° | 2,25° (premier zéro théorique 2,37°) |
| Largeur à −3 dB, ouverture traitée 90° | 1,70° (théorie 1,67°) |
| Faisceau réel, sans synthèse | 43,6° : la synthèse affine ~19 fois |
| `r` = 40 / 60 / 80 mm (60°, pas de 1°) | 3,36° / 2,23° / 1,66° |
| Faux-rond de la tête, 0,10 / 0,14 / 0,20 / 0,50 mm RMS | −0,24 / −0,47 / −0,97 / −6,3 dB au pic (pire : −0,33 / −0,66 / −1,4 / −10) |
| Erreur d'angle de la tourelle, 0,5° / 1° RMS | −0,48 / −1,8 dB (pire : −0,62 / −2,3) |
| Gigue de phase résiduelle, 20° / 45° RMS | −0,53 / −2,7 dB (pire : −0,93 / −5,0) |
| Pas de 1 à 2° par balayage | aucun lobe au-dessus de −20 dB sur ±90° |
| Pas de 3° par balayage | image fantôme vers ±47°, à −10 dB |
| Pas de 5° par balayage | image fantôme vers ±27,5°, à −3,6 dB |

La ligne de la gigue de phase sert aussi de contrôle du simulateur : une
erreur de phase gaussienne d'écart-type `σ` (en radians) réduit en théorie
une somme cohérente d'un facteur `exp(−σ²/2)` en amplitude, soit
`−4,34 σ²` dB : −0,53 dB pour 20°, −2,68 dB pour 45°. La simulation
retrouve ces valeurs.

Trois enseignements. Le **faux-rond du rayon** est la contrainte critique :
un écart radial allonge directement le trajet aller-retour, et la phase
tourne de 360° pour λ/2 ≈ 2,5 mm. L'**erreur d'angle** l'est beaucoup
moins : à 60 mm, 0,5° déplace l'antenne de 0,52 mm de côté et ne coûte pas
plus que 0,14 mm de faux-rond, car un décalage tangentiel change à peine la
distance aux cibles proches de l'axe de visée. Et le **pas
d'échantillonnage** suit la règle de Nyquist : au-delà de 2,37° par balayage
(60 mm, 60° d'ouverture), une image fantôme (lobe de réseau) apparaît, plus
proche du vrai point et plus forte à mesure que le pas grandit. La formule
simple `sin ψ ≈ λ / (2 r Δφ)` en donne l'ordre de grandeur (52° pour un pas
de 3°, 28° pour 5°) ; la simulation la place à 47° et 27,5°. L'écart à 3°
vient du faisceau : le fantôme se forme surtout avec les balayages les plus
tournés vers la cible, au bord de l'ouverture traitée. Un pas de 2°
(180 balayages par tour) reste sous la limite.

Ce sont des chiffres de **modèle**, pas des mesures : faisceau gaussien,
phase idéalement plate le long de l'impulsion (option *phase enhancement* de
l'A121), mire ponctuelle, aucune réflexion multiple. La gigue de phase réelle
peut être estimée à chaque balayage par un sous-balayage de bouclage
(*loopback* : l'impulsion est mesurée sur la puce, sans passer par l'air),
comme le fait le détecteur de distance d'Acconeer pour ses mesures proches.
Le bouclage n'est pas autorisé en profil 2 (`acc_config.h`) : ce
sous-balayage devra utiliser un autre profil, et la corrélation de la gigue
entre profils reste à vérifier. Le faux-rond réel d'une tourelle imprimée
reste lui aussi à mesurer, sur un coin réflecteur.
