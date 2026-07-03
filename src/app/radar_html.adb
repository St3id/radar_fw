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
      Img_F : constant String := Float'Image (V);
   begin
      if Img_F (Img_F'First) = ' ' then
         return Img_F (Img_F'First + 1 .. Img_F'Last);
      else
         return Img_F;
      end if;
   end F_Img;

end Radar_Html;
