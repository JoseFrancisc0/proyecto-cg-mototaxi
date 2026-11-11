"""Architecture components executed in the regional builder's Blender context.

Metric UVs, deliberately different joinery, closed balcony returns and roofs.
The glTF-supported multiply node preserves the actual painted facade colour.
"""
PALETTES={
'costa':[(.95,.62,.08),(.05,.64,.59),(.94,.36,.40),(.88,.84,.71),(.40,.65,.80),(.69,.34,.58),(.74,.85,.53),(.94,.50,.20),(.95,.94,.84),(.33,.46,.61),(.83,.70,.51),(.50,.66,.51)],
'sierra':[(.92,.88,.76),(.85,.77,.58),(.69,.40,.23),(.90,.87,.81),(.74,.55,.36),(.87,.68,.31),(.73,.80,.76),(.82,.44,.31)],
'selva':[(.16,.68,.63),(.98,.70,.16),(.62,.78,.87),(.94,.42,.24),(.78,.90,.66),(.85,.49,.66),(.89,.89,.76),(.42,.64,.87)]}
_paint_cache={}
def paint(index,region):
    key=(index%len(PALETTES[region]),region)
    if key in _paint_cache:return _paint_cache[key]
    color=PALETTES[region][key[0]]
    m=material('Pintura '+region+' '+str(key[0]),color=color)
    source=materials[region][9 if region=='costa' else 8 if region=='sierra' else 17]
    tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=next(n.image for n in source.node_tree.nodes if n.type=='TEX_IMAGE')
    mix=m.node_tree.nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=1
    mix.inputs[2].default_value=(*color,1)
    # Paint colour is the finish itself. The photographic plaster supplies
    # surface relief, not giant grey stains that bury the reference palette.
    principled=m.node_tree.nodes.get('Principled BSDF')
    bind_surface_normal(m,source,.20)
    m['atlas_tile']=0;m['uv_scale']=.8;_paint_cache[key]=m
    return m

joinery=[material('Carpinteria nogal',color=(.21,.10,.045)),material('Carpinteria miel',color=(.46,.25,.095)),material('Carpinteria crema',color=(.84,.81,.68)),material('Carpinteria turquesa',color=(.035,.30,.32)),material('Carpinteria azul andino',color=(.035,.19,.37)),material('Carpinteria granate',color=(.35,.065,.055))]
window_glass=[material('Vidrio reflejo '+str(i),color=c,metal=.22) for i,c in enumerate([(.12,.22,.25),(.21,.31,.32),(.10,.16,.19),(.27,.34,.34)])]

def polygon(name,coords,mat):
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(coords,[],[list(range(len(coords)))]);mesh.update()
    o=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(o);o.data.materials.append(mat)
    uv=mesh.uv_layers.new()
    for loop in mesh.loops:
        co=mesh.vertices[loop.vertex_index].co;uv.data[loop.index].uv=(co.x*mat.get('uv_scale',.7),co.z*mat.get('uv_scale',.7))
    return o

def arch_outline(x,y,z,w,h,mat,r=.045):
    spring=z+h-w*.5
    for sign in [-1,1]:pole('Jamba',(x+sign*w*.5,y,z),(x+sign*w*.5,y,spring),r,mat)
    for j in range(20):
        a=j*math.pi/20;b=(j+1)*math.pi/20
        pole('Arco de carpinteria',(x+math.cos(a)*w*.5,y,spring+math.sin(a)*w*.5),(x+math.cos(b)*w*.5,y,spring+math.sin(b)*w*.5),r,mat)

def window(x,y,z,w=1.2,h=1.25,bars=True,frame=None,kind=0,glass_override=None):
    """Seven silhouettes, varied muntins, real reveals and painted wood."""
    frame=frame or joinery[kind%len(joinery)];kind%=7
    opening_anchor('window',x,y,z,w,h)
    glassmat=glass_override or window_glass[kind%4];sill=z-h*.5
    if kind==3:
        spring=z+h*.5-w*.5
        pts=[(x-w*.5,y-.12,sill),(x+w*.5,y-.12,sill)]+[(x+math.cos(a)*w*.5,y-.12,spring+math.sin(a)*w*.5) for a in [j*math.pi/20 for j in range(21)]]
        polygon('Ventana de medio punto',pts,glassmat);arch_outline(x,y-.16,sill,w,h,frame)
        box('Parteluz',(x,y-.18,z),(.055,.065,h-.10),frame,0)
    elif kind==5:
        # Bay window has a solid sill, angled cheeks, and a projecting roof.
        box('Base de mirador',(x,y-.28,sill),(w+.12,.60,.15),frame)
        box('Tejadillo de mirador',(x,y-.28,z+h*.5),(w+.25,.72,.12),frame)
        box('Vidrio de mirador',(x,y-.54,z),(w*.72,.035,h),glassmat,0)
        for sign in [-1,1]:
            polygon('Retorno vidriado',[(x+sign*w*.36,y-.54,sill),(x+sign*w*.5,y-.06,sill),(x+sign*w*.5,y-.06,z+h*.5),(x+sign*w*.36,y-.54,z+h*.5)],glassmat)
            box('Pilar de mirador',(x+sign*w*.36,y-.56,z),(.075,.09,h),frame)
    else:
        box('Alfeizar',(x,y-.12,sill-.04),(w+.20,.35,.12),frame)
        box('Hueco en sombra',(x,y-.025,z),(w+.09,.08,h+.08),iron,0)
        box('Vidrio',(x,y-.09,z),(w,.035,h),glassmat,0)
        for sign in [-1,1]:
            box('Jamba de ventana',(x+sign*(w*.5+.035),y-.13,z),(.075,.16,h+.16),frame)
            box('Dintel de ventana',(x,y-.13,z+sign*(h*.5+.035)),(w+.15,.16,.075),frame)
        panes=[2,3,1,2,4,3,2][kind]
        for j in range(1,panes):box('Hoja de ventana',(x-w*.5+j*w/panes,y-.16,z),(.04,.05,h),frame,0)
        if kind in [1,4,6]:box('Travesano alto',(x,y-.17,z+h*.20),(w,.06,.045),frame,0)
    if kind in [1,6]:
        # Timber shutters are panels with louvers, not brick-textured plates.
        for sign in [-1,1]:
            sx=x+sign*(w*.5+.20)
            box('Hoja de postigo',(sx,y-.10,z),(.32,.10,h),frame)
            for j in range(8):box('Lama de postigo',(sx,y-.17,sill+.12+j*(h-.20)/8),(.28,.045,.035),frame,0)
    if bars and kind not in [3,5]:
        for j in range(max(3,int(w/.21))):
            bx=x-w*.44+j*w*.88/max(1,int(w/.21)-1)
            pole('Fierro de reja',(bx,y-.23,sill+.03),(bx,y-.23,sill+h-.03),.011,iron)
        for dz in [-.25,.25]:box('Travesano de reja',(x,y-.24,z+dz*h),(w,.035,.025),iron,0)

def door(x,y,z,mat=None,w=1.05,h=2.15,kind=0,glass_override=None):
    opening_anchor('door',x,y-.25,z+h*.5,w,h)
    mat=mat or joinery[kind%len(joinery)];kind%=5
    box('Umbral',(x,y-.14,z+.025),(w+.26,.38,.07),cement)
    for sign in [-1,1]:box('Jamba acceso',(x+sign*(w*.5+.045),y,z+h*.5),(.09,.24,h+.12),white)
    box('Dintel acceso',(x,y,z+h+.045),(w+.18,.24,.09),white)
    if kind==2:
        spring=z+h-w*.5
        polygon('Puerta arqueada',[(x-w*.5,y-.13,z),(x+w*.5,y-.13,z)]+[(x+math.cos(a)*w*.5,y-.13,spring+math.sin(a)*w*.5) for a in [j*math.pi/20 for j in range(21)]],mat)
        arch_outline(x,y-.18,z,w,h,joinery[2],.055)
    else:box('Hoja de puerta',(x,y-.13,z+h*.5),(w,.10,h),mat)
    if kind==0:
        for dx in [-.24,.24]:
            for dz in [.40,1.05,1.65]:box('Cuarteron',(x+dx*w,y-.19,z+dz),(w*.37,.045,.43),mat)
    elif kind==1:
        for j in range(10):box('Liston horizontal',(x,y-.20,z+.15+j*(h-.30)/10),(w*.89,.045,.08),mat,0)
    elif kind==3:
        for j in range(7):box('Barrote de porton',(x-w*.43+j*w*.143,y-.20,z+h*.5),(.025,.045,h*.90),iron,0)
    elif kind==4:
        box('Vidrio de acceso',(x,y-.20,z+h*.65),(w*.72,.025,h*.50),glass_override or glass)
        for sign in [-1,1]:box('Hoja acristalada',(x+sign*w*.38,y-.22,z+h*.65),(.045,.04,h*.56),mat,0)
    pole('Tirador',(x+w*.31,y-.25,z+.95),(x+w*.31,y-.25,z+1.14),.018,iron)

def balcony(w,y,z,mat=wood,kind=0):
    """Continuous front AND side rails; enclosed timber bay is a separate type."""
    depth=1.05;front=y-depth*.5
    box('Losa de balcon',(0,y,z),(w,depth,.18),cement)
    if kind==2:
        box('Antepecho de madera',(0,front,z+.37),(w,.12,.65),mat)
        for sign in [-1,1]:box('Retorno de madera',(sign*w*.5,y,z+.37),(.10,depth,.65),mat)
        count=max(3,int(w/.6))
        for j in range(count):window(-w*.4+j*w*.8/(count-1),front-.10,z+1.12,.50,.78,False,mat,0)
        for sign in [-1,1]:box('Cierre lateral de mirador',(sign*w*.5,y,z+1.12),(.10,depth,.92),mat)
        box('Alero de balcon',(0,y,z+1.68),(w+.22,depth+.22,.14),mat)
    else:
        paths=[((-w*.5,front),(w*.5,front)),((-w*.5,front),(-w*.5,y+depth*.5)),((w*.5,front),(w*.5,y+depth*.5))]
        for a,b in paths:
            pa=Vector((a[0],a[1],z+.15));pb=Vector((b[0],b[1],z+.15))
            pole('Pasamanos continuo',pa+Vector((0,0,.9)),pb+Vector((0,0,.9)),.035,mat)
            if kind==3:
                # Tinted glass balustrade with its closed side returns.
                polygon('Baranda de cristal',[tuple(pa),tuple(pb),tuple(pb+Vector((0,0,.84))),tuple(pa+Vector((0,0,.84)))],glass)
            else:
                n=max(1,math.ceil((pb-pa).length/.16))
                for j in range(n+1):
                    p=pa.lerp(pb,j/n);pole('Balaustre',p,p+Vector((0,0,.90)),.016 if kind==0 else .028,mat)
    # Corbels make the projection read as an attached building part.
    for x in [-w*.36,w*.36]:pole('Mensula',(x,y+.4,z-.42),(x,front+.15,z-.10),.055,mat)

def gable(w,d,base,rise,mat):
    for sign in [-1,1]:
        polygon('Testero cerrado',[(-w*.5,sign*d*.5,base),(w*.5,sign*d*.5,base),(0,sign*d*.5,base+rise)],wall)
    run=w*.5+.30;slope=math.atan2(rise,run)
    for sign in [-1,1]:
        o=box('Faldon de cubierta',(sign*run*.5,0,base+rise*.5),(math.hypot(run,rise),d+.70,.12),mat,.008);o.rotation_euler.y=sign*slope
        for edge in [-1,1]:pole('Fascia de madera',(sign*run,edge*(d*.5+.35),base),(0,edge*(d*.5+.35),base+rise),.055,joinery[0])
    pole('Cumbrera',(0,-d*.5-.37,base+rise+.04),(0,d*.5+.37,base+rise+.04),.06,mat)

def round_slab(name,cx,y,z,w,depth,mat):
    # A rounded projecting corner/balcony, extruded closed above and below.
    pts=[(cx-w*.5,y+depth*.5),(cx+w*.5,y+depth*.5),(cx+w*.5,y-depth*.15)]
    pts += [(cx+math.cos(a)*w*.5,y-depth*.15-math.sin(a)*depth*.6) for a in [j*math.pi/20 for j in range(21)]]
    n=len(pts);verts=[(x,yy,z+dz) for dz in [-.09,.09] for x,yy in pts]
    faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update();o=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(o);o.data.materials.append(mat)

def facade_details(style,v,w,d,base,level,floors,region):
    top=base+level*floors
    if style in ['barrio','invasion','andina_urbana','andina_ladera']:
        # Finished painted lower storey + unfinished upper addition is common.
        if floors>1 and v%2:
            box('Ampliacion ladrillo',(w*.25,d*.15,top+.65),(w*.43,d*.65,1.3),materials[region][0 if region=='costa' else 17]);box('Losa de ampliacion',(w*.25,d*.15,top+1.36),(w*.46,d*.68,.12),cement)
        if v%2==0:
            for x in [-w*.46,w*.46]:pole('Fierro de ampliacion',(x,d*.30,top),(x,d*.30,top+.55),.012,iron)
        if v in [1,3]:
            awning=box('Toldo de bodega',(w*.15,-d*.5-.65,base+2.2),(w*.47,1.3,.055),paint(v+6,region));awning.rotation_euler.x=.12
            box('Franja comercial',(w*.15,-d*.5-.11,base+2.30),(w*.48,.08,.32),paint(v+3,region))
    if style=='barranco':
        for x in [-w*.48,w*.48]:box('Pilastra republicana',(x,-d*.5-.10,top*.5),(.22,.22,top),joinery[2])
        for height in [base+.65,top-.22,top+.08]:box('Moldura corrida',(0,-d*.5-.13,height),(w+.20,.30,.10),joinery[2])
        if v==1:
            # Pediment rather than yet another flat parapet.
            polygon('Fronton',[(-w*.26,-d*.5-.15,top),(w*.26,-d*.5-.15,top),(0,-d*.5-.15,top+.75)],paint(v+1,region))
        if v==2:balcony(w*.45,-d*.5-.55,base+level,joinery[0],2)
    if style=='jardin':
        # Villa volumes, a portico, garden wall and a distinctly offset wing.
        wing=box('Ala de vivienda',(w*.26,d*.16,top+.65),(w*.48,d*.65,1.3),paint(v+8,region))
        for x in [-w*.32,w*.32]:box('Columna del porche',(x,-d*.5-.9,base+1.25),(.24,.24,2.5),white)
        box('Cubierta de porche',(0,-d*.5-.65,base+2.55),(w*.85,1.8,.18),white)
        for sign in [-1,1]:
            box('Muro de jardin',(sign*w*.34,-d*.5-1.35,.43),(w*.28,.18,.86),paint(v+8,region))
        if v in [0,2]:gable(w,d,top+1.3,1.1,materials[region][14])
    if style=='miraflores':
        if floors>4:
            for f in range(1,floors):
                z=base+f*level
                if v==2:
                    round_slab('Terraza curva',w*.18,-d*.5-.30,z,w*.66,1.15,white)
                    for k in range(17):
                        a=k*math.pi/16;x=w*.18+math.cos(a)*w*.33;y=-d*.5-.47-math.sin(a)*.7
                        pole('Montante curvo',(x,y,z+.08),(x,y,z+1.05),.018,iron)
                        if k: pole('Pasamanos curvo',prev,(x,y,z+1.05),.025,iron)
                        prev=(x,y,z+1.05)
                else:
                    box('Marco de doble altura',(-w*.35,-d*.5-.35,z+level*.5),(.45,.65,level),white)
            for x in [-w*.46,w*.03,w*.46]:box('Aleta vertical',(x,-d*.5-.2,top*.5),(.15,.4,top),white)
        else:
            for j in range(11):box('Celosia vertical',(w*.30+j*.13,-d*.5-.18,base+1.25),(.055,.22,2.5),joinery[1])
    if style in ['san_blas','valle_sagrado','adobe','andina_ladera']:
        if style in ['san_blas','valle_sagrado'] and v%2 and floors>1:
            balcony(w*.76,-d*.5-.55,base+level,joinery[4] if style=='san_blas' else joinery[0],1 if v==1 else 2)
        if style in ['adobe','andina_ladera']:
            for j in range(4):pole('Viga saliente',(-w*.40+j*w*.26,-d*.5+.15,top),(-w*.40+j*w*.26,-d*.5-.45,top),.065,joinery[0])
    if region=='selva':
        for x in [-w*.43,w*.43]:box('Zapata galeria',(x,-d*.5-1.0,base-.08),(.35,.35,.16),cement)
        if style=='iquitos':
            # Patterned tile dado belongs to the wall, below the openings.
            box('Zocalo de azulejos',(0,-d*.5-.10,base+.33),(w,.08,.60),materials[region][15+v%3])
            for x in [-w*.47,0,w*.47]:box('Pilastra de casona',(x,-d*.5-.15,top*.5),(.17,.24,top),joinery[2])
        if style in ['belen','comunidad']:
            # Narrow planks and exposed framing: large wood pixels are avoided.
            for x in [-w*.46,0,w*.46]:box('Pie derecho de madera',(x,-d*.5-.09,(base+top)*.5),(.10,.13,top-base),joinery[0])
        if style in ['tropical_actual','tarapoto']:
            for k in range(12):box('Parasoles tropicales',(-w*.42+k*w*.075,-d*.5-.21,top-.40),(.12,.18,.55),joinery[1])

def back_and_corner_elevations(style,v,w,d,base,level,floors):
    """Model exposed elevations too: a town seen from above is not a row of
    detailed fronts attached to completely featureless tall boxes."""
    from mathutils import Matrix
    frame=joinery[0] if style in ['san_blas','belen','comunidad'] else joinery[2]
    for f in range(floors):
        z=base+f*level+level*.59
        floor_w=w*(.76 if style in ['miraflores','andina_actual','tropical_actual'] and f>0 and floors<4 else .90 if style=='jardin' and f>0 else 1)
        for x in [-floor_w*.25,floor_w*.25]:
            start=set(bpy.context.scene.objects)
            window(x,0,z,min(1.8,w*.23),1.25 if floors<4 else 1.65,False,frame,0)
            xf=Matrix.Translation(Vector((0,d*.5+.035,0)))@Matrix.Rotation(math.pi,4,'Z')
            bpy.context.view_layer.update()
            for obj in set(bpy.context.scene.objects)-start:obj.matrix_world=xf@obj.matrix_world
        if v in [0,3] or floors>4:
            for sign in [-1,1]:
                for yy in [-d*.22,d*.24]:
                    start=set(bpy.context.scene.objects)
                    window(0,0,z,min(1.8,d*.22),1.25 if floors<4 else 1.65,False,frame,2 if v==3 else 0)
                    xf=Matrix.Translation(Vector((sign*(floor_w*.5+.035),yy,0)))@Matrix.Rotation(sign*math.pi*.5,4,'Z')
                    bpy.context.view_layer.update()
                    for obj in set(bpy.context.scene.objects)-start:obj.matrix_world=xf@obj.matrix_world
