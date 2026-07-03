with Ada.Real_Time;  use Ada.Real_Time;
with Ada.Text_IO;    use Ada.Text_IO;
with Radar_Sweep;    use Radar_Sweep;
with Radar_Buffer;   use Radar_Buffer;

package body Radar_Tasks is

   Period     : constant Time_Span := Milliseconds (250);
   Max_Cycles : constant := 8;

   --  ===== Tache PRODUCTEUR (cyclique) =====
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
            Mailbox.Put (S);
         end;

         Next := Next + Period;
         delay until Next;
      end loop;
   end Producer;

   --  ===== Tache CONSOMMATEUR (sporadique) =====
   --  Pas d'horloge propre : elle BLOQUE sur l'entry Get et n'est
   --  reveillee que lorsqu'une donnee arrive (barriere de l'objet
   --  protege). Zero polling, zero attente active.
   task body Consumer is
      Cycle : Natural := 0;
   begin
      loop
         exit when Cycle >= Max_Cycles;
         Cycle := Cycle + 1;

         declare
            S : Sweep;
         begin
            Mailbox.Get (S);
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

      --  Fin de la demo : on reveille le programme principal.
      Ada.Synchronous_Task_Control.Set_True (Demo_Done);
   end Consumer;

end Radar_Tasks;
