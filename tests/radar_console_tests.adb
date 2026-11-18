--  Memes octets UTF-8 que radar_modes.adb.
pragma Wide_Character_Encoding (BRACKETS);

with Ada.Directories;
with Ada.Numerics.Elementary_Functions;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;   use Ada.Strings.Unbounded;
with Ada.Text_IO;
with AUnit.Assertions;        use AUnit.Assertions;
with Radar_Cloud;
with Radar_Engine;
with Radar_Geometry;          use Radar_Geometry;
with Radar_Ld2450;
with Radar_Ld2450_Log;        use Radar_Ld2450_Log;
with Radar_Ld2450_Replay;     use Radar_Ld2450_Replay;
with Radar_Ld2450_Sim_Source; use Radar_Ld2450_Sim_Source;
with Radar_Ld2450_Stream;
with Radar_Map_Engine;
with Radar_Modes;             use Radar_Modes;
with Radar_Planar_Source;     use Radar_Planar_Source;
with Radar_Settings;
with Radar_Source;            use Radar_Source;
with Radar_Track;
with Radar_Track_2D;
with Radar_View;
with Radar_Watch_3D;

package body Radar_Console_Tests is

   package Log renames Radar_Ld2450_Log;
   package T2 renames Radar_Track_2D;
   use type Radar_Ld2450_Stream.Counter;
   use type Radar_Map_Engine.Stage_Kind;
   use type Radar_Engine.Engine_State;

   Test_Dir : constant String := "out/tests";
   Path     : constant String := Test_Dir & "/console.ld2450";

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Console sans GTK (pistage 2D, reglages, vues)");
   end Name;

   procedure Prepare is
   begin
      Ada.Directories.Create_Path (Test_Dir);
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   end Prepare;

   procedure Write_Raw (Head : String) is
      use Ada.Streams;
      F     : Stream_IO.File_Type;
      Bytes : Stream_Element_Array (1 .. Head'Length);
   begin
      for I in Bytes'Range loop
         Bytes (I) :=
           Character'Pos (Head (Head'First + Integer (I) - 1));
      end loop;
      Stream_IO.Create (F, Stream_IO.Out_File, Path);
      Stream_IO.Write (F, Bytes);
      Stream_IO.Close (F);
   end Write_Raw;

   --  L'origine ecrite se relit ; un ancien fichier reste lisible et inconnu ;
   --  un octet d'origine qui n'existe pas fait refuser le fichier.
   procedure Test_Origin (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Ok : Boolean;
      S  : Replay_Source;
   begin
      Prepare;
      for O in Origin_Emulated .. Origin_Hardware loop
         declare
            W : Log.Writer;
         begin
            Create (W, Path, O, Ok);
            Assert (Ok, "fichier cree");
            Close (W);
         end;
         Open (S, Path, Ok => Ok);
         Assert (Ok and then Origin (S) = O, "origine relue");
      end loop;

      Write_Raw (Magic_V1);
      Open (S, Path, Ok => Ok);
      Assert (Ok and then Origin (S) = Origin_Unknown, "ancien format");

      Write_Raw (Magic & Character'Val (7));
      Open (S, Path, Ok => Ok);
      Assert (not Ok, "octet d'origine inconnu");
   end Test_Origin;

   --  Ce qui s'affiche depend de l'origine, pas du mode de lecture.
   procedure Test_Truth (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Is_Simulated (Capture_File, Origin_Emulated), "fichier emule");
      Assert (not Is_Simulated (Capture_File, Origin_Hardware), "fichier reel");
      Assert (not Is_Simulated (Capture_File, Origin_Unknown), "fichier inconnu");
      Assert (Source_Text (Capture_File, Origin_Unknown)
              = "Fichier - provenance non prouvée", "texte inconnu");
      Assert (Source_Text (Capture_File, Origin_Emulated) = "Fichier - SIMULÉ",
              "texte emule");
      Assert (Allowed (Sim_Ld2450, Watch), "veille LD2450");
      Assert (not Allowed (Sim_Ld2450, Mapping), "pas de carte au LD2450");
      Assert (Reason (Sensor_Serial, Mapping) /= "", "motif affiche");
      Assert (Allowed (Sim_Profiles, Sar_Analysis), "SAR sur profils");
      Assert (not Allowed (Capture_File, Sar_Analysis), "pas de SAR sur fichier");
   end Test_Truth;

   --  Critere du premier jalon : autant de trames montrees que decodees, sur
   --  une capture ecrite par l'emulateur, et le rejeu reste marque emule.
   procedure Test_Capture_Replay (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Live : Live_Source := Make;
      R    : Planar_Report;
      Av   : Boolean;
      Ok   : Boolean;
      Sent : Natural := 0;
   begin
      Prepare;

      --  Enregistrement commence en route : le fichier doit partir de zero.
      for I in 1 .. 30 loop
         Next_Report (Live, R, Av);
      end loop;

      Start_Recording (Live, Path, Ok);
      Assert (Ok and then Is_Recording (Live), "enregistrement ouvert");
      for I in 1 .. 200 loop
         Next_Report (Live, R, Av);
         if Av then
            Sent := Sent + 1;
         end if;
      end loop;
      Stop_Recording (Live);
      Assert (not Is_Recording (Live), "enregistrement ferme");
      Assert (Sent = 200, "200 trames emises sans defaut");

      declare
         S   : Replay_Source;
         E   : Radar_Engine.Engine;
         Now : Time_Ms := 0;
      begin
         Open (S, Path, Ok => Ok);
         Assert (Ok and then Origin (S) = Origin_Emulated, "capture emulee");
         Radar_Engine.Start (E);
         while Now < 60_000
           and then Radar_Engine.Last (E).State = Radar_Engine.Running
         loop
            Radar_Engine.Step (E, S, Now);
            Now := Now + 20;
         end loop;
         Assert (Radar_Engine.Last (E).State = Radar_Engine.Finished, "fin");
         Assert (Radar_Engine.Last (E).Frames_Shown = Sent, "toutes montrees");
         Assert (Natural (Radar_Ld2450_Stream.Frames_Delivered (Stream (S)))
                 = Sent, "toutes decodees");
         Assert (Radar_Ld2450_Stream.Bytes_Discarded (Stream (S)) = 0,
                 "aucun octet perdu");
         Assert (Silences (S) = 0, "le debut du fichier n'est pas un silence");
         Assert (Now <= 21_000, "rejeu a la duree de la capture, sans attente");
      end;
   end Test_Capture_Replay;

   function One_Target (X, Y : Float; S : Time_Ms) return Planar_Report is
      R : Planar_Report;
   begin
      R.Items (1) := (X_Mm => X, Y_Mm => Y, Speed_Mm_S => 0.0);
      R.Count     := 1;
      R.Stamp     := S;
      return R;
   end One_Target;

   function Confirmed_Count (K : T2.Tracker) return Natural is
      N : Natural := 0;
   begin
      for Tr of K.Tracks loop
         if Tr.Active and then Tr.Confirmed then
            N := N + 1;
         end if;
      end loop;
      return N;
   end Confirmed_Count;

   --  Une tentative reste invisible, puis l'Id arrive a la 3e detection.
   procedure Test_Confirmation (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      K : T2.Tracker;
   begin
      T2.Update (K, One_Target (0.0, 2_000.0, 100));
      T2.Update (K, One_Target (0.0, 2_000.0, 200));
      Assert (Confirmed_Count (K) = 0, "pas confirmee a 2 detections");
      Assert (K.Tracks (1).Id = 0, "pas d'Id avant confirmation");
      T2.Update (K, One_Target (0.0, 2_000.0, 300));
      Assert (Confirmed_Count (K) = 1, "confirmee a 3 detections");
      Assert (K.Tracks (1).Id = 1, "premier Id");
   end Test_Confirmation;

   --  1 m/s en y, 10 Hz : la vitesse sort en mm/s, et l'Id ne change pas.
   procedure Test_Velocity (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      K : T2.Tracker;
   begin
      for I in 1 .. 40 loop
         T2.Update (K, One_Target (500.0, 1_000.0 + 100.0 * Float (I),
                                   Time_Ms (I) * 100));
      end loop;
      Assert (K.Tracks (1).Id = 1, "Id stable");
      Assert (abs (K.Tracks (1).Vy_Mm_S - 1_000.0) < 100.0, "vitesse y");
      Assert (abs K.Tracks (1).Vx_Mm_S < 100.0, "vitesse x");
      Assert (abs (K.Tracks (1).Y_Mm - 5_000.0) < 150.0, "position suivie");
   end Test_Velocity;

   --  Deux modules entrelaces : un rapport toutes les 50 ms, donc une
   --  correction de vitesse sur deux (seuil de 70 ms). Diviser l'ecart du
   --  seul dernier rapport par 100 ms sous-corrigeait : ~800 mm/s apres
   --  15 rapports. Avec l'ecart pris depuis l'ancre, ~950 (essai MATLAB Q01).
   procedure Test_Interleaved (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      K : T2.Tracker;
   begin
      for I in 1 .. 15 loop
         T2.Update (K, One_Target (500.0, 1_000.0 + 50.0 * Float (I),
                                   Time_Ms (I) * 50));
      end loop;
      Assert (K.Tracks (1).Vy_Mm_S > 900.0,
              "vitesse a 50 ms : >900 mm/s attendus, lu"
              & Integer'Image (Integer (K.Tracks (1).Vy_Mm_S)));
   end Test_Interleaved;

   --  Sans echo : la piste roule, marquee, puis meurt apres son delai.
   procedure Test_Coast (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      K     : T2.Tracker;
      Empty : Planar_Report;
   begin
      for I in 1 .. 5 loop
         T2.Update (K, One_Target (0.0, 2_000.0, Time_Ms (I) * 100));
      end loop;
      Empty.Stamp := 1_500;
      T2.Update (K, Empty);
      Assert (Confirmed_Count (K) = 1 and then K.Tracks (1).Coasting,
              "piste qui roule");
      Empty.Stamp := 3_100;
      T2.Update (K, Empty);
      Assert (Confirmed_Count (K) = 0, "morte apres 2,5 s");

      --  Une tentative meurt plus vite qu'une piste confirmee.
      T2.Update (K, One_Target (0.0, 3_000.0, 3_200));
      Empty.Stamp := 4_200;
      T2.Update (K, Empty);
      Assert ((for all Tr of K.Tracks => not Tr.Active), "tentative morte");
   end Test_Coast;

   --  Deux cibles paralleles gardent chacune leur Id.
   procedure Test_Two_Targets (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      K : T2.Tracker;
      R : Planar_Report;
   begin
      for I in 1 .. 20 loop
         R := (others => <>);
         R.Items (1) := (X_Mm => -1_500.0, Y_Mm => Float (I) * 100.0 + 1_000.0,
                         Speed_Mm_S => 0.0);
         R.Items (2) := (X_Mm => 1_500.0, Y_Mm => 4_000.0 - Float (I) * 100.0,
                         Speed_Mm_S => 0.0);
         R.Count := 2;
         R.Stamp := Time_Ms (I) * 100;
         T2.Update (K, R);
      end loop;
      Assert (Confirmed_Count (K) = 2, "deux pistes");
      Assert (K.Tracks (1).X_Mm < 0.0 and then K.Tracks (2).X_Mm > 0.0,
              "chacune de son cote");
      Assert (K.Tracks (1).Id /= K.Tracks (2).Id, "deux Id");
      Assert (K.Next_Id = 3, "aucun Id de trop");
   end Test_Two_Targets;

   --  Trame en retard, saut d'horloge, meme instant.
   procedure Test_Time_Policy (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      K : T2.Tracker;
   begin
      for I in 1 .. 5 loop
         T2.Update (K, One_Target (0.0, 2_000.0, Time_Ms (I) * 100));
      end loop;
      T2.Update (K, One_Target (0.0, 2_000.0, 400));
      Assert (K.Late_Frames = 1 and then Confirmed_Count (K) = 1, "retard");

      --  Meme instant : 100 mm d'ecart ne fabriquent aucune vitesse.
      T2.Update (K, One_Target (0.0, 2_100.0, 500));
      Assert (abs K.Tracks (1).Vy_Mm_S < 1.0, "pas de vitesse a dt = 0");

      T2.Update (K, One_Target (0.0, 2_000.0, 70_000));
      Assert (K.Clock_Resets = 1, "saut d'horloge compte");
      Assert (Confirmed_Count (K) = 0, "pistes effacees");
   end Test_Time_Policy;

   --  Les defauts sont bien les constantes du code, et un fichier abime ne
   --  fait tomber qu'un champ.
   procedure Test_Settings (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      use Radar_Settings;
      S   : Settings := Defaults;
      B   : Settings;
      Ok  : Boolean;
      Msg : Unbounded_String;
      F   : Ada.Text_IO.File_Type;
   begin
      Assert (Defaults.Confirm_Hits = Radar_Track.Confirm_Hits, "M de M-sur-N");
      Assert (Float (Defaults.Max_Speed_Mm_S) = Radar_Track.Max_Speed, "vitesse");
      Assert (Defaults.Calibration_Turns = 8 and then Defaults.Learn_Period = 4
              and then Defaults.Age_Period = 32, "constantes de live");
      Assert (Learn_Threshold_Percent (Defaults) = 12, "seuil 12 %");

      Prepare;
      Load (B, Path, Msg);
      Assert (B = Defaults and then Msg = Null_Unbounded_String, "absent");

      S.Confirm_Hits := 4;
      S.Map_Az_Steps := 240;
      Save (S, Path, Ok);
      Assert (Ok, "enregistre");
      Load (B, Path, Msg);
      Assert (B = S and then Msg = Null_Unbounded_String, "relu");

      Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put_Line (F, "radar_fw_settings=1");
      Ada.Text_IO.Put_Line (F, "confirm_hits=99");
      Ada.Text_IO.Put_Line (F, "coast_ms=abc");
      Ada.Text_IO.Put_Line (F, "age_period=64");
      Ada.Text_IO.Close (F);
      Load (B, Path, Msg);
      Assert (B.Confirm_Hits = Defaults.Confirm_Hits, "hors bornes = defaut");
      Assert (B.Coast_Ms = Defaults.Coast_Ms, "pas un nombre = defaut");
      Assert (B.Age_Period = 64, "le reste est lu");
      Assert (Length (Msg) > 0, "et c'est dit");

      Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put_Line (F, "autre_chose=2");
      Ada.Text_IO.Close (F);
      Load (B, Path, Msg);
      Assert (B = Defaults and then Length (Msg) > 0, "version inconnue");
   end Test_Settings;

   procedure Test_View (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      use Radar_View;
      use Ada.Numerics.Elementary_Functions;
      P : constant Plan :=
        (Width => 1_000.0, Height => 800.0, Range_Mm => 8_000.0, Around => False);
      O : constant Screen_Point := To_Screen (P, 0.0, 0.0);
      A : constant Screen_Point := To_Screen (P, 1_000.0, 2_000.0);
      C : constant Camera := (Yaw => 0.0, Pitch => 0.0, Distance => 10_000.0);
      Centre : constant Projected :=
        Project (C, 800.0, 600.0, (X => 0.0, Y => 0.0, Z => 0.0));
      Gauche : constant Projected :=
        Project (C, 800.0, 600.0, (X => 0.0, Y => 1_000.0, Z => 0.0));
      Haut   : constant Projected :=
        Project (C, 800.0, 600.0, (X => 0.0, Y => 0.0, Z => 1_000.0));
      Behind : constant Projected :=
        Project (C, 800.0, 600.0, (X => 20_000.0, Y => 0.0, Z => 0.0));
      Pts : constant Screen_Array (1 .. 3) :=
        ((X => 10.0, Y => 10.0), (X => 100.0, Y => 100.0),
         (X => 105.0, Y => 100.0));
   begin
      Assert (O.X = 500.0 and then O.Y = Origin (P).Y, "capteur en bas, centre");
      Assert (A.X > O.X and then A.Y < O.Y, "droite et devant");
      Assert (abs (Sqrt ((A.X - O.X) ** 2 + (A.Y - O.Y) ** 2)
                   - Sqrt (5.0) * 1_000.0 * Scale (P)) < 0.01, "echelle");
      Assert (To_Plan_X ((X => 1.0, Y => 2.0, Z => 3.0)) = -2.0, "repere X");
      Assert (To_Plan_Y ((X => 1.0, Y => 2.0, Z => 3.0)) = 1.0, "repere Y");

      Assert (Centre.Visible
              and then abs (Centre.S.X - 400.0) < 0.01
              and then abs (Centre.S.Y - 300.0) < 0.01, "origine au centre");
      --  La camera est en +X et regarde le capteur : sa gauche est notre droite.
      Assert (Gauche.S.X > 400.0, "gauche du capteur a droite de l'ecran");
      Assert (Haut.S.Y < 300.0, "Z vers le haut");
      Assert (not Behind.Visible, "derriere la camera");

      Assert (Nearest (Pts, (X => 12.0, Y => 11.0), 8.0) = 1, "clic proche");
      Assert (Nearest (Pts, (X => 300.0, Y => 300.0), 8.0) = 0, "clic dans le vide");
      Assert (Crowded (Pts, 2, 20.0) and then not Crowded (Pts, 1, 20.0),
              "voisins");
   end Test_View;

   --  La passe rapide puis la detaillee s'enchainent et remplissent le nuage.
   procedure Test_Map (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      use Radar_Map_Engine;
      M      : Map_Engine;
      Steps  : Natural := 0;
      Before : Radar_Cloud.Point_Count;
   begin
      Start (M, 60, 8);
      Assert (M.Stage = Quick_Pass and then Percent (M) = 0, "depart");
      while M.Stage = Quick_Pass and then Steps < 200 loop
         Step (M);
         Steps := Steps + 1;
      end loop;
      Assert (M.Stage = Detail_Pass and then Steps = 60, "60 colonnes");
      Before := M.Cloud.Count;
      Assert (Before > 0, "apercu non vide");
      while M.Stage = Detail_Pass and then Steps < 400 loop
         Step (M);
         Steps := Steps + 1;
      end loop;
      Assert (M.Stage = Complete and then Percent (M) = 100, "fin");
      Assert (M.Cloud.Count > Before, "le detail ajoute des points");
   end Test_Map;

   --  Calibration finie, puis Recalibrer repart sans recreer la veille :
   --  c'est le critere du poste de controle.
   procedure Test_Watch (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      use Radar_Watch_3D;
      W   : Radar_Watch_3D.Watch;
      Now : Time_Ms := 0;

      procedure Run_Until (Target : Time_Ms) is
      begin
         while Now < Target loop
            Now := Now + 40;
            Step (W, Now);
         end loop;
      end Run_Until;
   begin
      Start (W, Radar_Settings.Defaults);
      Assert (Calibrating (W), "calibration au depart");
      Run_Until (8_000);
      Assert (not Calibrating (W), "calibration terminee apres 8 tours");
      Assert (W.Decor.Count > 0, "decor appris");
      Assert (W.Turn >= 8 and then W.Turn <= 10, "cadence virtuelle tenue");

      Recalibrate (W);
      Assert (not Calibrating (W), "effet seulement en fin de tour");
      Run_Until (Now + 900);
      Assert (Calibrating (W), "recalibration sans relancer");
      Assert (W.Turn <= 1, "reprise au tour 0");
   end Test_Watch;

   overriding
   procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Origin'Access, "Origine d'une capture");
      Register_Routine (T, Test_Truth'Access, "Ce que l'ecran peut affirmer");
      Register_Routine
        (T, Test_Capture_Replay'Access, "Capture emulee rejouee entiere");
      Register_Routine (T, Test_Confirmation'Access, "Pistage 2D : confirmation");
      Register_Routine (T, Test_Velocity'Access, "Pistage 2D : vitesse en mm/s");
      Register_Routine (T, Test_Interleaved'Access,
                        "Pistage 2D : sources entrelacees a 50 ms");
      Register_Routine (T, Test_Coast'Access, "Pistage 2D : coasting et mort");
      Register_Routine (T, Test_Two_Targets'Access, "Pistage 2D : deux cibles");
      Register_Routine (T, Test_Time_Policy'Access, "Pistage 2D : temps");
      Register_Routine (T, Test_Settings'Access, "Reglages bornes");
      Register_Routine (T, Test_View'Access, "Geometrie d'ecran et clic");
      Register_Routine (T, Test_Map'Access, "Cartographie pas a pas");
      Register_Routine (T, Test_Watch'Access, "Veille 3D et recalibration");
   end Register_Tests;

end Radar_Console_Tests;
