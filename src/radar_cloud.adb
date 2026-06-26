with Ada.Numerics;                      use Ada.Numerics;
with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;

package body Radar_Cloud is

   --  Simule la distance jusqu'au mur d'une piece rectangulaire,
   --  pour une direction donnee (azimut). La piece fait 4000 x 3000 mm,
   --  le radar est au centre. On cherche quel mur on touche en premier.
   function Wall_Distance (Az_Rad : Float) return Float is
      Half_X : constant Float := 2000.0;   --  demi-largeur (mur a +/- 2000)
      Half_Y : constant Float := 1500.0;   --  demi-profondeur (mur a +/- 1500)

      Cos_A : constant Float := Cos (Az_Rad);
      Sin_A : constant Float := Sin (Az_Rad);

      Dist_X : Float := Float'Last;
      Dist_Y : Float := Float'Last;
   begin
      --  Distance pour toucher un mur vertical (gauche/droite).
      if abs Cos_A > 0.0001 then
         Dist_X := Half_X / abs Cos_A;
      end if;
      --  Distance pour toucher un mur horizontal (avant/arriere).
      if abs Sin_A > 0.0001 then
         Dist_Y := Half_Y / abs Sin_A;
      end if;

      --  On touche le mur le plus proche.
      return Float'Min (Dist_X, Dist_Y);
   end Wall_Distance;

   ---------------
   -- Scan_Room --
   ---------------

   function Scan_Room return Point_Cloud is
      Cloud : Point_Cloud := (Points => (others => (0.0, 0.0, 0.0)),
                              Count  => 0);
   begin
      for Ai in 0 .. Azimuth_Steps - 1 loop
         for Ei in 0 .. Elevation_Steps - 1 loop

            declare
               --  Azimut : tour complet (0 a 360 degres).
               Az : constant Float :=
                 Float (Ai) * 360.0 / Float (Azimuth_Steps);
               --  Elevation : de -30 a +30 degres.
               El : constant Float :=
                 -30.0 + Float (Ei) * 60.0 / Float (Elevation_Steps - 1);

               Az_Rad : constant Float := Az * Pi / 180.0;
               El_Rad : constant Float := El * Pi / 180.0;

               --  Distance au mur, ajustee par l'elevation
               --  (plus on vise haut/bas, plus le trajet est long).
               Base_Dist : constant Float := Wall_Distance (Az_Rad);
               Dist      : constant Float := Base_Dist / Cos (El_Rad);
            begin
               Cloud.Count := Cloud.Count + 1;
               Cloud.Points (Cloud.Count) := To_Point (Dist, Az, El);
            end;

         end loop;
      end loop;

      return Cloud;
   end Scan_Room;

end Radar_Cloud;