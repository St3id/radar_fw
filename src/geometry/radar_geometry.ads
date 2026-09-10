--  Radar_Geometry : passage entre la visee du radar (distance, azimut,
--  elevation) et les coordonnees cartesiennes utilisees par le nuage de
--  points et par le pistage.
--
--  Conventions du projet : les longueurs sont en millimetres, les angles
--  en degres, et le radar occupe l'origine du repere.

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

   --  Conversion inverse de To_Point : d'un point (X, Y, Z) vers sa
   --  direction et sa distance vues depuis le radar. C'est cette
   --  fonction, et non un calcul refait dans les pages HTML, qui fournit
   --  les coordonnees polaires affichees a l'utilisateur.
   function To_Polar (P : Point_3D) return Polar;

end Radar_Geometry;