local isaaccs = type(IsaacCS) == "table" and IsaacCS._isaaccs
if REPENTOGON and type(isaaccs) == "table" and isaaccs.native == true then
    include("goodtrip_repentogon")
else
    include("goodtrip_legacy")
end
