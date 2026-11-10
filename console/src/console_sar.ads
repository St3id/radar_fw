--  Console_Sar : lance l'analyse SAR sans figer la fenetre (~12 s de calcul)
--  et capture son texte, ecrit sur la sortie courante par Radar_Run_Sar.

package Console_Sar is

   procedure Start (Output_Path : String);

   function Done return Boolean;
   function Failed return Boolean;

end Console_Sar;
