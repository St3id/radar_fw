with Radar_Geometry; use Radar_Geometry;
with Radar_Source;   use Radar_Source;
with Radar_Sweep;    use Radar_Sweep;

package body Radar_Map_Engine is

   Quick_Az : constant := 60;
   Quick_El : constant := 8;

   procedure Start (M : in out Map_Engine; Az_Steps, El_Steps : Grid_Steps) is
   begin
      Restart_Random;
      M.Quick     := Make_Room_Scan (Quick_Az, Quick_El);
      M.Detail    := Make_Room_Scan (Az_Steps, El_Steps);
      M.Cloud     := Empty_Cloud;
      M.Processed := 0;
      M.Total     := Quick_Az * Quick_El + Az_Steps * El_Steps;
      M.Stage     := Quick_Pass;
   end Start;

   procedure Column (M : in out Map_Engine; Radar : in out Source'Class) is
      S  : Measurement;
      Ok : Boolean;
   begin
      for I in 1 .. Per_Azimuth (Radar) loop
         exit when not Radar.Has_More;
         Radar.Next (S, Ok);
         exit when not Ok;
         M.Processed := M.Processed + 1;
         declare
            D : constant Detection := Detect_Adaptive (S.Data);
         begin
            for K in 1 .. D.Count loop
               Append
                 (M.Cloud,
                  To_Point (Float (Bin_Distance (D.Targets (K))),
                            S.Azimuth, S.Elevation));
            end loop;
         end;
      end loop;
   end Column;

   procedure Step (M : in out Map_Engine) is
   begin
      case M.Stage is
         when Quick_Pass =>
            Column (M, M.Quick);
            if not M.Quick.Has_More then
               M.Stage := Detail_Pass;
            end if;
         when Detail_Pass =>
            Column (M, M.Detail);
            if not M.Detail.Has_More then
               M.Stage := Complete;
            end if;
         when Idle | Complete =>
            null;
      end case;
   end Step;

   function Percent (M : Map_Engine) return Natural is
     (Natural'Min (100, 100 * M.Processed / M.Total));

end Radar_Map_Engine;
