with Radar_Geometry;  use Radar_Geometry;

package body Radar_Sim_Source is

   Beam_Width : constant Float := 3.0;

   function Distance_To_Bin (Dist : Float) return Bin_Index is
      Mm_Per_Bin : constant Float :=
        Float (Max_Range_Mm) / Float (Sweep_Length);
      Raw : Integer;
   begin
      Raw := Integer (Dist / Mm_Per_Bin) + 1;
      if Raw < Integer (Bin_Index'First) then
         return Bin_Index'First;
      elsif Raw > Integer (Bin_Index'Last) then
         return Bin_Index'Last;
      else
         return Bin_Index (Raw);
      end if;
   end Distance_To_Bin;

   ----------
   -- Make --
   ----------

   function Make (Sweeps : Positive) return Simulated_Source is
   begin
      return (Step         => 0,
              Current_Turn => 0,
              Max_Turns    => Sweeps,
              Scene        => Initial_World);
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
      --  Plus de tours a faire : termine.
      if Self.Current_Turn >= Self.Max_Turns then
         Available := False;
         Result    := (Azimuth => 0.0, Elevation => 0.0,
                       Data => (others => 0));
         return;
      end if;

      declare
         Az : constant Float :=
           Float (Self.Step) * 360.0 / Float (Total_Steps);
         S : Sweep := (others => 5);
      begin
         for I in 1 .. Self.Scene.Count loop
            declare
               O : constant Object := Self.Scene.Objects (I);
               P : constant Point_3D := (O.X, O.Y, O.Z);
               R : constant Polar := To_Polar (P);
            begin
               if abs (R.Azimuth - Az) < Beam_Width then
                  S (Distance_To_Bin (R.Distance)) := 3_000;
               end if;
            end;
         end loop;

         Result    := (Azimuth => Az, Elevation => 0.0, Data => S);
         Available := True;
      end;

      --  On avance dans le tour.
      Self.Step := Self.Step + 1;

      --  Fin du tour : on passe au suivant et on FAIT AVANCER LE MONDE.
      if Self.Step >= Total_Steps then
         Self.Step         := 0;
         Self.Current_Turn := Self.Current_Turn + 1;
         Step (Self.Scene);   --  les objets se deplacent d'un pas de temps
      end if;
   end Next;

   --------------
   -- Has_More --
   --------------

   overriding
   function Has_More (Self : Simulated_Source) return Boolean is
   begin
      return Self.Current_Turn < Self.Max_Turns;
   end Has_More;

end Radar_Sim_Source;