with Ada.Text_IO;            use Ada.Text_IO;
with Ada.Calendar;          use Ada.Calendar;
with Radar_Sweep;           use Radar_Sweep;
with Radar_Sim;             use Radar_Sim;
with Radar_Display;         use Radar_Display;

procedure Radar_Fw is

   Frames : constant := 12;   --  nombre d'images

   --  Petite pause entre deux images (effet "temps reel").
   procedure Wait (Seconds : Duration) is
      Start : constant Time := Clock;
   begin
      loop
         exit when Clock - Start >= Seconds;
      end loop;
   end Wait;

   S : Sweep;
begin
   for F in 1 .. Frames loop

      --  Une cible FIXE (case 180) et une cible MOBILE qui se rapproche :
      --  elle part de la case 240 et avance de ~18 cases par image.
      declare
         Moving_Pos : constant Bin_Index :=
           Bin_Index (Integer'Max (10, 240 - (F - 1) * 18));

         Scene : constant Target_List :=
           (1 => (Position => 180,        Strength => 2_200),   --  fixe
            2 => (Position => Moving_Pos, Strength => 3_500));   --  mobile
      begin
         --  Noise_Level eleve => bruit de fond bien visible a l'ecran.
         S := Generate (Scene, Noise_Level => 1_200);

         Put_Line ("===== Image" & F'Image & " /" & Frames'Image
                   & "  (cible mobile en case" & Moving_Pos'Image & ") =====");
         Show (S);
      end;

      Wait (0.5);
   end loop;

   Put_Line ("Fin de la simulation.");
end Radar_Fw;