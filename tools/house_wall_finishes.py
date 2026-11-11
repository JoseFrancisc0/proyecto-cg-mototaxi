"""User-supplied masonry and graffiti photographs as real wall-face finishes."""
_wall_photos={}

def graffiti_wall_finish(style,v):
    if style not in ['invasion','barrio','andina_urbana','pucallpa'] or v not in [0,2]:return {}
    import bmesh,shutil
    folder=OUT/'materials/graffiti_references';folder.mkdir(exist_ok=True)
    identifiers=['19e97784-0410-40c5-ba32-61c94725219c','43ba9497-815e-460f-a7c9-8ed8eb544e8f','fc36109d-30ca-411a-9883-68f5f1dc25e6']
    index=(v//2+['invasion','barrio','andina_urbana','pucallpa'].index(style))%3
    target=folder/('wall_'+str(index)+'.png')
    if not target.exists():shutil.copyfile(Path('C:/Users/USUARIO/AppData/Local/Temp')/('codex-clipboard-'+identifiers[index]+'.png'),target)
    if index not in _wall_photos:
        finish=material('Pared pintada con grafiti '+str(index),color=(1,1,1))
        image=bpy.data.images.load(str(target),check_existing=True)
        tex=finish.node_tree.nodes.new('ShaderNodeTexImage');tex.image=image
        finish.node_tree.links.new(tex.outputs['Color'],finish.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
        finish.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.95
        _wall_photos[index]=(finish,image.size[0]/image.size[1])
    finish,aspect=_wall_photos[index]
    candidates=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.name.startswith(('Muro principal','Volumen de calle costera'))]
    if not candidates:raise ValueError('Missing blank masonry facade for graffiti: '+style)
    bpy.context.view_layer.update()
    obj=min(candidates,key=lambda o:min((o.matrix_world@Vector(c)).z for c in o.bound_box))
    coords=[obj.matrix_world@vertex.co for vertex in obj.data.vertices]
    minimum=min(p.z for p in coords);maximum=min(max(p.z for p in coords),minimum+2.35)
    cut=obj.matrix_world.inverted()@Vector((obj.location.x,obj.location.y,maximum))
    mesh=bmesh.new();mesh.from_mesh(obj.data)
    bmesh.ops.bisect_plane(mesh,geom=list(mesh.verts)+list(mesh.edges)+list(mesh.faces),plane_co=cut,plane_no=Vector((0,0,1)),clear_inner=False,clear_outer=False,dist=.00001)
    mesh.to_mesh(obj.data);mesh.free();obj.data.update()
    obj.data.materials.append(finish);material_index=len(obj.data.materials)-1
    sign=1 if v==0 else 0
    ymin=min(p.y if sign else p.x for p in coords);ymax=max(p.y if sign else p.x for p in coords);length=ymax-ymin
    vspan=aspect*(maximum-minimum)/length;vbase=max(.04,.55-vspan*.5)
    uv=obj.data.uv_layers.active or obj.data.uv_layers.new()
    assigned=0
    for face in obj.data.polygons:
        if (face.normal.x if sign else -face.normal.y)<.95:continue
        center=obj.matrix_world@face.center
        if center.z>maximum+.0001:continue
        face.material_index=material_index;assigned+=1
        for loop in face.loop_indices:
            p=obj.matrix_world@obj.data.vertices[obj.data.loops[loop].vertex_index].co
            u=((p.y if sign else p.x)-ymin)/length
            uv.data[loop].uv=(u,vbase+(p.z-minimum)*aspect/length)
    if not assigned:raise ValueError('No exterior wall face received graffiti')
    return {'graffiti_wall':True,'graffiti_side':sign,'graffiti_source':'materials/graffiti_references/'+target.name}
