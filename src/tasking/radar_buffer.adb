--  Corps de Radar_Buffer. Les deux operations sont volontairement courtes
--  et sans boucle : sous Ravenscar, le temps passe dans un objet protege
--  doit etre borne et previsible.

package body Radar_Buffer
  with SPARK_Mode => On
is

   protected body Mailbox is

      ---------
      -- Put --
      ---------

      procedure Put (S : Sweep; Last : Boolean) is
      begin
         --  Une donnee encore la n'a pas ete lue : elle est perdue.
         if Has_Data and then Lost < Natural'Last then
            Lost := Lost + 1;
         end if;
         Data     := S;
         Is_Last  := Last;
         Has_Data := True;
      end Put;

      ---------
      -- Get --
      ---------

      entry Get (S : out Sweep; Last : out Boolean) when Has_Data is
      begin
         S        := Data;
         Last     := Is_Last;
         Has_Data := False;   --  on a consomme la donnee
      end Get;

      -----------------
      -- Overwritten --
      -----------------

      function Overwritten return Natural is
      begin
         return Lost;
      end Overwritten;

   end Mailbox;

end Radar_Buffer;
