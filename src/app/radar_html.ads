with Ada.Text_IO;  use Ada.Text_IO;

--  Radar_Html : les aides d'ecriture partagees par les generateurs de
--  pages, chaque mode d'exploitation produisant son propre visualiseur.
--
--  Ces fonctions ne mettent pas en forme du texte pour l'agrement : elles
--  determinent le poids des pages produites et la precision apparente des
--  mesures affichees. Voir la justification du format compact, plus bas.

package Radar_Html is

   --  Image d'un entier sans l'espace de tete que met Ada (" 5" -> "5").
   function Img (N : Natural) return String;

   --  Ecrit un Float comme nombre JavaScript (pas d'espace de tete).
   procedure Put_Float (F : File_Type; V : Float);

   --  Meme chose mais en chaine (pour construire du JSON en memoire).
   --
   --  Format compact a une decimale : "-120.0" et non "-1.20000E+02".
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
