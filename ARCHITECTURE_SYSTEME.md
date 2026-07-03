# Architecture système — le radar physique et sa télémétrie

Réponses aux questions d'utilisation réelle : à quoi ressemble la carte et
ses composants, comment les ondes sont émises et captées, comment les
résultats arrivent jusqu'à toi (UART ? WiFi ? faut-il être à côté ?), et
est-ce que le WiFi perturbe le radar. Plus une revue des défauts
d'implémentation identifiés.

---

## 1. Le montage physique (phase matérielle 1 : LD2450)

```text
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
```

Phase matérielle 2 (A121) : même schéma, mais le capteur parle **SPI** et
livre un profil d'écho par cases de distance (notre type `Sweep`) — c'est
là que `Detect_Adaptive` (CFAR), `Radar_Clutter` et le pistage, déjà
cross-compilés pour le Cortex-M4F, tournent **sur la carte**.

## 2. Comment les ondes sont émises et captées

Tu ne « touches » jamais l'onde : la puce radar fait tout le RF.

1. La puce génère un signal 24/60 GHz (FMCW : fréquence qui glisse, ou
   impulsions cohérentes pour l'A121) et l'envoie sur son **antenne TX
   gravée sur le circuit** (quelques mm : intégrée, pas remplaçable) ;
2. l'onde part en cône (le « faisceau », large de 40–120° selon le
   module), rebondit sur ce qu'elle rencontre — un corps humain
   réfléchit bien, le plâtre absorbe/traverse partiellement à 24 GHz,
   bloque à 60 GHz ;
3. l'écho revient sur les **antennes RX** ; la puce mesure le retard
   (→ distance), le glissement de fréquence (→ vitesse Doppler) et la
   différence de phase entre RX (→ angle) ;
4. le module te livre le résultat **en numérique** (UART ou SPI). Ton
   travail — celui de ce dépôt — commence là.

## 3. Télémétrie : comment tu reçois les résultats

C'est la bonne question, et la réponse est en deux temps :

| Lien | Portée | Ce que ça demande | Verdict |
| ---- | ------ | ----------------- | ------- |
| UART + câble USB | 1–2 m (PC à côté) | rien (adaptateur 3 €) | **par là qu'on commence** : zéro inconnue, debug facile |
| **UART → ESP32 → WiFi** | toute la maison | l'ESP32 que tu POSSEDES déjà, en pont « bête » | **la cible** : tu es dans une autre pièce, le serveur live reçoit du TCP au lieu du simulateur |
| BLE | ~10 m | plus de travail, moins de débit | pas utile ici |

Le point d'architecture qui compte : l'ESP32 reste un **pont transparent**
(UART entrant → TCP sortant, zéro logique radar). Toute l'intelligence
reste dans le STM32 en Ada — la vitrine du projet est intacte, et le pont
est un composant standard de l'industrie (« gateway »).

Débits, pour fixer les idées : des pistes (id, x, y, z, vitesse) à 10 Hz
= **~1 Ko/s** (rien du tout : UART 115200 suffit) ; des profils bruts
A121 ≈ 10–20 Ko/s (UART 921600 ou WiFi, confortable) ; de l'IQ brut
BGT60 = des Mo/s — là il faudra décimer À BORD, et c'est un argument de
plus pour faire le traitement sur le STM32.

## 4. « Le WiFi perturbe-t-il le radar ? » — Non, et voici pourquoi

- Le WiFi émet à **2,4 / 5 / 6 GHz**. Tes radars écoutent à **24 GHz**
  (LD2450) ou **60 GHz** (A121, BGT60). Aucun recouvrement : pour le
  radar, le WiFi n'existe pas (ses filtres d'entrée rejettent tout ce
  qui n'est pas sa bande). Tu peux mettre l'ESP32 collé au module.
- Les VRAIES interférences à connaître :
  - **deux radars 24 GHz face à face** (deux LD2450 dans la même pièce)
    peuvent se polluer mutuellement ;
  - le **ventilateur / rideau** : pas une interférence radio, mais une
    cible mobile bien réelle pour le Doppler (documenté par les
    utilisateurs domotique — c'est notre carte de clutter et le M-sur-N
    qui la gèrent) ;
  - le cas particulier du **coffee-can 2,4 GHz** (projet DIY ultérieur) :
    lui partage la bande WiFi — interférences dans les deux sens, à
    faire loin des points d'accès.
- Sens inverse (le radar perturbe-t-il le WiFi/toi ?) : puissance émise
  de l'ordre du **milliwatt**, en bande libre réglementée — sans enjeu.

Et une conséquence utile : à 60 GHz les ondes **ne traversent pas les
cloisons**. Ton radar ne verra jamais la pièce d'à côté (à 24 GHz, une
cloison légère est partiellement transparente — les capteurs domotique
sont parfois cachés derrière un panneau). Le WiFi, lui, traverse : tu
peux donc être ailleurs dans la maison pendant que le radar scanne.

## 5. Défauts d'implémentation identifiés (revue honnête)

1. **Fragmentation de pistes** : une cible étendue scindée par la
   quantification d'élévation peut confirmer une piste « ombre » (vu en
   test live : 3 pistes confirmées pour 2 objets). Parade connue :
   association GLOBALE (algorithme hongrois/GNN) + fusion de pistes
   proches. C'est le prochain chantier tracker.
2. **Couplage implicite** : la grille de `Radar_Clutter` (120 × 7) doit
   correspondre à celle de la source — convention non vérifiée par le
   compilateur. À terme : passer la grille en paramètre (générique ou
   discriminant).
3. **Vitesses en mm/tour** : toujours pas de vraie base de temps (mm/s).
   À faire avant le matériel — le LD2450 fournira des timestamps réels.
4. **HTTP par sondage (250 ms)** : simple et suffisant à 0,8 s/tour ;
   si la cadence monte (LD2450 : 10 Hz), passer aux Server-Sent Events
   (plus simple que WebSocket, toujours sans dépendance).
5. **Serveur mono-thread** : si un tour de traitement dépassait la
   période, les requêtes attendraient. Sans enjeu sur PC ; à surveiller.
6. **Serveur en 127.0.0.1 sans authentification** : volontaire (démo
   locale). Pour consulter depuis le téléphone : écouter sur 0.0.0.0 —
   et assumer que c'est du LAN de confiance.
7. **La couche 3D reste en Float non SPARK** — chantier 3bis du GUIDE,
   inchangé, à faire avant le portage MCU du pipeline complet.

## 6. Ce que « facilement utilisable » veut dire pour la suite

Le jour du flash, l'expérience visée est exactement celle d'aujourd'hui :
`radar_fw live`, un navigateur ouvert sur la page 3D — sauf que la source
sera `Radar_Serial_Source` (trames LD2450 par câble, puis par WiFi via
l'ESP32) au lieu du simulateur. Rien d'autre ne change : c'est tout
l'intérêt d'avoir construit les modes AVANT le matériel.
