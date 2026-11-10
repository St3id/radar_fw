with Radar_Geometry; use Radar_Geometry;
with Radar_Sweep;    use Radar_Sweep;

package body Radar_Watch_3D is

   Max_Measures_Per_Step : constant := 120;

   procedure Forget_Tracks (W : in out Watch) is
   begin
      for K of W.Trk.Tracks loop
         K.Active := False;
      end loop;
      for L of W.Trk.Lost loop
         L.Id := 0;
      end loop;
      W.Trk.Next_Id    := 1;
      W.Trk.Last_Stamp := 0;
   end Forget_Tracks;

   procedure Start (W : in out Watch; S : Radar_Settings.Settings) is
   begin
      Restart_Random;
      W.Src         := Make (Sweeps => Positive'Last, See_Room => True);
      Forget_Tracks (W);
      Clear (W.Clut);
      Reset (W.F);
      W.Decor       := Empty_Cloud;
      W.Turn        := 0;
      W.In_Turn     := 0;
      W.Virtual     := 0;
      W.Recal_Asked := False;
      W.Calib       := S.Calibration_Turns;
      W.Learn_Every := S.Learn_Period;
      W.Age_Every   := S.Age_Period;
   end Start;

   procedure One_Measure (W : in out Watch; Radar : in out Source'Class) is
      M  : Measurement;
      Ok : Boolean;
   begin
      Radar.Next (M, Ok);
      if not Ok then
         return;
      end if;
      W.Virtual     := M.Stamp;
      W.F.Stamp     := M.Stamp;
      W.F.Min_Range := Profile_Min_Range;
      W.In_Turn     := W.In_Turn + 1;

      declare
         D : constant Detection := Detect_Adaptive (M.Data);
      begin
         if W.Turn < W.Calib or else W.Turn mod W.Learn_Every = 0 then
            Learn (W.Clut, M.Azimuth, M.Elevation, D);
         end if;

         if W.Turn = 0 then
            for K in 1 .. D.Count loop
               Append
                 (W.Decor,
                  To_Point (Float (Bin_Distance (D.Targets (K))),
                            M.Azimuth, M.Elevation));
            end loop;
         end if;

         if W.Turn >= W.Calib then
            declare
               DF : constant Detection :=
                 Filter (W.Clut, M.Azimuth, M.Elevation, D);
            begin
               for K in 1 .. DF.Count loop
                  exit when W.F.Count = Max_Detections;
                  declare
                     Dist : constant Float :=
                       Float (Bin_Distance (DF.Targets (K)));
                  begin
                     W.F.Count := W.F.Count + 1;
                     W.F.Items (W.F.Count) :=
                       (Pos      => To_Point (Dist, M.Azimuth, M.Elevation),
                        Distance => Dist);
                  end;
               end loop;
            end;
         end if;
      end;

      if W.In_Turn = Per_Turn (Radar) then
         if W.Turn >= W.Calib then
            Update (W.Trk, Cluster (W.F, Owners (W.Trk, W.F)));
         end if;
         if W.Turn > 0 and then W.Turn mod W.Age_Every = 0 then
            Age (W.Clut);
         end if;
         W.Turn    := W.Turn + 1;
         W.In_Turn := 0;
         Reset (W.F);

         if W.Recal_Asked then
            Forget_Tracks (W);
            Clear (W.Clut);
            W.Decor       := Empty_Cloud;
            W.Turn        := 0;
            W.Recal_Asked := False;
         end if;
      end if;
   end One_Measure;

   procedure Step (W : in out Watch; Now : Time_Ms) is
   begin
      for I in 1 .. Max_Measures_Per_Step loop
         exit when W.Virtual >= Now or else not W.Src.Has_More;
         One_Measure (W, W.Src);
      end loop;
   end Step;

   procedure Recalibrate (W : in out Watch) is
   begin
      W.Recal_Asked := True;
   end Recalibrate;

end Radar_Watch_3D;
