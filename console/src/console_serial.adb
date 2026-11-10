with Ada.Real_Time;   use Ada.Real_Time;
with Radar_Ld2450;    use Radar_Ld2450;
with Radar_Ld2450_Log;
with Radar_Ld2450_Replay;
with Radar_Serial_Win32;
with Radar_Source;    use Radar_Source;

package body Console_Serial is

   --  2 s de flux a 300 octets/s suffiraient ; 16 Kio laissent de la marge
   --  si la fenetre rame, et au-dela on compte ce qu'on jette.
   Capacity : constant := 16_384;

   type Byte_Ring is array (1 .. Capacity) of Byte;

   protected Buffer is
      procedure Reset;
      procedure Put (Data : Byte_Array; Stamp : Time_Ms);
      procedure Get (B : out Byte; Stamp : out Time_Ms; Found : out Boolean);
      procedure Set_Lost;
      function Is_Lost return Boolean;
      function Is_Empty return Boolean;
      function Lost_Bytes return Natural;
   private
      Ring  : Byte_Ring;
      First : Positive := 1;
      Count : Natural  := 0;
      Dropped : Natural := 0;
      Last_Stamp : Time_Ms := 0;
      Lost  : Boolean  := False;
   end Buffer;

   protected body Buffer is
      procedure Reset is
      begin
         First := 1;
         Count := 0;
         Dropped := 0;
         Lost := False;
      end Reset;

      procedure Put (Data : Byte_Array; Stamp : Time_Ms) is
      begin
         Last_Stamp := Stamp;
         for B of Data loop
            if Count = Capacity then
               Dropped := Dropped + 1;
            else
               Ring ((First + Count - 1) mod Capacity + 1) := B;
               Count := Count + 1;
            end if;
         end loop;
      end Put;

      procedure Get (B : out Byte; Stamp : out Time_Ms; Found : out Boolean) is
      begin
         Stamp := Last_Stamp;
         Found := Count > 0;
         B     := 0;
         if Found then
            B     := Ring (First);
            First := First mod Capacity + 1;
            Count := Count - 1;
         end if;
      end Get;

      procedure Set_Lost is
      begin
         Lost := True;
      end Set_Lost;

      function Is_Lost return Boolean is (Lost);
      function Is_Empty return Boolean is (Count = 0);
      function Lost_Bytes return Natural is (Dropped);
   end Buffer;

   Opened : Boolean := False with Atomic;

   --  Une seule entree/sortie du port, sur cette tache : un Read Win32 attend
   --  jusqu'a son delai.
   task Reader is
      entry Open (Name : String; Ok : out Boolean; Why : out Integer);
      entry Close;
   end Reader;

   task body Reader is
      Port  : Radar_Serial_Win32.Port;
      Start : Time := Clock;
      Chunk : Byte_Array (1 .. 512);
   begin
      loop
         select
            accept Open (Name : String; Ok : out Boolean; Why : out Integer) do
               Radar_Serial_Win32.Open (Port, Name, Ok, Why);
               if Ok then
                  Start := Clock;
                  Buffer.Reset;
                  Opened := True;
               end if;
            end Open;
         or
            accept Close;
         or
            terminate;
         end select;

         while Opened loop
            select
               accept Close;
               Radar_Serial_Win32.Close (Port);
               Opened := False;
            else
               declare
                  Last : Natural;
                  Ok   : Boolean;
               begin
                  Radar_Serial_Win32.Read (Port, Chunk, Last, Ok);
                  if not Ok then
                     Buffer.Set_Lost;
                     Radar_Serial_Win32.Close (Port);
                     Opened := False;
                  elsif Last >= Chunk'First then
                     Buffer.Put
                       (Chunk (Chunk'First .. Last),
                        Time_Ms (To_Duration (Clock - Start) * 1_000.0));
                  end if;
               end;
            end select;
         end loop;
      end loop;
   exception
      when others =>
         Buffer.Set_Lost;
         Opened := False;
   end Reader;

   type Writer_Access is access Radar_Ld2450_Log.Writer;
   Log : Writer_Access;
   Log_Base    : Time_Ms := 0;
   Log_Started : Boolean := False;

   procedure Open
     (Self : in out Serial_Source;
      Name : String;
      Ok   : out Boolean;
      Why  : out Integer)
   is
      Fresh : Serial_Source;
   begin
      Self := Fresh;
      Reader.Open (Name, Ok, Why);
   end Open;

   procedure Close (Self : in out Serial_Source) is
      pragma Unreferenced (Self);
   begin
      if Opened then
         Reader.Close;
      end if;
      Stop_Recording;
   end Close;

   overriding
   procedure Next_Report
     (Self      : in out Serial_Source;
      Result    : out Radar_Planar_Source.Planar_Report;
      Available : out Boolean)
   is
      B     : Byte;
      Stamp : Time_Ms;
      Found : Boolean;
   begin
      Result    := (others => <>);
      Available := False;
      loop
         Buffer.Get (B, Stamp, Found);
         exit when not Found;

         if Log /= null then
            --  Comme l'emulateur : le fichier part de zero, sinon le rejeu
            --  prendrait le debut pour un silence.
            if not Log_Started then
               Log_Started := True;
               Log_Base    := Stamp;
            end if;
            Radar_Ld2450_Log.Append
              (Log.all, Stamp - Log_Base, Byte_Array'(1 => B));
         end if;

         declare
            Frame : Radar_Ld2450_Stream.Decoded_Frame;
            Ready : Boolean;
         begin
            Radar_Ld2450_Stream.Feed (Self.Parser, B, Frame, Ready);
            if Ready then
               declare
                  Raw     : Raw_Report;
                  Elapsed : constant Natural :=
                    (if Self.Primed and then Natural (Stamp) > Self.Last
                     then Natural (Stamp) - Self.Last else 0);
               begin
                  Radar_Ld2450_Plausibility.Validate
                    (Self.Filter, Frame.Targets, Elapsed, Raw);
                  Result := Radar_Ld2450_Replay.To_Report (Raw, Stamp, 1);
                  Self.Last   := Natural (Stamp);
                  Self.Primed := True;
                  Available   := True;
                  return;
               end;
            end if;
         end;
      end loop;
   end Next_Report;

   overriding
   function Has_More (Self : Serial_Source) return Boolean is
      pragma Unreferenced (Self);
   begin
      return not (Buffer.Is_Lost and then Buffer.Is_Empty);
   end Has_More;

   function Port_Open return Boolean is (Opened);

   function Lost_Bytes return Natural is (Buffer.Lost_Bytes);

   procedure Start_Recording (Path : String; Ok : out Boolean) is
   begin
      Stop_Recording;
      Log_Started := False;
      Log := new Radar_Ld2450_Log.Writer;
      Radar_Ld2450_Log.Create
        (Log.all, Path, Radar_Ld2450_Log.Origin_Hardware, Ok);
      if not Ok then
         Log := null;
      end if;
   end Start_Recording;

   procedure Stop_Recording is
   begin
      if Log /= null then
         Radar_Ld2450_Log.Close (Log.all);
         Log := null;
      end if;
   end Stop_Recording;

   function Is_Recording return Boolean is (Log /= null);

   function Stream (Self : Serial_Source) return Radar_Ld2450_Stream.Parser is
     (Self.Parser);

   function Checks
     (Self : Serial_Source) return Radar_Ld2450_Plausibility.Validator is
     (Self.Filter);

end Console_Serial;
