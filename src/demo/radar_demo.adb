with Ada.Synchronous_Task_Control;  use Ada.Synchronous_Task_Control;
with GNAT.OS_Lib;
with Radar_Tasks;

--  Demonstrateur RAVENSCAR : tout le travail se passe dans les taches de
--  Radar_Tasks, demarrees a la fin de l'elaboration (politique
--  Sequential). Le profil Ravenscar est impose a TOUT cet executable par
--  ravenscar.adc (voir radar_demo.gpr) : le compilateur refuse alors
--  select, abort, entries multiples, delay relatif... C'est ce pragma
--  qui transforme "Ravenscar" d'une intention en garantie verifiee.
procedure Radar_Demo is
begin
   --  Attend la fin de la demo (signalee par le consommateur via
   --  l'objet de suspension - l'attente bloquante idiomatique Ravenscar).
   Suspend_Until_True (Radar_Tasks.Demo_Done);

   --  Sous Ravenscar, une tache terminee reste suspendue a jamais (sur
   --  la cible, les taches sont eternelles) : la partition ne s'arrete
   --  donc pas toute seule. Cette demo PC termine le processus
   --  explicitement, sinon elle resterait pendue apres ses 8 cycles.
   GNAT.OS_Lib.OS_Exit (0);
end Radar_Demo;
