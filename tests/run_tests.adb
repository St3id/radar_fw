with Ada.Command_Line;
with AUnit.Run;
with AUnit.Reporter.Text;
with AUnit.Test_Suites;  use AUnit.Test_Suites;

with Radar_Sweep_Tests;
with Radar_Pipeline_Tests;
with Radar_Sar_Tests;
with Radar_Ld2450_Tests;
with Radar_Ld2450_Stream_Tests;
with Radar_Dwell_Tests;

--  Lanceur des tests : construit la suite complete et rend un code de
--  sortie non nul si un seul cas echoue (assertion fausse ou exception
--  inattendue), ce qui suffit a faire echouer l'integration continue.
--  Test_Runner_With_Status et non Test_Runner : ce dernier calcule le
--  meme verdict mais le jette, et le programme sortait en 0 malgre des
--  echecs (constate le 2026-10-11).

procedure Run_Tests is

   use type AUnit.Status;

   --  Construit la suite : on y ajoute nos test cases.
   function Suite return Access_Test_Suite is
      S : constant Access_Test_Suite := New_Suite;
   begin
      S.Add_Test (new Radar_Sweep_Tests.Test_Case);
      S.Add_Test (new Radar_Pipeline_Tests.Test_Case);
      S.Add_Test (new Radar_Sar_Tests.Test_Case);
      S.Add_Test (new Radar_Ld2450_Tests.Test_Case);
      S.Add_Test (new Radar_Ld2450_Stream_Tests.Test_Case);
      S.Add_Test (new Radar_Dwell_Tests.Test_Case);
      return S;
   end Suite;

   --  Le moteur qui execute la suite ci-dessus et rend son verdict.
   function Run is new AUnit.Run.Test_Runner_With_Status (Suite);

   Reporter : AUnit.Reporter.Text.Text_Reporter;

begin
   if Run (Reporter) = AUnit.Failure then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Run_Tests;
