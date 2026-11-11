"""Four complete houses studied from the user's individual-building references.

Closed volumes, garage/pedestrian bays, recessed openings and guarded returns.
The reference pictures are documentation, never projected over the whole house.
"""
honey_wood=material('Madera fina de carpinteria',color=(1,1,1))
honey_wood['atlas_tile']=0;honey_wood['uv_scale']=.45
grain=honey_wood.node_tree.nodes.new('ShaderNodeTexImage');grain.image=bpy.data.images.load(str(OUT/'materials/custom/honey_joinery.png'),check_existing=True)
honey_wood.node_tree.links.new(grain.outputs['Color'],honey_wood.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
honey_wood.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.46

def garage(x,y,z,w,h,wooden=True):
    finish=honey_wood if wooden else iron
    box('Porton continuo',(x,y,z+h*.5),(w,.15,h),finish)
    for j in range(1,5 if wooden else 12):
        height=h/(5 if wooden else 12)
        box('Junta horizontal de porton',(x,y-.085,z+j*height),(w-.08,.015,.018 if wooden else .055),iron,0)
    if not wooden:
        for j in range(11):box('Lama blanca del porton',(x,y-.10,z+.13+j*(h-.2)/11),(w-.08,.035,.125),white,0)
    if wooden:
        for sign in [-1,1]:box('Union de hojas',(x+sign*w*.25,y-.09,z+h*.5),(.018,.02,h-.08),iron,0)

def loggia(x,y,z,w,depth,finish,glazing):
    box('Forjado de balcon',(x,y,z),(w,depth,.20),finish)
    pts=[(x-w*.5,y-depth*.5),(x+w*.5,y-depth*.5),(x+w*.5,y+depth*.5),(x-w*.5,y+depth*.5)]
    perimeter_rail(pts,z+.10,iron,glazing)

def side_opening(sign,y,z,w,h,material_frame):
    from mathutils import Matrix
    start=set(bpy.context.scene.objects);window(0,0,z,w,h,False,material_frame,0,reference_dark_glass)
    bpy.context.view_layer.update()
    xf=Matrix.Translation(Vector((sign*house_width*.5,y,0)))@Matrix.Rotation(sign*math.pi*.5,4,'Z')
    for obj in set(bpy.context.scene.objects)-start:obj.matrix_world=xf@obj.matrix_world

def modern_individual(v,w,d):
    global wall,house_width
    house_width=w
    whitewall=material('Estuco blanco vivienda moderna',color=rgb('d9dad5'));bind_surface_normal(whitewall,materials['costa'][9],.20)
    graphite=material('Microcemento gris moderno',color=rgb('576168'));bind_surface_normal(graphite,materials['costa'][10],.30)
    beige=material('Estuco rosado residencial',color=rgb('b3a49e'));bind_surface_normal(beige,materials['costa'][9],.20)
    indigo=material('Estuco azul antracita',color=rgb('3c4555'));bind_surface_normal(indigo,materials['costa'][9],.20)
    frame=material('Aluminio negro',color=rgb('252c2c'),metal=.42)
    paleglass=material('Vidrio de baranda',color=rgb('86a0a3'),metal=.15)
    wall=whitewall;base=.16;level=3.05;front=-d*.5
    if v==0:
        # Broad timber garage, independent pedestrian leaf, grey privacy screen,
        # concrete upper bay and white portal/roof with a continuous side return.
        box('Vivienda de tres niveles',(0,0,base+3.65),(w,d,7.30),whitewall)
        garage(w*.17,front-.12,base,w*.60,2.55)
        door(-w*.26,front-.09,base,honey_wood,w=1.12,h=2.55,kind=1)
        box('Enchape lateral de acceso',(-w*.44,front-.18,1.50),(w*.12,.15,2.70),materials['costa'][10])
        window(w*.23,front-.04,level+1.3,w*.34,2.05,False,frame,4,reference_curtain)
        box('Pantalla de privacidad',(-w*.23,front-.48,level+1.65),(w*.42,.18,2.75),graphite)
        box('Paño superior de concreto',(w*.25,front-.30,6.60),(w*.42,.14,1.35),materials['costa'][10])
        box('Viga blanca intermedia',(0,front-.43,3.12),(w+.12,.55,.30),whitewall)
        loggia(w*.24,front-.45,3.20,w*.42,.85,whitewall,paleglass)
        box('Antepecho blanco de terraza',(0,front-.88,3.73),(w+.1,.18,1.10),whitewall)
        box('Cubierta volada',(0,-.18,7.60),(w+.24,d+.65,.20),whitewall)
        for x in [-w*.46,w*.46]:box('Montante de azotea',(x,front-.18,7.0),(.10,.12,1.15),frame)
        loggia(0,0,6.45,w-.20,d-.20,whitewall,paleglass)
    elif v==1:
        # Narrow urban house: the entry and garage have distinct bays. A deep
        # white frame encloses the upper room and the glass balcony on 3 sides.
        wall=beige;box('Vivienda compacta',(0,0,base+3.15),(w,d,6.30),wall)
        garage(w*.25,front-.12,base,w*.45,2.45,False)
        door(-w*.13,front-.09,base,iron,w=.92,h=2.45,kind=3)
        window(-w*.37,front-.03,1.55,w*.17,1.36,False,whitewall,2)
        for j in range(5):box('Lama blanca de ventana',(-w*.37,front-.25,1.02+j*.24),(w*.17,.04,.10),whitewall,0)
        for j in range(10):box('Lama blanca de puerta',(-w*.13,front-.31,base+.15+j*.23),(.86,.04,.105),whitewall,0)
        window(-w*.39,front-.04,4.65,.68,2.12,False,honey_wood,2,reference_dark_glass)
        window(w*.12,front-.04,4.65,w*.57,2.20,False,frame,4,reference_curtain)
        x=w*.12;fw=w*.67;bottom=3.16;top=6.26
        for sign in [-1,1]:box('Retorno de marco blanco',(x+sign*fw*.5,front-.50,(bottom+top)*.5),(.19,1.20,top-bottom),whitewall)
        for z in [bottom,top]:box('Marco horizontal',(x,front-.50,z),(fw+.18,1.20,.19),whitewall)
        loggia(x,front-.53,3.20,fw,1.1,whitewall,paleglass)
        box('Jardinera de cubierta',(x,front-.26,6.53),(fw,.65,.38),whitewall)
        box('Sustrato de jardinera',(x,front-.26,6.73),(fw-.20,.45,.035),graphite)
        for j in range(10):
            bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=.22,location=(x-fw*.44+j*fw*.098,front-.26,6.84));bpy.context.object.scale=(1,.8,.7);bpy.context.object.data.materials.append(material('Follaje de azotea '+str(j),color=rgb('395637')))
    elif v==2:
        # Warm-climate white house: deep shaded loggia, stone outer portal,
        # timber double gate and a lower garden enclosure with side returns.
        box('Vivienda blanca tropical',(0,.6,base+3.05),(w,d-1.2,6.10),whitewall)
        door(0,front+1.22,base,honey_wood,w=1.1,h=2.45,kind=1)
        for sign in [-1,1]:window(sign*w*.29,front+1.17,1.65,w*.25,1.75,False,frame,0,reference_curtain)
        window(w*.29,front+1.17,4.65,w*.24,2.48,False,frame,4,reference_curtain)
        window(-w*.23,front+1.17,4.55,w*.36,2.10,False,frame,0,reference_curtain)
        box('Pantalla alta blanca',(-w*.03,front+.92,4.90),(w*.18,.26,3.80),whitewall)
        loggia(-w*.27,front+.70,3.20,w*.40,1.1,whitewall,paleglass)
        boundary=front-1.8
        gate_x=-w*.05;gate_half=1.75*.5+.09
        for a,b in [(-w*.5,gate_x-gate_half),(gate_x+gate_half,w*.5)]:
            height=.80 if b<gate_x else 1.90
            box('Muro de jardin cerrado',((a+b)*.5,boundary,height*.5),(b-a,.22,height),whitewall)
            if height<1:
                bars=[((a,boundary,.84),(b,boundary,.84),.025),((a,boundary,1.90),(b,boundary,1.90),.025)]
                count=math.ceil((b-a)/.115)
                for k in range(count+1):
                    xx=a+(b-a)*k/count;bars.append(((xx,boundary,.84),(xx,boundary,1.90),.012))
                rail_segments('Reja cerrada de jardin',bars,iron)
        for sign in [-1,1]:box('Retorno de cerco',(sign*(w*.5-.1),front-.28,.95),(.22,3.25,1.90),whitewall)
        door(-w*.05,boundary-.08,.12,honey_wood,w=1.75,h=2.45,kind=1)
        for sign in [-1,1]:box('Pilar de portico',(sign*w*.43,boundary,1.50),(.22,.40,3.0),materials['costa'][10])
        box('Dintel de portico',(0,boundary,3.05),(w*.90,.65,.25),materials['costa'][10])
        for j in range(12):box('Reja de jardin',(-w*.40+j*w*.026,boundary-.02,1.65),(.025,.045,1.8),iron,0)
        box('Alero de madera',(-w*.23,front+.45,5.99),(w*.40,1.55,.12),honey_wood)
    else:
        # A corner mansion has an occupied lower floor, tall rear pavilions and
        # a protected continuous roof terrace; the garage is in the boundary.
        box('Planta baja',(0,0,base+1.5),(w,d,3.0),whitewall)
        box('Pabellon oscuro izquierdo',(-w*.33,d*.10,4.55),(w*.27,d*.80,5.9),indigo)
        box('Pabellon oscuro central',(-w*.01,d*.23,4.9),(w*.30,d*.53,6.6),indigo)
        box('Ala blanca',(w*.31,d*.12,4.75),(w*.36,d*.76,3.0),whitewall)
        box('Sala frontal cerrada',(w*.10,front+1.5,4.65),(w*.60,3.0,2.98),whitewall)
        box('Revestimiento continuo de madera',(w*.10,front-.04,4.65),(w*.54,.08,2.85),honey_wood)
        for x,y in [(-w*.33,-d*.30-.04),(-w*.01,-d*.035-.04)]:window(x,y,5.4,w*.18,2.65,False,whitewall,4,reference_curtain)
        window(w*.45,-d*.26-.04,4.55,w*.08,2.10,False,frame,4,reference_curtain)
        for j in range(26):box('Celosia vertical de madera',(-w*.15+j*w*.019,front-.10,4.65),(.085,.16,2.98),honey_wood)
        box('Marco de terraza',(w*.10,front-.24,6.15),(w*.60+.20,.70,.28),whitewall)
        loggia(w*.26,front+1.2,6.34,w*.45,3.15,whitewall,paleglass)
        boundary=front-.65
        gate_x=-w*.29;gate_half=1.15*.5+.09;garage_x=w*.29;garage_half=w*.20
        for a,b in [(-w*.5,gate_x-gate_half),(gate_x+gate_half,garage_x-garage_half),(garage_x+garage_half,w*.5)]:
            if b-a>.01:box('Muro de esquina cerrado',((a+b)*.5,boundary,1.25),(b-a,.30,2.50),materials['costa'][10])
        door(-w*.29,boundary-.08,.14,honey_wood,w=1.15,h=2.35,kind=1)
        garage(w*.29,boundary-.07,.14,w*.40,2.35)
        for sign in [-1,1]:box('Retorno lateral de esquina',(sign*(w*.5-.10),-.325,1.25),(.20,d+.65,2.50),materials['costa'][10])
        box('Cierre sobre portones',(0,boundary,2.53),(w,.30,.12),materials['costa'][10])
    if v!=0:box('Losa superior',(0,.15,6.54 if v!=3 else 3.25),(w+.10,d+.10,.18),whitewall)
    for sign in [-1,1]:
        for y in [-d*.14,d*.27]:side_opening(sign,y,1.6,1.20,1.35,frame)
    rear_windows(w,d,1.65,frame,3)
    rear_windows(w,d,4.60,frame,3)
