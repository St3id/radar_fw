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

end Radar_Geometry;