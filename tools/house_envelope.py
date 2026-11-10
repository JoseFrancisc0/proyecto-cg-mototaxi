"""Blender-side opening, envelope and entrance checks before joining meshes."""
def opening_anchor(kind,x,y,z,w,h):
    obj=bpy.data.objects.new('Opening_'+kind,None);bpy.context.collection.objects.link(obj)
    obj.location=(x,y,z);obj['opening_kind']=kind;obj['width']=w;obj['height']=h

def finalize_house(key,w,d):
    import bmesh
    bpy.context.view_layer.update()
    anchors=[o for o in bpy.context.scene.objects if 'opening_kind' in o]
    doors=[o for o in anchors if o['opening_kind']=='door']
    if not doors:raise ValueError(key+': missing pedestrian entrance')
    low=min(o.matrix_world.translation.z-o['height']*.5 for o in doors)
    ground_doors=[o for o in doors if o.matrix_world.translation.z-o['height']*.5<low+.35]
    for door_obj in ground_doors:
        center=door_obj.matrix_world.translation
        for win in [o for o in anchors if o['opening_kind']=='window']:
            delta=door_obj.matrix_world.inverted()@win.matrix_world.translation
            normal=win.matrix_world.to_3x3()@Vector((0,1,0))
            if abs(normal.dot(door_obj.matrix_world.to_3x3()@Vector((0,1,0))))<.99:continue
            if abs(delta.y)>.65:continue
            dx=(door_obj['width']+win['width'])*.5-abs(delta.x)
            dz=(door_obj['height']+win['height'])*.5-abs(delta.z)
            if dx>.06 and dz>.06:raise ValueError(f'{key}: door/window overlap {dx:.2f} x {dz:.2f} m')
    entry=min(ground_doors,key=lambda o:o.matrix_world.translation.y)
    p=entry.matrix_world.translation-Vector((0,0,entry['height']*.5))
    sealed=0
    for obj in list(bpy.context.scene.objects):
        if obj.type!='MESH':continue
        mesh=bmesh.new();mesh.from_mesh(obj.data)
        boundary=any(e.is_boundary for e in mesh.edges)
        bmesh.ops.recalc_face_normals(mesh,faces=list(mesh.faces));mesh.to_mesh(obj.data);mesh.free()
        if boundary:
            bpy.context.view_layer.objects.active=obj
            mod=obj.modifiers.new('Espesor y retornos cerrados','SOLIDIFY');mod.thickness=.012;mod.offset=0;mod.use_rim=True
            bpy.ops.object.modifier_apply(modifier=mod.name);sealed+=1
    bpy.context.view_layer.update()
    for obj in list(anchors):bpy.data.objects.remove(obj,do_unlink=True)
    return {'entrance':[p.x,p.z,-p.y],'foundation_size':[w,d],'envelope':{'openings':len(anchors),'sealed_panels':sealed,'ground_doors':len(ground_doors)}}
