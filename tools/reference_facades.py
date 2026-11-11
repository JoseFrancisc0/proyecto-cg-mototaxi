"""Individual facades studied from the comparison photographs, not random skins."""
_insets={}
def photo_inset(name,x,y,z,w,h,key,rect):
    """Photographic joinery behind actual modelled frames and ironwork.

    UV selection uses the unchanged source photograph, not a facade billboard.
    """
    folder=OUT/'reference_details';folder.mkdir(exist_ok=True)
    filename='0_popular.png' if key=='coast' else '2_tradicional.jpg'
    source=ROOT/'output/comparacion/referencias'/filename
    import shutil
    target=folder/filename
    if not target.exists():shutil.copyfile(source,target)
    if key not in _insets:
        mat=material('Carpinteria fotografica '+key)
        node=mat.node_tree.nodes.new('ShaderNodeTexImage');node.image=bpy.data.images.load(str(target),check_existing=True)
        mat.node_tree.links.new(node.outputs['Color'],mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
        _insets[key]=mat
    mesh=bpy.data.meshes.new(name);mesh.from_pydata([(x-w*.5,y,z-h*.5),(x+w*.5,y,z-h*.5),(x+w*.5,y,z+h*.5),(x-w*.5,y,z+h*.5)],[],[(0,1,2,3)]);mesh.update()
    layer=mesh.uv_layers.new();u0,v0,u1,v1=rect
    for index,uv in enumerate([(u0,1-v1),(u1,1-v1),(u1,1-v0),(u0,1-v0)]):layer.data[index].uv=uv
    obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj);obj.data.materials.append(_insets[key])
def coast_reference_shop(v,w,d):
    global wall
    colors=[0,1,2,8];wall=paint(colors[v],'costa');base=.14;level=2.75
    floors=[2,2,2,1][v]
    box('Volumen de calle costera',(0,0,base+level*floors*.5),(w,d,level*floors),wall)
    box('Zocalo pintado',(0,-d*.5-.02,.30),(w,.08,.34),paint(3,'costa'))
    carp=joinery[1] if v==0 else joinery[0] if v==1 else joinery[2]
    if v==0:
        # Yellow grocery facade: narrow pedestrian entrance, barred shopfront,
        # right-hand roller garage, paired timber windows above.
        door(-w*.39,-d*.5-.08,base,iron,w=1.05,h=2.35,kind=3)
        window(-w*.02,-d*.5-.05,base+1.25,w*.34,2.25,True,iron,4)
        box('Persiana de garaje',(w*.32,-d*.5-.13,base+1.2),(w*.25,.10,2.4),joinery[2])
        for i in range(21):box('Lama de persiana',(w*.32,-d*.5-.19,base+.1+i*.11),(w*.25,.03,.025),cement,0)
        for x in [-w*.25,w*.24]:window(x,-d*.5-.04,base+level+1.38,w*.30,1.45,True,carp,2)
        photo_inset('Vitrina de abarrotes',-w*.02,-d*.5-.19,base+1.25,w*.34,2.25,'coast',(.226,.60,.336,.88))
        photo_inset('Reja de entrada',-w*.39,-d*.5-.28,base+1.17,1.02,2.28,'coast',(.12,.58,.207,.88))
        for x in [-w*.25,w*.24]:photo_inset('Madera de ventana',x,-d*.5-.20,base+level+1.38,w*.30,1.45,'coast',(.224,.245,.318,.432))
        box('Piso superior blanco',(-w*.23,d*.08,base+level*2+1.20),(w*.54,d*.80,2.4),paint(8,'costa'))
        window(-w*.23,-d*.32-.09,base+level*2+1.25,w*.41,1.35,False,carp,2)
        box('Alero superior',(-w*.23,d*.08,base+level*2+2.44),(w*.58,d*.84,.12),cement)
        # A restrained strand of neighbourhood pennants from the photograph.
        for j in range(19):
            x=-w*.48+j*w*.052
            polygon('Banderin',[(x,-d*.5-.20,base+2.57),(x+.24,-d*.5-.20,base+2.57),(x+.12,-d*.5-.20,base+2.36)],paint(8 if j%2 else 2,'costa'))
    else:
        door(w*.22,-d*.5-.08,base,joinery[v],w=1.25,h=2.35,kind=1 if v==1 else 0)
        window(-w*.23,-d*.5-.04,base+1.23,w*.32,1.72,True,iron,4)
        if floors>1:
            window(-w*.22,-d*.5-.04,base+level+1.35,w*.32,1.45,True,carp,2 if v==1 else 0)
            window(w*.24,-d*.5-.04,base+level+1.35,w*.25,1.45,True,carp,0)
    simple_roof(w,d,base+floors*level,cement)
    return base+floors*level+(2.45 if v==0 else .15)

def iquitos_reference(w,d):
    global wall
    wall=material('Azulejo marfil de Iquitos',color=(.77,.80,.72))
    red=material('Cedro rojo Iquitos',color=(.29,.035,.025))
    tileblue=material('Estampa azul gris',color=(.23,.39,.43))
    cream=material('Moldura cal Iquitos',color=(.91,.89,.79))
    base=.14;level=3.55;top=base+2*level
    box('Casona de dos plantas',(0,0,(base+top)*.5),(w,d,top-base),wall)
    # Small repeated oval tile pattern is metric, not a photograph stretched
    # across an entire storey. One mesh keeps this patterned wall inexpensive.
    verts=[];faces=[]
    for ix in range(int(w/.17)):
        for iz in range(int((top-base)/.21)):
            x=-w*.5+(ix+.5)*.17;z=base+(iz+.5)*.21
            for k in range(8):
                a=k*math.tau/8;b=(k+1)*math.tau/8
                i=len(verts)
                for r in [1,.73]:
                    for angle in [a,b]:verts.append((x+math.cos(angle)*.060*r,-d*.5-.012,z+math.sin(angle)*.088*r))
                faces.append((i,i+1,i+3,i+2))
    mesh=bpy.data.meshes.new('Azulejos de casona');mesh.from_pydata(verts,[],faces);mesh.update();o=bpy.data.objects.new('Azulejos de casona',mesh);bpy.context.collection.objects.link(o);o.data.materials.append(tileblue)
    for f in range(2):
        z=base+f*level
        for j in range(4):
            x=(j-1.5)*w*.235;ww=w*.14;h=2.75 if f==0 else 2.50
            door(x,-d*.5-.13,z,red,w=ww,h=h,kind=0)
            photo_inset('Cedro y cuarterones',x,-d*.5-.38,z+h*.5,ww*.93,h*.94,'iquitos',(.035,.593,.127,.865) if f==0 else (.29,.17,.379,.42))
            arch_outline(x,-d*.5-.25,z,ww+.20,3.14,cream,.085)
            if f==0:
                for k in range(5):box('Reja de sobreluz',(x-ww*.4+k*ww*.2,-d*.5-.27,z+2.68),(.018,.03,.35),iron,0)
            else:
                window(x,-d*.5-.18,z+1.58,ww*.90,1.55,False,red,2)
                photo_inset('Ventana de casona',x,-d*.5-.40,z+1.58,ww*.88,1.55,'iquitos',(.29,.17,.379,.42))
        for x in [-w*.49,-w*.25,0,w*.25,w*.49]:
            box('Pilastra clasica',(x,-d*.5-.13,z+level*.5),(.16,.25,level),cream)
            for zz in [.13,level-.15]:box('Capitel de pilastra',(x,-d*.5-.17,z+zz),(.28,.31,.16),cream)
    for zz in [.18,level+.1,top-.2,top+.12]:box('Cornisa clasica',(0,-d*.5-.19,zz),(w+.18,.40,.14),cream)
    balcony(w*.51,-d*.5-.58,base+level+.06,iron,0)
    simple_roof(w,d,top,cement)

def diamond_grilles(w,d,base,level,floors,v):
    # Use the actual openings, including the reserved door bay. Recomputing a
    # second window layout displaced grilles towards the door and outside frames.
    teal=joinery[3]
    bpy.context.view_layer.update()
    for anchor in [o for o in bpy.context.scene.objects if o.get('opening_kind')=='window']:
        if abs(anchor.location.y+d*.5)>.15:continue
        x,y,z=anchor.location;hw=anchor['width']*.5-.065;hh=anchor['height']*.5-.065
        depth=y-.205;segments=[]
        corners=[(x-hw,depth,z-hh),(x+hw,depth,z-hh),(x+hw,depth,z+hh),(x-hw,depth,z+hh)]
        for j in range(4):segments.append((corners[j],corners[(j+1)%4],.014))
        for slope in [-1.15,1.15]:
            count=math.ceil((hh+abs(slope)*hw)*2/.34)
            for j in range(count+1):
                c=-hh-abs(slope)*hw+j*.34
                bounds=sorted([(-hh-c)/slope,(hh-c)/slope]);a=max(-hw,bounds[0]);b=min(hw,bounds[1])
                if b-a<.025:continue
                segments.append(((x+a,depth,z+slope*a+c),(x+b,depth,z+slope*b+c),.008))
        rail_segments('Reja romboidal ajustada al marco',segments,teal)
