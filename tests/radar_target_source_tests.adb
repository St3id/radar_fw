with AUnit.Assertions;       use AUnit.Assertions;
with Radar_Detect;           use Radar_Detect;
with Radar_Source;           use Radar_Source;
with Radar_Target_Source;    use Radar_Target_Source;

package body Radar_Target_Source_Tests is

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Source de detections (contrat, fin de flux)");
   end Name;

   --  Source factice : rejoue une liste fixe de frames, puis plus rien.
   Max_Scripted : constant := 6;

   type Frame_Script is array (1 .. Max_Scripted) of Frame;

   type Fake_Source is new Target_Source with record
      Frames : Frame_Script;
      Count  : Natural  := 0;
      Next   : Positive := 1;
   end record;

   overriding
   procedure Next_Frame
     (Self      : in out Fake_Source;
      Result    : out Frame;
      Available : out Boolean);

   overriding
   function Has_More (Self : Fake_Source) return Boolean;

   --  Items n'a pas de valeur par defaut : on l'initialise ici, sinon la
   --  copie d'une frame partiellement lue lirait des flottants indefinis.
   Blank : constant Frame :=
     (Items     => (others => (Pos      => (X => 0.0, Y => 0.0, Z => 0.0),
                               Distance => 0.0)),
      Count     => 0,
      Stamp     => 0,
      Min_Range => 0.0);

   overriding
   procedure Next_Frame
     (Self      : in out Fake_Source;
      Result    : out Frame;
      Available : out Boolean) is
   begin
      Result    := Blank;
      Available := False;
      if Self.Next <= Self.Count then
         Result    := Self.Frames (Self.Next);
         Available := True;
         Self.Next := Self.Next + 1;
      end if;
   end Next_Frame;

   overriding
   function Has_More (Self : Fake_Source) return Boolean is
     (Self.Next <= Self.Count);

   --  Une frame a N detections, datee St. La distance de la premiere vaut
   --  100 x St : elle sert d'empreinte pour reconnaitre la frame a la sortie.
   function Make (St : Time_Ms; N : Detection_Count) return Frame is
      F : Frame := Blank;
   begin
      F.Stamp := St;
      F.Count := N;
      for I in 1 .. N loop
         F.Items (I).Distance := 100.0 * Float (St) + Float (I - 1);
      end loop;
      return F;
   end Make;

   --  Trois frames dont une vide au milieu : une frame vide est une
   --  observation valide, elle ne doit ni disparaitre ni finir le flux.
   function Three_Frames return Fake_Source is
      S : Fake_Source :=
        (Frames => (others => Blank), Count => 3, Next => 1);
   begin
      S.Frames (1) := Make (100, 2);
      S.Frames (2) := Make (200, 0);
      S.Frames (3) := Make (300, 1);
      return S;
   end Three_Frames;

   --  Le client ne connait que l'interface : tout passe par Src'Class.
   procedure Pull
     (Src : in out Target_Source'Class;
      F   : out Frame;
      Ok  : out Boolean) is
   begin
      Next_Frame (Src, F, Ok);
   end Pull;

   --  Les frames sortent dans l'ordre de la liste, chacune entiere, avec des
   --  heures strictement croissantes.
   procedure Test_Order_And_Stamps
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Src       : Fake_Source := Three_Frames;
      Expected  : constant Frame_Script :=
        (1 => Make (100, 2), 2 => Make (200, 0), 3 => Make (300, 1),
         others => Blank);
      F         : Frame;
      Ok        : Boolean;
      Last_Time : Time_Ms := 0;
      Got       : Natural := 0;
   begin
      while Has_More (Src) loop
         Pull (Src, F, Ok);
         Assert (Ok, "Has_More vrai mais pas de frame");
         Got := Got + 1;
         Assert (Got <= 3, "plus de frames que dans la liste");
         Assert (F.Stamp = Expected (Got).Stamp,
                 "heure de la frame" & Got'Image);
         Assert (F.Stamp > Last_Time,
                 "heures non croissantes a la frame" & Got'Image);
         Assert (F.Count = Expected (Got).Count,
                 "nombre de detections de la frame" & Got'Image);
         for I in 1 .. F.Count loop
            Assert (F.Items (I).Distance = Expected (Got).Items (I).Distance,
                    "detection" & I'Image & " de la frame" & Got'Image);
         end loop;
         Last_Time := F.Stamp;
      end loop;
      Assert (Got = 3, "frames livrees :" & Got'Image & " au lieu de 3");
   end Test_Order_And_Stamps;

   --  Fin de flux : Has_More tombe a False apres la derniere frame, et pas
   --  avant ; ensuite Next_Frame ne rend plus rien, autant de fois qu'on
   --  l'appelle, et ne fabrique aucune frame.
   procedure Test_End_Of_Stream
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Src : Fake_Source := Three_Frames;
      F   : Frame;
      Ok  : Boolean;
   begin
      for K in 1 .. 3 loop
         Assert (Has_More (Src), "fin annoncee trop tot, avant la frame"
                 & K'Image);
         Pull (Src, F, Ok);
         Assert (Ok, "frame" & K'Image & " absente");
      end loop;
      Assert (not Has_More (Src), "Has_More encore vrai apres la derniere");

      for K in 1 .. 2 loop
         Pull (Src, F, Ok);
         Assert (not Ok, "frame fabriquee apres la fin, appel" & K'Image);
         Assert (not Has_More (Src), "Has_More revenu apres la fin");
      end loop;
   end Test_End_Of_Stream;

   --  Une source vide est deja finie : zero frame, pas de boucle infinie.
   procedure Test_Empty_Source
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Src : Fake_Source := (Frames => (others => Blank), Count => 0, Next => 1);
      F   : Frame;
      Ok  : Boolean;
   begin
      Assert (not Has_More (Src), "source vide annoncee non finie");
      Pull (Src, F, Ok);
      Assert (not Ok, "frame livree par une source vide");
   end Test_Empty_Source;

   overriding
   procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Order_And_Stamps'Access,
         "Les frames sortent dans l'ordre, heures croissantes");
      Register_Routine
        (T, Test_End_Of_Stream'Access, "La fin de flux est signalee");
      Register_Routine
        (T, Test_Empty_Source'Access, "Une source vide est finie");
   end Register_Tests;

end Radar_Target_Source_Tests;
