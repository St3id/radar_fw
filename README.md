# radar_fw

[![Build, Test & Prove](https://github.com/St3id/radar_fw/actions/workflows/ci.yml/badge.svg)](https://github.com/St3id/radar_fw/actions/workflows/ci.yml)

Une chaîne de traitement radar 3D en Ada et SPARK. Elle détecte, suit plusieurs
cibles et affiche le résultat en 3D dans le navigateur. La détection est prouvée
formellement.

Aucun capteur n'est branché pour l'instant : tout tourne sur une source simulée,
derrière l'interface où viendra le vrai capteur. Le cœur cross-compile déjà pour
ARM Cortex-M4F, et la CI le vérifie à chaque commit.

[Démonstration en ligne](https://St3id.github.io/radar_fw/) : une pièce
cartographiée par la détection prouvée, à explorer dans le navigateur.

## En bref

| | |
| --- | --- |
| Langage | Ada, compilé en norme 2012 (aucun `-gnat2022`) ; `SPARK_Mode` sur le cœur de traitement |
| Vérification formelle | **354 checks prouvés, 0 non prouvé** (prouveurs CVC5 et Z3) : absence d'erreur d'exécution, cohérence au seuil calculé, contrats du parseur LD2450 et du plan de balayage. Rien sur la qualité de détection ni sur un module réel |
| Tests | **71 tests AUnit**, rejoués à chaque commit |
| Modes d'exploitation | 5 : `track`, `map`, `live`, `scan`, `sar` |
| Concurrence | profil **Ravenscar** imposé à la compilation |
| Cible embarquée | ARM Cortex-M4F, runtime `light` (STM32G474 visé) |
| Source de données | simulateur reproductible, aucun matériel à ce jour |

## Ce que fait le programme

Cinq modes, tous sur simulation :

    alr run                          # track : rejeu du pistage (defaut)
    alr exec -- ./bin/radar_fw map   # cartographie -> out/radar_3d.html
    alr exec -- ./bin/radar_fw live  # temps reel -> http://localhost:8080
    alr exec -- ./bin/radar_fw scan  # carto progressive -> meme adresse
    alr exec -- ./bin/radar_fw scan --dwell  # idem, en ralentissant sur les cibles
    alr exec -- ./bin/radar_fw sar   # synthese d'ouverture simulee (texte)

- **`track`, rejeu du pistage.** 60 tours d'un monde d'objets mobiles : détection,
  pistage, vitesses, puis un rejeu animé dans `out/radar_tracking_3d.html`. Le
  lissage et la vitesse de rejeu se règlent.
- **`map`, cartographie statique.** Un tour de 180 × 24 directions sur une pièce
  sans objets mobiles, soit environ 4 000 points dans `out/radar_3d.html`. Les
  murs vus de biais sont plus clairsemés que ceux vus de face et les coins
  ressortent, parce que l'écho dépend de l'angle d'incidence (ARCHITECTURE §1.6).
  On se déplace au clavier (ZQSD/WASD), et un clic sur un point donne sa position,
  sa distance et ses angles. La [page publiée](https://St3id.github.io/radar_fw/)
  vient de cette sortie.
- **`live`, surveillance temps réel.** Un serveur HTTP en Ada fait tourner la
  simulation en continu, murs et objets mobiles. Les huit premiers tours
  calibrent la carte de clutter, puis le décor est soustrait et seuls les mobiles
  sont pistés. Le serveur pousse chaque nouvel état à la page 3D (Server-Sent
  Events, sans sondage) : cibles numérotées, distance, vitesse en m/s, traînées.
- **`scan`, cartographie progressive.** Une passe rapide (60 × 8) d'abord, puis une
  passe de détail (180 × 24) qui l'enrichit. Dans la démonstration, la première
  prend environ 1,5 s et le détail 10,8 s : ce sont des cadences d'animation, pas
  des mesures du moteur ou du capteur. Seuls les nouveaux points partent à chaque
  rafraîchissement, par lots. Avec `--dwell`, la passe de détail garde sa durée et
  son nombre de mesures, mais les resserre sur les objets simulés, à parts égales
  entre eux (`ARCHITECTURE.md` §2.8).
- **`sar`, synthèse d'ouverture simulée.** Un capteur cohérent décentré de 60 mm
  sur une tourelle voit une mire à 3 m. En sommant les échos de tout l'arc de façon
  cohérente, l'azimut passe de ~44° (faisceau réel) à ~2,2°. Le mode chiffre aussi
  ce que coûtent le faux-rond de la tête, l'erreur d'angle, la gigue de phase et
  un échantillonnage trop lâche (ARCHITECTURE §2.9).

`live` et `scan` partagent le serveur HTTP Ada (`Radar_Http`) : ouvrir l'URL
pendant que le programme tourne. Pour `track` et `map`, ouvrir le fichier HTML
produit dans `out/`.

## La chaîne de traitement

`Radar_Sweep` (SPARK, prouvé) transforme un balayage brut en cibles : seuil de
détection, pic (`Peak_Bin`), conversion case → distance (`Bin_Distance`),
détection multi-cibles, regroupement des échos voisins et seuil adaptatif CFAR
(`Detect_Adaptive`, celle qu'utilise tout le pipeline).

Les données entrent par un contrat qui dépend de ce que sort le capteur :

- `Radar_Source` pour un profil de balayage. Les modes de cartographie et le mode
  `live` basé sur balayages passent par là, et c'est ici que le vrai capteur
  remplacera la simulation sans réécrire le traitement.
- `Radar_Target_Source` pour des positions 3D déjà calculées. Aucun adaptateur
  matériel ne l'utilise encore.
- `Radar_Planar_Source` pour un capteur qui ne donne que x/y, comme le LD2450. Il
  attend un pistage planaire, encore à faire : on ne lui invente pas d'altitude.

Côté LD2450, le format de trame est codé et prouvé dans le cœur embarquable
(`Radar_Ld2450`) et un émulateur simule la liaison série (`Radar_Ld2450_Sim`). Le
parseur de flux (`Radar_Ld2450_Stream`, prouvé) et le filtre de plausibilité
existent. `Radar_Ld2450_Replay` livre des rapports planaires depuis un fichier
d'octets enregistrés : c'est la seule source concrète de ce contrat, et elle n'a
encore jamais relu une capture réelle.

Ensuite vient la perception 3D :

1. `Radar_Detect` : chaque mesure passe par la détection prouvée puis devient un
   point 3D. Deux objets alignés sur un même rayon donnent bien deux détections.
2. `Cluster` : fusion spatiale des détections d'un même tour.
3. `Radar_Clutter` : en surveillance par profils, on soustrait le décor appris
   (MTI) pour ne garder que les objets mobiles.
4. `Radar_Track` : association gloutonne (la paire piste-détection la plus proche
   d'abord), identifiants conservés d'un tour à l'autre (objets simulés lents),
   filtre alpha-beta, confirmation M-sur-N, fusion des pistes fragmentées sur la
   position et la vitesse, pour que deux cibles qui se croisent restent deux
   pistes. S'y ajoutent le regroupement guidé par les pistes et le recollage d'une
   piste perdue qui réapparaît. Il reçoit des frames horodatées, quel que soit le
   contrat d'entrée.

## État d'avancement

Acquis :

- [x] Traitement d'un balayage : seuil de détection, pic, conversion en distance,
      multi-cibles (`Detect_All`) et regroupement des échos voisins
      (`Detect_Clustered`).
- [x] Contrats SPARK fonctionnels, CFAR compris, et terminaison prouvée. La preuve
      porte sur le code, pas sur la qualité de détection (voir « Vérification
      formelle »).
- [x] Pipeline 3D complet sur source simulée : interface abstraite, monde simulé
      mobile, détections 3D, regroupement spatial, pistage à identifiants conservés
      d'un tour à l'autre et vitesses. Les objets simulés vont à environ 0,14 m/s.
      Face à des cibles réelles plus rapides, on ne sait pas encore, et la gestion
      du temps réel du pistage (cadence, retards, trames hors ordre) reste une dette
      ouverte.
- [x] Horodatage sur horloge simulée : chaque mesure est datée, les vitesses sont en
      mm/s et ne dépendent plus de la cadence de balayage. La fenêtre d'association
      et la durée de coasting se comptent en temps.
- [x] Pistage : prédiction et coasting, filtre alpha-beta, confirmation M-sur-N (ni
      les tentatives ni les fantômes ne sont affichés), association gloutonne par
      paire la plus proche, fusion anti-fragmentation, exclusion logicielle des 8
      premières cases simulées (625 mm).
- [x] MTI par carte de clutter adaptative, avec apprentissage de fond et oubli lent,
      embarquable et cross-compilée pour ARM en CI.
- [x] Cibles simulées imparfaites : 4 réflecteurs, fading uniforme inspiré des
      modèles de Swerling (sans en reprendre la loi statistique), trous de
      détection, bruit de fond et fantômes multitrajet. Le CFAR n'a donc pas affronté
      un bruit réaliste (voir `documentation/public/ARCHITECTURE.md` §1).
- [x] Concurrence Ravenscar : profil imposé à la compilation, tâche cyclique, objet
      protégé analysé en SPARK, tâche sporadique.
- [x] Cross-compilation du cœur prouvé pour Cortex-M4F, sans la carte.
- [x] Format de trame du LD2450, prouvé et embarquable : les quatre trames du manuel
      du fabricant ressortent octet pour octet.
- [x] Émulateur du LD2450 : les octets qu'enverrait le module, dix fois par seconde,
      pour la scène simulée (distance oblique, champ et portée selon l'angle, trois
      cibles au plus, bruit, pertes, fantômes). Les défauts de liaison sont à la
      demande (octet abîmé, module muet, redémarrage), et tout est reproductible à la
      graine près.
- [x] Parseur de flux du LD2450, prouvé et embarquable. Sa fenêtre glissante ne recule
      que d'un octet à la fois, retrouve les trames du manuel depuis n'importe quel
      départ et se resynchronise en au plus 59 octets. Essayé sur flux abîmés et sur
      l'émulateur, **jamais sur un module réel**.
- [x] Plausibilité des cibles, séparée du parseur : les seuils sont nommés et commentés
      comme hypothèses à remesurer, avec un compteur par motif de rejet.
- [x] Capture et rejeu : un fichier garde les octets reçus et leur heure de réception.
      `Radar_Ld2450_Replay` le relit par le même parseur et distingue un module muet
      de la fin du fichier. Essayé sur des fichiers générés, **jamais sur une capture
      réelle**.
- [x] Serveur HTTP en Ada (`GNAT.Sockets`), partagé par `live` et `scan`.
- [x] CI sur toutes les branches : build, tests, démo Ravenscar exécutée, quatre
      preuves SPARK bloquantes, cross-compilation ARM.

Reste à faire :

- [ ] Validation sur un module réel. L'enregistreur `radar_ld2450_record` est écrit
      pour Windows, mais **seuls ses chemins d'erreur ont été exécutés** : la lecture
      du port et 256 000 bauds restent à essayer. Le parseur, les seuils de
      plausibilité, l'heure de réception, le côté du `x` positif et le sens de la
      vitesse n'ont jamais vu de vraie trame.
- [ ] Pistage 2D du LD2450 (le format, le parseur, le type de rapport planaire et
      l'émulateur existent). Le type 3D reste réservé aux mesures qui ont vraiment une
      altitude. La fusion viendra après, avec horloges et poses calibrées.
- [ ] Raffinement des seuls secteurs utiles après la passe rapide : `scan` refait
      encore toute la grille en détail.
- [ ] Driver capteur en Ada sur STM32 (matériel requis).
- [ ] Balayage motorisé réel (matériel requis).

## Vérification formelle

Le code en `SPARK_Mode` est prouvé avec SPARK (prouveurs CVC5 et Z3) : **354 checks,
0 non prouvé** pour le projet principal, dont 154 contrôles d'exécution, 67
assertions, 77 contrats fonctionnels, 49 de terminaison et 7 d'initialisation.

Ce que ça établit :

- L'absence d'erreur d'exécution : débordements, indices hors bornes.
- Des contrats sur le résultat : `Peak_Bin` renvoie bien le maximum du balayage,
  `Peak_Distance` vaut exactement `Bin_Distance (Peak_Bin (S))`, et les détecteurs ne
  rapportent que des cases au-dessus de leur seuil logiciel. Ça ne dit rien d'un taux
  de fausse alarme réel, ni de l'origine d'un écho. **La qualité de détection n'est
  pas prouvée** : on a exécuté des mutants, et un détecteur muet ou un facteur CFAR de
  2 ou de 16 restent prouvés.
- Le codage des trames LD2450 (`Radar_Ld2450`) : décoder une valeur codée rend cette
  valeur, pour les 65 535 possibles, et chaque trame construite porte son en-tête et
  sa fin.
- Le parseur de flux LD2450 (`Radar_Ld2450_Stream`), pour toute suite d'octets : une
  trame livrée a son en-tête et sa fin à leurs rangs et des champs conformes à ses
  octets. Seuls des débuts impossibles sont écartés, jamais un candidat encore
  possible. Octets lus = 30 × trames livrées + écartés + en attente, tant que les
  compteurs ne saturent pas. Des mutants (saut de 30 octets, en-tête mal comparé,
  compteurs faux) ont été exécutés : la preuve et les tests rejettent chacun d'eux.
- Le filtre `Radar_Ld2450_Plausibility` : une cible retenue respecte les seuils. Ni ces
  seuils, posés sans module réel, ni le contenu d'une trame, qui n'a pas de somme de
  contrôle, ne sont validés pour autant.
- Le plan de balayage `Radar_Dwell` : sans cible, la passe dure exactement sa durée
  nominale. Sinon, la somme vaut le temps minimal plus une part par cible, avec la
  réserve de rampe, et aucun secteur ne dépasse la vitesse maximale. Donner une part
  ajoute exactement ce temps à la fenêtre de la cible et ne change rien ailleurs. Les
  durées et les angles restent des hypothèses, et rien n'a tourné sur un vrai moteur.
- La terminaison des sous-programmes (aspect implicite `Always_Terminates`).

L'objet protégé `Mailbox` est analysé à part, dans le contexte Ravenscar (projet
`radar_demo.gpr`) : absence d'erreur d'exécution et de flot, sans propriété
fonctionnelle. Il ne compte pas dans les 354 checks.

Reproduire les quatre preuves, sur un répertoire `obj/` neuf :

    alr exec -- gnatprove -P radar_fw.gpr   --report=all --checks-as-errors=on                       # 187 checks
    alr exec -- gnatprove -P radar_fw.gpr -u radar_ld2450.adb --report=all --checks-as-errors=on     # 214 au total (187 + 27)
    alr exec -- gnatprove -P radar_fw.gpr -u radar_ld2450_stream.adb radar_ld2450_plausibility.adb --report=all --checks-as-errors=on   # 354 au total (214 + 140)
    alr exec -- gnatprove -P radar_demo.gpr --report=all --checks-as-errors=on                       # 89 checks

Il faut les trois premières parce que `gnatprove -P` ne regarde que ce qu'utilise
l'exécutable (187 checks). `Radar_Ld2450` est hors de cette fermeture, d'où la
seconde (214), et le parseur avec sa plausibilité aussi, d'où la troisième (354). Ces
unités et `Radar_Dwell` se prouvent au niveau 1 (réglage de `radar_fw.gpr`, fichier
par fichier) : CVC5 seul ne relie pas certains quantificateurs, Z3 y arrive. Le projet
de démonstration compte 89 checks. Les deux projets partagent des unités du cœur, ce
qui fait 358 checks distincts au total.

## Concurrence Ravenscar

`radar_demo` (projet `radar_demo.gpr`) reprend le motif Ravenscar classique.
`ravenscar.adc` impose le profil à la compilation (`pragma Profile (Ravenscar)` et
élaboration séquentielle).

- `Producer`, tâche cyclique cadencée par `delay until`, dépose un balayage toutes les
  250 ms dans l'objet protégé.
- `Mailbox`, objet protégé analysé en SPARK (absence d'erreur d'exécution et de flot),
  expose une `entry Get` à barrière simple : le noyau suspend le consommateur tant
  qu'il n'y a rien à lire, sans sondage.
- `Consumer`, tâche sporadique réveillée par la barrière, traite le balayage avec les
  fonctions prouvées de `Radar_Sweep`.
- La fin de la démonstration passe par un objet de suspension
  (`Ada.Synchronous_Task_Control`), l'autre primitive de synchronisation que le profil
  autorise.

Compiler puis exécuter la démonstration :

    alr exec -- gprbuild -p -P radar_demo.gpr
    alr exec -- ./bin/radar_demo

## Le cœur embarquable, sans la carte

`radar_core.gpr` compile le cœur pour arm-eabi / Cortex-M4F avec le runtime réduit
`light`, celui du processeur du STM32G474 visé. La CI rejoue cette compilation à chaque
commit, sans édition de liens : on obtient des objets, pas d'image exécutable.

`core_restrictions.adc` fait échouer la compilation si le cœur se met à utiliser
`Ada.Text_IO`, `Ada.Calendar`, un allocateur `new`, une instruction `raise` ou un
gestionnaire d'exception. Ces rejets ont été vérifiés avec des unités sondes injectées
dans `src/core`. Sur la taille du code, le temps d'exécution ou le comportement sur la
carte, cette compilation ne dit rien.

## Tests

**71 tests AUnit** répartis en six suites :

- traitement du balayage : pic, seuil, multi-cibles, regroupement ;
- balayage adaptatif : parts égales, fenêtres recouvertes ou coupées, rampes d'un moteur
  simulé, gain en mesures et en échos sur les objets ;
- pipeline 3D : CFAR, aller-retour géométrique, normalisation d'azimut, zénith,
  regroupement spatial, cycle de vie du pistage (filtre, M-sur-N, coasting, mort des
  tentatives, traversée de la zone aveugle, croisement de deux cibles, recollage d'une
  piste perdue), deux échos sur un même rayon, murs (distance, incidence, écho spéculaire
  ou diffus), clutter adaptatif (tout angle fini accepté, sans boucle ni exception),
  pilotage de la source par l'interface, format de sérialisation, vitesse en mm/s
  indépendante de la cadence de balayage, cycle de vie des pistes compté en temps,
  horodatages du pistage (même instant, frame tardive, absence, sources entrelacées, saut
  d'horloge), vitesse bornée ;
- synthèse d'ouverture en arc : focalisation et finesse conformes à la théorie, gain sur
  le faisceau réel, tolérances mécaniques, repliement quand l'échantillonnage est trop
  lâche ;
- module LD2450 : les quatre trames du manuel reproduites octet pour octet, bit de signe
  aux limites, emplacements vides ; émulateur : cadence, champ et portée, distance oblique
  et vitesse radiale, défauts de liaison, reproductibilité ;
- flux LD2450 : les quatre trames du manuel depuis chacun des 30 décalages de départ,
  resynchronisation en au plus 59 octets après une insertion de 1 à 60 octets ou une perte
  de 1 à 29, bit faux dans l'en-tête ou la fin, troncature, réponses de commande, un
  million d'octets aléatoires, trames noyées dans le bruit, émulateur avec défauts ;
  plausibilité : cible vide, un compteur par motif, porte de saut, 768 bits inversés ;
  rejeu d'un fichier généré, silence et fin distingués, fichiers abîmés.

Compiler puis lancer les suites :

    alr exec -- gprbuild -p -P radar_fw_tests.gpr
    alr exec -- ./bin/run_tests

## Compilation et exécution

    alr build
    alr run                          # track -> out/radar_tracking_3d.html
    alr exec -- ./bin/radar_fw map   # cartographie -> out/radar_3d.html
    alr exec -- ./bin/radar_fw live  # temps reel -> http://localhost:8080
    alr exec -- ./bin/radar_fw scan  # carto progressive -> meme adresse
    alr exec -- ./bin/radar_fw sar   # synthese d'ouverture simulee (texte)

L'enregistreur est un outil à part, propre à Windows et **non validé sur matériel**
(seuls ses chemins d'erreur ont été exécutés) :

    alr exec -- gprbuild -p -P radar_ld2450_record.gpr
    alr exec -- ./bin/radar_ld2450_record COM3 out/capture.ld2450 60

## Intégration continue

`.github/workflows/ci.yml` tourne à chaque push, sur toutes les branches : compilation,
tests AUnit, exécution du démonstrateur Ravenscar, preuves SPARK des deux projets, qui
bloquent grâce à `--checks-as-errors=on`, et cross-compilation du cœur pour ARM.
L'enregistreur y est compilé sans édition de liens, car le runner est sous Linux et
l'outil appelle l'API Windows.

## Documentation

- `documentation/public/ARCHITECTURE.md` : pourquoi le code fait ce qu'il fait, la
  physique radar que le simulateur doit affronter, l'architecture matérielle visée et le
  protocole de télémétrie.
- `documentation/public/GUIDE_DEPOT.md` : la carte du dépôt, où trouver quel fichier, et
  pourquoi il y a cinq projets de compilation.

## Outils

Ada (norme 2012), SPARK, Alire, GNAT (natif et `gnat_arm_elf` pour la cible STM32).

## Remerciements

Merci à [Stevee87](https://github.com/Stevee87) pour ses projets publics de fusion LiDAR
+ radar mmWave sur ESP32
([Lidar-Radar-combination-Raspberry](https://github.com/Stevee87/Lidar-Radar-combination-Raspberry),
[Tactical-Radar-System-ESP32-P4](https://github.com/Stevee87/Tactical-Radar-System-ESP32-P4-elcrow-Display),
MIT). Les lire a fait gagner du temps sur trois points :

- le codage des coordonnées du protocole Hi-Link, qui n'est pas du complément à deux. Leurs
  projets en montrent deux lectures différentes, et l'exemple du constructeur a tranché
  pour un bit de signe ;
- la séquence de configuration multi-cible, et le prix d'une séquence bloquante ;
- la cécité au mouvement tangentiel d'un capteur Doppler, une limite physique qu'une
  couronne de capteurs ne lève pas et que le pistage doit absorber.

Le détail est dans
[`documentation/public/ARCHITECTURE.md`](documentation/public/ARCHITECTURE.md) §1.1 et
§2.6. Aucun code repris, seulement des leçons.

## Licence

MIT, voir [`LICENSE`](LICENSE).
