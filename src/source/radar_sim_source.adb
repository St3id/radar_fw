package body Radar_Sim_Source is

   --  Position (azimut) de notre objet simule, en degres.
   Object_Azimuth : constant Float := 90.0;
   --  Case (distance) ou se trouve l'objet dans le balayage.
   Object_Bin     : constant Bin_Index := 100;

   ----------
   -- Make --
   ----------

   function Make return Simulated_Source is
   begin
      return (Step => 0);
   end Make;

   ----------
   -- Next --
   ----------

   overriding
   procedure Next
     (Self      : in out Simulated_Source;
      Result    : out Measurement;
      Available : out Boolean)
   is
   begin
      if Self.Step >= Total_Steps then
         --  Balayage termine : plus rien a fournir.
         Available := False;
         Result    := (Azimuth => 0.0, Elevation => 0.0,
                       Data => (others => 0));
         return;
      end if;

      declare
         --  Direction visee pour ce pas : un tour complet sur 360 degres.
         Az : constant Float :=
           Float (Self.Step) * 360.0 / Float (Total_Steps);

         --  On part d'un balayage vide (bruit de fond leger).
         S : Sweep := (others => 5);
      begin
         --  Si le radar pointe (a peu pres) vers l'objet, on place un echo.
         if abs (Az - Object_Azimuth) < 3.0 then
            S (Object_Bin) := 3_000;
         end if;

         Result    := (Azimuth => Az, Elevation => 0.0, Data => S);
         Available := True;
      end;

      Self.Step := Self.Step + 1;
   end Next;

   --------------
   -- Has_More --
   --------------

   overriding
   function Has_More (Self : Simulated_Source) return Boolean is
   begin
      return Self.Step < Total_Steps;
   end Has_More;

end Radar_Sim_Source;