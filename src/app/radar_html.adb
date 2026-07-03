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
      Img_F : constant String := Float'Image (V);
   begin
      if Img_F (Img_F'First) = ' ' then
         Put (F, Img_F (Img_F'First + 1 .. Img_F'Last));
      else
         Put (F, Img_F);
      end if;
   end Put_Float;

end Radar_Html;
