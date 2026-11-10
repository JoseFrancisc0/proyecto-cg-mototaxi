"""Reference-proportioned traffic: clean solid panels, actual glazing and wheel arches."""
import bpy,math,json
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parent.parent;OUT=ROOT/'project/assets/traffic'
def material(name,color,metal=0,rough=.5,alpha=1):
    m=bpy.data.materials.new(name);m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,alpha);p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough;p.inputs['Alpha'].default_value=alpha
    if alpha<1:m.surface_render_method='DITHERED'
    return m
def box(name,p,size,mat,bevel=.025):
    bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=bpy.context.object;o.name=name;o.dimensions=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(mat)
    if bevel:
        mod=o.modifiers.new('Cantos de carroceria','BEVEL');mod.width=bevel;mod.segments=3;bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=mod.name)
        for face in o.data.polygons:face.use_smooth=True
        mod=o.modifiers.new('Normales de chapa','WEIGHTED_NORMAL');bpy.ops.object.modifier_apply(modifier=mod.name)
    return o
def panel(name,points,mat):
    # Explicit outside-facing winding. Left/right panels cannot share one
    # winding: it made entire sides disappear with Godot back-face culling.
    from mathutils import Vector
    normal=(Vector(points[1])-Vector(points[0])).cross(Vector(points[2])-Vector(points[0]))
    center=sum((Vector(p) for p in points),Vector())/len(points)
    outward=Vector((center.x,center.y,0))
    order=list(range(len(points)))
    if normal.dot(outward)<0:order.reverse()
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(points,[],[order]);mesh.update();o=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(o);o.data.materials.append(mat);return o
def bar(name,a,b,r,mat):
    direction=Vector(b)-Vector(a);bpy.ops.mesh.primitive_cylinder_add(vertices=12,radius=r,depth=direction.length,location=(Vector(a)+Vector(b))*.5);o=bpy.context.object;o.name=name;o.rotation_euler=direction.to_track_quat('Z','Y').to_euler();o.data.materials.append(mat);return o
def framed(points,mat):
    panel('Cristal real',points,mat)
    for j in range(len(points)):bar('Marco del cristal',points[j],points[(j+1)%len(points)],.018,black)
def text(body,p,size,mat):
    bpy.ops.object.text_add(location=p,rotation=(math.pi/2,0,0));o=bpy.context.object;o.name='Rotulo '+body;o.data.body=body;o.data.align_x='CENTER';o.data.size=size;o.data.extrude=.001;o.data.materials.append(mat);bpy.ops.object.convert(target='MESH');return o
def wheels(w,length,r,front,rear):
    data=[]
    for axle,y in [('F',front),('R',rear)]:
        for side,sign in [('L',-1),('R',1)]:
            x=sign*w*.475;tag='Wheel'+axle+side
            pivot=bpy.data.objects.new(tag,None);bpy.context.collection.objects.link(pivot);pivot.location=(x,y,r);pivot['wheel_radius']=r;pivot['front']=axle=='F'
            spin=bpy.data.objects.new(tag+'Spin',None);bpy.context.collection.objects.link(spin);spin.parent=pivot
            start=set(bpy.context.scene.objects)
            bpy.ops.mesh.primitive_torus_add(major_radius=r*.72,minor_radius=r*.28,major_segments=32,minor_segments=12,location=(x,y,r),rotation=(0,math.pi/2,0));bpy.context.object.data.materials.append(rubber)
            for sign2 in [-1,1]:
                bpy.ops.mesh.primitive_cylinder_add(vertices=32,radius=r*.62,depth=.025,location=(x+sign2*r*.21,y,r),rotation=(0,math.pi/2,0));bpy.context.object.data.materials.append(alloy)
                for k in range(8):
                    a=k*math.tau/8
                    bpy.ops.mesh.primitive_cylinder_add(vertices=10,radius=r*.065,depth=.028,location=(x+sign2*r*.235,y+math.cos(a)*r*.41,r+math.sin(a)*r*.41),rotation=(0,math.pi/2,0));bpy.context.object.data.materials.append(black)
                    bpy.ops.mesh.primitive_cylinder_add(vertices=8,radius=r*.024,depth=.032,location=(x+sign2*r*.24,y+math.cos(a)*r*.19,r+math.sin(a)*r*.19),rotation=(0,math.pi/2,0));bpy.context.object.data.materials.append(alloy)
            groups={}
            for o in set(bpy.context.scene.objects)-start:groups.setdefault(o.data.materials[0].name,[]).append(o)
            for objects in groups.values():
                bpy.ops.object.select_all(action='DESELECT')
                for o in objects:o.select_set(True)
                bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join();o=bpy.context.object;o.parent=spin;o.location-=pivot.location
            data.append({'node':tag,'position':[x,r,-y],'radius':r,'front':axle=='F'})
    return data
for key,w,length,height,r,front,rear in [('tico',1.45,3.35,1.55,.265,-1.02,1.04),('sedan',1.70,4.50,1.48,.29,-1.37,1.32),('coaster',2.05,6.8,2.65,.38,-1.95,2.04),('urban_bus',2.48,9,3.1,.46,-2.62,2.76)]:
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    bus=key in ['coaster','urban_bus'];tico=key=='tico'
    paint=material('PinturaCarroceria',(.73,.10,.065) if bus else (.88,.65,.035) if tico else (.035,.045,.06),.22,.29)
    ivory=material('PinturaFranja',(.83,.83,.73),.1,.42);black=material('Juntas y gomas',(.018,.022,.026),.05,.72);rubber=material('Neumatico',(.028,.030,.032),0,.93);alloy=material('Acero llanta',(.48,.50,.51),.7,.3)
    glass=material('Cristal azulado',(.16,.25,.29),.06,.22,.86);glass.use_backface_culling=False
    lamp=material('Optica faro',(.85,.85,.69),.18,.18);tail=material('Piloto rojo',(.66,.025,.015),.1,.23);amber=material('Intermitente',(.85,.36,.025),.1,.25);seat=material('Tapizado',(.045,.055,.065),0,.98)
    bottom=.27 if not bus else .48;belt=.94 if not bus else height*.46
    box('Bastidor',(0,0,bottom+.09),(w*.87,length*.91,.18),black)
    # Side skin follows each wheel arch. It contains no photographed tyre pixels.
    for sign in [-1,1]:
        steps=64;positions=[]
        for j in range(steps+1):
            y=-length*.49+j*length*.98/steps
            b=bottom
            for axle in [front,rear]:
                dy=abs(y-axle)
                if dy<r*1.12:b=max(b,r+math.sqrt(max(0,(r*1.12)**2-dy**2)))
            positions.append((y,min(b,belt-.035)))
        for j in range(steps):
            a,az=positions[j];b,bz=positions[j+1]
            panel('Chapa lateral',[(sign*w*.5,a,az),(sign*w*.5,b,bz),(sign*w*.5,b,belt),(sign*w*.5,a,belt)],paint)
        for axle in [front,rear]:
            for j in range(18):
                a=math.pi*j/18;b=math.pi*(j+1)/18
                bar('Borde de guardafango',(sign*(w*.5+.012),axle+math.cos(a)*r*1.13,r+math.sin(a)*r*1.13),(sign*(w*.5+.012),axle+math.cos(b)*r*1.13,r+math.sin(b)*r*1.13),.018,paint)
        box('Moldura lateral',(sign*(w*.5+.017),0,belt*.82),(.045,length*.92,.055),black)
    for y,back in [(-length*.49,False),(length*.49,True)]:
        box('Frente y maletera',(0,y,(bottom+belt)*.5),(w*.98,.16,belt-bottom),paint,.055)
        box('Parachoques',(0,y+(.06 if back else -.06),bottom+.10),(w*1.01,.19,.18),black,.045)
        box('Placa',(0,y+(.16 if back else -.16),bottom+.19),(.38,.025,.13),ivory,.006)
        for s in [-1,1]:
            box('Faro trasero' if back else 'Faro delantero',(s*w*.34,y+(.10 if back else -.10),belt-.20),(w*.24,.06,.15 if not bus else .22),tail if back else lamp,.025)
            box('Senal de giro',(s*w*.44,y+(.105 if back else -.105),belt-.20),(.08,.065,.14),amber,.01)
    if bus:
        box('Piso del salon',(0,0,belt-.06),(w*.92,length*.94,.14),black)
        roof=box('Techo curvo',(0,0,height-.12),(w,length*.98,.24),ivory,.11)
        for sign in [-1,1]:
            # Continuous opaque headers/sills and end returns close the shell.
            box('Dintel continuo',(sign*w*.48,0,height-.30),(.10,length*.96,.22),ivory)
            box('Cintura bajo cristales',(sign*w*.49,0,belt+.035),(.09,length*.96,.17),ivory)
            for end in [-1,1]:
                box('Pilar de esquina',(sign*w*.46,end*length*.465,(height+belt-.10)*.5),(.12,length*.07,height-belt-.10),ivory)
            framed([(sign*w*.49,-length*.43,belt+.10),(sign*w*.49,-length*.335,belt+.10),(sign*w*.47,-length*.335,height-.32),(sign*w*.47,-length*.43,height-.32)],glass)
            box('Cierre trasero lateral',(sign*w*.48,length*.42,(height+belt-.28)*.5),(.09,length*.08,height-belt-.28),ivory)
            box('Franja de ruta',(sign*(w*.5+.012),0,belt-.13),(.045,length*.96,.25),ivory)
            company=text('S.M.PORRES' if key=='urban_bus' else 'EMP. TRANSPORTE',(sign*(w*.5+.04),0,belt-.21),.19 if key=='urban_bus' else .14,black)
            company.rotation_euler=(math.pi/2,0,sign*math.pi/2)
            panel('Franja diagonal',[(sign*(w*.5+.025),-length*.30,.72),(sign*(w*.5+.025),length*.28,.51),(sign*(w*.5+.025),length*.35,.69),(sign*(w*.5+.025),-length*.25,.91)],ivory)
            count=5 if key=='urban_bus' else 4
            for j in range(count):
                y=-length*.34+(j+.5)*length*.73/count;span=length*.73/count-.11
                framed([(sign*w*.49,y-span*.5,belt+.10),(sign*w*.49,y+span*.5,belt+.10),(sign*w*.47,y+span*.5,height-.32),(sign*w*.47,y-span*.5,height-.32)],glass)
                box('Pilar',(sign*w*.485,y-span*.5-.05,(height+belt-.28)*.5),(.10,.08,height-belt-.28),ivory)
                for row in [-.22,.22]:box('Asiento',(sign*w*.29,y+row,belt+.23),(.44,.38,.16),seat,.06);box('Respaldo',(sign*w*.29,y+row+.15,belt+.55),(.44,.11,.55),seat,.055)
            bar('Pasamanos interior',(sign*w*.23,-length*.31,height-.43),(sign*w*.23,length*.38,height-.43),.025,amber)
            # Close the last vertical jamb as well as the first.
            box('Ultimo montante',(sign*w*.485,length*.39,(height+belt-.28)*.5),(.10,.10,height-belt-.28),ivory)
        for back,y in [(False,-length*.49-.02),(True,length*.49+.02)]:
            framed([(-w*.44,y,belt+.08),(w*.44,y,belt+.08),(w*.43,y+( .05 if back else .12),height-.43),(-w*.43,y+(.05 if back else .12),height-.43)],glass)
            box('Marco inferior',(0,y,(belt+.01)),(w,.10,.10),ivory)
            if not back:
                bar('Division parabrisas',(0,y-.025,belt+.1),(0,y+.09,height-.42),.018,black)
                for s in [-1,1]:bar('Limpiaparabrisas',(s*w*.20,y-.04,belt+.12),(s*w*.28,y-.04,belt+.64),.018,black)
                box('Tablero',(0,y+.32,belt+.08),(w*.87,.40,.15),black,.04)
                box('Cartel de ruta',(0,y-.02,height-.29),(w*.84,.05,.24),ivory)
                anchor=bpy.data.objects.new('RouteAnchor',None);bpy.context.collection.objects.link(anchor);anchor.location=(0,y-.055,height-.33)
        # The passenger door is built as glass panels with its own stiles.
        y=-length*.31
        for j in [-1,1]:
            box('Puerta de pasajeros',(w*.505,y+j*.22,1.20),(.04,.40,1.48),glass,.005)
            bar('Montante de puerta',(w*.53,y+j*.44,.48),(w*.53,y+j*.44,2.0),.025,black)
        for j in range(5):box('Rejilla motor',(0,-length*.5-.015,bottom+.32+j*.048),(w*.42,.018,.022),black,.005)
        chrome=material('Cromados de bus',(.60,.62,.61),.8,.24)
        for j in range(4):
            box('Lamina de parrilla',(0,-length*.5-.035,bottom+.26+j*.065),(w*.48,.035,.025),chrome,.008)
        for sign in [-1,1]:
            for dx in [-.07,.07]:
                box('Modulo optico',(sign*w*.34+dx,-length*.49-.14,belt-.20),(.12,.035,.13),lamp,.035)
            # The common red/ivory bus livery wraps continuously around the nose.
            box('Franja frontal',(sign*w*.27,-length*.49-.115,belt-.035),(w*.46,.025,.08),ivory,.012)
        text('38  A' if key=='urban_bus' else 'RUTA  12',(0,-length*.49-.16,belt-.30),.13,ivory)
    else:
        front_glass=-.80 if tico else -.87;roof_front=-.53 if tico else -.48;roof_back=.91 if tico else .59;back_glass=1.36 if tico else 1.04
        box('Capo',(0,(-length*.48+front_glass)*.5,belt-.025),(w*.96,front_glass+length*.48,.13),paint,.065)
        box('Techo',(0,(roof_front+roof_back)*.5,height-.07),(w*.81,roof_back-roof_front,.14),paint,.075)
        framed([(-w*.46,front_glass,belt+.05),(w*.46,front_glass,belt+.05),(w*.39,roof_front,height-.12),(-w*.39,roof_front,height-.12)],glass)
        framed([(-w*.39,roof_back,height-.12),(w*.39,roof_back,height-.12),(w*.45,back_glass,belt+.06),(-w*.45,back_glass,belt+.06)],glass)
        box('Maletera',(0,(back_glass+length*.48)*.5,belt-.02),(w*.94,length*.48-back_glass,.13),paint,.05)
        for sign in [-1,1]:
            pts=[(sign*w*.47,front_glass,belt+.06),(sign*w*.47,back_glass,belt+.06),(sign*w*.39,roof_back,height-.12),(sign*w*.39,roof_front,height-.12)]
            framed(pts,glass)
            bar('Pilar central',(sign*w*.47,.25,belt+.04),(sign*w*.39,.23,height-.10),.038,paint)
            for y in [-.35,.78]:box('Manija de puerta',(sign*(w*.5+.025),y,belt-.07),(.04,.16,.035),black,.012)
            box('Espejo lateral',(sign*w*.60,front_glass+.09,belt+.25),(.21,.15,.13),paint,.05)
            box('Asiento delantero',(sign*w*.24,-.1,.65),(.44,.48,.16),seat,.07);box('Respaldo delantero',(sign*w*.24,.10,.96),(.44,.13,.57),seat,.07)
        box('Tablero',(0,front_glass+.18,belt-.04),(w*.82,.28,.15),black,.03)
        box('Letrero de taxi',(0,0,height+.05),(.40,.25,.12),ivory,.035);text('TAXI',(0,-.132,height+.012),.10,black)
        for s in [-1,1]:bar('Limpiaparabrisas',(s*.10,front_glass-.035,belt+.10),(s*.42,front_glass+.04,belt+.22),.012,black)
    for sign in [-1,1]:
        if bus:
            bar('Brazo del espejo',(sign*w*.43,-length*.45,height-.40),(sign*w*.68,-length*.48,height-.48),.028,black)
            box('Retrovisor',(sign*w*.68,-length*.48,height-.65),(.17,.18,.40),black,.05)
    wheel_data=wheels(w,length,r,front,rear)
    # Join only static pieces by material. The four wheel pivots stay articulated.
    static=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.parent is None];groups={}
    for o in static:groups.setdefault(o.data.materials[0].name,[]).append(o)
    for objects in groups.values():
        bpy.ops.object.select_all(action='DESELECT')
        for o in objects:o.select_set(True)
        bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join()
    bpy.ops.object.select_all(action='SELECT');bpy.ops.export_scene.gltf(filepath=str(OUT/(key+'.glb')),export_format='GLB',use_selection=True,export_yup=True,export_extras=True)
    (OUT/(key+'_vehicle.json')).write_text(json.dumps(dict(width=w,length=length,height=height,wheels=wheel_data),indent=2))
    print('CLEAN_TRAFFIC',key,flush=True)
