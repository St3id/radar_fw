with Radar_Geometry;  use Radar_Geometry;

package body Radar_Sim_Source is

   --  Tolerance angulaire : un objet est "vu" si le radar pointe a moins
   --  de cette valeur (en degres) de sa direction.
   Beam_Width : constant Float := 3.0;

   --  Convertit une distance physique (mm) en numero de case du balayage.
   function Distance_To_Bin (Dist : Float) return Bin_Index is
      Mm_Per_Bin : constant Float :=
        Float (Max_Range_Mm) / Float (Sweep_Length);
      Raw : Integer;
   begin
      Raw := Integer (Dist / Mm_Per_Bin) + 1;
      --  On borne dans l'intervalle valide des cases.
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

   function Make return Simulated_Source is
   begin
      return (Step => 0, Scene => Initial_World);
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
         Available := False;
         Result    := (Azimuth => 0.0, Elevation => 0.0,
                       Data => (others => 0));
         return;
      end if;

      declare
         --  Direction visee pour ce pas.
         Az : constant Float :=
           Float (Self.Step) * 360.0 / Float (Total_Steps);

         --  Balayage vide (bruit de fond leger).
         S : Sweep := (others => 5);
      begin
         --  Pour chaque objet reel, on regarde s'il tombe dans le faisceau.
         for I in 1 .. Self.Scene.Count loop
            declare
               O : constant Object := Self.Scene.Objects (I);
               P : constant Point_3D := (O.X, O.Y, O.Z);
               R : constant Polar := To_Polar (P);
            begin
               --  L'objet est-il (a peu pres) dans la direction visee ?
               if abs (R.Azimuth - Az) < Beam_Width then
                  --  Oui : on place un echo a la case correspondant
                  --  a sa distance.
                  S (Distance_To_Bin (R.Distance)) := 3_000;
               end if;
            end;
         end loop;

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