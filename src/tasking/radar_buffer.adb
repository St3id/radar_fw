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

      procedure Put (S : Sweep) is
      begin
         Data     := S;
         Has_Data := True;
      end Put;

      ---------
      -- Get --
      ---------

      entry Get (S : out Sweep) when Has_Data is
      begin
         S        := Data;
         Has_Data := False;   --  on a consomme la donnee
      end Get;

   end Mailbox;

end Radar_Buffer;
