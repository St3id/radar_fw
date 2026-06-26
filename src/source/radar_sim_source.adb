with Radar_Geometry;  use Radar_Geometry;

package body Radar_Sim_Source is

   Beam_Width : constant Float := 3.0;   --  tolerance azimut (degres)
   El_Width   : constant Float := 5.0;   --  tolerance elevation (degres)

   --  Plage d'elevation balayee : de -30 a +30 degres.
   El_Min : constant Float := -30.0;
   El_Max : constant Float := 30.0;

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

   function Make (Sweeps : Positive) return Simulated_Source is
   begin
      return (Az_Step      => 0,
              El_Step      => 0,
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
      if Self.Current_Turn >= Self.Max_Turns then
         Available := False;
         Result    := (Azimuth => 0.0, Elevation => 0.0,
                       Data => (others => 0));
         return;
      end if;

      declare
         --  Direction visee : azimut ET elevation.
         Az : constant Float :=
           Float (Self.Az_Step) * 360.0 / Float (Azimuth_Steps);
         El : constant Float :=
           El_Min + Float (Self.El_Step)
                    * (El_Max - El_Min) / Float (Elevation_Steps - 1);
         S : Sweep := (others => 5);
      begin
         for I in 1 .. Self.Scene.Count loop
            declare
               O : constant Object := Self.Scene.Objects (I);
               P : constant Point_3D := (O.X, O.Y, O.Z);
               R : constant Polar := To_Polar (P);
            begin
               --  L'objet doit etre dans le faisceau EN AZIMUT ET EN ELEVATION.
               if abs (R.Azimuth - Az) < Beam_Width
                 and then abs (R.Elevation - El) < El_Width
               then
                  S (Distance_To_Bin (R.Distance)) := 3_000;
               end if;
            end;
         end loop;

         Result    := (Azimuth => Az, Elevation => El, Data => S);
         Available := True;
      end;

      --  Avancer dans la grille : d'abord l'elevation, puis l'azimut.
      Self.El_Step := Self.El_Step + 1;
      if Self.El_Step >= Elevation_Steps then
         Self.El_Step := 0;
         Self.Az_Step := Self.Az_Step + 1;

         --  Fin du tour complet (tous azimuts x toutes elevations).
         if Self.Az_Step >= Azimuth_Steps then
            Self.Az_Step      := 0;
            Self.Current_Turn := Self.Current_Turn + 1;
            Step (Self.Scene);
         end if;
      end if;
   end Next;

   overriding
   function Has_More (Self : Simulated_Source) return Boolean is
   begin
      return Self.Current_Turn < Self.Max_Turns;
   end Has_More;

end Radar_Sim_Source;