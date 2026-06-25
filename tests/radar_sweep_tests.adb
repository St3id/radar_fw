with AUnit.Assertions;  use AUnit.Assertions;
with Radar_Sweep;       use Radar_Sweep;

package body Radar_Sweep_Tests is

   ----------
   -- Name --
   ----------

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Radar_Sweep : detection de pic et de cible");
   end Name;

   --  Test 1 : un pic net en case 64 doit etre detecte au bon endroit.
   procedure Test_Peak_Detection (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      S : Sweep := (others => 10);
   begin
      S (64) := 3_000;

      Assert (Peak_Bin (S) = 64,
              "Le pic devrait etre detecte en case 64");
      Assert (Has_Target (S),
              "Une cible devrait etre detectee");
   end Test_Peak_Detection;

   --  Test 2 : du bruit faible partout ne doit PAS donner de cible.
   procedure Test_No_Target (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      S : constant Sweep := (others => 10);
   begin
      Assert (not Has_Target (S),
              "Le bruit seul ne devrait pas declencher de cible");
   end Test_No_Target;

--  Test 3 : trois cibles posees doivent etre toutes les trois detectees.
   procedure Test_Multi_Target (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      S : Sweep := (others => 10);
   begin
      S (40)  := 1_500;
      S (128) := 2_800;
      S (200) := 900;

      declare
         D : constant Detection := Detect_All (S);
      begin
         Assert (D.Count = 3,
                 "On devrait detecter exactement 3 cibles");
         Assert (D.Targets (1) = 40,
                 "La 1re cible devrait etre en case 40");
         Assert (D.Targets (2) = 128,
                 "La 2e cible devrait etre en case 128");
         Assert (D.Targets (3) = 200,
                 "La 3e cible devrait etre en case 200");
      end;
   end Test_Multi_Target;

   --------------------
   -- Register_Tests --
   --------------------

   overriding
   procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Multi_Target'Access, "Detection multi-cibles");
      Register_Routine (T, Test_Peak_Detection'Access, "Detection du pic");
      Register_Routine (T, Test_No_Target'Access, "Absence de cible");
   end Register_Tests;

end Radar_Sweep_Tests;