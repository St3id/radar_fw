package body Radar_Ld2450_Faults is

   --  Rend un tableau au premier indice 1 : les concatenations gardent
   --  l'indice de leur operande gauche, et les tests indexent depuis 1.
   function From_One (S : Byte_Array) return Byte_Array is
      R : constant Byte_Array (1 .. S'Length) := S;
   begin
      return R;
   end From_One;

   --------------
   -- Frame_Of --
   --------------

   function Frame_Of (K : Manual_Index) return Frame_Bytes is
     (case K is
         when 1 => Manual_Frame (Example_Bytes),
         when 2 => Manual_Frame (Faq_1_Bytes),
         when 3 => Manual_Frame (Faq_2_Bytes),
         when 4 => Manual_Frame (Faq_3_Bytes));

   ---------------
   -- Target_Of --
   ---------------

   function Target_Of (K : Manual_Index) return Raw_Target is
     (case K is
         when 1 => (-782, 1_713, -16, 320),
         when 2 => (-272, 850, 0, 360),
         when 3 => (-228, 903, 17, 360),
         when 4 => (2_750, 3_655, -17, 360));

   -------------------
   -- Manual_Stream --
   -------------------

   function Manual_Stream return Byte_Array is
     (Frame_Of (1) & Frame_Of (2) & Frame_Of (3) & Frame_Of (4));

   ----------------
   -- Drop_Start --
   ----------------

   function Drop_Start (S : Byte_Array; Count : Natural) return Byte_Array is
     (From_One (S (S'First + Count .. S'Last)));

   --------------
   -- Truncate --
   --------------

   function Truncate (S : Byte_Array; Count : Natural) return Byte_Array is
     (From_One (S (S'First .. S'Last - Count)));

   ----------
   -- Lose --
   ----------

   function Lose
     (S : Byte_Array; Kept : Natural; Count : Natural) return Byte_Array
   is
     (From_One
        (S (S'First .. S'First + Kept - 1)
         & S (S'First + Kept + Count .. S'Last)));

   ------------
   -- Insert --
   ------------

   function Insert
     (S : Byte_Array; Kept : Natural; Extra : Byte_Array) return Byte_Array
   is
     (From_One
        (S (S'First .. S'First + Kept - 1)
         & Extra
         & S (S'First + Kept .. S'Last)));

   --------------
   -- Flip_Bit --
   --------------

   function Flip_Bit
     (S : Byte_Array; Rank : Positive; Bit : Natural) return Byte_Array
   is
      R    : Byte_Array := From_One (S);
      Mask : constant Byte := 2 ** Bit;
   begin
      --  Byte n'est pas modulaire : pas de "xor", on ajoute ou retire le bit.
      if (R (Rank) / Mask) mod 2 = 1 then
         R (Rank) := R (Rank) - Mask;
      else
         R (Rank) := R (Rank) + Mask;
      end if;
      return R;
   end Flip_Bit;

   ---------------
   -- Next_Byte --
   ---------------

   procedure Next_Byte (S : in out Random_State; B : out Byte) is
   begin
      S := S * 1_664_525 + 1_013_904_223;
      --  Les bits de poids fort : les bits faibles d'un congruentiel ont une
      --  periode tres courte.
      B := Byte (S / 2 ** 24);
   end Next_Byte;

   ------------------
   -- Random_Bytes --
   ------------------

   function Random_Bytes (Seed : Random_State; Count : Natural)
     return Byte_Array
   is
      S : Random_State := Seed;
      R : Byte_Array (1 .. Count);
   begin
      for I in R'Range loop
         Next_Byte (S, R (I));
      end loop;
      return R;
   end Random_Bytes;

end Radar_Ld2450_Faults;
