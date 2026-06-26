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