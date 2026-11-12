--  Les libelles sont en UTF-8 dans ce fichier, et GTK les attend tels quels.
--  Avec -gnatW8 (Alire), le compilateur les decoderait en Latin-1 : mojibake.
pragma Wide_Character_Encoding (BRACKETS);

with Ada.Calendar;
with Ada.Calendar.Formatting;
with Ada.Command_Line;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Ada.Real_Time;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;     use Ada.Strings.Unbounded;
with Ada.Text_IO;

with Cairo;
with Gdk.Event;                 use Gdk.Event;
with Gdk.Screen;
with Glib;                      use Glib;
with Glib.Main;
with Glib.Properties;
with Gtk.Box;
with Gtk.Button;
with Gtk.Check_Button;
with Gtk.Combo_Box;
with Gtk.Combo_Box_Text;
with Gtk.Css_Provider;
with Gtk.Drawing_Area;
with Gtk.Enums;                 use Gtk.Enums;
with Gtk.Expander;
with Gtk.File_Chooser;
with Gtk.File_Chooser_Button;
with Gtk.GEntry;
with Gtk.Grid;
with Gtk.Label;
with Gtk.Main;
with Gtk.Scrolled_Window;
with Gtk.Settings;
with Gtk.Spin_Button;
with Gtk.Stack;
with Gtk.Stack_Switcher;
with Gtk.Style_Context;
with Gtk.Style_Provider;
with Gtk.Text_Buffer;
with Gtk.Text_View;
with Gtk.Toggle_Button;
with Gtk.Widget;                use Gtk.Widget;
with Gtk.Window;
with Pango.Layout;

with Console_Sar;
with Console_Serial;
with Radar_Engine;
with Radar_Geometry;            use Radar_Geometry;
with Radar_Ld2450_Log;
with Radar_Ld2450_Plausibility;
with Radar_Ld2450_Replay;
with Radar_Ld2450_Sim_Source;
with Radar_Ld2450_Stream;
with Radar_Map_Engine;
with Radar_Modes;               use Radar_Modes;
with Radar_Settings;
with Radar_Source;              use Radar_Source;
with Radar_Track;
with Radar_Track_2D;
with Radar_View;                use Radar_View;
with Radar_Watch_3D;

package body Console_Ui is

   package RT   renames Ada.Real_Time;
   package EF   renames Ada.Numerics.Elementary_Functions;
   package Plaus renames Radar_Ld2450_Plausibility;

   use type Radar_Engine.Engine_State;
   use type Radar_Map_Engine.Stage_Kind;
   use type Radar_Ld2450_Plausibility.Counter;
   use type Ada.Real_Time.Time;
   use type Gtk.Scrolled_Window.Gtk_Scrolled_Window;

   Pi : constant := Ada.Numerics.Pi;

   --  ----- Etat de la session -----

   type Run_Mode is
     (None, Run_Live, Run_Replay, Run_Serial, Run_Watch_3D, Run_Map, Run_Sar);

   Mode       : Run_Mode := None;
   Finished_Note : Boolean := False;
   Settings   : Radar_Settings.Settings;
   Eng        : Radar_Engine.Engine;
   Live       : Radar_Ld2450_Sim_Source.Live_Source;
   Replay     : Radar_Ld2450_Replay.Replay_Source;
   Serial     : Console_Serial.Serial_Source;
   Port_Name  : Unbounded_String;
   Watch_3D   : Radar_Watch_3D.Watch;
   Map        : Radar_Map_Engine.Map_Engine;
   Cam        : Camera;
   Last_Tick  : RT.Time := RT.Clock;
   Virtual_Ms : Long_Float := 0.0;
   Tick_Count : Natural := 0;
   Sar_Path   : Unbounded_String;
   Last_Frames : Natural := 0;
   Last_Fresh  : RT.Time := RT.Clock;

   --  Traînees : par emplacement de piste, pas par Id.
   Trail_Len  : constant := 40;
   type Trail is record
      Id    : Natural := 0;
      Count : Natural := 0;
      Xs    : Radar_View.Screen_Array (1 .. Trail_Len);  --  en mm, pas en px
   end record;
   Trails : array (1 .. Radar_Track_2D.Max_Tracks) of Trail;

   --  Une piste telle que la dessine la vue, quelle que soit son origine.
   type View_Track is record
      Id       : Natural := 0;
      X, Y     : Float   := 0.0;
      Vx, Vy   : Float   := 0.0;
      Coasting : Boolean := False;
   end record;
   Max_View : constant := Radar_Track.Max_Tracks;
   type View_List is array (1 .. Max_View) of View_Track;
   Shown       : View_List;
   Shown_Count : Natural := 0;
   Selected_Id : Natural := 0;
   Selected_Point : Natural := 0;

   Draw_Last_Ms : Float := 0.0;
   Draw_Max_Ms  : Float := 0.0;
   Plan_Width   : Float := 800.0;
   Plan_Height  : Float := 600.0;
   Drag_X, Drag_Y : Gdouble := 0.0;
   Dragged      : Boolean := False;

   --  ----- Widgets -----

   Win         : Gtk.Window.Gtk_Window;
   Area        : Gtk.Drawing_Area.Gtk_Drawing_Area;
   Center      : Gtk.Stack.Gtk_Stack;
   Sar_Buffer  : Gtk.Text_Buffer.Gtk_Text_Buffer;
   Lbl_Source, Lbl_Link, Lbl_Frames, Lbl_Plaus, Lbl_Alert, Lbl_Msg,
   Lbl_Tracks, Lbl_Detail, Lbl_Learn : Gtk.Label.Gtk_Label;
   Src_Combo, Act_Combo : Gtk.Combo_Box_Text.Gtk_Combo_Box_Text;
   Port_Entry  : Gtk.GEntry.Gtk_Entry;
   File_Btn    : Gtk.File_Chooser_Button.Gtk_File_Chooser_Button;
   Start_Btn, Stop_Btn, Rec_Btn, Recal_Btn : Gtk.Button.Gtk_Button;
   Chk_Det, Chk_Tracks, Chk_Trails, Chk_Labels, Chk_Decor, Chk_Field
     : Gtk.Check_Button.Gtk_Check_Button;
   Spin_Confirm, Spin_Coast, Spin_Speed, Spin_Replay, Spin_Learn, Spin_Age,
   Spin_Calib, Spin_Az, Spin_El : Gtk.Spin_Button.Gtk_Spin_Button;
   Diag_Buffer, Journal : Gtk.Text_Buffer.Gtk_Text_Buffer;
   Updating_Spins : Boolean := False;

   --  ----- Petits outils -----

   function Img (V : Integer) return String is
     (Ada.Strings.Fixed.Trim (Integer'Image (V), Ada.Strings.Both));

   function Fixed_1 (V : Float) return String is
      Tenths : constant Integer := Integer (Float'Rounding (abs V * 10.0));
      Sign   : constant String :=
        (if V < 0.0 and then Tenths /= 0 then "-" else "");
   begin
      return Sign & Img (Tenths / 10) & "," & Img (Tenths mod 10);
   end Fixed_1;

   function Data_Dir return String is
      Base : constant String :=
        (if Ada.Environment_Variables.Exists ("USERPROFILE")
         then Ada.Environment_Variables.Value ("USERPROFILE") & "/Documents"
         else ".");
      Dir  : constant String := Base & "/radar_fw";
   begin
      Ada.Directories.Create_Path (Dir);
      return Dir;
   exception
      when others =>
         return ".";
   end Data_Dir;

   function Settings_Path return String is (Data_Dir & "/console.cfg");

   procedure Log (Msg : String) is
      Stamp : constant String :=
        Ada.Calendar.Formatting.Image (Ada.Calendar.Clock);
   begin
      Journal.Insert_At_Cursor
        (Stamp (Stamp'First + 11 .. Stamp'First + 18) & "  " & Msg
         & ASCII.LF);
   end Log;

   procedure Say (Msg : String) is
   begin
      Lbl_Msg.Set_Text (Msg);
      if Msg /= "" then
         Log (Msg);
      end if;
   end Say;

   function Current_Source return Source_Kind is
     (Source_Kind'Val (Integer (Src_Combo.Get_Active)));

   function Current_Activity return Activity_Kind is
     (Activity_Kind'Val (Integer (Act_Combo.Get_Active)));

   function Origin_Now return Radar_Ld2450_Log.Capture_Origin is
     (if Mode = Run_Replay then Radar_Ld2450_Replay.Origin (Replay)
      else Radar_Ld2450_Log.Origin_Unknown);

   function Active_Source return Source_Kind is
     (case Mode is
         when Run_Serial => Sensor_Serial,
         when Run_Replay => Capture_File,
         when Run_Live   => Sim_Ld2450,
         when others     => Sim_Profiles);

   function Now_Ms return Time_Ms is
     (Time_Ms (Long_Float'Min (Virtual_Ms, 2_000_000_000.0)));

   function Track_Params return Radar_Track_2D.Parameters is
     ((Confirm_Hits       => Settings.Confirm_Hits,
       Coast_Confirmed_Ms => Time_Ms (Settings.Coast_Ms),
       Max_Speed_Mm_S     => Float (Settings.Max_Speed_Mm_S),
       others             => <>));

   --  ----- Etat lu par l'affichage -----

   procedure Collect_Tracks is
   begin
      Shown_Count := 0;
      if Mode in Run_Live | Run_Replay | Run_Serial then
         declare
            Snap : constant Radar_Engine.Snapshot := Radar_Engine.Last (Eng);
         begin
            for T of Snap.Tracker.Tracks loop
               if T.Active and then T.Confirmed then
                  Shown_Count := Shown_Count + 1;
                  Shown (Shown_Count) :=
                    (Id => T.Id, X => T.X_Mm, Y => T.Y_Mm,
                     Vx => T.Vx_Mm_S, Vy => T.Vy_Mm_S,
                     Coasting => T.Coasting);
               end if;
            end loop;
         end;
      elsif Mode = Run_Watch_3D then
         for T of Watch_3D.Trk.Tracks loop
            if T.Active and then T.Confirmed then
               Shown_Count := Shown_Count + 1;
               Shown (Shown_Count) :=
                 (Id => T.Id,
                  X  => To_Plan_X (T.Pos), Y => To_Plan_Y (T.Pos),
                  Vx => -T.Velocity.Y, Vy => T.Velocity.X,
                  Coasting => T.Missing > 0);
            end if;
         end loop;
      end if;
   end Collect_Tracks;

   procedure Update_Trails is
      Snap : constant Radar_Engine.Snapshot := Radar_Engine.Last (Eng);
   begin
      for I in Trails'Range loop
         declare
            K : Radar_Track_2D.Track renames Snap.Tracker.Tracks (I);
            L : Trail renames Trails (I);
         begin
            if not K.Active or else not K.Confirmed then
               L.Id    := 0;
               L.Count := 0;
            else
               if L.Id /= K.Id then
                  L.Id    := K.Id;
                  L.Count := 0;
               end if;
               if L.Count = Trail_Len then
                  L.Xs (1 .. Trail_Len - 1) := L.Xs (2 .. Trail_Len);
                  L.Count := Trail_Len - 1;
               end if;
               L.Count := L.Count + 1;
               L.Xs (L.Count) := (X => K.X_Mm, Y => K.Y_Mm);
            end if;
         end;
      end loop;
   end Update_Trails;

   function Stream_Of return Radar_Ld2450_Stream.Parser is
     (case Mode is
         when Run_Serial => Console_Serial.Stream (Serial),
         when Run_Replay => Radar_Ld2450_Replay.Stream (Replay),
         when others     => Radar_Ld2450_Sim_Source.Stream (Live));

   function Checks_Of return Plaus.Validator is
     (case Mode is
         when Run_Serial => Console_Serial.Checks (Serial),
         when Run_Replay => Radar_Ld2450_Replay.Checks (Replay),
         when others     => Radar_Ld2450_Sim_Source.Checks (Live));

   function Rejected_Total return Natural is
      Sum : Plaus.Counter := 0;
      V   : constant Plaus.Validator := Checks_Of;
   begin
      for R in Plaus.Reject_Reason loop
         Sum := Sum + Plaus.Rejected (V, R);
      end loop;
      return Natural (Sum);
   end Rejected_Total;

   function Is_Planar return Boolean is
     (Mode in Run_Live | Run_Replay | Run_Serial);

   function Alert_Count return Natural is
      N : Natural := 0;
   begin
      if Is_Planar then
         declare
            K : constant Radar_Track_2D.Tracker :=
              Radar_Engine.Last (Eng).Tracker;
         begin
            N := K.Late_Frames + K.Clock_Resets + K.Dropped;
         end;
      end if;
      if Mode = Run_Replay then
         N := N + Radar_Ld2450_Replay.Silences (Replay);
      elsif Mode = Run_Serial then
         N := N + (if Console_Serial.Lost_Bytes > 0 then 1 else 0)
           + (if Console_Serial.Port_Open then 0 else 1);
      elsif Mode = Run_Map then
         N := N + Map.Cloud.Dropped;
      end if;
      return N;
   end Alert_Count;

   procedure Update_Status is
      Age : constant Float :=
        Float (RT.To_Duration (RT.Clock - Last_Fresh));
   begin
      if Mode = None then
         Lbl_Source.Set_Text ("SOURCE  aucune");
         Lbl_Link.Set_Text ("LIAISON  -");
         Lbl_Frames.Set_Text ("TRAMES  -");
         Lbl_Plaus.Set_Text ("PLAUSIBILITÉ  -");
         Lbl_Alert.Set_Text ("ALERTES  0");
         return;
      end if;

      Lbl_Source.Set_Text
        ("SOURCE  " & Source_Text (Active_Source, Origin_Now));
      Lbl_Alert.Set_Text ("ALERTES  " & Img (Alert_Count));

      case Mode is
         when Run_Serial =>
            Lbl_Link.Set_Text
              ("LIAISON  " & (if Console_Serial.Port_Open
                              then To_String (Port_Name) & " ouvert"
                              else "port perdu"));
         when Run_Replay =>
            Lbl_Link.Set_Text ("LIAISON  sans objet (fichier)");
         when others =>
            Lbl_Link.Set_Text ("LIAISON  sans objet (simulation)");
      end case;

      if Is_Planar then
         declare
            Snap : constant Radar_Engine.Snapshot := Radar_Engine.Last (Eng);
            N    : constant Natural := Snap.Frames_Shown;
         begin
            if N = 0 then
               Lbl_Frames.Set_Text ("TRAMES  aucune reçue");
            elsif Snap.State = Radar_Engine.Finished or else Age > 1.5 then
               Lbl_Frames.Set_Text
                 ("TRAMES  " & Img (N) & ", figée depuis "
                  & Fixed_1 (Age) & " s");
            else
               Lbl_Frames.Set_Text
                 ("TRAMES  " & Img (N) & ", âge " & Fixed_1 (Age) & " s");
            end if;
            declare
               V : constant Plaus.Validator := Checks_Of;
            begin
               Lbl_Plaus.Set_Text
                 ("PLAUSIBILITÉ  " & Img (Natural (Plaus.Accepted (V)))
                  & " ok / " & Img (Rejected_Total) & " rejet(s)");
            end;
         end;
      elsif Mode = Run_Watch_3D then
         Lbl_Frames.Set_Text
           ("TOURS  " & Img (Watch_3D.Turn)
            & (if Radar_Watch_3D.Calibrating (Watch_3D)
               then " (calibration du décor)" else ""));
         Lbl_Plaus.Set_Text ("PLAUSIBILITÉ  sans objet");
      elsif Mode = Run_Map then
         Lbl_Frames.Set_Text
           ("CARTE  " & Img (Radar_Map_Engine.Percent (Map)) & " %, "
            & Img (Natural (Map.Cloud.Count)) & " points");
         Lbl_Plaus.Set_Text ("PLAUSIBILITÉ  sans objet");
      else
         Lbl_Frames.Set_Text ("CALCUL  en cours");
         Lbl_Plaus.Set_Text ("PLAUSIBILITÉ  sans objet");
      end if;
   end Update_Status;

   procedure Update_Tracks_Panel is
      Text : Unbounded_String;
   begin
      if Shown_Count = 0 then
         Text := To_Unbounded_String ("Aucune piste confirmée");
      end if;
      for I in 1 .. Shown_Count loop
         declare
            T    : View_Track renames Shown (I);
            Dist : constant Float := EF.Sqrt (T.X ** 2 + T.Y ** 2) / 1_000.0;
            Spd  : constant Float :=
              EF.Sqrt (T.Vx ** 2 + T.Vy ** 2) / 1_000.0;
         begin
            Append
              (Text,
               "#" & Img (T.Id) & "  " & Fixed_1 (Dist) & " m  "
               & Fixed_1 (Spd) & " m/s"
               & (if T.Coasting then "  (extrapolée)" else "")
               & ASCII.LF);
         end;
      end loop;
      Lbl_Tracks.Set_Text (To_String (Text));
   end Update_Tracks_Panel;

   procedure Update_Diagnostic is
      Text : Unbounded_String;
      procedure Add (Name, Value : String) is
      begin
         Append (Text, Name & " : " & Value & ASCII.LF);
      end Add;
   begin
      Add ("Temps d'image (dernier)", Fixed_1 (Draw_Last_Ms) & " ms");
      Add ("Temps d'image (pire)", Fixed_1 (Draw_Max_Ms) & " ms");
      if Is_Planar then
         declare
            P : constant Radar_Ld2450_Stream.Parser := Stream_Of;
            V : constant Plaus.Validator := Checks_Of;
            K : constant Radar_Track_2D.Tracker :=
              Radar_Engine.Last (Eng).Tracker;
         begin
            Add ("Octets lus",
                 Img (Natural (Radar_Ld2450_Stream.Bytes_Read (P))));
            Add ("Octets écartés",
                 Img (Natural (Radar_Ld2450_Stream.Bytes_Discarded (P))));
            Add ("Trames décodées",
                 Img (Natural (Radar_Ld2450_Stream.Frames_Delivered (P))));
            Add ("Trames affichées",
                 Img (Radar_Engine.Last (Eng).Frames_Shown));
            Add ("Cibles acceptées", Img (Natural (Plaus.Accepted (V))));
            Add ("Emplacements vides", Img (Natural (Plaus.Absent (V))));
            for R in Plaus.Reject_Reason loop
               Add ("Rejet " & Plaus.Reject_Reason'Image (R),
                    Img (Natural (Plaus.Rejected (V, R))));
            end loop;
            Add ("Trames en retard", Img (K.Late_Frames));
            Add ("Sauts d'horloge", Img (K.Clock_Resets));
            Add ("Détections sans place", Img (K.Dropped));
         end;
         if Mode = Run_Replay then
            Add ("Silences du module",
                 Img (Radar_Ld2450_Replay.Silences (Replay)));
         elsif Mode = Run_Serial then
            Add ("Octets perdus (tampon)", Img (Console_Serial.Lost_Bytes));
         end if;
      elsif Mode = Run_Map then
         Add ("Points", Img (Natural (Map.Cloud.Count)));
         Add ("Points rejetés", Img (Map.Cloud.Dropped));
      elsif Mode = Run_Watch_3D then
         Add ("Tours", Img (Watch_3D.Turn));
         Add ("Trames en retard", Img (Watch_3D.Trk.Late_Frames));
         Add ("Remises à zéro d'horloge", Img (Watch_3D.Trk.Clock_Resets));
         Add ("Points du décor", Img (Natural (Watch_3D.Decor.Count)));
      end if;
      Diag_Buffer.Set_Text (To_String (Text));
   end Update_Diagnostic;

   procedure Set_Running_Buttons is
      Is_On : constant Boolean := Mode /= None;
   begin
      Start_Btn.Set_Sensitive (not Is_On);
      Stop_Btn.Set_Sensitive (Is_On);
      Rec_Btn.Set_Sensitive (Mode in Run_Live | Run_Serial);
      Recal_Btn.Set_Sensitive (Mode = Run_Watch_3D);
      Src_Combo.Set_Sensitive (not Is_On);
      Act_Combo.Set_Sensitive (not Is_On);
   end Set_Running_Buttons;

   procedure Stop_Session is
   begin
      if Mode = Run_Serial then
         Console_Serial.Close (Serial);
      elsif Mode = Run_Live then
         Radar_Ld2450_Sim_Source.Stop_Recording (Live);
      end if;
      Rec_Btn.Set_Label ("Enregistrer");
      Mode := None;
      Shown_Count := 0;
      Selected_Id := 0;
      Selected_Point := 0;
      Lbl_Detail.Set_Text ("");
      Center.Set_Visible_Child_Name ("scene");
      Set_Running_Buttons;
      Update_Status;
      Update_Tracks_Panel;
      Area.Queue_Draw;
   end Stop_Session;

   procedure Update_Choice_Hint is
      S : constant Source_Kind := Current_Source;
      A : constant Activity_Kind := Current_Activity;
   begin
      Port_Entry.Set_Visible (S = Sensor_Serial);
      File_Btn.Set_Visible (S = Capture_File);
      Start_Btn.Set_Sensitive (Allowed (S, A) and then Mode = None);
      Lbl_Msg.Set_Text (Reason (S, A));
   end Update_Choice_Hint;

   procedure Do_Start is
      S : constant Source_Kind := Current_Source;
      A : constant Activity_Kind := Current_Activity;
   begin
      if not Allowed (S, A) then
         Say (Reason (S, A));
         return;
      end if;

      Virtual_Ms  := 0.0;
      Last_Tick   := RT.Clock;
      Last_Frames := 0;
      Last_Fresh  := RT.Clock;
      Draw_Max_Ms := 0.0;
      Finished_Note := False;
      Trails := (others => <>);

      if A = Mapping then
         Radar_Map_Engine.Start
           (Map, Settings.Map_Az_Steps, Settings.Map_El_Steps);
         Mode := Run_Map;
      elsif A = Sar_Analysis then
         Sar_Path := To_Unbounded_String (Data_Dir & "/analyse_sar.txt");
         Console_Sar.Start (To_String (Sar_Path));
         Sar_Buffer.Set_Text ("Analyse SAR simulée en cours (environ 12 s).");
         Center.Set_Visible_Child_Name ("texte");
         Mode := Run_Sar;
      else
         case S is
            when Sim_Profiles =>
               Radar_Watch_3D.Start (Watch_3D, Settings);
               Mode := Run_Watch_3D;
            when Sim_Ld2450 =>
               Live := Radar_Ld2450_Sim_Source.Make;
               Radar_Engine.Start (Eng, Track_Params);
               Mode := Run_Live;
            when Capture_File =>
               declare
                  Path : constant String := File_Btn.Get_Filename;
                  Ok   : Boolean;
               begin
                  if Path = "" then
                     Say ("Choisir d'abord un fichier de capture.");
                     return;
                  end if;
                  Radar_Ld2450_Replay.Open (Replay, Path, Ok => Ok);
                  if not Ok then
                     Say ("Fichier illisible ou hors format : " & Path);
                     return;
                  end if;
                  Radar_Engine.Start (Eng, Track_Params);
                  Mode := Run_Replay;
               end;
            when Sensor_Serial =>
               declare
                  Name : constant String := Port_Entry.Get_Text;
                  Ok   : Boolean;
                  Why  : Integer;
               begin
                  Console_Serial.Open (Serial, Name, Ok, Why);
                  if not Ok then
                     Say ("Port " & Name & " non ouvert (erreur Windows "
                          & Img (Why) & ").");
                     return;
                  end if;
                  Port_Name := To_Unbounded_String (Name);
                  Radar_Engine.Start (Eng, Track_Params);
                  Mode := Run_Serial;
               end;
         end case;
      end if;

      Say (Activity_Label (A) & " démarrée : " & Source_Label (S) & ".");
      Set_Running_Buttons;
      Update_Status;
   end Do_Start;

   procedure Load_Sar_Result is
      use Ada.Text_IO;
      F    : File_Type;
      Text : Unbounded_String;
   begin
      Open (F, In_File, To_String (Sar_Path));
      while not End_Of_File (F) loop
         Append (Text, Get_Line (F) & ASCII.LF);
      end loop;
      Close (F);
      Sar_Buffer.Set_Text (To_String (Text));
   exception
      when others =>
         if Is_Open (F) then
            Close (F);
         end if;
         Sar_Buffer.Set_Text ("Résultat SAR illisible.");
   end Load_Sar_Result;

   --  ----- La boucle d'interface : ~33 appels par seconde -----

   function Tick return Boolean is
      T  : constant RT.Time := RT.Clock;
      Dt : constant Long_Float :=
        Long_Float (RT.To_Duration (T - Last_Tick)) * 1_000.0;
   begin
      Last_Tick := T;
      if Mode = None then
         return True;
      end if;

      Virtual_Ms := Virtual_Ms
        + Dt * (if Mode = Run_Replay
                then Long_Float (Settings.Replay_Percent) / 100.0 else 1.0);
      Tick_Count := Tick_Count + 1;

      case Mode is
         when Run_Live =>
            Radar_Engine.Step (Eng, Live, Now_Ms);
         when Run_Replay =>
            Radar_Engine.Step (Eng, Replay, Now_Ms);
         when Run_Serial =>
            Radar_Engine.Step (Eng, Serial, Now_Ms);
         when Run_Watch_3D =>
            Radar_Watch_3D.Step (Watch_3D, Now_Ms);
         when Run_Map =>
            Radar_Map_Engine.Step (Map);
         when Run_Sar =>
            if Console_Sar.Done then
               if Console_Sar.Failed then
                  Say ("L'analyse SAR a échoué.");
                  Sar_Buffer.Set_Text ("L'analyse SAR a échoué.");
               else
                  Load_Sar_Result;
                  Say ("Analyse SAR terminée.");
               end if;
               Mode := None;
               Set_Running_Buttons;
               Update_Status;
            end if;
         when None =>
            null;
      end case;

      if Is_Planar then
         declare
            Snap : constant Radar_Engine.Snapshot := Radar_Engine.Last (Eng);
         begin
            if Snap.Frames_Shown /= Last_Frames then
               Last_Frames := Snap.Frames_Shown;
               Last_Fresh  := T;
               Update_Trails;
            end if;
            if Snap.State = Radar_Engine.Finished and then not Finished_Note
            then
               Finished_Note := True;
               Say ("Fin du fichier : données figées.");
            end if;
         end;
      elsif Mode = Run_Map and then Map.Stage = Radar_Map_Engine.Complete
        and then not Finished_Note
      then
         Finished_Note := True;
         Say ("Cartographie terminée : vue explorable.");
      end if;

      Collect_Tracks;
      --  Carte finie : rien ne bouge plus, sauf a la souris, qui redessine
      --  elle-meme. Inutile de repeindre 4 500 points 33 fois par seconde.
      if Mode /= Run_Map or else Map.Stage /= Radar_Map_Engine.Complete then
         Area.Queue_Draw;
      end if;
      if Tick_Count mod 6 = 0 then
         Update_Status;
         Update_Tracks_Panel;
         Update_Diagnostic;
      end if;
      return True;
   end Tick;

   --  ----- Le dessin -----

   procedure Text_At
     (Cr : Cairo.Cairo_Context; X, Y : Float; S : String) is
   begin
      Cairo.Move_To (Cr, Gdouble (X), Gdouble (Y));
      Cairo.Show_Text (Cr, S);
      --  Show_Text laisse un point courant : le Arc suivant tirerait un
      --  trait depuis la fin du texte jusqu'au debut du cercle.
      Cairo.New_Path (Cr);
   end Text_At;

   function On (C : Gtk.Check_Button.Gtk_Check_Button) return Boolean is
     (C.Get_Active);

   procedure Draw_Plan (Cr : Cairo.Cairo_Context; W, H : Float) is
      P : constant Plan :=
        (Width => W, Height => H,
         Range_Mm => (if Mode = Run_Watch_3D then 6_000.0 else 8_000.0),
         Around => Mode = Run_Watch_3D);
      O : constant Screen_Point := Radar_View.Origin (P);
      K : constant Float := Scale (P);
      Screen : Screen_Array (1 .. Integer'Max (Shown_Count, 1));
   begin
      Cairo.Set_Line_Width (Cr, 1.0);
      Cairo.Set_Source_Rgb (Cr, 0.27, 0.31, 0.30);
      for R in 1 .. Integer (P.Range_Mm / 1_000.0) loop
         Cairo.Arc (Cr, Gdouble (O.X), Gdouble (O.Y),
                    Gdouble (Float (R) * 1_000.0 * K), 0.0, 2.0 * Pi);
         Cairo.Stroke (Cr);
         Text_At (Cr, O.X + 4.0, O.Y - Float (R) * 1_000.0 * K - 2.0,
                  Img (R) & " m");
      end loop;

      if not P.Around and then On (Chk_Field) then
         declare
            Rad : constant Float := 60.0 * Pi / 180.0;
            Len : constant Float := P.Range_Mm;
            A   : constant Screen_Point :=
              To_Screen (P, -EF.Sin (Rad) * Len, EF.Cos (Rad) * Len);
            B   : constant Screen_Point :=
              To_Screen (P, EF.Sin (Rad) * Len, EF.Cos (Rad) * Len);
         begin
            Cairo.Move_To (Cr, Gdouble (A.X), Gdouble (A.Y));
            Cairo.Line_To (Cr, Gdouble (O.X), Gdouble (O.Y));
            Cairo.Line_To (Cr, Gdouble (B.X), Gdouble (B.Y));
            Cairo.Stroke (Cr);
         end;
      end if;

      if Mode = Run_Watch_3D and then On (Chk_Decor) then
         Cairo.Set_Source_Rgb (Cr, 0.45, 0.50, 0.48);
         for I in 1 .. Natural (Watch_3D.Decor.Count) loop
            declare
               Q : constant Screen_Point :=
                 To_Screen (P, To_Plan_X (Watch_3D.Decor.Points (I)),
                            To_Plan_Y (Watch_3D.Decor.Points (I)));
            begin
               Cairo.Rectangle (Cr, Gdouble (Q.X), Gdouble (Q.Y), 2.0, 2.0);
            end;
         end loop;
         Cairo.Fill (Cr);
      end if;

      if Is_Planar then
         if On (Chk_Trails) then
            Cairo.Set_Source_Rgba (Cr, 0.22, 0.53, 0.90, 0.5);
            for L of Trails loop
               for I in 1 .. L.Count loop
                  declare
                     Q : constant Screen_Point :=
                       To_Screen (P, L.Xs (I).X, L.Xs (I).Y);
                  begin
                     if I = 1 then
                        Cairo.Move_To (Cr, Gdouble (Q.X), Gdouble (Q.Y));
                     else
                        Cairo.Line_To (Cr, Gdouble (Q.X), Gdouble (Q.Y));
                     end if;
                  end;
               end loop;
               Cairo.Stroke (Cr);
            end loop;
         end if;

         if On (Chk_Det) then
            declare
               Rep : constant Radar_Engine.Snapshot :=
                 Radar_Engine.Last (Eng);
            begin
               Cairo.Set_Source_Rgb (Cr, 0.72, 0.76, 0.74);
               for I in 1 .. Rep.Last_Report.Count loop
                  declare
                     Q : constant Screen_Point :=
                       To_Screen (P, Rep.Last_Report.Items (I).X_Mm,
                                  Rep.Last_Report.Items (I).Y_Mm);
                  begin
                     Cairo.Arc (Cr, Gdouble (Q.X), Gdouble (Q.Y), 3.5, 0.0,
                                2.0 * Pi);
                     Cairo.Stroke (Cr);
                  end;
               end loop;
            end;
         end if;
      end if;

      for I in 1 .. Shown_Count loop
         Screen (I) := To_Screen (P, Shown (I).X, Shown (I).Y);
      end loop;

      if On (Chk_Tracks) then
         for I in 1 .. Shown_Count loop
            declare
               T : View_Track renames Shown (I);
               Q : Screen_Point renames Screen (I);
               E : constant Screen_Point :=
                 To_Screen (P, T.X + T.Vx, T.Y + T.Vy);
            begin
               if T.Coasting then
                  Cairo.Set_Source_Rgb (Cr, 0.55, 0.58, 0.57);
               else
                  Cairo.Set_Source_Rgb (Cr, 0.22, 0.53, 0.90);
               end if;
               Cairo.Arc (Cr, Gdouble (Q.X), Gdouble (Q.Y),
                          (if T.Id = Selected_Id then 8.0 else 6.0),
                          0.0, 2.0 * Pi);
               Cairo.Fill (Cr);
               Cairo.Move_To (Cr, Gdouble (Q.X), Gdouble (Q.Y));
               Cairo.Line_To (Cr, Gdouble (E.X), Gdouble (E.Y));
               Cairo.Stroke (Cr);

               if On (Chk_Labels) then
                  Cairo.Set_Source_Rgb (Cr, 0.90, 0.93, 0.92);
                  if Crowded (Screen (1 .. Shown_Count), I, 70.0) then
                     Text_At (Cr, Q.X + 9.0, Q.Y - 7.0, "#" & Img (T.Id));
                  else
                     Text_At
                       (Cr, Q.X + 9.0, Q.Y - 7.0,
                        "#" & Img (T.Id) & "  "
                        & Fixed_1 (EF.Sqrt (T.X ** 2 + T.Y ** 2) / 1_000.0)
                        & " m  "
                        & Fixed_1 (EF.Sqrt (T.Vx ** 2 + T.Vy ** 2) / 1_000.0)
                        & " m/s");
                  end if;
               end if;
            end;
         end loop;
      end if;
   end Draw_Plan;

   procedure Draw_Map (Cr : Cairo.Cairo_Context; W, H : Float) is
      Steps : constant := 12;

      procedure Ring (R : Float) is
         First : Boolean := True;
      begin
         for I in 0 .. 72 loop
            declare
               A : constant Float := Float (I) * 5.0 * Pi / 180.0;
               Q : constant Projected :=
                 Project (Cam, W, H,
                          (X => R * EF.Cos (A), Y => R * EF.Sin (A),
                           Z => 0.0));
            begin
               if Q.Visible then
                  if First then
                     Cairo.Move_To (Cr, Gdouble (Q.S.X), Gdouble (Q.S.Y));
                     First := False;
                  else
                     Cairo.Line_To (Cr, Gdouble (Q.S.X), Gdouble (Q.S.Y));
                  end if;
               end if;
            end;
         end loop;
         Cairo.Stroke (Cr);
      end Ring;
   begin
      Cairo.Set_Line_Width (Cr, 1.0);
      Cairo.Set_Source_Rgb (Cr, 0.27, 0.31, 0.30);
      for R in 1 .. 5 loop
         Ring (Float (R) * 2_000.0);
      end loop;

      --  Un trace par teinte : Cairo paie au changement de source.
      for T in 0 .. Steps - 1 loop
         declare
            Level : constant Float := Float (T) / Float (Steps - 1);
         begin
            Cairo.Set_Source_Rgb
              (Cr,
               Gdouble (0.30 + 0.45 * Level),
               Gdouble (0.42 + 0.40 * Level),
               Gdouble (0.40 + 0.25 * Level));
            for I in 1 .. Natural (Map.Cloud.Count) loop
               declare
                  P : Point_3D renames Map.Cloud.Points (I);
                  L : constant Integer :=
                    Integer'Max
                      (0, Integer'Min
                         (Steps - 1,
                          Integer (Float'Floor
                            ((P.Z + 1_000.0) / 3_500.0 * Float (Steps)))));
               begin
                  if L = T then
                     declare
                        Q : constant Projected := Project (Cam, W, H, P);
                     begin
                        if Q.Visible then
                           Cairo.Rectangle
                             (Cr, Gdouble (Q.S.X), Gdouble (Q.S.Y), 2.0, 2.0);
                        end if;
                     end;
                  end if;
               end;
            end loop;
            Cairo.Fill (Cr);
         end;
      end loop;

      if Selected_Point in 1 .. Natural (Map.Cloud.Count) then
         declare
            Q : constant Projected :=
              Project (Cam, W, H, Map.Cloud.Points (Selected_Point));
         begin
            if Q.Visible then
               Cairo.Set_Source_Rgb (Cr, 0.95, 0.75, 0.30);
               Cairo.Arc (Cr, Gdouble (Q.S.X), Gdouble (Q.S.Y), 5.0, 0.0,
                          2.0 * Pi);
               Cairo.Stroke (Cr);
            end if;
         end;
      end if;
   end Draw_Map;

   function On_Draw
     (Self : access Gtk_Widget_Record'Class;
      Cr   : Cairo.Cairo_Context) return Boolean
   is
      T0 : constant RT.Time := RT.Clock;
      W  : constant Float := Float (Self.Get_Allocated_Width);
      H  : constant Float := Float (Self.Get_Allocated_Height);
   begin
      Plan_Width  := W;
      Plan_Height := H;
      Cairo.Set_Source_Rgb (Cr, 0.08, 0.10, 0.095);
      Cairo.Paint (Cr);
      Cairo.Set_Font_Size (Cr, 12.0);

      if Mode = Run_Map then
         Draw_Map (Cr, W, H);
      elsif Mode /= None then
         Draw_Plan (Cr, W, H);
      else
         Cairo.Set_Source_Rgb (Cr, 0.62, 0.66, 0.64);
         Text_At (Cr, W / 2.0 - 150.0, H / 2.0,
                  "Aucune source : choisir, puis Démarrer");
      end if;

      if Mode /= None
        and then Is_Simulated (Active_Source, Origin_Now)
      then
         Cairo.Set_Source_Rgba (Cr, 0.95, 0.75, 0.30, 0.16);
         Cairo.Set_Font_Size (Cr, 92.0);
         Text_At (Cr, W / 2.0 - 180.0, H / 2.0 + 30.0, "SIMULÉ");
      end if;

      Draw_Last_Ms := Float (RT.To_Duration (RT.Clock - T0)) * 1_000.0;
      Draw_Max_Ms  := Float'Max (Draw_Max_Ms, Draw_Last_Ms);
      return False;
   end On_Draw;

   --  ----- Souris -----

   procedure Select_At (X, Y : Float) is
      Mouse : constant Screen_Point := (X => X, Y => Y);
   begin
      if Mode = Run_Map then
         declare
            Count : constant Natural := Natural (Map.Cloud.Count);
            Pts   : Screen_Array (1 .. Integer'Max (Count, 1));
            Hit   : Natural;
         begin
            for I in 1 .. Count loop
               declare
                  Q : constant Projected :=
                    Project (Cam, Plan_Width, Plan_Height,
                             Map.Cloud.Points (I));
               begin
                  Pts (I) :=
                    (if Q.Visible then Q.S
                     else (X => -1.0E6, Y => -1.0E6));
               end;
            end loop;
            Hit := Nearest (Pts (1 .. Count), Mouse, 8.0);
            Selected_Point := Hit;
            if Hit = 0 then
               Lbl_Detail.Set_Text ("");
            else
               declare
                  P : Point_3D renames Map.Cloud.Points (Hit);
                  V : constant Polar := To_Polar (P);
               begin
                  Lbl_Detail.Set_Text
                    ("Point #" & Img (Hit) & ASCII.LF
                     & "distance " & Fixed_1 (V.Distance / 1_000.0) & " m"
                     & ASCII.LF
                     & "azimut " & Fixed_1 (V.Azimuth) & " deg" & ASCII.LF
                     & "élévation " & Fixed_1 (V.Elevation) & " deg");
               end;
            end if;
         end;
      elsif Mode /= None then
         declare
            P : constant Plan :=
              (Width => Plan_Width, Height => Plan_Height,
               Range_Mm => (if Mode = Run_Watch_3D then 6_000.0 else 8_000.0),
               Around => Mode = Run_Watch_3D);
            Pts : Screen_Array (1 .. Integer'Max (Shown_Count, 1));
            Hit : Natural;
         begin
            for I in 1 .. Shown_Count loop
               Pts (I) := To_Screen (P, Shown (I).X, Shown (I).Y);
            end loop;
            Hit := Nearest (Pts (1 .. Shown_Count), Mouse, 14.0);
            Selected_Id := (if Hit = 0 then 0 else Shown (Hit).Id);
            if Hit = 0 then
               Lbl_Detail.Set_Text ("");
            else
               declare
                  T : View_Track renames Shown (Hit);
               begin
                  Lbl_Detail.Set_Text
                    ("Piste #" & Img (T.Id) & ASCII.LF
                     & "x " & Fixed_1 (T.X / 1_000.0) & " m, y "
                     & Fixed_1 (T.Y / 1_000.0) & " m" & ASCII.LF
                     & "vx " & Fixed_1 (T.Vx / 1_000.0) & " m/s, vy "
                     & Fixed_1 (T.Vy / 1_000.0) & " m/s");
               end;
            end if;
         end;
      end if;
   end Select_At;

   function On_Press
     (Self  : access Gtk_Widget_Record'Class;
      Event : Gdk_Event_Button) return Boolean
   is
      pragma Unreferenced (Self);
   begin
      Drag_X  := Event.X;
      Drag_Y  := Event.Y;
      Dragged := False;
      return False;
   end On_Press;

   function On_Motion
     (Self  : access Gtk_Widget_Record'Class;
      Event : Gdk_Event_Motion) return Boolean
   is
      pragma Unreferenced (Self);
   begin
      if Mode = Run_Map then
         Cam.Yaw := Cam.Yaw - Float (Event.X - Drag_X) * 0.008;
         Cam.Pitch :=
           Float'Max (-0.2, Float'Min
             (1.5, Cam.Pitch + Float (Event.Y - Drag_Y) * 0.008));
         Dragged := True;
         Drag_X  := Event.X;
         Drag_Y  := Event.Y;
         Area.Queue_Draw;
      end if;
      return False;
   end On_Motion;

   function On_Release
     (Self  : access Gtk_Widget_Record'Class;
      Event : Gdk_Event_Button) return Boolean
   is
      pragma Unreferenced (Self);
   begin
      if not Dragged then
         Select_At (Float (Event.X), Float (Event.Y));
         Area.Queue_Draw;
      end if;
      return False;
   end On_Release;

   function On_Scroll
     (Self  : access Gtk_Widget_Record'Class;
      Event : Gdk_Event_Scroll) return Boolean
   is
      pragma Unreferenced (Self);
   begin
      if Mode = Run_Map then
         Cam.Distance :=
           Float'Max (2_000.0, Float'Min
             (40_000.0,
              Cam.Distance
              * (if Event.Direction = Scroll_Up then 0.9 else 1.1)));
         Area.Queue_Draw;
      end if;
      return False;
   end On_Scroll;

   --  ----- Boutons et reglages -----

   procedure On_Start (Self : access Gtk.Button.Gtk_Button_Record'Class) is
      pragma Unreferenced (Self);
   begin
      Do_Start;
   end On_Start;

   procedure On_Stop (Self : access Gtk.Button.Gtk_Button_Record'Class) is
      pragma Unreferenced (Self);
   begin
      Stop_Session;
      Say ("Arrêté.");
      Update_Choice_Hint;
   end On_Stop;

   procedure On_Recal (Self : access Gtk.Button.Gtk_Button_Record'Class) is
      pragma Unreferenced (Self);
   begin
      if Mode = Run_Watch_3D then
         Radar_Watch_3D.Recalibrate (Watch_3D);
         Say ("Recalibration du décor à la fin du tour en cours.");
      end if;
   end On_Recal;

   function Capture_Path return String is
      Stamp : String := Ada.Calendar.Formatting.Image (Ada.Calendar.Clock);
   begin
      for C of Stamp loop
         if C = ':' or else C = ' ' then
            C := '-';
         end if;
      end loop;
      return Data_Dir & "/capture_" & Stamp & ".ld2450";
   end Capture_Path;

   procedure On_Record (Self : access Gtk.Button.Gtk_Button_Record'Class) is
      Ok   : Boolean := False;
      Path : constant String := Capture_Path;
   begin
      if Mode = Run_Live then
         if Radar_Ld2450_Sim_Source.Is_Recording (Live) then
            Radar_Ld2450_Sim_Source.Stop_Recording (Live);
            Self.Set_Label ("Enregistrer");
            Say ("Enregistrement arrêté.");
         else
            Radar_Ld2450_Sim_Source.Start_Recording (Live, Path, Ok);
            if Ok then
               Self.Set_Label ("Arrêter l'enregistrement");
               Say ("Enregistrement simulé : " & Path);
            else
               Say ("Fichier non créé : " & Path);
            end if;
         end if;
      elsif Mode = Run_Serial then
         if Console_Serial.Is_Recording then
            Console_Serial.Stop_Recording;
            Self.Set_Label ("Enregistrer");
            Say ("Enregistrement arrêté.");
         else
            Console_Serial.Start_Recording (Path, Ok);
            if Ok then
               Self.Set_Label ("Arrêter l'enregistrement");
               Say ("Enregistrement du port : " & Path);
            else
               Say ("Fichier non créé : " & Path);
            end if;
         end if;
      end if;
   end On_Record;

   procedure Spins_From_Settings is
   begin
      Updating_Spins := True;
      Spin_Confirm.Set_Value (Gdouble (Settings.Confirm_Hits));
      Spin_Coast.Set_Value (Gdouble (Settings.Coast_Ms));
      Spin_Speed.Set_Value (Gdouble (Settings.Max_Speed_Mm_S));
      Spin_Replay.Set_Value (Gdouble (Settings.Replay_Percent));
      Spin_Learn.Set_Value (Gdouble (Settings.Learn_Period));
      Spin_Age.Set_Value (Gdouble (Settings.Age_Period));
      Spin_Calib.Set_Value (Gdouble (Settings.Calibration_Turns));
      Spin_Az.Set_Value (Gdouble (Settings.Map_Az_Steps));
      Spin_El.Set_Value (Gdouble (Settings.Map_El_Steps));
      Updating_Spins := False;
   end Spins_From_Settings;

   procedure Apply_Settings is
      Ok : Boolean;
   begin
      Lbl_Learn.Set_Text
        ("Une case de décor est apprise si elle est vue plus de "
         & Img (Radar_Settings.Learn_Threshold_Percent (Settings))
         & " % des tours.");
      if Is_Planar then
         Radar_Engine.Set_Params (Eng, Track_Params);
      end if;
      Radar_Settings.Save (Settings, Settings_Path, Ok);
      if not Ok then
         Say ("Réglages non enregistrés : " & Settings_Path);
      end if;
   end Apply_Settings;

   procedure On_Spin
     (Self : access Gtk.Spin_Button.Gtk_Spin_Button_Record'Class)
   is
      pragma Unreferenced (Self);
   begin
      if Updating_Spins then
         return;
      end if;
      Settings :=
        (Confirm_Hits      => Integer (Spin_Confirm.Get_Value_As_Int),
         Coast_Ms          => Integer (Spin_Coast.Get_Value_As_Int),
         Max_Speed_Mm_S    => Integer (Spin_Speed.Get_Value_As_Int),
         Replay_Percent    => Integer (Spin_Replay.Get_Value_As_Int),
         Learn_Period      => Integer (Spin_Learn.Get_Value_As_Int),
         Age_Period        => Integer (Spin_Age.Get_Value_As_Int),
         Calibration_Turns => Integer (Spin_Calib.Get_Value_As_Int),
         Map_Az_Steps      => Integer (Spin_Az.Get_Value_As_Int),
         Map_El_Steps      => Integer (Spin_El.Get_Value_As_Int));
      Apply_Settings;
   end On_Spin;

   procedure On_Defaults (Self : access Gtk.Button.Gtk_Button_Record'Class) is
      pragma Unreferenced (Self);
   begin
      Settings := Radar_Settings.Defaults;
      Spins_From_Settings;
      Apply_Settings;
      Say ("Réglages par défaut rétablis.");
   end On_Defaults;

   procedure On_Combo (Self : access Gtk.Combo_Box.Gtk_Combo_Box_Record'Class)
   is
      pragma Unreferenced (Self);
   begin
      Update_Choice_Hint;
   end On_Combo;

   procedure On_Layer
     (Self : access Gtk.Toggle_Button.Gtk_Toggle_Button_Record'Class)
   is
      pragma Unreferenced (Self);
   begin
      Area.Queue_Draw;
   end On_Layer;

   procedure On_Window_Destroy (Self : access Gtk_Widget_Record'Class) is
      pragma Unreferenced (Self);
   begin
      if Mode = Run_Serial then
         Console_Serial.Close (Serial);
      elsif Mode = Run_Live then
         Radar_Ld2450_Sim_Source.Stop_Recording (Live);
      end if;
      Gtk.Main.Main_Quit;
   end On_Window_Destroy;

   --  ----- Construction -----

   Css : constant String :=
     "* { font-family: 'Segoe UI', sans-serif; font-size: 10pt; }" &
     ".etat { font-family: Consolas, monospace; padding: 2px 10px; }" &
     ".note { color: #9aa5a0; }";

   procedure Make_Label
     (L : out Gtk.Label.Gtk_Label; Text : String; Width : Gint := -1;
      Style : String := "") is
   begin
      Gtk.Label.Gtk_New (L, Text);
      L.Set_Xalign (0.0);
      if Width > 0 then
         L.Set_Width_Chars (Width);
         L.Set_Max_Width_Chars (Width);
      end if;
      if Style /= "" then
         Gtk.Style_Context.Get_Style_Context (L).Add_Class (Style);
      end if;
   end Make_Label;

   procedure Make_Check
     (C : out Gtk.Check_Button.Gtk_Check_Button;
      Text : String;
      Box  : Gtk.Box.Gtk_Box) is
   begin
      Gtk.Check_Button.Gtk_New (C, Text);
      C.Set_Active (True);
      C.On_Toggled (On_Layer'Access);
      Box.Pack_Start (C, False, False, 0);
   end Make_Check;

   procedure Add_Spin
     (G     : Gtk.Grid.Gtk_Grid;
      Row   : in out Gint;
      S     : out Gtk.Spin_Button.Gtk_Spin_Button;
      Name  : String;
      Lo, Hi, Step : Gdouble;
      Tag   : String)
   is
      Lab, T : Gtk.Label.Gtk_Label;
   begin
      Make_Label (Lab, Name);
      Gtk.Spin_Button.Gtk_New (S, Lo, Hi, Step);
      S.On_Value_Changed (On_Spin'Access);
      Make_Label (T, Tag, Style => "note");
      G.Attach (Lab, 0, Row);
      G.Attach (S, 1, Row);
      G.Attach (T, 2, Row);
      Row := Row + 1;
   end Add_Spin;

   function Build_Settings return Gtk_Widget is
      G    : Gtk.Grid.Gtk_Grid;
      Row  : Gint := 0;
      Btn  : Gtk.Button.Gtk_Button;
      Head : Gtk.Label.Gtk_Label;

      procedure Section (Text : String) is
      begin
         Make_Label (Head, Text);
         Head.Set_Margin_Top (12);
         G.Attach (Head, 0, Row, 3);
         Row := Row + 1;
      end Section;
   begin
      Gtk.Grid.Gtk_New (G);
      G.Set_Row_Spacing (6);
      G.Set_Column_Spacing (16);
      G.Set_Border_Width (16);

      Section ("Pistage 2D (hypothèses, non mesurées sur un module réel)");
      Add_Spin (G, Row, Spin_Confirm, "Détections pour confirmer", 2.0, 5.0,
                1.0, "immédiat");
      Add_Spin (G, Row, Spin_Coast, "Durée de survie sans écho (ms)",
                1_000.0, 10_000.0, 100.0, "immédiat");
      Add_Spin (G, Row, Spin_Speed, "Vitesse maximale (mm/s)", 1_000.0,
                6_000.0, 100.0, "immédiat");
      Section ("Rejeu");
      Add_Spin (G, Row, Spin_Replay, "Vitesse de lecture (%)", 50.0, 800.0,
                10.0, "immédiat");
      Section ("Veille 3D simulée");
      Add_Spin (G, Row, Spin_Calib, "Tours de calibration", 2.0, 32.0, 1.0,
                "au redémarrage");
      Add_Spin (G, Row, Spin_Learn, "Apprentissage : 1 tour sur", 1.0, 16.0,
                1.0, "au redémarrage");
      Add_Spin (G, Row, Spin_Age, "Oubli : 1 fois tous les (tours)", 8.0,
                128.0, 1.0, "au redémarrage");
      Make_Label (Lbl_Learn, "", Style => "note");
      G.Attach (Lbl_Learn, 0, Row, 3);
      Row := Row + 1;
      Section ("Cartographie simulée");
      Add_Spin (G, Row, Spin_Az, "Colonnes d'azimut", 60.0, 360.0, 10.0,
                "au redémarrage");
      Add_Spin (G, Row, Spin_El, "Rangées d'élévation", 8.0, 32.0, 1.0,
                "au redémarrage");

      Gtk.Button.Gtk_New (Btn, "Rétablir les valeurs par défaut");
      Btn.On_Clicked (On_Defaults'Access);
      Btn.Set_Margin_Top (14);
      G.Attach (Btn, 0, Row, 2);
      return Gtk_Widget (G);
   end Build_Settings;

   function Build_Text
     (Buffer : out Gtk.Text_Buffer.Gtk_Text_Buffer) return Gtk_Widget
   is
      V : Gtk.Text_View.Gtk_Text_View;
      S : Gtk.Scrolled_Window.Gtk_Scrolled_Window;
   begin
      Gtk.Text_Buffer.Gtk_New (Buffer);
      Gtk.Text_View.Gtk_New (V, Buffer);
      V.Set_Editable (False);
      V.Set_Cursor_Visible (False);
      V.Set_Left_Margin (10);
      V.Set_Top_Margin (8);
      Gtk.Scrolled_Window.Gtk_New (S);
      S.Add (V);
      return Gtk_Widget (S);
   end Build_Text;

   function Build_Diagnostic return Gtk_Widget is
      Box : Gtk.Box.Gtk_Box;
      Lab : Gtk.Label.Gtk_Label;
   begin
      Gtk.Box.Gtk_New (Box, Orientation_Vertical, 6);
      Box.Set_Border_Width (10);
      Make_Label (Lab, "Compteurs");
      Box.Pack_Start (Lab, False, False, 0);
      Box.Pack_Start (Build_Text (Diag_Buffer), True, True, 0);
      Make_Label (Lab, "Journal");
      Box.Pack_Start (Lab, False, False, 0);
      Box.Pack_Start (Build_Text (Journal), True, True, 0);
      return Gtk_Widget (Box);
   end Build_Diagnostic;

   function Build_Watch return Gtk_Widget is
      Row      : Gtk.Box.Gtk_Box;
      Left     : Gtk.Box.Gtk_Box;
      Right    : Gtk.Box.Gtk_Box;
      Exp_L    : Gtk.Expander.Gtk_Expander;
      Exp_R    : Gtk.Expander.Gtk_Expander;
   begin
      Gtk.Box.Gtk_New (Row, Orientation_Horizontal, 0);

      Gtk.Expander.Gtk_New (Exp_L, "Couches");
      Exp_L.Set_Margin_Start (6);
      Gtk.Box.Gtk_New (Left, Orientation_Vertical, 4);
      Make_Check (Chk_Det, "Détections", Left);
      Make_Check (Chk_Tracks, "Pistes", Left);
      Make_Check (Chk_Trails, "Traînées", Left);
      Make_Check (Chk_Labels, "Étiquettes", Left);
      Make_Check (Chk_Decor, "Décor", Left);
      Make_Check (Chk_Field, "Champ du capteur", Left);
      Exp_L.Add (Left);
      Row.Pack_Start (Exp_L, False, False, 4);

      Gtk.Stack.Gtk_New (Center);
      Gtk.Drawing_Area.Gtk_New (Area);
      Area.Add_Events
        (Button_Press_Mask or Button_Release_Mask or Button1_Motion_Mask
         or Scroll_Mask);
      Area.On_Draw (On_Draw'Access);
      Area.On_Button_Press_Event (On_Press'Access);
      Area.On_Button_Release_Event (On_Release'Access);
      Area.On_Motion_Notify_Event (On_Motion'Access);
      Area.On_Scroll_Event (On_Scroll'Access);
      Center.Add_Named (Area, "scene");
      Center.Add_Named (Build_Text (Sar_Buffer), "texte");
      Row.Pack_Start (Center, True, True, 0);

      Gtk.Expander.Gtk_New (Exp_R, "Pistes");
      Exp_R.Set_Margin_End (6);
      Exp_R.Set_Expanded (True);
      Gtk.Box.Gtk_New (Right, Orientation_Vertical, 8);
      Make_Label (Lbl_Tracks, "Aucune piste confirmée", 34, "etat");
      Lbl_Tracks.Set_Yalign (0.0);
      Make_Label (Lbl_Detail, "", 34, "etat");
      Right.Pack_Start (Lbl_Tracks, False, False, 0);
      Right.Pack_Start (Lbl_Detail, False, False, 0);
      Exp_R.Add (Right);
      Row.Pack_Start (Exp_R, False, False, 4);
      return Gtk_Widget (Row);
   end Build_Watch;

   procedure Run is
      Root, Top, Bottom : Gtk.Box.Gtk_Box;
      Status   : Gtk.Grid.Gtk_Grid;
      Views    : Gtk.Stack.Gtk_Stack;
      Switcher : Gtk.Stack_Switcher.Gtk_Stack_Switcher;
      Provider : Gtk.Css_Provider.Gtk_Css_Provider;
      Message  : Unbounded_String;
      Css_Ok   : Boolean;
      Id       : Glib.Main.G_Source_Id;
      pragma Unreferenced (Id);
   begin
      Gtk.Main.Init;

      Glib.Properties.Set_Property
        (Gtk.Settings.Get_Default,
         Gtk.Settings.Gtk_Application_Prefer_Dark_Theme_Property, True);
      Gtk.Css_Provider.Gtk_New (Provider);
      Css_Ok := Provider.Load_From_Data (Css, null);
      if Css_Ok then
         Gtk.Style_Context.Add_Provider_For_Screen
           (Gdk.Screen.Get_Default, Gtk.Css_Provider."+" (Provider),
            Gtk.Style_Provider.Priority_Application);
      end if;

      Gtk.Window.Gtk_New (Win);
      Win.Set_Title ("radar_fw");
      Win.Set_Default_Size (1240, 720);
      Win.On_Destroy (On_Window_Destroy'Access);

      Gtk.Box.Gtk_New (Root, Orientation_Vertical, 0);
      Win.Add (Root);

      --  Le bandeau : champs a largeur fixe, rien ne bouge quand un chiffre
      --  change.
      Gtk.Box.Gtk_New (Top, Orientation_Horizontal, 0);
      Top.Set_Border_Width (6);
      Gtk.Stack.Gtk_New (Views);
      Views.Set_Vexpand (True);
      Gtk.Stack_Switcher.Gtk_New (Switcher);
      Switcher.Set_Stack (Views);
      Top.Pack_Start (Switcher, False, False, 0);
      Make_Label (Lbl_Source, "SOURCE  aucune", 42, "etat");
      Make_Label (Lbl_Link, "LIAISON  -", 42, "etat");
      Make_Label (Lbl_Frames, "TRAMES  -", 38, "etat");
      Make_Label (Lbl_Plaus, "PLAUSIBILITÉ  -", 38, "etat");
      Make_Label (Lbl_Alert, "ALERTES  0", 14, "etat");
      Gtk.Grid.Gtk_New (Status);
      Status.Attach (Lbl_Source, 0, 0);
      Status.Attach (Lbl_Link, 0, 1);
      Status.Attach (Lbl_Frames, 1, 0);
      Status.Attach (Lbl_Plaus, 1, 1);
      Status.Attach (Lbl_Alert, 2, 0);
      Top.Pack_Start (Status, False, False, 8);
      Root.Pack_Start (Top, False, False, 0);

      Views.Add_Titled (Build_Watch, "veille", "Veille");
      Views.Add_Titled (Build_Settings, "reglages", "Réglages");
      Views.Add_Titled (Build_Diagnostic, "diagnostic", "Diagnostic");
      Root.Pack_Start (Views, True, True, 0);

      --  Le parcours : source, activite, demarrer.
      Gtk.Box.Gtk_New (Bottom, Orientation_Horizontal, 8);
      Bottom.Set_Border_Width (8);

      Gtk.Combo_Box_Text.Gtk_New (Src_Combo);
      for S in Source_Kind loop
         Src_Combo.Append_Text (Source_Label (S));
      end loop;
      Src_Combo.Set_Active (Source_Kind'Pos (Sim_Ld2450));
      Src_Combo.On_Changed (On_Combo'Access);
      Bottom.Pack_Start (Src_Combo, False, False, 0);

      Gtk.GEntry.Gtk_New (Port_Entry);
      Port_Entry.Set_Text ("COM3");
      Port_Entry.Set_Width_Chars (8);
      Bottom.Pack_Start (Port_Entry, False, False, 0);

      Gtk.File_Chooser_Button.Gtk_New
        (File_Btn, "Fichier de capture", Gtk.File_Chooser.Action_Open);
      File_Btn.Set_Width_Chars (18);
      Bottom.Pack_Start (File_Btn, False, False, 0);

      Gtk.Combo_Box_Text.Gtk_New (Act_Combo);
      for A in Activity_Kind loop
         Act_Combo.Append_Text (Activity_Label (A));
      end loop;
      Act_Combo.Set_Active (0);
      Act_Combo.On_Changed (On_Combo'Access);
      Bottom.Pack_Start (Act_Combo, False, False, 0);

      Gtk.Button.Gtk_New (Start_Btn, "Démarrer");
      Start_Btn.On_Clicked (On_Start'Access);
      Bottom.Pack_Start (Start_Btn, False, False, 0);
      Gtk.Button.Gtk_New (Stop_Btn, "Arrêter");
      Stop_Btn.On_Clicked (On_Stop'Access);
      Bottom.Pack_Start (Stop_Btn, False, False, 0);
      Gtk.Button.Gtk_New (Rec_Btn, "Enregistrer");
      Rec_Btn.On_Clicked (On_Record'Access);
      Bottom.Pack_Start (Rec_Btn, False, False, 0);
      Gtk.Button.Gtk_New (Recal_Btn, "Recalibrer le décor");
      Recal_Btn.On_Clicked (On_Recal'Access);
      Bottom.Pack_Start (Recal_Btn, False, False, 0);

      Make_Label (Lbl_Msg, "", Style => "note");
      --  Un chemin long ne doit pas elargir la fenetre : tronque ici, entier
      --  dans le journal.
      Lbl_Msg.Set_Ellipsize (Pango.Layout.Ellipsize_End);
      Lbl_Msg.Set_Width_Chars (10);
      Bottom.Pack_Start (Lbl_Msg, True, True, 6);
      Root.Pack_Start (Bottom, False, False, 0);

      Radar_Settings.Load (Settings, Settings_Path, Message);
      Spins_From_Settings;

      --  Capture passee en argument : celle sur laquelle on a double-clique.
      if Ada.Command_Line.Argument_Count >= 1
        and then File_Btn.Set_Filename (Ada.Command_Line.Argument (1))
      then
         Src_Combo.Set_Active (Source_Kind'Pos (Capture_File));
      end if;

      Win.Show_All;
      Set_Running_Buttons;
      Update_Choice_Hint;
      Apply_Settings;
      if Length (Message) > 0 then
         Say (To_String (Message));
      end if;
      Update_Status;

      Id := Glib.Main.Timeout_Add (30, Tick'Access);
      Gtk.Main.Main;
   end Run;

end Console_Ui;
