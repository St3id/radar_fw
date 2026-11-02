with Radar_Detect; use Radar_Detect;

--  Radar_Target_Source : entree pour les capteurs qui livrent deja des
--  detections (par exemple un module FMCW avec traitement integre).
--
--  Ce contrat est volontairement distinct de Radar_Source : une liste de
--  cibles n'est pas un profil d'amplitude et ne doit pas etre convertie en
--  Sweep artificiel. Les frames sortent dans le repere commun de
--  l'application et alimentent directement Radar_Track.Update.
--
--  Frame est 3D. Un capteur qui ne mesure que x/y ne doit pas y
--  inventer un z ; il lui faut d'abord une representation et un
--  pistage planaires explicites.
package Radar_Target_Source is

   type Target_Source is interface;

   --  Fournit la prochaine frame de detections. Une frame vide est valide :
   --  elle represente une observation sans cible et fait avancer le temps
   --  du pistage. Stamp doit etre l'heure de capture, pas l'heure de lecture.
   procedure Next_Frame
     (Self      : in out Target_Source;
      Result    : out Frame;
      Available : out Boolean) is abstract;

   --  Vrai tant qu'une source simulee a des frames a rejouer. Une source
   --  materielle continue peut repondre toujours True et bloquer dans
   --  Next_Frame selon son pilote.
   function Has_More (Self : Target_Source) return Boolean is abstract;

end Radar_Target_Source;
