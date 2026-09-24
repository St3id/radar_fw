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
9. **Murs spéculaires** — **non implémenté.** Le simulateur rend
   aujourd'hui le même écho pour un mur, quel que soit l'angle sous lequel le
   faisceau le frappe. En réalité (§1.6), l'écho d'un mur lisse chute dès que
   l'incidence s'écarte de la normale, tandis que les coins restent
   brillants. À simuler : une amplitude fonction de l'angle d'incidence, un
   écho renforcé dans les coins, et les images miroirs sous le sol. Enjeu :
   le CFAR et le regroupement sont aujourd'hui réglés sur des murs plus
   faciles que les vrais.

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

Le simulateur rend encore un écho de mur indépendant de l'incidence.
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
| LD2450 | aucun adaptateur dans le dépôt ; sortie série déjà traitée en cibles planaires | décodage série + rapport 2D horodaté ; ne pas fabriquer un `Sweep` ni une altitude |
| A121/XM125 | aucun pilote matériel dans le dépôt | choisir le firmware XM125 ou le chemin A121 qui expose les données requises, puis mapper plage/étape/IQ/calibration |

Le principe de `Radar_Source` reste central : développer et éprouver le
traitement de profils sur simulation, puis remplacer le producteur A121 sans
réécrire le pipeline. `Radar_Target_Source` est la frontière séparée pour
les rapports déjà calculés, à condition qu'ils soient honnêtement
représentables en 3D. Le LD2450 reste une source planaire : avant de l'utiliser
pour le suivi rapide, le code doit introduire un type d'observation 2D et un
filtre de piste 2D. Poser `z = 0` dans `Frame` ferait passer une convention
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
       [azimut : tour borne, index et retour sans mesure + elevation]

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
puis le contrôleur compte les pas sur un tour borné. Le retour à l'index vérifie
la répétabilité, mais un pas perdu au milieu du balayage ne sera pas détecté
immédiatement. Le jeu du réducteur se mesure sur le montage ; l'acquisition se
fait toujours dans le même sens et le retour se fait sans mesure.

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
ne fournissent pas aujourd'hui un tel flux commun.

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

### 2.5 Compatibilité radio et intégration électrique

- Les porteuses Wi-Fi usuelles (2,4, 5 et 6 GHz) sont distinctes des porteuses
  nominales des LD2450 (24 GHz) et A121 (60,5 GHz). Cela écarte un
  recouvrement direct des porteuses fondamentales, mais ne démontre pas à lui
  seul l'immunité du récepteur à proximité d'un ESP32 ou d'un convertisseur.
  Les émissions hors bande, le couplage proche, les retours d'alimentation et
  les perturbations conduites doivent être évalués sur l'assemblage final.
- Le risque de brouillage RF le plus évident à mesurer est celui de plusieurs
  LD2450 actifs dans la même bande FMCW. Le résultat dépend des signaux et des
  réglages internes, qui ne sont pas entièrement publiés par la fiche. Les
  moteurs et ventilateurs peuvent aussi devenir des cibles physiques mobiles
  ou créer du bruit électrique ; ce sont deux phénomènes différents.
- Pour choisir l'emplacement de l'ESP32, du convertisseur et des moteurs,
  comparer les données brutes et les erreurs de transport avec radio Wi-Fi
  inactive/active, moteur arrêté/en mouvement, puis tous les modules actifs.
  Séparer les alimentations ou les retours uniquement si la mesure révèle un
  couplage utile à corriger ; vérifier chutes de tension et réinitialisations.
- Ne pas déduire puissance d'émission, conformité réglementaire ou innocuité
  du seul numéro de fréquence. Vérifier les déclarations du module exact et
  les règles applicables à son pays et à son antenne.

### 2.6 Décoder les trames du capteur — trois pièges

À ne pas confondre avec le protocole de télémétrie de la section suivante :
ici il s'agit de lire ce que le **module radar** envoie, un format imposé par
son fabricant. Les points ci-dessous proviennent d'implémentations tierces du
protocole Hi-Link (famille LD2450 / RD-03D) et restent à confirmer sur le
manuel du module retenu, mais ils coûtent chacun plusieurs heures à
redécouvrir.

**Structure de trame** — en-tête `AA FF 03 00`, trois blocs cible de 8 octets,
queue `55 CC`, soit **30 octets** au total. Trois cibles sont toujours
transmises : les emplacements inutilisés sont simplement nuls.

**Piège 1 — l'encodage des coordonnées n'est pas du complément à deux.**
Les coordonnées et les vitesses arrivent en **binaire décalé** : `0x8000`
représente zéro, au-dessus c'est positif, en dessous négatif.

    valeur = raw - 16#8000#

Déclarer un entier signé 16 bits avec une clause de représentation donnerait
donc **tous les signes faux**. Le symptôme est perfide : les cibles
apparaissent en miroir par rapport à l'origine, ce qui reste assez plausible
pour qu'on cherche longtemps ailleurs.

**Piège 2 — le module oublie sa configuration.** Le mode multi-cible doit
être demandé explicitement par une séquence de commandes (en-tête
`FD FC FB FA`, longueur, mot de commande, queue `04 03 02 01`). Sans elle, le
module démarre dans un état indéterminé et le pistage décroche par
intermittence. Pire : il peut y **retomber tout seul**, ce qui impose de
réaffirmer la configuration périodiquement — l'ordre de la minute.

**Piège 3 — la configuration ne doit rien bloquer.** La séquence comporte des
attentes entre commandes. Les implémenter par des pauses bloquantes affame la
liaison série et le réseau, et provoque une perte de données par minute. En
Ada sous profil Ravenscar, cela s'écrit naturellement comme une **tâche
périodique** et le problème ne se pose pas ; c'est un des endroits où la
concurrence déterministe paie comptant.

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
sont planaires dans le contrat actuel : leur suivi rapide demande encore un
type 2D, sans altitude inventée. Une couronne de modules peut couvrir plus
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
