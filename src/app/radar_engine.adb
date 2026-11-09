package body Radar_Engine is

   procedure Start (E : out Engine) is
   begin
      E := (Snap => (State => Running, others => <>), others => <>);
   end Start;

   procedure Step
     (E      : in out Engine;
      Source : in out Planar_Source'Class;
      Now    : Time_Ms)
   is
      Available : Boolean;
   begin
      if E.Snap.State /= Running then
         return;
      end if;

      --  Next_Report rend les trames aussi vite qu'on l'appelle, sans regarder
      --  l'heure. Du coup on en garde une d'avance jusqu'a son Stamp.
      if not E.Has_Pending then
         Source.Next_Report (E.Pending, Available);
         if not Available then
            --  Available = False et Has_More = True : un silence du module,
            --  la derniere trame reste a l'ecran et rien n'est invente.
            if not Source.Has_More then
               E.Snap.State := Finished;
            end if;
            return;
         end if;
         E.Has_Pending := True;
      end if;

      if E.Pending.Stamp <= Now then
         E.Snap.Last_Report  := E.Pending;
         E.Snap.Has_Report   := True;
         E.Snap.Frames_Shown := E.Snap.Frames_Shown + 1;
         E.Has_Pending       := False;
      end if;
   end Step;

   function Last (E : Engine) return Snapshot is (E.Snap);

end Radar_Engine;
