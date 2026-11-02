with Ada.Real_Time;  use Ada.Real_Time;
with Ada.Text_IO;    use Ada.Text_IO;
with Radar_Sweep;    use Radar_Sweep;
with Radar_Buffer;   use Radar_Buffer;

--  Corps de Radar_Tasks : le motif Ravenscar canonique, une tache
--  cyclique produisant vers une tache sporadique a travers un objet
--  protege.

package body Radar_Tasks is

   Period     : constant Time_Span := Milliseconds (250);
   Max_Cycles : constant := 8;

   --  ----- Tache producteur (cyclique) -----
   --  Cadence stricte par "delay until" (jamais de delay relatif en
   --  Ravenscar) : produit un balayage simule toutes les 250 ms.
   task body Producer is
      Next  : Time := Clock;
      Frame : Natural := 0;
   begin
      loop
         exit when Frame >= Max_Cycles;
         Frame := Frame + 1;

         declare
            S   : Sweep := (others => 10);
            Pos : constant Bin_Index :=
              Bin_Index (Integer'Max (1, 200 - Frame * 20));
         begin
            S (Pos) := 3_000;
            --  Le dernier balayage le dit : c'est lui qui arrete le
            --  consommateur, quel que soit le nombre de balayages perdus.
            Mailbox.Put (S, Last => Frame = Max_Cycles);
         end;

         Next := Next + Period;
         delay until Next;
      end loop;
   end Producer;

   --  ----- Tache consommateur (sporadique) -----
   --  Pas d'horloge propre : elle bloque sur l'entry Get et n'est
   --  reveillee que lorsqu'une donnee arrive (barriere de l'objet
   --  protege). Zero polling, zero attente active.
   task body Consumer is
      Cycle : Natural := 0;
      Last  : Boolean := False;
   begin
      --  On s'arrete sur la marque du dernier balayage, jamais sur un
      --  compte : Put ecrase une donnee non lue, et un consommateur qui
      --  attendrait exactement Max_Cycles balayages resterait bloque pour
      --  toujours apres une seule perte (et la CI avec lui).
      while not Last loop
         Cycle := Cycle + 1;

         declare
            S : Sweep;
         begin
            Mailbox.Get (S, Last);
            if Has_Target (S) then
               Put_Line ("[Consumer] cycle" & Cycle'Image
                         & " : cible en case" & Peak_Bin (S)'Image
                         & " a" & Peak_Distance (S)'Image & " mm");
            else
               Put_Line ("[Consumer] cycle" & Cycle'Image
                         & " : bruit seul, pas de cible");
            end if;
         end;
      end loop;

      Put_Line ("[Consumer] fin :" & Natural'Image (Cycle)
                & " balayage(s) lu(s),"
                & Natural'Image (Mailbox.Overwritten)
                & " ecrase(s) avant lecture");

      --  Fin de la demo : on reveille le programme principal.
      Ada.Synchronous_Task_Control.Set_True (Demo_Done);
   end Consumer;

end Radar_Tasks;
