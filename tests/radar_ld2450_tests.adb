with AUnit.Assertions;  use AUnit.Assertions;
with Radar_Ld2450;      use Radar_Ld2450;

--  Corps de la suite 4. Les quatre cibles de reference sont recopiees du
--  manuel Hi-Link du LD2450 : l'exemple de la section protocole (repris
--  en ARCHITECTURE.md, section 2.6) et les trois captures de sa FAQ.

package body Radar_Ld2450_Tests is

   --  Les 8 octets de chaque cible de reference, tels que le manuel les
   --  imprime.
   Example_Bytes : constant Byte_Array :=     --  -782, 1713, -16 cm/s, 320
     (16#0E#, 16#03#, 16#B1#, 16#86#, 16#10#, 16#00#, 16#40#, 16#01#);
   Faq_1_Bytes   : constant Byte_Array :=     --  -272, 850, 0 cm/s, 360
     (16#10#, 16#01#, 16#52#, 16#83#, 16#00#, 16#00#, 16#68#, 16#01#);
   Faq_2_Bytes   : constant Byte_Array :=     --  -228, 903, +17 cm/s, 360
     (16#E4#, 16#00#, 16#87#, 16#83#, 16#11#, 16#80#, 16#68#, 16#01#);
   Faq_3_Bytes   : constant Byte_Array :=     --  2750, 3655, -17 cm/s, 360
     (16#BE#, 16#8A#, 16#47#, 16#8E#, 16#11#, 16#00#, 16#68#, 16#01#);

   Empty_Slot : constant Byte_Array (1 .. Target_Length) := (others => 0);

   --  La trame attendue pour une seule cible : en-tete, ses 8 octets, deux
   --  emplacements vides, fin.
   function Manual_Frame (Slot_Bytes : Byte_Array) return Frame_Bytes is
     (Header & Slot_Bytes & Empty_Slot & Empty_Slot & Tail);

   --  Une cible dans les unites du module.
   function Target
     (X, Y, Speed : Signed_Value;
      Resolution  : Word) return Raw_Target
   is
     ((X_Mm          => X,
       Y_Mm          => Y,
       Speed_Cm_S    => Speed,
       Resolution_Mm => Resolution));

   --  Un rapport a une seule cible.
   function One_Target (T : Raw_Target) return Raw_Report is
     ((Targets => (1 => T, others => <>), Count => 1));

   --  Compare deux trames et nomme le premier octet different.
   procedure Assert_Frame (Got, Expected : Frame_Bytes; What : String) is
   begin
      for I in Got'Range loop
         Assert (Got (I) = Expected (I),
                 What & " : l'octet" & Positive'Image (I) & " vaut"
                 & Byte'Image (Got (I)) & " au lieu de"
                 & Byte'Image (Expected (I)));
      end loop;
   end Assert_Frame;

   ----------
   -- Name --
   ----------

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Module LD2450 (trames et emulateur)");
   end Name;

   --  Test 1 : les quatre trames du manuel, octet pour octet. Ensemble,
   --  elles couvrent un X negatif et positif, une vitesse negative, nulle
   --  et positive, et les deux resolutions rencontrees (320 et 360).
   procedure Test_Manual_Frames
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_Frame (Encode_Frame (One_Target (Target (-782, 1_713, -16, 320))),
                    Manual_Frame (Example_Bytes), "Exemple du protocole");
      Assert_Frame (Encode_Frame (One_Target (Target (-272, 850, 0, 360))),
                    Manual_Frame (Faq_1_Bytes), "FAQ 1 (vitesse nulle)");
      Assert_Frame (Encode_Frame (One_Target (Target (-228, 903, 17, 360))),
                    Manual_Frame (Faq_2_Bytes), "FAQ 2 (vitesse positive)");
      Assert_Frame
        (Encode_Frame (One_Target (Target (2_750, 3_655, -17, 360))),
         Manual_Frame (Faq_3_Bytes), "FAQ 3 (X positif)");
   end Test_Manual_Frames;

   --  Test 2 : le codage a bit de signe aux limites, et l'ordre des
   --  octets. L'aller-retour sur toutes les valeurs est prouve par SPARK
   --  (postcondition de Encode_Signed) ; ces cas le rendent lisible.
   procedure Test_Signed_Coding
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert (Encode_Signed (0) = 0,
              "Zero se code 00 00 : bit de signe a 0");
      Assert (Encode_Signed (1) = 16#8001#,
              "+1 porte le bit de signe");
      Assert (Encode_Signed (-1) = 1,
              "-1 se code par sa seule valeur absolue");
      Assert (Encode_Signed (Signed_Value'Last) = Word'Last,
              "+32767 : les seize bits a 1");
      Assert (Encode_Signed (Signed_Value'First) = 16#7FFF#,
              "-32767 : quinze bits a 1, signe a 0");
      Assert (Decode_Signed (0) = 0 and then Decode_Signed (Sign_Bit) = 0,
              "Les deux zeros, 00 00 et 00 80, se lisent 0");
      Assert (Low_Byte (16#86B1#) = 16#B1#
                and then High_Byte (16#86B1#) = 16#86#,
              "Poids faible en premier : 86B1 part en B1 puis 86");
      Assert (To_Word (16#B1#, 16#86#) = 16#86B1#,
              "B1 puis 86 se relisent 86B1");
   end Test_Signed_Coding;

   --  Test 3 : les emplacements. Sans cible, la trame ne contient que des
   --  zeros entre l'en-tete et la fin ; avec trois cibles, chacune occupe
   --  sa place ; et c'est Count qui decide, pas le contenu du tableau.
   procedure Test_Slots
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      None  : constant Raw_Report := (others => <>);
      Three : Raw_Report;
   begin
      Assert_Frame (Encode_Frame (None),
                    Header & Empty_Slot & Empty_Slot & Empty_Slot & Tail,
                    "Trame sans cible");

      Three.Targets :=
        (Target (-782, 1_713, -16, 320),
         Target (-272, 850, 0, 360),
         Target (2_750, 3_655, -17, 360));
      Three.Count := 3;
      Assert_Frame (Encode_Frame (Three),
                    Header & Example_Bytes & Faq_1_Bytes & Faq_3_Bytes
                    & Tail,
                    "Trois cibles, chacune a sa place");

      Three.Count := 1;
      Assert_Frame (Encode_Frame (Three), Manual_Frame (Example_Bytes),
                    "Au-dela de Count, les emplacements restent nuls");
   end Test_Slots;

   --------------------
   -- Register_Tests --
   --------------------

   overriding
   procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Manual_Frames'Access,
         "LD2450 : les quatre trames du manuel, octet pour octet");
      Register_Routine
        (T, Test_Signed_Coding'Access,
         "LD2450 : bit de signe aux limites, poids faible en premier");
      Register_Routine
        (T, Test_Slots'Access,
         "LD2450 : emplacements vides, trois cibles, Count fait foi");
   end Register_Tests;

end Radar_Ld2450_Tests;
