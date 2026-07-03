with Radar_Geometry;  use Radar_Geometry;
with Radar_Detect;    use Radar_Detect;

package Radar_Track is

   --  Une PISTE : un objet suivi dans le temps.
   --
   --  Cycle de vie (regle "M-sur-N", ANALYSE_REALISME.md point 3) :
   --  une piste nait TENTATIVE (invisible pour l'affichage) et n'est
   --  CONFIRMEE qu'apres Confirm_Hits detections. Une tentative qui
   --  rate un tour de trop meurt aussitot : les fausses alarmes et les
   --  fantomes de multitrajet, intermittents par nature, ne survivent
   --  pas assez longtemps pour etre confirmes.
   type Track is record
      Id        : Natural := 0;        --  identifiant stable (0 = libre)
      Pos       : Point_3D;            --  position estimee (filtree)
      Velocity  : Point_3D;            --  vitesse estimee (mm/tour)
      Missing   : Natural := 0;        --  tours consecutifs sans echo
      Hits      : Natural := 0;        --  detections recues en tout
      Confirmed : Boolean := False;    --  regle M-sur-N passee ?
      Active    : Boolean := False;    --  emplacement utilise ?
   end record;

   Max_Tracks : constant := 16;

   type Track_Array is array (1 .. Max_Tracks) of Track;

   --  L'ensemble des pistes suivies + le prochain ID a attribuer.
   type Tracker is record
      Tracks  : Track_Array;
      Next_Id : Positive := 1;
   end record;

   --  Nombre de detections pour confirmer une piste (le "M" de M-sur-N).
   Confirm_Hits : constant := 3;

   --  Met a jour les pistes avec les cibles d'un nouveau tour (frame
   --  deja regroupee), en quatre temps :
   --    1. PREDICTION : chaque piste avance selon sa vitesse (une piste
   --       non revue "roule sur son erre" au lieu de geler) ;
   --    2. ASSOCIATION par proximite avec les positions PREDITES ;
   --    3. CORRECTION alpha-beta des pistes associees (position et
   --       vitesse lissees : le jitter d'une cible etendue ne part plus
   --       tel quel dans la vitesse) ;
   --    4. VIE ET MORT : confirmation M-sur-N, abandon des pistes
   --       perdues, creation de tentatives pour les detections orphelines.
   procedure Update (T : in out Tracker; F : Frame);

end Radar_Track;
