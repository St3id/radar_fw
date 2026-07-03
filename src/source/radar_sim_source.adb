with Radar_Geometry;  use Radar_Geometry;
with Radar_Sweep;     use Radar_Sweep;

package body Radar_Sim_Source is

   Beam_Width : constant Float := 3.0;   --  tolerance azimut (degres)
   El_Width   : constant Float := 5.0;   --  tolerance elevation (degres)

   --  Plage d'elevation balayee : de -30 a +30 degres.
   El_Min : constant Float := -30.0;
   El_Max : constant Float := 30.0;

   --  Ecart angulaire minimal entre deux angles en degres, en tenant
   --  compte du passage 0/360 : l'ecart entre 359 et 1 vaut 2, pas 358.
   function Angle_Diff (A, B : Float) return Float is
      D : constant Float := abs (A - B);
   begin
      if D > 180.0 then
         return 360.0 - D;
      else
         return D;
      end if;
   end Angle_Diff;

   function Distance_To_Bin (Dist : Float) return Bin_Index is
      Mm_Per_Bin : constant Float :=
        Float (Max_Range_Mm) / Float (Sweep_Length);
      Raw : Integer;
   begin
      --  Float'Floor et pas une conversion directe : en Ada, Integer (X)
      --  ARRONDIT au plus proche, alors que la conversion inverse
      --  (Bin_Distance) tronque. Les deux sens doivent partager la meme
      --  convention (debut de tranche), sinon l'aller-retour
      --  distance -> case -> distance derive d'une demi-case.
      Raw := Integer (Float'Floor (Dist / Mm_Per_Bin)) + 1;
      if Raw < Integer (Bin_Index'First) then
         return Bin_Index'First;
      elsif Raw > Integer (Bin_Index'Last) then
         return Bin_Index'Last;
      else
         return Bin_Index (Raw);
      end if;
   end Distance_To_Bin;

   function Make
     (Sweeps   : Positive;
      See_Room : Boolean := False) return Simulated_Source is
   begin
      return (Az_Step      => 0,
              El_Step      => 0,
              Current_Turn => 0,
              Max_Turns    => Sweeps,
              Az_Steps     => Default_Azimuth_Steps,
              El_Steps     => Default_Elevation_Steps,
              See_Room     => See_Room,
              Scene        => Initial_World);
   end Make;

   --------------
   -- Per_Turn --
   --------------

   function Per_Turn (Self : Simulated_Source) return Positive is
   begin
      return Self.Az_Steps * Self.El_Steps;
   end Per_Turn;

   --------------------
   -- Make_Room_Scan --
   --------------------

   function Make_Room_Scan
     (Az_Steps : Grid_Steps := 180;
      El_Steps : Grid_Steps := 24) return Simulated_Source is
   begin
      return (Az_Step      => 0,
              El_Step      => 0,
              Current_Turn => 0,
              Max_Turns    => 1,              --  un seul tour, meticuleux
              Az_Steps     => Az_Steps,
              El_Steps     => El_Steps,
              See_Room     => True,           --  percoit les murs
              Scene        => Empty_World);   --  pas d'objet mobile
   end Make_Room_Scan;

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
           Float (Self.Az_Step) * 360.0 / Float (Self.Az_Steps);
         El : constant Float :=
           El_Min + Float (Self.El_Step)
                    * (El_Max - El_Min) / Float (Self.El_Steps - 1);
         S : Sweep := (others => 5);
      begin
         --  Les murs de la piece (mode cartographie) : un echo a la
         --  distance du premier mur touche dans cette direction.
         if Self.See_Room then
            S (Distance_To_Bin (Wall_Distance (Az, El))) := 2_500;
         end if;

         for I in 1 .. Self.Scene.Count loop
            declare
               O : constant Object := Self.Scene.Objects (I);
               P : constant Point_3D := (O.X, O.Y, O.Z);
               R : constant Polar := To_Polar (P);
            begin
               --  L'objet doit etre dans le faisceau EN AZIMUT ET EN
               --  ELEVATION. L'azimut se compare modulo 360 (Angle_Diff) :
               --  un objet a 359 degres est bien dans le faisceau vise a 0.
               if Angle_Diff (R.Azimuth, Az) < Beam_Width
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
      if Self.El_Step >= Self.El_Steps then
         Self.El_Step := 0;
         Self.Az_Step := Self.Az_Step + 1;

         --  Fin du tour complet (tous azimuts x toutes elevations).
         if Self.Az_Step >= Self.Az_Steps then
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