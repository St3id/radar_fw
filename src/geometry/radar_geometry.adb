with Ada.Numerics;                     use Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
use  Ada.Numerics.Elementary_Functions;

package body Radar_Geometry is

   --------------
   -- To_Point --
   --------------

   function To_Point
     (Distance_Mm : Float;
      Azimuth     : Degrees;
      Elevation   : Degrees)
      return Point_3D
   is
      --  Les fonctions trigo travaillent en radians : on convertit.
      Az_Rad : constant Float := Azimuth   * Pi / 180.0;
      El_Rad : constant Float := Elevation * Pi / 180.0;

      --  Projection horizontale (la distance "vue de dessus").
      Horizontal : constant Float := Distance_Mm * Cos (El_Rad);
   begin
      return (X => Horizontal * Cos (Az_Rad),
              Y => Horizontal * Sin (Az_Rad),
              Z => Distance_Mm * Sin (El_Rad));
   end To_Point;

   --------------
   -- To_Polar --
   --------------

   function To_Polar (P : Point_3D) return Polar is
      --  Distance totale (norme du vecteur).
      Dist : constant Float := Sqrt (P.X * P.X + P.Y * P.Y + P.Z * P.Z);

      Az : Float := 0.0;
      El : Float := 0.0;
   begin
      --  Azimut : angle horizontal dans le plan X-Y.
      --  Arctan(Y, X) gere tous les quadrants et le cas X=0.
      if P.X /= 0.0 or else P.Y /= 0.0 then
         Az := Arctan (P.Y, P.X) * 180.0 / Pi;
         --  Ramener l'angle dans [0, 360[ : un azimut negatif (ex. -143)
         --  designe la meme direction que +217. Le radar balaie 0..360,
         --  donc on normalise pour que la correspondance fonctionne.
         if Az < 0.0 then
            Az := Az + 360.0;
         end if;
      end if;

      --  Elevation : angle vertical (hauteur Z par rapport a la distance).
      if Dist > 0.0 then
         El := Arcsin (P.Z / Dist) * 180.0 / Pi;
      end if;

      return (Distance => Dist, Azimuth => Az, Elevation => El);
   end To_Polar;

end Radar_Geometry;