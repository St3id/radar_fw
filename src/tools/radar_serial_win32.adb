with Interfaces.C;
with System;

--  Corps de Radar_Serial_Win32. Convention C sur les fonctions Win32 : sur
--  Windows x86_64, il n'y a qu'une convention d'appel, et stdcall n'y existe
--  pas ; un portage 32 bits devrait la changer. Les declarations suivent
--  winbase.h et n'ont ete essayees que sur leur chemin d'erreur (voir la
--  specification).

package body Radar_Serial_Win32 is

   use Interfaces;
   use type Interfaces.C.int;

   --  Le DWORD de Windows : 32 bits, a la difference de unsigned_long, qui
   --  en fait 64 sous Linux, ou ce fichier est aussi compile.
   subtype DWord is Unsigned_32;

   Generic_Read  : constant DWord  := 16#8000_0000#;
   Open_Existing : constant DWord  := 3;

   --  INVALID_HANDLE_VALUE, soit (HANDLE) -1.
   Invalid_Handle : constant Handle := -1;

   --  Le DCB de winbase.h, 28 octets. Les champs de bits de la troisieme
   --  ligne tiennent dans Flags : seul fBinary (bit 0) nous importe ; a zero,
   --  parite, controle de flux et XON/XOFF sont desactives, ce qu'il faut
   --  pour lire un flux binaire brut.
   type Dcb_Record is record
      Dcb_Length : DWord;
      Baud_Rate  : DWord;
      Flags      : DWord;
      Reserved   : C.unsigned_short;
      Xon_Lim    : C.unsigned_short;
      Xoff_Lim   : C.unsigned_short;
      Byte_Size  : C.unsigned_char;
      Parity     : C.unsigned_char;
      Stop_Bits  : C.unsigned_char;
      Xon_Char   : C.char;
      Xoff_Char  : C.char;
      Error_Char : C.char;
      Eof_Char   : C.char;
      Evt_Char   : C.char;
      Reserved_1 : C.unsigned_short;
   end record
     with Convention => C, Size => 28 * 8;

   F_Binary : constant DWord := 1;

   type Comm_Timeouts is record
      Read_Interval         : DWord;
      Read_Total_Multiplier : DWord;
      Read_Total_Constant   : DWord;
      Write_Total_Multipler : DWord;
      Write_Total_Constant  : DWord;
   end record
     with Convention => C;

   --  Combinaison documentee par COMMTIMEOUTS : ReadFile rend tout de suite
   --  ce qui est deja la, sinon attend le premier octet, au plus Wait_Ms.
   Max_DWord : constant DWord := 16#FFFF_FFFF#;
   Wait_Ms   : constant DWord := 100;

   function Create_File
     (Name          : C.char_array;
      Access_Mode   : DWord;
      Share_Mode    : DWord;
      Security      : System.Address;
      Creation      : DWord;
      Flags         : DWord;
      Template      : System.Address) return Handle
     with Import, Convention => C, External_Name => "CreateFileA";

   function Get_Comm_State
     (H : Handle; D : access Dcb_Record) return C.int
     with Import, Convention => C, External_Name => "GetCommState";

   function Set_Comm_State
     (H : Handle; D : access Dcb_Record) return C.int
     with Import, Convention => C, External_Name => "SetCommState";

   function Set_Comm_Timeouts
     (H : Handle; T : access Comm_Timeouts) return C.int
     with Import, Convention => C, External_Name => "SetCommTimeouts";

   function Read_File
     (H       : Handle;
      Buffer  : System.Address;
      To_Read : DWord;
      Did     : access DWord;
      Overlap : System.Address) return C.int
     with Import, Convention => C, External_Name => "ReadFile";

   function Close_Handle (H : Handle) return C.int
     with Import, Convention => C, External_Name => "CloseHandle";

   function Get_Last_Error return DWord
     with Import, Convention => C, External_Name => "GetLastError";

   ----------
   -- Open --
   ----------

   procedure Open
     (P    : in out Port;
      Name : String;
      Ok   : out Boolean;
      Why  : out Integer)
   is
      State    : aliased Dcb_Record;
      Timeouts : aliased Comm_Timeouts :=
        (Read_Interval         => Max_DWord,
         Read_Total_Multiplier => Max_DWord,
         Read_Total_Constant   => Wait_Ms,
         Write_Total_Multipler => 0,
         Write_Total_Constant  => 0);

      procedure Fail is
      begin
         Why := Integer (Get_Last_Error);
         Ok  := False;
         if P.Open then
            Close (P);
         end if;
      end Fail;
   begin
      Ok  := True;
      Why := 0;

      P.H := Create_File
        (Name        => C.To_C (Name),
         Access_Mode => Generic_Read,
         Share_Mode  => 0,
         Security    => System.Null_Address,
         Creation    => Open_Existing,
         Flags       => 0,
         Template    => System.Null_Address);
      if P.H = Invalid_Handle then
         Fail;
         return;
      end if;
      P.Open := True;

      State.Dcb_Length := Dcb_Record'Size / 8;
      if Get_Comm_State (P.H, State'Access) = 0 then
         Fail;
         return;
      end if;

      State.Baud_Rate := Serial_Rate;
      State.Flags     := F_Binary;
      State.Byte_Size := 8;
      State.Parity    := 0;   --  NOPARITY
      State.Stop_Bits := 0;   --  ONESTOPBIT
      if Set_Comm_State (P.H, State'Access) = 0 then
         Fail;
         return;
      end if;

      if Set_Comm_Timeouts (P.H, Timeouts'Access) = 0 then
         Fail;
         return;
      end if;
   end Open;

   ----------
   -- Read --
   ----------

   procedure Read
     (P    : in out Port;
      Into : out Radar_Ld2450.Byte_Array;
      Last : out Natural;
      Ok   : out Boolean)
   is
      --  Le tampon de ReadFile est fait d'octets machine. Byte est un type
      --  borne dont rien ne garantit la taille en memoire : on recopie.
      Raw : array (Into'Range) of aliased C.unsigned_char
        with Convention => C;
      Did : aliased DWord := 0;
   begin
      Last := Into'First - 1;
      Ok   := P.Open
        and then Read_File (P.H, Raw'Address, Raw'Length, Did'Access,
                            System.Null_Address) /= 0;
      if Ok then
         for I in 0 .. Integer (Did) - 1 loop
            Into (Into'First + I) :=
              Radar_Ld2450.Byte (Raw (Raw'First + I));
         end loop;
         Last := Into'First + Integer (Did) - 1;
      end if;
   end Read;

   -----------
   -- Close --
   -----------

   procedure Close (P : in out Port) is
      Ignored : C.int;
   begin
      if P.Open then
         Ignored := Close_Handle (P.H);
         P.Open  := False;
      end if;
   end Close;

end Radar_Serial_Win32;
