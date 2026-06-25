with Ada.Text_IO;  use Ada.Text_IO;

package body Radar_Display is

   --  On regroupe les 256 cases en quelques lignes pour un affichage lisible.
   Group : constant := 8;   --  8 cases par ligne affichee
   --  Sequence ANSI pour effacer l'ecran et remettre le curseur en haut.
   procedure Clear_Screen is
   begin
      Put (ASCII.ESC & "[2J" & ASCII.ESC & "[H");
   end Clear_Screen;

   ----------
   -- Show --
   ----------

   procedure Show (S : Sweep) is
      Bar_Width : constant := 40;  --  longueur max d'une barre, en caracteres
   begin
      Put_Line ("+--- Ecran radar -----------------------------------+");

      --  Une ligne par groupe de cases : on prend l'amplitude max du groupe.
      declare
         I : Bin_Index := Bin_Index'First;
      begin
         loop
            --  Amplitude max sur le groupe courant.
            declare
               Peak_In_Group : Amplitude := 0;
               Last : constant Bin_Index :=
                 Bin_Index'Min (I + (Group - 1), Bin_Index'Last);
            begin
               for J in I .. Last loop
                  if S (J) > Peak_In_Group then
                     Peak_In_Group := S (J);
                  end if;
               end loop;

               --  Longueur de la barre, proportionnelle a l'amplitude.
               declare
                  Len : constant Natural :=
                    Natural ((Integer (Peak_In_Group) * Bar_Width) / 4_095);
               begin
                  Put (I'Image & " |");
                  for K in 1 .. Len loop
                     Put ("#");
                  end loop;
                  New_Line;
               end;

               exit when Last = Bin_Index'Last;
               I := Last + 1;
            end;
         end loop;
      end;

      Put_Line ("+---------------------------------------------------+");

      --  Bilan de detection via ta logique prouvee.
      if Has_Target (S) then
         Put_Line ("  >> Cible principale : case" & Peak_Bin (S)'Image
                   & " a" & Peak_Distance (S)'Image & " mm");
      else
         Put_Line ("  >> Aucune cible.");
      end if;
      New_Line;
   end Show;

end Radar_Display;