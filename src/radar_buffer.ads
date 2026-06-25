with Radar_Sweep;  use Radar_Sweep;

package Radar_Buffer is

   --  Objet protege : une "boite aux lettres" partagee entre taches.
   --  Le producteur y depose un balayage, le consommateur le recupere,
   --  sans risque de conflit (Ada gere l'exclusion mutuelle).
   protected Mailbox is

      --  Depose un balayage dans la boite (appele par le producteur).
      procedure Put (S : Sweep);

      --  Recupere le dernier balayage (appele par le consommateur).
      --  Available indique s'il y avait bien une nouvelle donnee.
      procedure Get (S : out Sweep; Available : out Boolean);

   private
      Data      : Sweep := (others => 0);
      Has_Data  : Boolean := False;
   end Mailbox;

end Radar_Buffer;