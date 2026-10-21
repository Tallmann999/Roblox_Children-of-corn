# B trail corn border

The saved four-stud trail reserved seven studs between stalk roots because the common prop exclusion added1.5studs on each side. Fixed2.631174stud lattice phase made the visible gap wider still.

The new source recognizes only current exact-owned B `NoCornZones/Maze02Masks/trail_001` through `trail_100`: both owner attributes, field/map identity, four-stud width, .08stud thickness, at least30stud length, and identity rotation. These masks use zero extra root padding. All other exclusions retain their previous dimensions and padding.

Existing surviving lattice cells within one spacing of an owned trail side move to2.05studs from the trail center. Candidate and original root must satisfy every exclusion; projection fails closed around crossing paths, barns, key slots, spawns and the gate. Near and backdrop call the same function, with existing shape selection, height variation, LOD, budgets and physics unchanged. No separate edge plants or generator is added. Effective padding already participates in the layout signature, so ownership and dimension changes invalidate chunks.

The dedicated fixture passes5078assertions. Exact accepted B grid analysis finds45257→50187eligible dense roots and11180→12433eligible even-grid Far roots after reclaiming the old shoulders. Projection moves7985existing cells, max2.580322studs, with no shifted root entering any exclusion. The candidate count increase comes from zero padding; projection itself retains the count.

Across3447eligible straight-trail sample positions, approximate Near leaf vertices at4..6.6studs above ground have a median distance from trail center of0.7014studs, compared with3.3425before and1.7611for zero padding alone.79.68%of sampled sides have leaf vertices within1stud;94.98%of samples have leaves within2studs on both sides. Geometry and pose remain unchanged. This is geometric analysis, not rendered-image or ordinary human-walk acceptance.

No exact duplicate roots occur.310root pairs are closer than.75stud out of50187eligible roots; minimum.0353stud. These are noncolliding clumps, and do not add any plants or change render budgets. Native image inspection must check that local clumps look natural and that real Near rendering shows the intended brush at head height.

Production files owned by this subtask are CornLayout and one callsite in each near/backdrop controller. Studio was never mutated by this subtask. Analysis only deserializes the accepted saved B privately and writes JSON; no scene is serialized.
