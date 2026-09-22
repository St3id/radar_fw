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

   --  L'ensemble des pistes suivies + le prochain ID a attribuer.
   type Tracker is record
      Tracks     : Track_Array;
      Next_Id    : Positive := 1;

      --  Heure de la derniere frame traitee : la difference avec la
      --  frame suivante donne le dt reel. Sans lui, tout le pistage
      --  raisonnerait en "tours", une unite qui ne veut plus rien dire
      --  des que le balayage est mecanique et que chaque direction est
      --  revue a un rythme different.
      Last_Stamp : Time_Ms := 0;
   end record;

   --  Nombre de detections pour confirmer une piste (le "M" de M-sur-N).
   --
   --  3 et pas 2 : une fausse alarme CFAR tombe au hasard dans l espace,
   --  et la probabilite qu elle retombe deux fois de suite dans la meme
   --  fenetre d association reste non negligeable. A 2, des fantomes
   --  passaient. A 3, ils ne passent plus.
   --
   --  3 et pas 5 : chaque tour de confirmation retarde l affichage d une
   --  cible REELLE. A 840 ms par tour, 3 detections font deja 2,5 s
   --  d attente avant qu une personne apparaisse a l ecran.
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
   --    5. fusion : deux pistes trop proches = un meme objet fragmente
   --       (cible etendue scindee par la quantification) - la plus
   --       ancienne absorbe l'autre, pas de piste "ombre".
   procedure Update (T : in out Tracker; F : Frame);

end Radar_Track;
