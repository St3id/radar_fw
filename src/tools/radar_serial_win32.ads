with Radar_Ld2450;

--  Radar_Serial_Win32 : lire un port serie Windows a 256 000 bauds.
--
--  Pourquoi pas GNAT.Serial_Communications : son type Data_Rate est une
--  enumeration fermee (g-sercom.ads de GNAT 15 : B230400, puis B460800), sans
--  256 000. Le LD2450 emet a 256 000 bauds par defaut. Cette liaison directe
--  a l'API Win32 est la limite assumee : ce paquet est propre a Windows
--  x86_64, le seul poste de developpement du projet. Sous Linux, la CI le
--  COMPILE sans faire d'edition de liens, pour qu'il ne pourrisse pas.
--
--  NON VALIDE SUR MATERIEL : aucun module ni adaptateur USB-serie n'existe a
--  ce jour. Seul le chemin d'erreur (port absent) a ete execute. La lecture,
--  l'acceptation de 256 000 bauds par le pilote de l'adaptateur et les
--  delais restent a verifier au premier branchement.
--
--  Tout ce qui touche au port tient ici : le reste du depot n'en depend pas.

package Radar_Serial_Win32 is

   type Port is limited private;

   Serial_Rate : constant := 256_000;

   --  Ouvre le port en lecture seule, 8 bits, sans parite, 1 bit d'arret,
   --  sans controle de flux, et ne transmet rien : l'enregistreur n'envoie
   --  aucune commande au module. Name : le nom Windows du port, COM3 par
   --  exemple ; a partir de COM10, la forme longue de Windows.
   --  Ok = False : Why porte le code GetLastError.
   procedure Open
     (P    : in out Port;
      Name : String;
      Ok   : out Boolean;
      Why  : out Integer);

   --  Rend les octets deja recus, sans attendre d'avoir rempli Into, ou
   --  Last = Into'First - 1 si rien n'est arrive en Wait_Ms. Ok = False si la
   --  lecture echoue (adaptateur debranche).
   procedure Read
     (P    : in out Port;
      Into : out Radar_Ld2450.Byte_Array;
      Last : out Natural;
      Ok   : out Boolean);

   procedure Close (P : in out Port);

private

   type Handle is new Long_Long_Integer;

   type Port is limited record
      H    : Handle  := 0;
      Open : Boolean := False;
   end record;

end Radar_Serial_Win32;
