package Radar_World is

   --  Un objet reel dans le monde simule : sa position, sa vitesse, son ID.
   --  (la "verite terrain", connue du seul simulateur).
   type Object is record
      Id : Positive;        --  identifiant unique
      X  : Float;           --  position en mm (repere centre sur le radar)
      Y  : Float;
      Z  : Float;
      Vx : Float;           --  vitesse en mm par pas de temps
      Vy : Float;
      Vz : Float;
   end record;

   --  Nombre maximum d'objets dans la scene.
   Max_Objects : constant := 8;

   subtype Object_Count is Natural range 0 .. Max_Objects;

   type Object_Array is array (1 .. Max_Objects) of Object;

   --  Le monde : les objets presents + combien il y en a.
   type World is record
      Objects : Object_Array;
      Count   : Object_Count;
   end record;

   --  Cree une scene de depart avec quelques objets mobiles.
   function Initial_World return World;

   --  Fait avancer tous les objets d'un pas de temps (position += vitesse).
   procedure Step (W : in out World);

end Radar_World;