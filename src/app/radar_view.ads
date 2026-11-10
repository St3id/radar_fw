with Radar_Geometry; use Radar_Geometry;

--  Radar_View : ou placer chaque chose a l'ecran, et ce que designe un clic.
--  Aucun dessin ici : Cairo aujourd'hui, OpenGL un jour, meme geometrie.

package Radar_View with SPARK_Mode => Off is

   type Screen_Point is record
      X : Float := 0.0;
      Y : Float := 0.0;
   end record;

   type Screen_Array is array (Positive range <>) of Screen_Point;

   --  ----- Le plan, repere du capteur : X a droite, Y devant, en mm -----

   type Plan is record
      Width    : Float   := 800.0;
      Height   : Float   := 600.0;
      Range_Mm : Float   := 8_000.0;
      Around   : Boolean := False;   --  True : capteur au centre, 360 deg
   end record;

   function Scale (P : Plan) return Float;           --  pixels par mm
   function Origin (P : Plan) return Screen_Point;   --  le capteur a l'ecran

   function To_Screen (P : Plan; X_Mm, Y_Mm : Float) return Screen_Point;
   function To_Plan_X (Pos : Point_3D) return Float is (-Pos.Y);
   function To_Plan_Y (Pos : Point_3D) return Float is (Pos.X);

   --  ----- La vue 3D : X devant, Y a gauche, Z en haut, en mm -----

   type Camera is record
      Yaw      : Float := 3.5;       --  radians autour de Z, depuis +X
      Pitch    : Float := 0.5;       --  radians au-dessus de l'horizon
      Distance : Float := 11_000.0;
   end record;

   type Projected is record
      S       : Screen_Point;
      Depth   : Float   := 0.0;
      Visible : Boolean := False;    --  devant la camera
   end record;

   function Project
     (C : Camera; Width, Height : Float; P : Point_3D) return Projected;

   --  ----- Le clic -----

   --  L'indice du point le plus proche de Mouse a moins de Max_Px, 0 sinon.
   function Nearest
     (Points : Screen_Array;
      Mouse  : Screen_Point;
      Max_Px : Float) return Natural;

   --  Etiquette courte (Id seul) quand un voisin est plus pres que Min_Px :
   --  ID + distance + vitesse se chevaucheraient.
   function Crowded
     (Points : Screen_Array;
      Index  : Positive;
      Min_Px : Float) return Boolean;

end Radar_View;
