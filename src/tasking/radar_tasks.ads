with Ada.Synchronous_Task_Control;

package Radar_Tasks is

   --  Les deux taches sont declarees ici, au niveau du paquet
   --  (library level), comme l'exige le profil Ravenscar.

   task Producer;
   task Consumer;

   --  Objet de suspension (primitive Ravenscar) : leve par le
   --  consommateur quand la demo est finie. Le programme principal s'y
   --  suspend, puis termine le processus - car sous Ravenscar une tache
   --  terminee reste suspendue a jamais et la partition ne s'arrete
   --  donc pas toute seule (sur cible, les taches sont eternelles).
   Demo_Done : Ada.Synchronous_Task_Control.Suspension_Object;

end Radar_Tasks;
