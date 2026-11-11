"""Specific Andean/Amazonian construction, rather than a shared facade recipe."""
def rgb(code):
    code=code.lstrip('#');values=[int(code[i:i+2],16)/255 for i in [0,2,4]]
    return tuple(c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in values)

reference_dark_glass=material('Vidrio oscuro de referencia',color=rgb('243330'),metal=.22)
reference_dark_glass.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.24
reference_curtain=material('Cortina de galeria tropical',color=rgb('c7c7b1'))

def rear_windows(w,d,z,mat,count=2):
    from mathutils import Matrix
    for j in range(count):
        start=set(bpy.context.scene.objects)
        window((j-(count-1)*.5)*w/(count+.8),0,z,min(1.25,w/(count+1.8)),1.2,False,mat,0)
        bpy.context.view_layer.update()
        xf=Matrix.Translation(Vector((0,d*.5+.03,0)))@Matrix.Rotation(math.pi,4,'Z')
        for obj in set(bpy.context.scene.objects)-start:obj.matrix_world=xf@obj.matrix_world

def wedge_room(x,y,z,w,d,h0,h1,mat):
    verts=[(x-w*.5,y-d*.5,z),(x+w*.5,y-d*.5,z),(x+w*.5,y+d*.5,z),(x-w*.5,y+d*.5,z),
           (x-w*.5,y-d*.5,z+h0),(x+w*.5,y-d*.5,z+h1),(x+w*.5,y+d*.5,z+h1),(x-w*.5,y+d*.5,z+h0)]
    mesh=bpy.data.meshes.new('Dormitorio de cubierta asimetrica');mesh.from_pydata(verts,[],[(0,3,2,1),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)]);mesh.update()
    layer=mesh.uv_layers.new()
    for face in mesh.polygons:
        axis=max(range(3),key=lambda k:abs(face.normal[k]));axes=[k for k in range(3) if k!=axis]
        for loop in face.loop_indices:
            p=mesh.vertices[mesh.loops[loop].vertex_index].co;layer.data[loop].uv=(p[axes[0]]*mat.get('uv_scale',.6),p[axes[1]]*mat.get('uv_scale',.6))
    obj=bpy.data.objects.new('Dormitorio de cubierta asimetrica',mesh);bpy.context.collection.objects.link(obj);obj.data.materials.append(mat)
    return obj

def huayoccari_reference(v,w,d):
    global wall
    stone=materials['sierra'][5 if v%2==0 else 3]
    timber=honey_wood
    frame=material('Carpinteria Huayoccari',color=rgb('503e2c'))
    wall=stone;base=.22;level=2.75
    box('Basamento de piedra',(0,0,.16),(w+.15,d+.15,.32),stone)
    box('Muro de piedra del valle',(0,0,base+level*.5),(w,d,level),stone)
    bays=6 if w>13 else 5
    for j in range(bays):
        x=(j-(bays-1)*.5)*w/(bays+.35)
        if abs(x-w*.12)<(min(1.0,w/(bays+3))+1.15)*.5+.18:continue
        window(x,-d*.5-.03,base+1.36,min(1.0,w/(bays+3)),2.18,False,frame,0,reference_dark_glass)
    door(w*.12,-d*.5-.10,base,frame,w=1.15,h=2.25,kind=4,glass_override=reference_dark_glass)
    # Long transverse clay roof and distinct timber clerestories.
    from mathutils import Matrix
    start=set(bpy.context.scene.objects);wall=timber
    gable(d,w,base+level,1.6+v*.12,materials['sierra'][10+v%3])
    bpy.context.view_layer.update()
    xf=Matrix.Rotation(math.pi*.5,4,'Z')
    for obj in set(bpy.context.scene.objects)-start:obj.matrix_world=xf@obj.matrix_world
    for j,x in enumerate([-w*.30,0,w*.31] if v!=2 else [-w*.24,w*.23]):
        ww=w*.25 if j==1 else w*.20
        h0=.50 if j==1 and v==0 else 1.4;h1=2.55 if j==1 else 2.1
        wedge_room(x,-d*.18,base+level,ww,d*.56,h0,h1,timber)
        # The glazing follows the asymmetric roof instead of poking through
        # the low corner of the wedge as a rectangular window did.
        y=-d*.46-.045;floor=base+level;margin=.16
        left=x-ww*.5+margin;right=x+ww*.5-margin;bottom=floor+.22
        top_left=floor+h0+(h1-h0)*margin/ww-.15
        top_right=floor+h1-(h1-h0)*margin/ww-.15
        points=[(left,y,bottom),(right,y,bottom),(right,y,top_right),(left,y,top_left)]
        polygon('Vidrio ajustado a cubierta inclinada',points,reference_dark_glass)
        edges=[(points[k],points[(k+1)%4],.035) for k in range(4)]
        for t in [.33,.66]:
            xx=left+(right-left)*t;top=top_left+(top_right-top_left)*t
            edges.append(((xx,y-.025,bottom),(xx,y-.025,top),.022))
        rail_segments('Carpinteria de cubierta inclinada',edges,frame)
    box('Alero de madera continuo',(0,-d*.5-.20,base+level+.02),(w+.35,.62,.15),timber)
    box('Chimenea de piedra',(-w*.44,d*.20,base+level+1.1),(.67,.75,2.2),stone)
    for j in range(4):box('Grada de acceso',(w*.12,-d*.5-.35-j*.32,base-.055-j*.055),(2.1,.38,.11),stone)
    rear_windows(w,d,base+1.36,frame,5)
    wall=stone

def adobe_street_reference(v,w,d):
    global wall
    wall=materials['sierra'][v%2] if v in [1,3] else material('Cal envejecida del pueblo '+str(v),color=rgb('d5c8b0' if v==0 else 'e0d3bb'))
    woodmat=materials['sierra'][15];base=.14;room_depth=d*.62
    # A house behind its thick courtyard boundary, not an apartment block.
    height=2.5 if v!=2 else 4.8
    box('Vivienda de adobe',(0,d*.16,base+height*.5),(w,room_depth,height),wall)
    start=set(bpy.context.scene.objects);gable(w,room_depth,base+height,.8,materials['sierra'][10+v%3])
    for obj in set(bpy.context.scene.objects)-start:obj.location.y+=d*.16
    front=-d*.5;door_x=(-.25 if v%2 else .24)*w;door_width=1.15
    boundary=2.05+v*.12
    # Two solid wall pieces leave an actual pedestrian opening.
    left=-w*.5;right=w*.5
    for a,b in [(left,door_x-door_width*.5),(door_x+door_width*.5,right)]:
        box('Cerco de adobe',((a+b)*.5,front,base+boundary*.5),(b-a,.40,boundary),wall)
        box('Albarda del cerco',((a+b)*.5,front,base+boundary+.04),(b-a+.05,.52,.10),materials['sierra'][10+v%3])
    door(door_x,front-.03,base,woodmat,w=door_width,h=2.08,kind=1 if v%2 else 0)
    box('Piedra en la base',(0,front-.04,.27),(w,.44,.48),materials['sierra'][5])
    if v==2:
        for x in [-w*.25,w*.25]:window(x,-room_depth*.5+d*.16-.03,base+3.45,1.05,1.0,False,joinery[0],0)
    # Timber ends and thick eaves belong to the roof, not a repeated balcony.
    for j in range(6):pole('Canecillo',(-w*.43+j*w*.17,front+.4,base+boundary),(-w*.43+j*w*.17,front-.35,base+boundary),.055,joinery[0])
    rear_windows(w,room_depth+d*.32,base+1.25,joinery[0],2)

def tarapoto_reference(v,w,d):
    global wall
    wall=material('Fachada tropical de Tarapoto '+str(v),color=rgb(['dd4385','cfb28b','96c623','29953d'][v]))
    whitefinish=material('Fascia y canaleta blanca',color=rgb('deded4'))
    timber=material('Puerta de madera miel',color=rgb('98612e'))
    base=.14;top=3.0
    box('Habitacion de una planta',(0,0,(base+top)*.5),(w,d,top-base),wall)
    window(-w*.25,-d*.5-.035,1.52,.92,1.62,True,iron,2,reference_dark_glass)
    door(w*.22,-d*.5-.05,base,timber,w=.93,h=2.40,kind=1)
    # A low rear tile slope is screened by the white fascia at the street.
    roof=box('Cubierta baja',(0,.25,top+.14),(w+.24,d+.7,.13),materials['sierra'][10+v%3]);roof.rotation_euler.x=.055
    box('Fascia blanca',(0,-d*.5-.18,top-.01),(w+.3,.31,.22),whitefinish)
    pole('Canaleta',(w*.50,-d*.5-.39,top),(w*.50,-d*.5-.39,.75),.045,whitefinish)
    pole('Codo de canaleta',(w*.50,-d*.5-.39,.75),(w*.50,-d*.5-.68,.66),.045,whitefinish)
    rear_windows(w,d,1.65,iron,1)

def tropical_gallery_reference(v,w,d):
    global wall
    wall=material('Muro blanco tropical '+str(v),color=rgb('e0e1d4'))
    timber=materials['selva'][0 if v%2==0 else 4]
    frame=material('Madera estructural tropical',color=rgb('60442c'))
    base=.18;level=2.85
    box('Planta de mamposteria',(0,0,base+level*.5),(w,d,level),wall)
    door(0,-d*.5-.06,base,frame,w=1.10,h=2.35,kind=1)
    for x in [-w*.30,w*.28]:window(x,-d*.5-.03,1.72,.83,.65,True,joinery[2],2)
    box('Piso de galeria',(0,-.20,base+level+.04),(w+.55,d+.55,.18),timber)
    box('Habitaciones de madera',(0,d*.18,base+level+1.18),(w*.86,d*.65,2.36),timber)
    for x in [-w*.26,w*.26]:window(x,-d*.145-.03,base+level+1.30,w*.30,1.65,False,frame,4,reference_curtain)
    door(0,-d*.145-.04,base+level+.13,frame,w=1.05,h=2.20,kind=1)
    # Open veranda in front of enclosed rooms, with complete corner returns.
    top=base+level+2.7
    def ceiling(x,y):return top+.95*(1-abs(x)/(w*.5+.6))-.06 if v%2 else top+.20+math.sin(.075)*y-.08
    for x in [-w*.47,0,w*.47]:pole('Pilar de galeria',(x,-d*.5-.25,base+level),(x,-d*.5-.25,ceiling(x,-d*.5-.25)),.075,frame)
    for x in [-w*.47,w*.47]:pole('Pilar lateral',(x,d*.45,base+level),(x,d*.45,ceiling(x,d*.45)),.075,frame)
    perimeter_rail(outline(w+.12,d+.18,.06),base+level+.13,frame)
    if v%2:
        wall=timber;gable(w+.6,d+.7,top,.95,materials['selva'][8+v%2])
        box('Cierre superior de habitaciones',(0,d*.18,(base+level+2.36+top)*.5),(w*.86,d*.65,top-(base+level+2.36)),timber)
        box('Cielo de galeria cerrado',(0,0,top-.06),(w+.6,d+.7,.12),timber)
    else:
        roof=box('Gran cubierta tropical',(0,0,top+.20),(w+1.6,d+2.0,.16),materials['selva'][8+v%2]);roof.rotation_euler.x=.075
        soffit=box('Cielo inclinado de galeria',(0,0,top+.09),(w+1.6,d+2.0,.06),timber);soffit.rotation_euler.x=.075
        # Complete the occupied rooms up to the sloping soffit. The veranda
        # remains open above its rail, while its rooms and roof have no slit.
        low=base+level+2.36;y0=-d*.145;y1=d*.505
        z0=ceiling(0,y0)-.06;z1=ceiling(0,y1)-.06
        vertices=[(-w*.43,y0,low),(w*.43,y0,low),(w*.43,y1,low),(-w*.43,y1,low),(-w*.43,y0,z0),(w*.43,y0,z0),(w*.43,y1,z1),(-w*.43,y1,z1)]
        mesh=bpy.data.meshes.new('Remate de habitaciones bajo cubierta');mesh.from_pydata(vertices,[],[(0,3,2,1),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)]);mesh.update()
        obj=bpy.data.objects.new('Remate de habitaciones bajo cubierta',mesh);bpy.context.collection.objects.link(obj);obj.data.materials.append(timber)
    for x in [-w*.46,0,w*.46]:pole('Viga de alero',(x,-d*.5-1,ceiling(x,-d*.5-1)),(x,d*.5+.8,ceiling(x,d*.5+.8)),.065,frame)
    if v in [0,2]:
        boundary=-d*.5-1.4;gate_half=1.15*.5+.09
        boundary_material=wall if v==2 else materials['costa'][0]
        for a,b in [(-w*.5,-gate_half),(gate_half,w*.5)]:box('Muro de acceso unido a porton',((a+b)*.5,boundary,.90),(b-a,.20,1.8),boundary_material)
        for sign in [-1,1]:box('Retorno cerrado de jardin',(sign*(w*.5-.10),-d*.5-.70,.90),(.20,1.4,1.8),boundary_material)
        box('Paso entre porton y puerta',(0,-d*.5-.70,.06),(1.35,1.4,.12),materials['costa'][10])
        door(0,boundary-.05,.12,frame,w=1.15,h=1.8,kind=1)
    rear_windows(w,d,1.6,joinery[2],2)
