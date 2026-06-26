with Radar_Sweep;  use Radar_Sweep;

package body Radar_Detect is

   -----------
   -- Reset --
   -----------

   procedure Reset (F : in out Frame) is
   begin
      F.Count := 0;
   end Reset;

   ---------
   -- Add --
   ---------

   procedure Add (F : in out Frame; M : Measurement) is
   begin
      --  On n'ajoute que s'il y a une cible et qu'il reste de la place.
      if Has_Target (M.Data) and then F.Count < Max_Detections then
         declare
            --  Distance physique du pic detecte.
            Dist : constant Float := Float (Peak_Distance (M.Data));

            --  Position 3D : on combine la direction visee (azimut,
            --  elevation de la mesure) avec la distance du pic.
            P : constant Point_3D :=
              To_Point (Dist, M.Azimuth, M.Elevation);
         begin
            F.Count := F.Count + 1;
            F.Items (F.Count) := (Pos => P, Distance => Dist);
         end;
      end if;
   end Add;

end Radar_Detect;