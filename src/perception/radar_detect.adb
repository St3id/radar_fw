with Radar_Sweep;  use Radar_Sweep;
with Ada.Numerics.Elementary_Functions;
use  Ada.Numerics.Elementary_Functions;

--  Corps de Radar_Detect. Le regroupement est un parcours simple en
--  O(n^2) sur au plus Max_Detections elements : a cette taille, une
--  structure d'acceleration couterait plus cher qu'elle ne rapporte.

package body Radar_Detect is

   -----------
   -- Reset --
   -----------

   procedure Reset (F : in out Frame) is
   begin
      F.Count     := 0;
      F.Stamp     := 0;
      F.Min_Range := 0.0;
   end Reset;

   ---------
   -- Add --
   ---------

   procedure Add (F : in out Frame; M : Measurement) is
      --  Toutes les cases qui depassent le seuil local calcule par la
      --  detection CFAR prouvee en SPARK. Cette preuve porte sur le code,
      --  pas sur un taux de fausse alarme mesure ni sur une cible reelle.
      D : constant Detection := Detect_Adaptive (M.Data);
   begin
      --  La frame porte l heure de sa DERNIERE mesure : Add etant
      --  appele pour chaque direction du tour, c est l instant ou le
      --  tour s acheve.
      F.Stamp := M.Stamp;

      --  Detect_Adaptive vient de s interdire les premieres cases : la
      --  frame doit le dire, sinon le pistage croirait vide une zone
      --  qu il n a simplement pas pu voir.
      F.Min_Range := Profile_Min_Range;

      for K in 1 .. D.Count loop
         exit when F.Count = Max_Detections;

         declare
            --  Distance simulee de la case detectee (Bin_Distance est
            --  partagee avec Peak_Distance).
            Dist : constant Float := Float (Bin_Distance (D.Targets (K)));

            --  Position 3D : on combine la direction visee (azimut,
            --  elevation de la mesure) avec la distance de l'echo.
            P : constant Point_3D :=
              To_Point (Dist, M.Azimuth, M.Elevation);
         begin
            F.Count := F.Count + 1;
            F.Items (F.Count) := (Pos => P, Distance => Dist);
         end;
      end loop;
   end Add;

   ----------------
   -- Scan_Order --
   ----------------

   subtype Detection_Index is Positive range 1 .. Max_Detections;
   type Index_List is array (Detection_Index) of Detection_Index;

   --  Ordre strict et total sur les detections : distance au capteur, puis
   --  X, Y, Z. Total pour que deux echos distincts ne soient jamais ex
   --  aequo, sinon leur ordre d'arrivee redeciderait de la graine.
   function Before (A, B : Detection_3D) return Boolean is
     (A.Distance < B.Distance
      or else (A.Distance = B.Distance
               and then (A.Pos.X < B.Pos.X
                         or else (A.Pos.X = B.Pos.X
                                  and then (A.Pos.Y < B.Pos.Y
                                            or else (A.Pos.Y = B.Pos.Y
                                                     and then A.Pos.Z
                                                              < B.Pos.Z))))))
   with SPARK_Mode => On;

   --  L'ordre dans lequel Cluster prend ses graines. Avant, c'etait l'ordre
   --  d'arrivee : trois echos alignes a 500 mm donnaient 2 groupes en
   --  A-B-C et un seul en B-A-C (dette 38). On trie des indices et pas la
   --  frame, parce que Owners est indexe sur l'ordre d'origine.
   --
   --  Tri par insertion, a echanges voisins : 32 elements au plus, et la
   --  preuve n'a besoin que de l'asymetrie de Before, pas de sa
   --  transitivite. Le "pont" (J - 1 avant J + 1) est ce qui garde la
   --  suite triee quand l'element insere recule d'une case.
   --  Injectif sur 1 .. Count et a valeurs dans 1 .. Count : c'est bien
   --  une permutation, chaque detection est examinee une fois.
   function Scan_Order (F : Frame) return Index_List
   with
     SPARK_Mode => On,
     Post =>
       (for all K in 1 .. F.Count => Scan_Order'Result (K) <= F.Count)
       and then
         (for all K1 in 1 .. F.Count =>
            (for all K2 in K1 + 1 .. F.Count =>
               Scan_Order'Result (K1) /= Scan_Order'Result (K2)))
       and then
         (for all K in 2 .. F.Count =>
            not Before (F.Items (Scan_Order'Result (K)),
                        F.Items (Scan_Order'Result (K - 1))))
   is
      --  L'agregat semble inutile, la boucle remplit tout. Sans lui,
      --  gnatprove signale Order "might not be initialized" a chaque
      --  lecture dans les invariants.
      Order : Index_List := (others => 1);
      Swap  : Detection_Index;
      J     : Detection_Index;
   begin
      for K in Order'Range loop
         Order (K) := K;
         pragma Loop_Invariant (for all M in 1 .. K => Order (M) = M);
      end loop;

      for I in 2 .. F.Count loop
         pragma Loop_Invariant
           (for all K in 1 .. F.Count => Order (K) <= F.Count);
         pragma Loop_Invariant
           (for all K1 in 1 .. F.Count =>
              (for all K2 in K1 + 1 .. F.Count => Order (K1) /= Order (K2)));
         pragma Loop_Invariant
           (for all K in 2 .. I - 1 =>
              not Before (F.Items (Order (K)), F.Items (Order (K - 1))));

         --  Order (J) est l'element en cours d'insertion.
         J := I;
         loop
            pragma Loop_Invariant (J <= I);
            pragma Loop_Invariant
              (for all K in 1 .. F.Count => Order (K) <= F.Count);
            pragma Loop_Invariant
              (for all K1 in 1 .. F.Count =>
                 (for all K2 in K1 + 1 .. F.Count =>
                    Order (K1) /= Order (K2)));
            pragma Loop_Invariant
              (for all K in 2 .. J - 1 =>
                 not Before (F.Items (Order (K)), F.Items (Order (K - 1))));
            pragma Loop_Invariant
              (for all K in J + 2 .. I =>
                 not Before (F.Items (Order (K)), F.Items (Order (K - 1))));
            pragma Loop_Invariant
              (if J < I then
                 Before (F.Items (Order (J)), F.Items (Order (J + 1))));
            pragma Loop_Invariant
              (if J < I and then J > 1 then
                 not Before (F.Items (Order (J + 1)),
                             F.Items (Order (J - 1))));
            pragma Loop_Variant (Decreases => J);

            exit when J = 1
              or else not Before (F.Items (Order (J)),
                                  F.Items (Order (J - 1)));

            declare
               --  Photo de Order avant l'echange, pour la preuve seulement.
               Pre_Swap : constant Index_List := Order with Ghost;
            begin
               Swap          := Order (J);
               Order (J)     := Order (J - 1);
               Order (J - 1) := Swap;
               --  L'invariant "pas de doublon" demande de voir le nouveau
               --  tableau comme l'ancien lu a travers la permutation
               --  J <-> J-1. Laisse seul, le prouveur la cherche : 4 s ici,
               --  au-dela du delai du runner GitHub (CI de 46ce636). Ecrite
               --  ici, il n'a plus qu'a substituer.
               pragma Assert
                 (for all K in 1 .. F.Count =>
                    Order (K) = Pre_Swap
                      (if K = J then J - 1 elsif K = J - 1 then J else K));
            end;
            J := J - 1;
         end loop;

         --  Le tri de 1 .. I redit ici : sans cet Assert, la postcondition
         --  de tri ne passait pas, meme au niveau 2.
         pragma Assert
           (for all K in 2 .. I =>
              not Before (F.Items (Order (K)), F.Items (Order (K - 1))));
      end loop;

      return Order;
   end Scan_Order;

   -------------
   -- Cluster --
   -------------

   function Cluster (F : Frame) return Frame is
     (Cluster (F, No_Owner));

   function Cluster (F : Frame; Owners : Owner_List) return Frame is
      Result : Frame;
      Used   : array (1 .. Max_Detections) of Boolean := (others => False);
      Order  : constant Index_List := Scan_Order (F);

      --  Distance 3D entre deux points.
      function Dist3D (A, B : Point_3D) return Float is
        (Sqrt ((A.X - B.X) ** 2 + (A.Y - B.Y) ** 2 + (A.Z - B.Z) ** 2));

   begin
      Reset (Result);
      --  Le regroupement ne change ni l heure ni ce que le capteur
      --  voyait : les oublier ici les perdrait avant le pistage.
      Result.Stamp     := F.Stamp;
      Result.Min_Range := F.Min_Range;

      --  Pour chaque detection pas encore regroupee, dans l'ordre trie :
      --  la graine est la plus proche des detections libres.
      for P in 1 .. F.Count loop
         if not Used (Order (P)) then

            declare
               --  On demarre un groupe avec la detection I.
               I     : constant Detection_Index := Order (P);
               Sum_X : Float := F.Items (I).Pos.X;
               Sum_Y : Float := F.Items (I).Pos.Y;
               Sum_Z : Float := F.Items (I).Pos.Z;
               Sum_D : Float := F.Items (I).Distance;
               N     : Natural := 1;

               --  La piste qui revendique le groupe (0 = aucune encore). On
               --  la suit pour le GROUPE et non pour la seule graine : une
               --  graine sans proprietaire ne doit pas servir de pont entre
               --  les detections de deux pistes differentes.
               Group_Owner : Natural := Owners (I);
            begin
               Used (I) := True;

               --  On cherche toutes les detections proches de I, sauf
               --  celles d'une AUTRE piste confirmee que celle du groupe.
               --  Meme ordre trie que pour les graines : quand une graine
               --  libre touche deux pistes, c'est la plus proche qui
               --  l'emporte, plus l'ordre d'arrivee.
               for Q in P + 1 .. F.Count loop
                  declare
                     J : constant Detection_Index := Order (Q);
                  begin
                     if not Used (J)
                       and then Dist3D (F.Items (I).Pos, F.Items (J).Pos)
                                < Cluster_Radius
                       and then (Owners (J) = 0
                                 or else Group_Owner = 0
                                 or else Owners (J) = Group_Owner)
                     then
                        Sum_X := Sum_X + F.Items (J).Pos.X;
                        Sum_Y := Sum_Y + F.Items (J).Pos.Y;
                        Sum_Z := Sum_Z + F.Items (J).Pos.Z;
                        Sum_D := Sum_D + F.Items (J).Distance;
                        N := N + 1;
                        Used (J) := True;
                        if Group_Owner = 0 then
                           Group_Owner := Owners (J);
                        end if;
                     end if;
                  end;
               end loop;

               --  La cible regroupee = moyenne des positions du groupe.
               if Result.Count < Max_Detections then
                  Result.Count := Result.Count + 1;
                  Result.Items (Result.Count) :=
                    (Pos => (X => Sum_X / Float (N),
                             Y => Sum_Y / Float (N),
                             Z => Sum_Z / Float (N)),
                     Distance => Sum_D / Float (N));
               end if;
            end;
         end if;
      end loop;

      return Result;
   end Cluster;

end Radar_Detect;
