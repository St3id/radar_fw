with Radar_Ld2450_Plausibility;
with Radar_Ld2450_Stream;
with Radar_Planar_Source;

--  Console_Serial : le LD2450 branche en direct. NON VALIDE SUR MATERIEL :
--  aucune trame reelle n'est passee ici, seul le port absent a ete execute.
--
--  Une tache lit le port et depose les octets dans un tampon borne : un Read
--  qui bloque ne doit pas figer la fenetre (dette 5). Aucune commande n'est
--  envoyee au module, et il peut donc rester en mono-cible.

package Console_Serial is

   type Serial_Source is new Radar_Planar_Source.Planar_Source with private;

   --  Why : le code GetLastError si Ok = False.
   procedure Open
     (Self : in out Serial_Source;
      Name : String;
      Ok   : out Boolean;
      Why  : out Integer);

   procedure Close (Self : in out Serial_Source);

   overriding
   procedure Next_Report
     (Self      : in out Serial_Source;
      Result    : out Radar_Planar_Source.Planar_Report;
      Available : out Boolean);

   --  Faux quand le port est perdu et le tampon vide.
   overriding
   function Has_More (Self : Serial_Source) return Boolean;

   function Port_Open return Boolean;

   --  Octets jetes faute de place dans le tampon.
   function Lost_Bytes return Natural;

   procedure Start_Recording (Path : String; Ok : out Boolean);
   procedure Stop_Recording;
   function Is_Recording return Boolean;

   function Stream (Self : Serial_Source) return Radar_Ld2450_Stream.Parser;
   function Checks
     (Self : Serial_Source) return Radar_Ld2450_Plausibility.Validator;

private

   type Serial_Source is new Radar_Planar_Source.Planar_Source with record
      Parser : Radar_Ld2450_Stream.Parser;
      Filter : Radar_Ld2450_Plausibility.Validator;
      Primed : Boolean := False;
      Last   : Natural := 0;
   end record;

end Console_Serial;
