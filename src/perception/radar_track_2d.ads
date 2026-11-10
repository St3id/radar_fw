with Radar_Planar_Source; use Radar_Planar_Source;
with Radar_Source;        use Radar_Source;

--  Radar_Track_2D : le pistage dans le plan d'un capteur comme le LD2450.
--
--  Un paquet a part plutot que Radar_Track avec z = 0 : ce module ne mesure
--  pas la hauteur, et une altitude nulle passerait pour une mesure.
--
--  Toutes les durees et seuils de Parameters sont des hypotheses : aucun
--  LD2450 reel n'a encore alimente ce filtre.
--
--  Hors SPARK : Float, comme la couche 3D.

package Radar_Track_2D is

   type Track is record
      Id        : Natural := 0;     --  0 tant qu'elle n'est pas confirmee
      X_Mm      : Float   := 0.0;
      Y_Mm      : Float   := 0.0;
      Vx_Mm_S   : Float   := 0.0;
      Vy_Mm_S   : Float   := 0.0;
      Last_Seen : Time_Ms := 0;
      Vel_Stamp : Time_Ms := 0;     --  derniere correction de vitesse
      Hits      : Natural := 0;
      Confirmed : Boolean := False;
      Coasting  : Boolean := False; --  non vue a la derniere trame
      Active    : Boolean := False;
   end record;

   Max_Tracks : constant := 8;

   type Track_Array is array (1 .. Max_Tracks) of Track;

   type Parameters is record
      Confirm_Hits       : Positive := 3;
      Coast_Confirmed_Ms : Time_Ms  := 2_500;
      Coast_Tentative_Ms : Time_Ms  := 900;
      Max_Speed_Mm_S     : Float    := 3_000.0;
      Base_Gate_Mm       : Float    := 600.0;
   end record;

   Default_Parameters : constant Parameters := (others => <>);

   type Tracker is record
      Tracks       : Track_Array;
      Next_Id      : Positive := 1;
      Last_Stamp   : Time_Ms  := 0;
      Started      : Boolean  := False;
      Late_Frames  : Natural  := 0;  --  trames plus vieilles, rejetees
      Clock_Resets : Natural  := 0;  --  sauts d'horloge, pistes effacees
      Dropped      : Natural  := 0;  --  detections sans place libre
   end record;

   --  Meme politique de temps que Radar_Track : trame en retard rejetee et
   --  comptee, saut d'horloge = pistes effacees sans reutiliser d'Id, meme
   --  instant = position corrigee sans inventer de vitesse. Un rapport vide
   --  fait vieillir les pistes.
   procedure Update
     (T : in out Tracker;
      R : Planar_Report;
      P : Parameters := Default_Parameters);

end Radar_Track_2D;
