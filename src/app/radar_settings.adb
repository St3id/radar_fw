with Ada.IO_Exceptions;
with Ada.Strings.Fixed;
with Ada.Text_IO;

package body Radar_Settings is

   use Ada.Strings.Unbounded;

   Version_Line : constant String := "radar_fw_settings=1";

   function Img (V : Integer) return String is
     (Ada.Strings.Fixed.Trim (Integer'Image (V), Ada.Strings.Both));

   procedure Save (S : Settings; Path : String; Ok : out Boolean) is
      use Ada.Text_IO;
      F : File_Type;

      procedure Put_Key (Key : String; V : Integer) is
      begin
         Put_Line (F, Key & "=" & Img (V));
      end Put_Key;
   begin
      Create (F, Out_File, Path);
      Put_Line (F, Version_Line);
      Put_Key ("confirm_hits", S.Confirm_Hits);
      Put_Key ("coast_ms", S.Coast_Ms);
      Put_Key ("max_speed_mm_s", S.Max_Speed_Mm_S);
      Put_Key ("replay_percent", S.Replay_Percent);
      Put_Key ("learn_period", S.Learn_Period);
      Put_Key ("age_period", S.Age_Period);
      Put_Key ("calibration_turns", S.Calibration_Turns);
      Put_Key ("map_az_steps", S.Map_Az_Steps);
      Put_Key ("map_el_steps", S.Map_El_Steps);
      Close (F);
      Ok := True;
   exception
      when Ada.IO_Exceptions.Name_Error
         | Ada.IO_Exceptions.Use_Error
         | Ada.IO_Exceptions.Device_Error =>
         if Is_Open (F) then
            Close (F);
         end if;
         Ok := False;
   end Save;

   procedure Load
     (S       : out Settings;
      Path    : String;
      Message : out Unbounded_String)
   is
      use Ada.Text_IO;
      F : File_Type;

      procedure Bad (Key : String) is
      begin
         Append (Message, "Valeur invalide pour " & Key & ", defaut garde. ");
      end Bad;

      --  Un generique par sous-type borne : une conversion hors bornes leve
      --  Constraint_Error, qui devient le message.
      generic
         type Field is range <>;
      procedure Read_Field
        (Key : String; Text : String; Into : in out Integer);

      procedure Read_Field
        (Key : String; Text : String; Into : in out Integer)
      is
      begin
         declare
            --  'Value ne verifie que le type de base : c'est la declaration
            --  de V, dans le sous-type, qui rejette 99 pour un champ 2 .. 5.
            --  Dans un bloc : le traite-exception ci-dessous ne couvre pas
            --  la partie declarative de la procedure elle-meme.
            V : constant Field := Field'Value (Text);
         begin
            Into := Integer (V);
         end;
      exception
         when Constraint_Error =>
            Bad (Key);
      end Read_Field;

      type Confirm_T is new Confirm_Range;
      type Coast_T   is new Coast_Range;
      type Speed_T   is new Speed_Range;
      type Replay_T  is new Replay_Range;
      type Learn_T   is new Learn_Range;
      type Age_T     is new Age_Range;
      type Calib_T   is new Calib_Range;
      type Az_T      is new Az_Steps_Range;
      type El_T      is new El_Steps_Range;

      procedure Read_Confirm is new Read_Field (Confirm_T);
      procedure Read_Coast   is new Read_Field (Coast_T);
      procedure Read_Speed   is new Read_Field (Speed_T);
      procedure Read_Replay  is new Read_Field (Replay_T);
      procedure Read_Learn   is new Read_Field (Learn_T);
      procedure Read_Age     is new Read_Field (Age_T);
      procedure Read_Calib   is new Read_Field (Calib_T);
      procedure Read_Az      is new Read_Field (Az_T);
      procedure Read_El      is new Read_Field (El_T);
   begin
      S := Defaults;
      Message := Null_Unbounded_String;

      Open (F, In_File, Path);
      if End_Of_File (F) or else Get_Line (F) /= Version_Line then
         Close (F);
         Message := To_Unbounded_String ("Version inconnue, defauts.");
         return;
      end if;

      while not End_Of_File (F) loop
         declare
            Line : constant String := Get_Line (F);
            Eq   : constant Natural :=
              Ada.Strings.Fixed.Index (Line, "=");
         begin
            if Eq = 0 then
               Bad (Line);
            else
               declare
                  Key : constant String := Line (Line'First .. Eq - 1);
                  Val : constant String := Line (Eq + 1 .. Line'Last);
               begin
                  if Key = "confirm_hits" then
                     Read_Confirm (Key, Val, S.Confirm_Hits);
                  elsif Key = "coast_ms" then
                     Read_Coast (Key, Val, S.Coast_Ms);
                  elsif Key = "max_speed_mm_s" then
                     Read_Speed (Key, Val, S.Max_Speed_Mm_S);
                  elsif Key = "replay_percent" then
                     Read_Replay (Key, Val, S.Replay_Percent);
                  elsif Key = "learn_period" then
                     Read_Learn (Key, Val, S.Learn_Period);
                  elsif Key = "age_period" then
                     Read_Age (Key, Val, S.Age_Period);
                  elsif Key = "calibration_turns" then
                     Read_Calib (Key, Val, S.Calibration_Turns);
                  elsif Key = "map_az_steps" then
                     Read_Az (Key, Val, S.Map_Az_Steps);
                  elsif Key = "map_el_steps" then
                     Read_El (Key, Val, S.Map_El_Steps);
                  else
                     Bad (Key);
                  end if;
               end;
            end if;
         end;
      end loop;
      Close (F);
   exception
      when Ada.IO_Exceptions.Name_Error =>
         null;
      when Ada.IO_Exceptions.Use_Error | Ada.IO_Exceptions.Device_Error =>
         if Is_Open (F) then
            Close (F);
         end if;
         Message := To_Unbounded_String ("Reglages illisibles, defauts.");
   end Load;

end Radar_Settings;
