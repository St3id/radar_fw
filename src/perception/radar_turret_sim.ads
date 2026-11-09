with Radar_Dwell;

--  Radar_Turret_Sim : ce qu'un moteur fait d'un plan de Radar_Dwell.
--
--  Le plan demande une vitesse par secteur ; un vrai moteur y arrive et en
--  repart par des rampes, donc il passe plus de temps que prevu pres des
--  fenetres. Ce modele mesure ce retard : c'est lui qui justifie la reserve de
--  rampe du plan. Il suppose un moteur qui ne perd aucun pas, et ignore
--  l'inversion de fin de passe, comptee a part dans la duree d'une rangee.

package Radar_Turret_Sim is

   --  HYPOTHESE - acceleration tenue par le NEMA 17 et la tete. Aucun moteur
   --  n'a ete essaye : a remesurer, car la reserve de rampe en depend.
   Accel_Deg_S2 : constant Float := 2_000.0;

   --  Duree reelle de chaque secteur, en secondes.
   type Realised_Times is array (Radar_Dwell.Sector) of Float;

   function Realise (Plan : Radar_Dwell.Sector_Times) return Realised_Times;

   function Pass_Seconds (Times : Realised_Times) return Float;

   --  L'angle atteint dans la passe apres Seconds secondes, en degres
   --  (0 .. Radar_Dwell.Pass_Degrees), par vitesse uniforme dans un secteur.
   function Angle_At (Times : Realised_Times; Seconds : Float) return Float;

end Radar_Turret_Sim;
