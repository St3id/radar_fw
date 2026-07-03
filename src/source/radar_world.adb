with Ada.Numerics;                      use Ada.Numerics;
with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;

package body Radar_World is

   -------------------
   -- Initial_World --
   -------------------

   function Initial_World return World is
      W : World := (Objects => (others => (Id => 1, others => 0.0)),
                    Count   => 0);
   begin
      --  Objet 1 : part a droite, avance vers la gauche.
      W.Objects (1) := (Id => 1,
                        X  => 3000.0, Y => 1000.0, Z => 0.0,
                        Vx => -120.0, Vy => 0.0,    Vz => 0.0);

      --  Objet 2 : part en bas, monte lentement.
      W.Objects (2) := (Id => 2,
                        X  => -2000.0, Y => -1500.0, Z => 500.0,
                        Vx => 0.0,     Vy => 80.0,   Vz => 0.0);

      W.Count := 2;
      return W;
   end Initial_World;

   -----------------
   -- Empty_World --
   -----------------

   function Empty_World return World is
   begin
      return (Objects => (others => (Id => 1, others => 0.0)),
              Count   => 0);
   end Empty_World;

   -------------------
   -- Wall_Distance --
   -------------------

   function Wall_Distance (Azimuth_Deg, Elevation_Deg : Float) return Float is
      Az_Rad : constant Float := Azimuth_Deg   * Pi / 180.0;
      El_Rad : constant Float := Elevation_Deg * Pi / 180.0;

      Cos_A : constant Float := Cos (Az_Rad);
      Sin_A : constant Float := Sin (Az_Rad);

      Dist_X : Float := Float'Last;
      Dist_Y : Float := Float'Last;
   begin
      --  Distance (vue de dessus) pour toucher un mur vertical
      --  (gauche/droite), puis un mur horizontal (avant/arriere).
      if abs Cos_A > 0.0001 then
         Dist_X := Room_Half_X / abs Cos_A;
      end if;
      if abs Sin_A > 0.0001 then
         Dist_Y := Room_Half_Y / abs Sin_A;
      end if;

      --  On touche le mur le plus proche ; viser haut ou bas allonge le
      --  trajet (elevation supposee < 90 degres : cos > 0).
      return Float'Min (Dist_X, Dist_Y) / Cos (El_Rad);
   end Wall_Distance;

   ----------
   -- Step --
   ----------

   procedure Step (W : in out World) is
   begin
      --  Chaque objet avance d'un pas : position += vitesse.
      for I in 1 .. W.Count loop
         W.Objects (I).X := W.Objects (I).X + W.Objects (I).Vx;
         W.Objects (I).Y := W.Objects (I).Y + W.Objects (I).Vy;
         W.Objects (I).Z := W.Objects (I).Z + W.Objects (I).Vz;
      end loop;
   end Step;

end Radar_World;