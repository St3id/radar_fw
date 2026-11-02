--  Corps de Radar_Html. Ces trois fonctions n'ont l'air de rien, mais
--  elles decident du poids des pages produites : voir la justification du
--  format compact dans la specification.

package body Radar_Html is

   ---------
   -- Img --
   ---------

   function Img (N : Natural) return String is
      S : constant String := N'Image;
   begin
      return S (S'First + 1 .. S'Last);
   end Img;

   ---------------
   -- Put_Float --
   ---------------

   procedure Put_Float (F : File_Type; V : Float) is
   begin
      Put (F, F_Img (V));
   end Put_Float;

   -----------
   -- F_Img --
   -----------

   function F_Img (V : Float) return String is
      --  On travaille en dixiemes, sur un entier : la conversion Ada
      --  d'un flottant vers un entier arrondit (au plus proche), donc
      --  Scaled porte deja la valeur arrondie au dixieme.
      --  Long_Float evite de perdre des chiffres sur les grandes
      --  valeurs, Long_Integer donne une marge tres large devant les
      --  20 metres et les 360 degres que le projet manipule.
      Scaled   : constant Long_Integer :=
        Long_Integer (Long_Float (V) * 10.0);
      Negative : constant Boolean      := Scaled < 0;
      Magnitude : constant Long_Integer := abs Scaled;

      --  'Image d'un entier positif commence par un espace : on le
      --  retire en sautant le premier caractere.
      Whole_Img : constant String := Long_Integer'Image (Magnitude / 10);
      Tenth_Img : constant String := Long_Integer'Image (Magnitude mod 10);

      Whole : constant String :=
        Whole_Img (Whole_Img'First + 1 .. Whole_Img'Last);
      Tenth : constant String :=
        Tenth_Img (Tenth_Img'First + 1 .. Tenth_Img'Last);
   begin
      --  Le signe est porte a part : sinon "-0.5" deviendrait "0.-5",
      --  la partie entiere valant zero.
      return (if Negative then "-" else "") & Whole & "." & Tenth;
   end F_Img;

end Radar_Html;
