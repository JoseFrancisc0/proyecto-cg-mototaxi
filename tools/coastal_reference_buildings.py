"""Coastal architectural silhouettes: Quinta houses and distinct oceanfront towers."""
def outline(w,d,r):
    points=[]
    for cx,cy,start in [(w*.5-r,d*.5-r,0),(-w*.5+r,d*.5-r,90),(-w*.5+r,-d*.5+r,180),(w*.5-r,-d*.5+r,270)]:
        for k in range(7):
            a=math.radians(start+k*90/6);points.append((cx+math.cos(a)*r,cy+math.sin(a)*r))
    return points

def solid_plan(name,points,z,height,mat):
    n=len(points);verts=[(x,y,z+dz) for dz in [0,height] for x,y in points]
    faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(j,(j+1)%n,(j+1)%n+n,j+n) for j in range(n)]
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update();obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj);obj.data.materials.append(mat)
    return obj

def rail_segments(name,segments,mat):
    vertices=[];faces=[]
    for a,b,r in segments:
        a=Vector(a);b=Vector(b);axis=b-a
        if axis.length<.001:continue
        basis=axis.to_track_quat('Z','Y').to_matrix();offset=len(vertices);sides=8
        for p in [a,b]:
            for k in range(sides):vertices.append(tuple(p+basis@Vector((math.cos(k*math.tau/sides)*r,math.sin(k*math.tau/sides)*r,0))))
        faces.extend([tuple(offset+k for k in reversed(range(sides))),tuple(offset+sides+k for k in range(sides))])
        for k in range(sides):faces.append((offset+k,offset+(k+1)%sides,offset+(k+1)%sides+sides,offset+k+sides))
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(vertices,[],faces);mesh.update();obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj);obj.data.materials.append(mat)

def perimeter_rail(points,z,mat,glassmat=None):
    segments=[]
    for j in range(len(points)):
        a=points[j];b=points[(j+1)%len(points)]
        if (Vector(a)-Vector(b)).length<.015:continue
        segments.append(((a[0],a[1],z+1.05),(b[0],b[1],z+1.05),.022))
        segments.append(((a[0],a[1],z+.05),(a[0],a[1],z+1.05),.020))
        if glassmat:polygon('Cristal de baranda',[(a[0],a[1],z+.12),(b[0],b[1],z+.12),(b[0],b[1],z+.98),(a[0],a[1],z+.98)],glassmat)
        spacing=1.20 if glassmat else .12
        count=max(1,math.ceil((Vector(a)-Vector(b)).length/spacing))
        for k in range(1,count):
            p=Vector(a).lerp(Vector(b),k/count)
            segments.append(((p.x,p.y,z+.08),(p.x,p.y,z+1.04),.020 if glassmat else .012))
    rail_segments('Baranda perimetral con cierres',segments,mat)

def modern_reference_tower(v,w,d):
    global wall
    whitewall=material('Hormigon blanco moderno',color=(.88,.88,.82))
    darkframe=material('Aluminio anodizado',color=(.085,.105,.11),metal=.65)
    green=material('Cristal verde del malecon',color=(.025,.115,.105),metal=.48)
    blueglass=material('Vidrio de apartamentos',color=(.12,.23,.28),metal=.42)
    warm=material('Enchape terracota moderno',color=(.34,.19,.10))
    stone=materials['costa'][18]
    wall=whitewall
    storeys=[8,11,15,19][v];level=3.05;base=.18
    box('Podio de ingreso',(0,0,1.65),(w,d,3.3),stone)
    box('Acceso de doble altura',(0,-d*.5-.055,1.55),(w*.38,.09,2.75),blueglass)
    door(0,-d*.5-.15,.18,darkframe,w=1.55,h=2.65,kind=4,glass_override=blueglass)
    for x in [-w*.22,0,w*.22]:box('Montante de lobby',(x,-d*.5-.14,1.55),(.07,.12,2.9),darkframe)
    box('Marquesina',(0,-d*.5-.7,3.15),(w*.56,1.7,.16),whitewall)
    for f in range(1,storeys):
        z=base+f*level
        if v==0:
            # Rounded ivory apartment slabs, glazed facade set back from rail.
            inner=outline(w-.95,d-.85,1.1);outer=outline(w+.18,d+.22,1.55)
            solid_plan('Volumen de apartamentos',inner,z,level-.22,blueglass)
            solid_plan('Losa curva continua',outer,z,.20,whitewall)
            perimeter_rail(outer,z+.20,darkframe,blueglass if f%3 else None)
        elif v==1:
            # Broad brown/ivory terraces, alternating deep loggias.
            inner=outline(w-1.4,d-.5,.45);outer=outline(w,d+.5,1.1)
            solid_plan('Torre de terrazas',inner,z,level-.18,blueglass)
            solid_plan('Banda de terraza',outer,z,.24,whitewall)
            for x in [-w*.47,w*.47]:box('Pantalla de enchape',(x,0,z+level*.5),(.30,d*.92,level),warm)
            if f%2:box('Parasol intercalado',(-w*.20,-d*.5-.28,z+1.6),(w*.24,.15,2.6),warm)
            perimeter_rail(outer,z+.24,darkframe)
        elif v==2:
            # A slender white tower with glazed corner bays and no huge balcony.
            solid_plan('Cuerpo esbelto',outline(w*.88,d*.88,.5),z,level,blueglass)
            solid_plan('Losa fina',outline(w,d,.65),z,.16,whitewall)
            for sign in [-1,1]:
                box('Aleta blanca',(sign*w*.40,0,z+level*.5),(.32,d,level),whitewall)
                box('Costilla frontal',(sign*w*.20,-d*.48,z+level*.5),(.18,.28,level),whitewall)
        else:
            # Dark green offices: stepped silhouette, white structural grid.
            inset=0 if f<8 else 1.2 if f<14 else 2.35
            fw=w-inset;fd=d-inset
            solid_plan('Cristal de oficinas',outline(fw,fd,.48),z,level,green)
            solid_plan('Franja de oficinas',outline(fw+.12,fd+.12,.50),z,.12 if f%2 else .23,whitewall)
            for x in [-fw*.48,0,fw*.48]:box('Montante frontal de oficinas',(x,-fd*.5-.015,z+level*.5),(.075,.08,level),whitewall,0)
            for y in [-fd*.48,0,fd*.48]:
                for sign in [-1,1]:box('Montante lateral',(sign*fw*.5,y,z+level*.5),(.08,.075,level),whitewall,0)
        if v<3:
            # Fine mullions, occasionally closed blinds, visible on every side.
            for j in range(5):
                x=-w*.36+j*w*.18
                for sign in [-1,1]:box('Carpinteria de fachada',(x,sign*(d*.5-.46),z+level*.50),(.045,.075,level-.28),darkframe,0)
                if (j+f+v)%7==0:box('Persiana interior',(x,-d*.5+.40,z+1.45),(w*.14,.035,2.10),joinery[2],0)
    top=base+storeys*level
    solid_plan('Cubierta de torre',outline(w if v<3 else w-2.2,d if v<3 else d-2.2,.6),top,.22,whitewall)
    box('Cuarto de maquinas',(0,d*.16,top+.9),(w*.36,d*.40,1.8),whitewall)
    for x in [-w*.31,w*.31]:box('Macetero de acceso',(x,-d*.5-.55,.34),(w*.17,.8,.68),stone)

def quinta_reference(v,w,d):
    global wall
    colors=[rgb(c) for c in ['d7d5cc','314c77','66517c','a47d8a']]
    wall=material('Estuco de quinta '+str(v),color=colors[v]);trim=material('Moldura marfil de quinta',color=(.93,.91,.83))
    bind_surface_normal(wall,materials['costa'][9],.22)
    base=.16;level=3.15;top=base+2*level
    box('Cuerpo alto de casona',(w*.15,0,(base+top)*.5),(w*.70,d,top-base),wall)
    # Asymmetric low wing makes the detached villa more than a square prism.
    wing_width=w*.30;wing_depth=d*.70
    box('Ala baja',(-w*.35,-d*.15,1.65),(wing_width,wing_depth,3.0),wall)
    roof_objects=set(bpy.context.scene.objects);gable(w*.70,d-1.5,top,.8,materials['sierra'][10+v%3])
    for obj in set(bpy.context.scene.objects)-roof_objects:obj.location+=Vector((w*.15,.55,0))
    roof_objects=set(bpy.context.scene.objects);gable(wing_width,wing_depth,3.18,.6,materials['sierra'][10+v%3])
    for obj in set(bpy.context.scene.objects)-roof_objects:obj.location+=Vector((-w*.35,-d*.15,0))
    # Curvilinear republicano parapet, specific to the actual Quinta photograph.
    silhouette=[]
    for j in range(41):
        x=-w*.20+w*.70*j/40;t=j/40
        height=top+.12+.85*math.exp(-((t-.5)/.19)**2)+.16*math.cos(t*math.tau*3)
        silhouette.append((x,-d*.5-.06,height))
    polygon('Fronton ondulado',[(-w*.20,-d*.5-.06,top-.3),(w*.50,-d*.5-.06,top-.3)]+list(reversed(silhouette)),wall)
    for j in range(1,len(silhouette)):
        pole('Cornisa ondulada',silhouette[j-1],silhouette[j],.075,trim)
        a=Vector(silhouette[j-1])+Vector((0,-.015,-.18));b=Vector(silhouette[j])+Vector((0,-.015,-.18))
        pole('Segunda moldura',a,b,.045,trim)
    for x in [-w*.18,w*.48]:
        box('Pilastra de quinta',(x,-d*.5-.12,top*.5),(.18,.24,top),trim)
        pole('Remate de pilastra',(x,-d*.5-.12,top-.15),(x,-d*.5-.12,top+.30),.08,trim)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=12,ring_count=6,radius=.13,location=(x,-d*.5-.12,top+.34));bpy.context.object.data.materials.append(trim)
    window(w*.13,-d*.5-.10,base+level+1.42,w*.44,1.75,False,trim,4)
    for x in [-w*.18,w*.18]:box('Antepecho ornamental',(x,-d*.5-.18,base+level+.42),(w*.16,.09,.19),trim)
    door(-w*.27,-d*.5-.10,base,joinery[2],w=1.10,h=2.55,kind=2)
    window(w*.21,-d*.5-.10,base+1.25,w*.33,1.85,False,trim,3)
    # Diamond ironwork of the white arched opening.
    for j in range(5):
        x=w*.21-w*.15+j*w*.075
        pole('Reja diagonal',(x,-d*.5-.31,base+.5),(min(x+.75,w*.37),-d*.5-.31,base+1.70),.013,trim)
        pole('Reja cruzada',(x,-d*.5-.31,base+1.7),(min(x+.75,w*.37),-d*.5-.31,base+.5),.013,trim)
    # Front garden fence: brick piers, a continuous bottom rail and balusters.
    front=-d*.5-2.2
    for x in [-w*.49,w*.49]:
        box('Pilar de ladrillo',(x,front,.65),(.40,.40,1.3),materials['costa'][1])
        box('Tapa de pilar',(x,front,1.32),(.48,.48,.09),trim)
    for z in [.18,1.07]:box('Travesano de cerco',(0,front,z),(w,.10,.08),trim)
    for j in range(int(w/.14)):
        x=-w*.45+j*.14
        if abs(x+w*.26)<.55:continue
        pole('Balaustre de cerco',(x,front,.22),(x,front,1.05),.025,trim)
    for sign in [-1,1]:
        for z in [.18,1.07]:pole('Retorno de cerco',(sign*w*.49,front,z),(sign*w*.49,-d*.5,z),.035,trim)
        for j in range(17):
            yy=front+j*2.2/16
            pole('Balaustre lateral',(sign*w*.49,yy,.22),(sign*w*.49,yy,1.05),.025,trim)
    for x in [-w*.26-.53,-w*.26+.53]:pole('Marco de puerta de jardin',(x,front,.18),(x,front,1.07),.035,trim)
    for j in range(8):pole('Reja de puerta de jardin',(-w*.26-.46+j*.13,front,.23),(-w*.26-.46+j*.13,front,1.04),.018,trim)
    # Rear windows follow the actual tall wing, avoiding floating openings over
    # the low side wing. They are part of the exported, usable house model.
    from mathutils import Matrix
    for f in range(2):
        objects=set(bpy.context.scene.objects)
        window(-w*.15,0,base+f*level+1.55,w*.35,1.35,False,trim,4)
        bpy.context.view_layer.update()
        xf=Matrix.Translation(Vector((0,d*.5+.04,0)))@Matrix.Rotation(math.pi,4,'Z')
        for obj in set(bpy.context.scene.objects)-objects:obj.matrix_world=xf@obj.matrix_world
