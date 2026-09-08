with Ada.Text_IO;  use Ada.Text_IO;

package Radar_Html is

   --  Aides d'ecriture partagees par les generateurs HTML (les deux
   --  modes d'exploitation produisent chacun leur visualiseur).

   --  Image d'un entier sans l'espace de tete que met Ada (" 5" -> "5").
   function Img (N : Natural) return String;

   --  Ecrit un Float comme nombre JavaScript (pas d'espace de tete).
   procedure Put_Float (F : File_Type; V : Float);

   --  Meme chose mais en chaine (pour construire du JSON en memoire).
   --
   --  Format COMPACT a une decimale : "-120.0" et non "-1.20000E+02".
   --  Deux raisons. D'abord la taille : la notation scientifique de
   --  Float'Image coute 11 a 12 caracteres par nombre, ce qui pesait
   --  pres du double sur des pages de plusieurs milliers de points.
   --  Ensuite l'honnetete : les cases de distance font 78 mm, afficher
   --  cinq chiffres significatifs sur une position en millimetres
   --  suggere une precision que le capteur n'a pas.
   --  Le dixieme de millimetre (et de degre) reste tres au-dela de ce
   --  que la chaine de mesure peut distinguer.
   function F_Img (V : Float) return String;

end Radar_Html;
