with Radar_Geometry;  use Radar_Geometry;
with Radar_Detect;    use Radar_Detect;
with Radar_Source;    use Radar_Source;

--  Radar_Track : le pistage, c'est-a-dire le suivi des cibles d'un tour
--  a l'autre sous un identifiant stable.
--
--  Une detection dit "quelque chose est la" ; une piste dit "c'est le
--  meme objet qu'au tour precedent, il va dans cette direction". Tout le
--  paquet existe pour tenir cette seconde affirmation malgre le bruit,
--  les trous de detection et les cibles qui se croisent.

package Radar_Track is

   --  Une piste : un objet suivi dans le temps.
   --
   --  Cycle de vie (regle "M-sur-N", ARCHITECTURE.md realisme point 3) :
   --  une piste nait tentative (invisible pour l'affichage) et n'est
   --  confirmee qu'apres Confirm_Hits detections. Une tentative qui
   --  rate un tour de trop meurt aussitot : les fausses alarmes et les
   --  fantomes de multitrajet, intermittents par nature, ne survivent
   --  pas assez longtemps pour etre confirmes.
   type Track is record
      Id        : Natural := 0;        --  identifiant stable (0 = libre)
      Pos       : Point_3D;            --  position estimee (filtree)
      Velocity  : Point_3D;            --  vitesse estimee (mm/s)
      Missing   : Natural := 0;        --  mises a jour consecutives sans echo
      Last_Seen : Time_Ms := 0;        --  QUAND elle a ete vue pour la
                                       --  derniere fois : c est lui qui
                                       --  decide de sa mort, pas Missing
      Hits      : Natural := 0;        --  detections recues en tout
      Confirmed : Boolean := False;    --  regle M-sur-N passee ?
      Active    : Boolean := False;    --  emplacement utilise ?

      --  Ancre de la vitesse : heure et position filtree de la derniere
      --  correction de VITESSE. L'ecart de position mesure depuis elle
      --  couvre tout le temps ecoule, meme si des corrections de position
      --  ont eu lieu entre-temps (voir Update).
      Vel_Stamp  : Time_Ms  := 0;
      Vel_Anchor : Point_3D := (0.0, 0.0, 0.0);
   end record;

   --  Nombre de pistes suivies simultanement.
   --
   --  16 est large pour une piece : un module de niveau detection rend au
   --  plus 3 cibles, et meme une couronne de cinq capteurs retombe bien
   --  en dessous apres la fusion des doublons de recouvrement.
   --
   --  Ce qui casse si on descend trop bas : passe cette borne, une
   --  detection orpheline ne cree plus de piste du tout, sans le moindre
   --  message. Un objet reel deviendrait invisible parce que des
   --  fantomes occupent les emplacements.
   Max_Tracks : constant := 16;

   type Track_Array is array (1 .. Max_Tracks) of Track;

   --  Une piste CONFIRMEE morte recemment, gardee quelques secondes pour
   --  lui rendre son identifiant si l'objet reapparait la ou il devait
   --  etre ("recollage", ou track stitching). Id = 0 : emplacement libre.
   type Lost_Track is record
      Id       : Natural  := 0;
      Pos      : Point_3D := (0.0, 0.0, 0.0);  --  position a sa mort
      Velocity : Point_3D := (0.0, 0.0, 0.0);  --  vitesse a sa mort (mm/s)
      Lost_At  : Time_Ms  := 0;                --  heure de sa mort
   end record;

   type Lost_Array is array (1 .. Max_Tracks) of Lost_Track;

   --  L'ensemble des pistes suivies + le prochain ID a attribuer.
   type Tracker is record
      Tracks     : Track_Array;
      Lost       : Lost_Array;
      Next_Id    : Positive := 1;

      --  Heure de la derniere frame traitee : la difference avec la
      --  frame suivante donne le dt reel. Sans lui, tout le pistage
      --  raisonnerait en "tours", une unite qui ne veut plus rien dire
      --  des que le balayage est mecanique et que chaque direction est
      --  revue a un rythme different.
      Last_Stamp : Time_Ms := 0;

      --  Frames anterieures a Last_Stamp, rejetees par Update (sature a
      --  Natural'Last). Une perte doit se voir, pas disparaitre.
      Late_Frames : Natural := 0;

      --  Remises a zero sur saut d'horloge (voir Update), saturees.
      Clock_Resets : Natural := 0;
   end record;

   --  Vitesse maximale d'une piste, en mm/s. HYPOTHESE, non mesuree : une
   --  personne dans une piece depasse rarement 3 m/s. Sans borne, une
   --  vitesse fausse elargit sa propre porte d'association (600 + v x dt)
   --  et la piste decroche encore plus loin.
   Max_Speed : constant Float := 3_000.0;

   --  Nombre de detections pour confirmer une piste (le "M" de M-sur-N).
   --
   --  3 et pas 2 : une fausse alarme CFAR tombe au hasard dans l espace,
   --  et la probabilite qu elle retombe deux fois de suite dans la meme
   --  fenetre d association reste non negligeable. A 2, des fantomes
   --  passaient. A 3, ils ne passent plus.
   --
   --  3 et pas 5 : chaque observation de confirmation retarde l affichage
   --  d une cible REELLE. Cela ajoute deux intervalles apres la premiere
   --  detection : 1,68 s a 840 ms entre frames, ou 200 ms a 10 Hz. Le
   --  premier delai vient du balayage simule ; le second est la cadence
   --  nominale annoncee pour le LD2450, encore a mesurer sur notre montage.
   Confirm_Hits : constant := 3;

   --  Met a jour les pistes avec les cibles d'un nouveau tour (frame
   --  deja regroupee), en cinq temps :
   --    1. prediction : chaque piste avance selon sa vitesse (une piste
   --       non revue "roule sur son erre" au lieu de geler) ;
   --    2. association globale avec les positions predites : on prend
   --       iterativement la paire (piste, detection) la plus proche au
   --       monde - aucune piste ne "vole" la detection d'une autre
   --       mieux placee (defaut classique de l'association gloutonne) ;
   --    3. correction alpha-beta des pistes associees (position et
   --       vitesse lissees : le jitter d'une cible etendue ne part plus
   --       tel quel dans la vitesse) ;
   --    4. vie et mort : confirmation M-sur-N, abandon des pistes
   --       perdues, creation de tentatives pour les detections orphelines ;
   --       une piste qui se confirme la ou une piste confirmee vient de
   --       mourir reprend son identifiant (recollage) ;
   --    5. fusion : deux pistes trop proches ET de meme vitesse = un meme
   --       objet fragmente (cible etendue scindee par la quantification) -
   --       la plus ancienne absorbe l'autre, pas de piste "ombre". Deux
   --       pistes confirmees proches mais de vitesses differentes sont deux
   --       objets qui se croisent : elles survivent toutes les deux.
   --
   --  Politique de temps :
   --    - une frame ANTERIEURE a Last_Stamp est rejetee entiere et comptee
   --      dans Late_Frames : rien n'est predit, associe ni vieilli. Ce
   --      n'est pas une synchronisation de capteurs ;
   --    - un SAUT d'horloge (recul de plus de 2 s : capteur redemarre ;
   --      avance de plus de 60 s) efface les pistes et se compte dans
   --      Clock_Resets, sans reutiliser d'identifiant. Rejeter ces frames
   --      bloquerait le pistage jusqu'a ce que l'horloge rattrape l'ancienne
   --      valeur ;
   --    - une frame au MEME instant corrige les positions sans les predire
   --      et n'infere aucune vitesse d'une observation simultanee ;
   --    - la vitesse d'une piste n'est corrigee que si son ancre date d'au
   --      moins Min_Velocity_Interval_Ms (corps du paquet).
   procedure Update (T : in out Tracker; F : Frame);

   --  La piste confirmee qui revendique chaque detection BRUTE de F (avant
   --  regroupement) : la plus proche de sa position PREDITE a l'heure de
   --  F, dans sa fenetre d'association. 0 = aucune. A passer a
   --  Radar_Detect.Cluster pour qu'un croisement ne fasse pas d'un couple
   --  d'objets une seule detection :
   --
   --     Update (Trk, Cluster (F, Owners (Trk, F)));
   --
   --  Ne modifie pas le pistage : c'est une lecture, appelee juste avant
   --  Update sur la meme frame. Une frame qu'Update rejetterait (anterieure
   --  a Last_Stamp) n'est revendiquee par aucune piste.
   function Owners (T : Tracker; F : Frame) return Owner_List;

end Radar_Track;
