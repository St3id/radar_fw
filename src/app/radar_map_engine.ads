with Radar_Cloud;      use Radar_Cloud;
with Radar_Sim_Source; use Radar_Sim_Source;

--  Radar_Map_Engine : la cartographie progressive sans serveur. Apercu
--  grossier puis passe detaillee, une colonne d'azimut par Step.

package Radar_Map_Engine with SPARK_Mode => Off is

   type Stage_Kind is (Idle, Quick_Pass, Detail_Pass, Complete);

   type Map_Engine is limited record
      Stage     : Stage_Kind := Idle;
      Quick     : Simulated_Source;
      Detail    : Simulated_Source;
      Cloud     : Point_Cloud;
      Processed : Natural := 0;
      Total     : Natural := 1;
   end record;

   procedure Start (M : in out Map_Engine; Az_Steps, El_Steps : Grid_Steps);
   procedure Step (M : in out Map_Engine);
   function Percent (M : Map_Engine) return Natural;

end Radar_Map_Engine;
