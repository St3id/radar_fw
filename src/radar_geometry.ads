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
   subtype Degrees is Float range -180.0 .. 180.0;

   --  Convertit une mesure radar (distance + direction) en point 3D.
   function To_Point
     (Distance_Mm : Float;
      Azimuth     : Degrees;
      Elevation   : Degrees)
      return Point_3D;

end Radar_Geometry;