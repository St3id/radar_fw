with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Real_Time;
with Ada.Text_IO;
with Radar_Ld2450;
with Radar_Ld2450_Log;
with Radar_Serial_Win32;
with Radar_Source;

--  Radar_Ld2450_Record : copie un flux serie vers un fichier de capture, avec
--  l'heure de reception de chaque bloc (format : Radar_Ld2450_Log).
--
--     radar_ld2450_record <port> <fichier> [duree en secondes, 60 par defaut]
--
--  Un outil a part plutot qu'un 6e mode de radar_fw : il n'a besoin ni du
--  pipeline ni du serveur, le poste de mesure n'a pas a les compiler, et le
--  port serie reste hors de l'application. Le fichier se relit ensuite par
--  Radar_Ld2450_Replay.
--
--  NON VALIDE SUR MATERIEL : aucun module n'existe a ce jour. Ce programme
--  n'a execute que ses chemins d'erreur. Ce qu'il promet (octets complets,
--  heures justes a la latence pres) reste a verifier au premier branchement.
--
--  Il ne parle pas au module : si celui-ci est en mono-cible, la capture le
--  sera aussi.

procedure Radar_Ld2450_Record is

   use Ada.Text_IO;
   use type Ada.Real_Time.Time;

   --  Quand rien n'arrive, un bloc vide au plus toutes les secondes : le
   --  fichier dit ainsi que la liaison etait ouverte et le module muet.
   Marker_Period_Ms : constant := 1_000;

   procedure Usage is
   begin
      Put_Line
        ("usage : radar_ld2450_record <port> <fichier> [duree_s, defaut 60]");
      Put_Line ("exemple : radar_ld2450_record COM3 out/capture.ld2450 60");
   end Usage;

   Duration_S : Natural := 60;
begin
   if Ada.Command_Line.Argument_Count not in 2 .. 3 then
      Usage;
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   if Ada.Command_Line.Argument_Count = 3 then
      begin
         Duration_S := Natural'Value (Ada.Command_Line.Argument (3));
      exception
         when Constraint_Error =>
            Usage;
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
      end;
   end if;

   declare
      Port_Name : constant String := Ada.Command_Line.Argument (1);
      Path      : constant String := Ada.Command_Line.Argument (2);
      Port      : Radar_Serial_Win32.Port;
      Log       : Radar_Ld2450_Log.Writer;
      Ok        : Boolean;
      Why       : Integer;
      Buffer    : Radar_Ld2450.Byte_Array (1 .. 1_024);
      Last      : Natural;
      Total     : Long_Long_Integer := 0;
      Chunks    : Long_Long_Integer := 0;
      Start     : Ada.Real_Time.Time;
      Marker_At : Radar_Source.Time_Ms := Marker_Period_Ms;

      use type Radar_Source.Time_Ms;

      --  Les millisecondes depuis le debut de la capture.
      function Now_Ms return Radar_Source.Time_Ms is
        (Radar_Source.Time_Ms
           (Duration'Min
              (Ada.Real_Time.To_Duration (Ada.Real_Time.Clock - Start)
               * 1_000.0,
               Duration (Radar_Source.Time_Ms'Last / 1_000) * 1_000.0)));
   begin
      Radar_Serial_Win32.Open (Port, Port_Name, Ok, Why);
      if not Ok then
         Put_Line
           (Standard_Error,
            "Port " & Port_Name & " non ouvert ou refuse a"
            & Natural'Image (Radar_Serial_Win32.Serial_Rate)
            & " bauds (erreur Windows" & Why'Image & ")");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      Radar_Ld2450_Log.Create (Log, Path, Ok);
      if not Ok then
         Put_Line (Standard_Error, "Fichier " & Path & " non cree");
         Radar_Serial_Win32.Close (Port);
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      Put_Line ("Capture de" & Duration_S'Image & " s sur " & Port_Name
                & " vers " & Path & " (NON VALIDE SUR MATERIEL)");
      Start := Ada.Real_Time.Clock;

      while Now_Ms < Radar_Source.Time_Ms (Duration_S) * 1_000 loop
         Radar_Serial_Win32.Read (Port, Buffer, Last, Ok);
         if not Ok then
            Put_Line (Standard_Error, "Lecture du port en echec : arret");
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            exit;
         end if;

         declare
            Stamp : constant Radar_Source.Time_Ms := Now_Ms;
         begin
            if Last >= Buffer'First then
               Radar_Ld2450_Log.Append
                 (Log, Stamp, Buffer (Buffer'First .. Last));
               Total     := Total + Long_Long_Integer (Last);
               Chunks    := Chunks + 1;
               Marker_At := Stamp + Marker_Period_Ms;
            elsif Stamp >= Marker_At then
               Radar_Ld2450_Log.Append (Log, Stamp, Buffer (1 .. 0));
               Marker_At := Stamp + Marker_Period_Ms;
            end if;
         end;
      end loop;

      Radar_Ld2450_Log.Close (Log);
      Radar_Serial_Win32.Close (Port);
      Put_Line ("Termine :" & Total'Image & " octets en" & Chunks'Image
                & " blocs");
   exception
      when E : others =>
         Put_Line (Standard_Error,
                   "Arret sur exception : "
                   & Ada.Exceptions.Exception_Message (E));
         Radar_Ld2450_Log.Close (Log);
         Radar_Serial_Win32.Close (Port);
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end;
end Radar_Ld2450_Record;
