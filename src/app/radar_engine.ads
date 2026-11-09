with Radar_Planar_Source; use Radar_Planar_Source;
with Radar_Source;        use Radar_Source;

--  Radar_Engine : ce qui fait avancer les donnees, sans fenetre ni socket.
--  Une interface appelle Step et lit Last ; un test fait pareil, sans GTK.
--
--  Hors SPARK : Planar_Report porte des Float et la source derriere
--  Planar_Source'Class n'est pas prouvee.

package Radar_Engine with SPARK_Mode => Off is

   type Engine_State is (Stopped, Running, Finished);

   type Snapshot is record
      State        : Engine_State := Stopped;
      Last_Report  : Planar_Report;
      Has_Report   : Boolean := False;
      Frames_Shown : Natural := 0;
   end record;

   type Engine is private;

   procedure Start (E : out Engine);

   --  Now vient de l'appelant, et sur la meme base de temps que les Stamp :
   --  un rejeu suit l'heure de la capture, un test deroule 10 s d'un coup.
   --
   --  Au plus une trame par appel. Plusieurs trames arrivees ensemble ont le
   --  meme Stamp : en les vidant d'un coup, l'ecran n'en verrait que la
   --  derniere, alors que Frames_Shown les compterait toutes.
   procedure Step
     (E      : in out Engine;
      Source : in out Planar_Source'Class;
      Now    : Time_Ms);

   function Last (E : Engine) return Snapshot;

private

   type Engine is record
      Snap        : Snapshot;
      Pending     : Planar_Report;
      Has_Pending : Boolean := False;
   end record;

end Radar_Engine;
