--  Radar_World : la verite terrain du simulateur, c'est-a-dire ce que le
--  radar est cense voir.
--
--  Ce paquet ne sait rien du radar : il decrit une scene (objets mobiles
--  qui rebondissent, murs d'une piece) que la source simulee observera
--  ensuite avec ses propres imperfections. Separer les deux permet de
--  comparer ce qui est detecte a ce qui existe reellement.

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

   --  Un monde sans objet mobile : sert au mode cartographie, ou l'on
   --  scanne l'environnement statique (les murs) sans etre pollue par
   --  des objets en mouvement.
   function Empty_World return World;

   --  Fait avancer tous les objets d'un pas de temps (position += vitesse).
   procedure Step (W : in out World);

   --  ----- La piece statique (mode cartographie) -----

   --  Dimensions de la piece rectangulaire, centree sur le radar (mm).
   Room_Half_X : constant Float := 2000.0;   --  murs a +/- 2000 en X
   Room_Half_Y : constant Float := 1500.0;   --  murs a +/- 1500 en Y

   --  Distance du radar au premier mur touche dans une direction donnee
   --  (angles en degres). Modele volontairement simple : murs verticaux
   --  "infinis" (pas de sol ni de plafond) ; viser haut ou bas allonge
   --  le trajet d'un facteur 1/cos(elevation).
   function Wall_Distance (Azimuth_Deg, Elevation_Deg : Float) return Float;

   --  Angle d'incidence, en degres, entre le rayon vise et la normale du
   --  mur qu'il touche : 0 quand on regarde le mur de face, pres de 90
   --  quand le faisceau le rase. C'est de lui que depend l'echo d'un mur
   --  lisse (ARCHITECTURE.md, section 1.6) : sa composante speculaire ne
   --  revient vers le radar que s'il est vu presque de face ; ailleurs, il
   --  ne reste qu'une faible part diffuse.
   function Wall_Incidence
     (Azimuth_Deg, Elevation_Deg : Float) return Float
     with Post => Wall_Incidence'Result in 0.0 .. 90.0;

end Radar_World;
