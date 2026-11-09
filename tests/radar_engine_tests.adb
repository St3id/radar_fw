with AUnit.Assertions;     use AUnit.Assertions;
with Radar_Engine;         use Radar_Engine;
with Radar_Planar_Source;  use Radar_Planar_Source;
with Radar_Source;         use Radar_Source;

package body Radar_Engine_Tests is

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Moteur de la console (cadence, silences, fin)");
   end Name;

   --  Une fausse source qui deroule un scenario ecrit a la main : Stamp = 0
   --  y marque un silence, les vraies trames des tests sont datees apres 0.
   type Script is array (1 .. 8) of Time_Ms;

   type Fake_Source is new Planar_Source with record
      Steps : Script := (others => 0);
      Count : Natural := 0;
      Next  : Positive := 1;
   end record;

   overriding
   procedure Next_Report
     (Self      : in out Fake_Source;
      Result    : out Planar_Report;
      Available : out Boolean);

   overriding
   function Has_More (Self : Fake_Source) return Boolean;

   overriding
   procedure Next_Report
     (Self      : in out Fake_Source;
      Result    : out Planar_Report;
      Available : out Boolean) is
   begin
      Result    := (others => <>);
      Available := False;
      if Self.Next <= Self.Count then
         if Self.Steps (Self.Next) /= 0 then
            Result.Stamp := Self.Steps (Self.Next);
            Available    := True;
         end if;
         Self.Next := Self.Next + 1;
      end if;
   end Next_Report;

   overriding
   function Has_More (Self : Fake_Source) return Boolean is
     (Self.Next <= Self.Count);

   procedure Check
     (E      : Engine;
      State  : Engine_State;
      Frames : Natural;
      Stamp  : Time_Ms;
      Where  : String)
   is
      S : constant Snapshot := Last (E);
   begin
      Assert (S.State = State, Where & " : etat");
      Assert (S.Frames_Shown = Frames, Where & " : nombre de trames");
      Assert (S.Has_Report = (Frames > 0), Where & " : presence d'un rapport");
      if Frames > 0 then
         Assert (S.Last_Report.Stamp = Stamp, Where & " : heure du rapport");
      end if;
   end Check;

   --  Une trame sort a son heure, pas avant, et une seule fois.
   procedure Test_Waits_For_Stamp
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Src : Fake_Source :=
        (Steps => (100, 200, others => 0), Count => 2, Next => 1);
      E   : Engine;
   begin
      Check (E, Stopped, 0, 0, "avant Start");
      Step (E, Src, 500);
      Check (E, Stopped, 0, 0, "Step sans Start");

      Start (E);
      Step (E, Src, 50);
      Check (E, Running, 0, 0, "avant la premiere heure");
      Step (E, Src, 50);
      Check (E, Running, 0, 0, "toujours en attente");
      Step (E, Src, 100);
      Check (E, Running, 1, 100, "a la premiere heure");
      Step (E, Src, 150);
      Check (E, Running, 1, 100, "entre deux heures");
      Step (E, Src, 200);
      Check (E, Running, 2, 200, "a la seconde heure");
   end Test_Waits_For_Stamp;

   --  Toutes les trames passent, sans perte ni doublon. Des trames de meme
   --  heure sortent une par appel : c'est le cas d'un bloc recu d'un coup.
   procedure Test_Every_Frame_Once
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Src : Fake_Source :=
        (Steps => (100, 200, 300, 400, 500, others => 0),
         Count => 5,
         Next  => 1);
      Burst : Fake_Source :=
        (Steps => (100, 100, 100, others => 0), Count => 3, Next => 1);
      E      : Engine;
      Now    : Time_Ms := 0;
      Before : Natural := 0;
   begin
      Start (E);
      while Now <= 2_000 and then Last (E).State = Running loop
         Step (E, Src, Now);
         Assert (Last (E).Frames_Shown in Before | Before + 1,
                 "au plus une trame par appel");
         Before := Last (E).Frames_Shown;
         Now    := Now + 10;
      end loop;
      Check (E, Finished, 5, 500, "fin du scenario");

      Start (E);
      Step (E, Burst, 100);
      Check (E, Running, 1, 100, "rafale, appel 1");
      Step (E, Burst, 100);
      Check (E, Running, 2, 100, "rafale, appel 2");
      Step (E, Burst, 100);
      Check (E, Running, 3, 100, "rafale, appel 3");
      Step (E, Burst, 100);
      Check (E, Finished, 3, 100, "rafale, fin");
   end Test_Every_Frame_Once;

   --  Un silence ne termine rien et ne fabrique aucune donnee.
   procedure Test_Silence_Is_Not_The_End
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Src : Fake_Source :=
        (Steps => (100, 0, 300, others => 0), Count => 3, Next => 1);
      E   : Engine;
   begin
      Start (E);
      Step (E, Src, 100);
      Check (E, Running, 1, 100, "avant le silence");
      Step (E, Src, 150);
      Check (E, Running, 1, 100, "pendant le silence");
      Step (E, Src, 300);
      Check (E, Running, 2, 300, "apres le silence");
      Step (E, Src, 310);
      Check (E, Finished, 2, 300, "vraie fin");
      Step (E, Src, 900);
      Check (E, Finished, 2, 300, "rien apres la fin");
   end Test_Silence_Is_Not_The_End;

   overriding
   procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Waits_For_Stamp'Access, "Une trame attend son heure");
      Register_Routine
        (T, Test_Every_Frame_Once'Access, "Chaque trame passe une fois");
      Register_Routine
        (T, Test_Silence_Is_Not_The_End'Access, "Un silence n'est pas la fin");
   end Register_Tests;

end Radar_Engine_Tests;
