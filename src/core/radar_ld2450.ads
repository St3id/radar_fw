--  Radar_Ld2450 : le format des trames du module radar HLK-LD2450.
--
--  Une trame fait 30 octets : un en-tete AA FF 03 00, trois emplacements
--  de cible de 8 octets, une fin 55 CC (ARCHITECTURE.md, section 2.6).
--  Chaque champ tient sur deux octets, poids faible en premier.
--
--  Ce paquet ne fait que du calcul sur des octets : ni entree-sortie, ni
--  horloge, ni exception propagee. Il vit donc dans le coeur embarquable :
--  le meme code servira sur la carte (jalon 7), et la compilation ARM de
--  radar_core.gpr le verifie deja.
--
--  Il contient ce qui DEFINIT le format (le codage d'une valeur, la place
--  des champs) et l'encodeur dont l'emulateur a besoin. Lire un flux
--  d'octets (se resynchroniser, rejeter une trame abimee, compter les
--  pertes) est le travail du parseur du jalon 5.

package Radar_Ld2450
  with SPARK_Mode => On
is

   --  Un octet de la liaison serie, et un champ de deux octets avant toute
   --  interpretation. Des types entiers BORNES, et non modulaires : dans
   --  un type modulaire, 255 + 1 vaut 0 sans la moindre erreur ; ici, tout
   --  depassement serait un controle en echec, et SPARK prouve qu'il ne
   --  peut pas arriver. Le prouveur raisonne aussi bien mieux sur des
   --  entiers que sur des vecteurs de bits.
   type Byte is range 0 .. 2 ** 8 - 1;
   type Word is range 0 .. 2 ** 16 - 1;

   type Byte_Array is array (Positive range <>) of Byte;

   --  ----- La trame -----

   Frame_Length  : constant := 30;
   Header_Length : constant := 4;
   Tail_Length   : constant := 2;

   --  Un emplacement de cible : X, Y, vitesse, resolution, 2 octets chacun.
   Target_Length : constant := 8;

   --  Des sous-types CONTRAINTS : le prouveur connait ainsi leur longueur
   --  sans avoir a deviner les bornes d'un agregat.
   subtype Frame_Bytes  is Byte_Array (1 .. Frame_Length);
   subtype Header_Bytes is Byte_Array (1 .. Header_Length);
   subtype Tail_Bytes   is Byte_Array (1 .. Tail_Length);

   Header : constant Header_Bytes := (16#AA#, 16#FF#, 16#03#, 16#00#);
   Tail   : constant Tail_Bytes   := (16#55#, 16#CC#);

   --  Rang du premier octet de la fin dans la trame : 29.
   Tail_First : constant := Frame_Length - Tail_Length + 1;

   --  Le module transmet toujours trois emplacements ; ceux qui ne portent
   --  pas de cible sont remplis de zeros.
   Max_Targets : constant := 3;

   subtype Target_Slot is Positive range 1 .. Max_Targets;
   subtype Target_Count is Natural range 0 .. Max_Targets;

   --  Rang du premier octet de l'emplacement S dans la trame : 5, 13, 21.
   function Slot_First (S : Target_Slot) return Positive is
     (Header_Length + (S - 1) * Target_Length + 1);

   --  ----- Le codage d'une valeur (piege 1 de la section 2.6) -----

   --  15 bits de valeur absolue plus un bit de signe : ni complement a
   --  deux, ni binaire decale.
   Max_Magnitude : constant := 2 ** 15 - 1;

   type Signed_Value is range -Max_Magnitude .. Max_Magnitude;

   --  Le bit 15 porte le signe, a 1 pour une valeur positive. Il est ecrit
   --  en arithmetique : "W >= 2**15" et "bit 15 = 1" disent la meme chose.
   Sign_Bit : constant := 2 ** 15;

   function Decode_Signed (W : Word) return Signed_Value is
     (if W >= Sign_Bit then Signed_Value (W - Sign_Bit)
      else -Signed_Value (W));

   --  Zero part avec le bit de signe a 0 : le module ecrit une vitesse
   --  nulle 00 00, et non 00 80 (premiere trame de la FAQ du manuel).
   --  Postcondition prouvee : le decodage rend toujours la valeur codee,
   --  pour les 65 535 valeurs a la fois.
   function Encode_Signed (V : Signed_Value) return Word is
     (if V > 0 then Word (V) + Sign_Bit else Word (-V))
     with Post => Decode_Signed (Encode_Signed'Result) = V;

   --  Deux octets, poids faible en premier (petit-boutiste).
   function Low_Byte (W : Word) return Byte is (Byte (W mod 256));
   function High_Byte (W : Word) return Byte is (Byte (W / 256));

   function To_Word (Low, High : Byte) return Word is
     (Word (Low) + 256 * Word (High));

   --  ----- Une cible, dans les unites du module -----

   --  X lateral et Y vers l'avant, en mm, dans le repere du capteur.
   --  Vitesse en cm/s : c'est l'unite du module, PAS celle du projet (le
   --  pistage travaille en mm/s). Resolution de distance en mm, non signee.
   type Raw_Target is record
      X_Mm          : Signed_Value := 0;
      Y_Mm          : Signed_Value := 0;
      Speed_Cm_S    : Signed_Value := 0;
      Resolution_Mm : Word         := 0;
   end record;

   type Raw_Target_Array is array (Target_Slot) of Raw_Target;

   --  Le contenu d'une trame : les cibles presentes, dans les premiers
   --  emplacements.
   type Raw_Report is record
      Targets : Raw_Target_Array;
      Count   : Target_Count := 0;
   end record;

   --  La trame que le module enverrait pour ce rapport. Les emplacements
   --  au-dela de Count restent nuls, comme sur le module. La postcondition
   --  est ecrite octet par octet : c'est la forme que le prouveur etablit
   --  sans avoir a comparer deux tableaux entiers.
   function Encode_Frame (R : Raw_Report) return Frame_Bytes
     with Post =>
       (for all I in Header'Range =>
          Encode_Frame'Result (I) = Header (I))
       and then
       (for all I in Tail'Range =>
          Encode_Frame'Result (Tail_First + I - 1) = Tail (I));

end Radar_Ld2450;
