"""Replace reconstructed tyre surfaces with complete, independent mechanical wheels."""
import bpy,bmesh,math,json,shutil
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parent.parent;OUT=ROOT/'project/assets/traffic';CACHE=ROOT/'tools/.worldgen/traffic_originals';CACHE.mkdir(parents=True,exist_ok=True)
def mat(name,color,metal=0,rough=.65):
    m=bpy.data.materials.new(name);m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal;return m
for key,width,length,height,radius,front,rear in [('tico',1.45,3.35,1.55,.265,-.99,1.02),('sedan',1.70,4.50,1.48,.29,-1.36,1.35),('coaster',2.05,6.8,2.65,.38,-1.95,2.04),('urban_bus',2.48,9,3.1,.46,-2.62,2.76)]:
    source=CACHE/(key+'.glb')
    if not source.exists():shutil.copyfile(OUT/(key+'.glb'),source)
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(source))
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    body=max((o for o in bpy.context.scene.objects if o.type=='MESH'),key=lambda o:len(o.data.polygons))
    # Locate actual tyre contact patches in the reconstruction, rather than assuming an axle offset.
    feet=[v.co for v in body.data.vertices if v.co.z<.075 and abs(v.co.x)>width*.25]
    for is_front in [True,False]:
        ys=sorted(v.y for v in feet if (v.y<-length*.12 if is_front else v.y>length*.12))
        if ys:
            if is_front:front=ys[len(ys)//2]
            else:rear=ys[len(ys)//2]
    # Delete all original tyre/rim faces, including their projected wheel photographs.
    bm=bmesh.new();bm.from_mesh(body.data)
    remove=[]
    for face in bm.faces:
        c=face.calc_center_median()
        if abs(c.x)>width*.20 and any((c.y-y)**2+(c.z-radius-.025)**2<(radius*1.55)**2 for y in [front,rear]):remove.append(face)
    bmesh.ops.delete(bm,geom=remove,context='FACES');bm.to_mesh(body.data);bm.free()
    tire=mat('Caucho',(.022,.024,.026),0,.93);steel=mat('Aleacion',(.43,.46,.49),.8,.28);black=mat('Interior de llanta',(.035,.039,.041),.4,.55)
    wheel_width=.18 if key=='tico' else .21 if key=='sedan' else .25
    centres=[]
    for axle,y in [('F',front),('R',rear)]:
        for side,x in [('L',-width*.43),('R',width*.43)]:
            name='Wheel'+axle+side
            pivot=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(pivot);pivot.location=(x,y,radius);pivot['wheel_radius']=radius;pivot['front']=axle=='F'
            spin=bpy.data.objects.new(name+'Spin',None);bpy.context.collection.objects.link(spin);spin.parent=pivot
            made=[]
            bpy.ops.mesh.primitive_torus_add(major_segments=36,minor_segments=12,major_radius=radius*.79,minor_radius=radius*.21)
            tyre=bpy.context.object;tyre.name=name+'Tire';tyre.rotation_euler.y=math.pi*.5;tyre.scale.z=wheel_width/(radius*.42);tyre.data.materials.append(tire);made.append(tyre)
            bpy.ops.mesh.primitive_cylinder_add(vertices=32,radius=radius*.62,depth=wheel_width*.85,rotation=(0,math.pi*.5,0));rim=bpy.context.object;rim.name=name+'Rim';rim.data.materials.append(black);made.append(rim)
            for j in range(8 if key in ['coaster','urban_bus'] else 6):
                angle=j*math.tau/(8 if key in ['coaster','urban_bus'] else 6)
                bpy.ops.mesh.primitive_cube_add(size=1,location=(0,math.sin(angle)*radius*.32,math.cos(angle)*radius*.32));spoke=bpy.context.object;spoke.dimensions=(wheel_width*.90,.042,radius*.65);spoke.rotation_euler.x=-angle;spoke.data.materials.append(steel);made.append(spoke)
            bpy.ops.mesh.primitive_cylinder_add(vertices=20,radius=radius*.18,depth=wheel_width*.94,rotation=(0,math.pi*.5,0));hub=bpy.context.object;hub.data.materials.append(steel);made.append(hub)
            for o in made:
                o.parent=spin
                for face in o.data.polygons:face.use_smooth=True
            # A dark inner arch hides the cut edge without retaining a second photographic wheel.
            bpy.ops.mesh.primitive_cylinder_add(vertices=32,radius=radius*1.35,depth=.035,location=(x*.89,y,radius),rotation=(0,math.pi*.5,0))
            well=bpy.context.object;well.name=name+'Well';well.data.materials.append(black)
            centres.append(dict(node=name,position=[x,radius,-y],radius=radius,front=axle=='F'))
    # Keep the restored silhouette smooth without smearing the UV charts.
    bpy.context.view_layer.objects.active=body
    smooth=body.modifiers.new('Regularizar carroceria','SMOOTH');smooth.factor=.35;smooth.iterations=3;bpy.ops.object.modifier_apply(modifier=smooth.name)
    bus=key in ['coaster','urban_bus']
    for vertex in body.data.vertices:
        p=vertex.co
        if height*.50<p.z<height*.89 and abs(p.x)>width*.31:
            ratio=max(0,min(1,(p.z/height-.50)/.39))
            p.x=math.copysign(width*(.49-ratio*(.025 if bus else .075)),p.x)
        if height*.50<p.z<height*.86 and abs(p.x)<width*.42:
            if bus and p.y<-length*.33:p.y=-length*.485+(p.z/height-.50)*length*.035
            elif not bus and -length*.33<p.y<-length*.04:p.y=-length*.23+(p.z/height-.50)*length*.41
    body.data.update()
    # Physical glazing and straight metal frames replace the most visibly distorted photo projections.
    tree=BVHTree.FromObject(body,bpy.context.evaluated_depsgraph_get())
    glass=mat('Vidrio fisico',(.055,.10,.13),.35,.18);rubber=mat('Marcos de ventana',(.028,.031,.034),.25,.55)
    body.data.materials.append(glass);glass_index=len(body.data.materials)-1
    for face in body.data.polygons:
        p=face.center
        if height*.51<p.z<height*.87 and (abs(p.x)>width*.30 or p.y<-length*(.32 if bus else .07)):
            face.material_index=glass_index
    def surface(x,y,z,side=0):
        origin=Vector((side*10,y,z)) if side else Vector((x,-20,z));direction=Vector((-side,0,0)) if side else Vector((0,1,0))
        hit,normal,_,_=tree.ray_cast(origin,direction,40)
        if hit is None:return Vector((side*width*.45,y,z)) if side else Vector((x,-length*.47,z))
        return hit+normal*.012
    def panel(name,points,material):
        mesh=bpy.data.meshes.new(name);mesh.from_pydata(points,[],[(0,1,2),(0,2,3)]);mesh.update();o=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(o);o.data.materials.append(material);return o
    def edge(a,b):
        delta=Vector(b)-Vector(a)
        bpy.ops.mesh.primitive_cylinder_add(vertices=8,radius=.014 if key in ['tico','sedan'] else .022,depth=delta.length,location=(Vector(a)+Vector(b))*.5)
        o=bpy.context.object;o.name='Carpinteria recta';o.rotation_euler=delta.to_track_quat('Z','Y').to_euler();o.data.materials.append(rubber)
    for side in [-1,1]:
        count=3 if key in ['tico','sedan'] else 5 if key=='coaster' else 7
        start=-length*.13 if key in ['tico','sedan'] else -length*.29
        end=length*.35 if key in ['tico','sedan'] else length*.41
        for j in range(count):
            a=start+(end-start)*j/count+.025;b=start+(end-start)*(j+1)/count-.025
            bottom=height*(.54 if key in ['tico','sedan'] else .55);top=height*(.84 if key in ['tico','sedan'] else .85)
            points=[surface(0,a,bottom,side),surface(0,b,bottom,side),surface(0,b,top,side),surface(0,a,top,side)]
            panel('Cristal lateral',points,glass)
            for k in range(4):edge(points[k],points[(k+1)%4])
    points=[surface(-width*.34,0,height*.53),surface(width*.34,0,height*.53),surface(width*.32,0,height*.84),surface(-width*.32,0,height*.84)]
    panel('Parabrisas',points,glass)
    for j in range(4):edge(points[j],points[(j+1)%4])
    for side in [-1,1]:
        a=surface(side*width*.22,0,height*.55);b=surface(side*width*.13,0,height*.73)
        edge(a,b)
    if key in ['coaster','urban_bus']:
        p=surface(0,0,height*.91)
        marker=bpy.data.objects.new('RouteAnchor',None);bpy.context.collection.objects.link(marker);marker.location=p
        plate=[surface(-width*.38,0,height*.865),surface(width*.38,0,height*.865),surface(width*.38,0,height*.965),surface(-width*.38,0,height*.965)]
        panel('Cartel de ruta',plate,mat('Fondo cartel',(.75,.73,.65),0,.9))
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=str(OUT/(key+'.glb')),export_format='GLB',use_selection=True,export_extras=True)
    (OUT/(key+'_vehicle.json')).write_text(json.dumps(dict(width=width,length=length,height=height,wheels=centres),indent=2))
    print('RIGGED',key,len(remove),'photographic wheel faces removed',flush=True)
