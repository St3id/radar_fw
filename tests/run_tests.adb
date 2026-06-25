with AUnit.Run;
with AUnit.Reporter.Text;
with AUnit.Test_Suites;  use AUnit.Test_Suites;

with Radar_Sweep_Tests;

procedure Run_Tests is

   --  Construit la suite : on y ajoute notre test case.
   function Suite return Access_Test_Suite is
      S : constant Access_Test_Suite := New_Suite;
   begin
      S.Add_Test (new Radar_Sweep_Tests.Test_Case);
      return S;
   end Suite;

   --  Le moteur qui execute la suite ci-dessus.
   procedure Run is new AUnit.Run.Test_Runner (Suite);

   Reporter : AUnit.Reporter.Text.Text_Reporter;

begin
   Run (Reporter);
end Run_Tests;