with Ada.IO_Exceptions;

package body Radar_Ld2450_Log is

   use Ada.Streams;
   use Radar_Ld2450;

   Header_Bytes : constant := 6;   --  4 pour l'heure, 2 pour la longueur

   ------------
   -- Create --
   ------------

   procedure Create (W : in out Writer; Path : String; Ok : out Boolean) is
      Head : Stream_Element_Array (1 .. Magic'Length);
   begin
      Stream_IO.Create (W.File, Stream_IO.Out_File, Path);
      for I in Head'Range loop
         Head (I) :=
           Stream_Element
             (Character'Pos (Magic (Magic'First + Integer (I) - 1)));
      end loop;
      Stream_IO.Write (W.File, Head);
      Ok := True;
   exception
      when Ada.IO_Exceptions.Name_Error | Ada.IO_Exceptions.Use_Error =>
         Ok := False;
   end Create;

   ------------
   -- Append --
   ------------

   procedure Append
     (W     : in out Writer;
      Stamp : Radar_Source.Time_Ms;
      Bytes : Radar_Ld2450.Byte_Array)
   is
      --  Long_Long_Integer : les divisions sur l'heure restent evidentes,
      --  et aucun calcul intermediaire ne frole la borne de Time_Ms.
      S     : constant Long_Long_Integer := Long_Long_Integer (Stamp);
      Block : Stream_Element_Array
        (1 .. Stream_Element_Offset (Header_Bytes + Bytes'Length));
   begin
      Block (1) := Stream_Element (S mod 256);
      Block (2) := Stream_Element ((S / 2 ** 8) mod 256);
      Block (3) := Stream_Element ((S / 2 ** 16) mod 256);
      Block (4) := Stream_Element ((S / 2 ** 24) mod 256);
      Block (5) := Stream_Element (Bytes'Length mod 256);
      Block (6) := Stream_Element (Bytes'Length / 256);
      for I in Bytes'Range loop
         Block (Stream_Element_Offset (Header_Bytes + I - Bytes'First + 1)) :=
           Stream_Element (Bytes (I));
      end loop;
      Stream_IO.Write (W.File, Block);
      Stream_IO.Flush (W.File);
   end Append;

   -----------
   -- Close --
   -----------

   procedure Close (W : in out Writer) is
   begin
      if Stream_IO.Is_Open (W.File) then
         Stream_IO.Close (W.File);
      end if;
   end Close;

   ----------
   -- Load --
   ----------

   procedure Load
     (Path    : String;
      Content : out Byte_Vectors.Vector;
      Next    : out Positive;
      Ok      : out Boolean)
   is
      File  : Stream_IO.File_Type;
      Block : Stream_Element_Array (1 .. 4_096);
      Last  : Stream_Element_Offset;
   begin
      Content.Clear;
      Next := Magic'Length + 1;
      Ok   := False;

      Stream_IO.Open (File, Stream_IO.In_File, Path);
      loop
         Stream_IO.Read (File, Block, Last);
         exit when Last < Block'First;
         for I in Block'First .. Last loop
            Content.Append (Byte (Block (I)));
         end loop;
      end loop;
      Stream_IO.Close (File);

      if Natural (Content.Length) < Magic'Length then
         return;
      end if;
      for I in Magic'Range loop
         if Integer (Content.Element (I - Magic'First + 1))
              /= Character'Pos (Magic (I))
         then
            return;
         end if;
      end loop;
      Ok := True;
   exception
      when Ada.IO_Exceptions.Name_Error
         | Ada.IO_Exceptions.Use_Error
         | Ada.IO_Exceptions.Device_Error =>
         if Stream_IO.Is_Open (File) then
            Stream_IO.Close (File);
         end if;
         Ok := False;
   end Load;

   ----------------
   -- Next_Chunk --
   ----------------

   procedure Next_Chunk
     (Content : Byte_Vectors.Vector;
      Next    : in out Positive;
      Stamp   : out Radar_Source.Time_Ms;
      First   : out Positive;
      Length  : out Natural;
      Status  : out Read_Status)
   is
      Total : constant Natural := Natural (Content.Length);

      function At_Offset (K : Natural) return Long_Long_Integer is
        (Long_Long_Integer (Content.Element (Next + K)));
   begin
      Stamp  := 0;
      First  := Next;
      Length := 0;

      if Next > Total then
         Status := End_Of_Log;
         return;
      end if;
      if Total - Next + 1 < Header_Bytes then
         Status := Truncated;
         return;
      end if;

      declare
         Raw_Stamp : constant Long_Long_Integer :=
           At_Offset (0) + At_Offset (1) * 2 ** 8
           + At_Offset (2) * 2 ** 16 + At_Offset (3) * 2 ** 24;
         Raw_Len   : constant Long_Long_Integer :=
           At_Offset (4) + At_Offset (5) * 2 ** 8;
      begin
         if Raw_Stamp > Long_Long_Integer (Radar_Source.Time_Ms'Last)
           or else Raw_Len > Max_Chunk_Bytes
         then
            Status := Malformed;
            return;
         end if;
         if Total - (Next + Header_Bytes) + 1 < Natural (Raw_Len) then
            Status := Truncated;
            return;
         end if;

         Stamp  := Radar_Source.Time_Ms (Raw_Stamp);
         First  := Next + Header_Bytes;
         Length := Natural (Raw_Len);
         Next   := First + Length;
         Status := Chunk_Ok;
      end;
   end Next_Chunk;

end Radar_Ld2450_Log;
