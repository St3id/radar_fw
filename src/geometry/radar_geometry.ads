package Radar_Geometry is

   --  Un point dans l'espace 3D, en millimetres.
   type Point_3D is record
      X : Float;
      Y : Float;
      Z : Float;
   end record;

   --  Angles de visee, en degres.
   --  Azimut   : rotation horizontale (0 = devant, +90 = a gauche...).
   --  Elevation: inclinaison verticale (0 = horizontal, +90 = vers le haut).
   subtype Degrees is Float range -360.0 .. 360.0;

   --  Convertit une mesure radar (distance + direction) en point 3D.
   function To_Point
     (Distance_Mm : Float;
      Azimuth     : Degrees;
      Elevation   : Degrees)
      return Point_3D;

   --  Resultat de la conversion inverse : ou se trouve un point, vu du radar.
   type Polar is record
      Distance  : Float;    --  distance radar -> point, en mm
      Azimuth   : Float;    --  direction horizontale, en degres
      Elevation : Float;    --  direction verticale, en degres
   end record;

   --  Conversion INVERSE de To_Point : d'un point (X,Y,Z) vers
   --  sa direction et sa distance vues depuis le radar (a l'origine).
   function To_Polar (P : Point_3D) return Polar;
   
end Radar_Geometry;