pragma Profile (Ravenscar);

with Radar_Tasks;
pragma Unreferenced (Radar_Tasks);

procedure Radar_Fw is
begin
   null;   --  Les taches (declarees dans Radar_Tasks) demarrent automatiquement.
end Radar_Fw;