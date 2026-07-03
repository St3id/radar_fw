with Ada.Text_IO;  use Ada.Text_IO;

package Radar_Html is

   --  Aides d'ecriture partagees par les generateurs HTML (les deux
   --  modes d'exploitation produisent chacun leur visualiseur).

   --  Image d'un entier sans l'espace de tete que met Ada (" 5" -> "5").
   function Img (N : Natural) return String;

   --  Ecrit un Float comme nombre JavaScript (pas d'espace de tete).
   --  Float'Image donne par ex. "-1.20000E+02" : JS sait lire ce format.
   procedure Put_Float (F : File_Type; V : Float);

   --  Meme chose mais en chaine (pour construire du JSON en memoire).
   --  Le format exposant de Float'Image est du JSON valide.
   function F_Img (V : Float) return String;

end Radar_Html;
