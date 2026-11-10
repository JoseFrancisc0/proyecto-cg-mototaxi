"""Regional modular buildings; Blender metres, facade faces -Y (+Z in Godot)."""
import bpy, math, random, json,sys
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parent.parent
OUT=ROOT/'project/assets/houses/peru';OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
random.seed(92)
atlas=bpy.data.images.load(str(OUT/'material_atlas.png'))
sys.path.insert(0,str(ROOT/'tools/.avatar_runtime'))
from PIL import Image
sheet=Image.open(OUT/'material_atlas.png').convert('RGB')
textures=OUT/'textures';textures.mkdir(exist_ok=True)
for index in range(8):
    x=index%4;y=index//4
    sheet.crop((x*sheet.width//4,y*sheet.height//2,(x+1)*sheet.width//4,(y+1)*sheet.height//2)).save(textures/('%d.png'%index))
def material(name,tile=None,color=(1,1,1),metal=0):
    m=bpy.data.materials.new(name);m.use_nodes=True
    n=m.node_tree.nodes;p=n.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=.82;p.inputs['Metallic'].default_value=metal
    if tile is not None:
        m['atlas_tile']=tile
        tex=n.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(textures/('%d.png'%tile)),check_existing=True);tex.interpolation='Linear'
        uv=n.new('ShaderNodeUVMap');mapping=n.new('ShaderNodeVectorMath');mapping.operation='MULTIPLY_ADD'
        mapping.inputs[1].default_value=(.245,.49,1);mapping.inputs[2].default_value=((tile%4)*.25+.0025,(1-tile//4)*.5+.005,0)
        m.node_tree.links.new(uv.outputs[0],tex.inputs[0]);m.node_tree.links.new(tex.outputs['Color'],p.inputs['Base Color'])
        bump=n.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.22;bump.inputs['Distance'].default_value=.045
        m.node_tree.links.new(tex.outputs['Color'],bump.inputs['Height']);m.node_tree.links.new(bump.outputs[0],p.inputs['Normal'])
    return m
brick=material('Ladrillo visto',0);cement=material('Concreto',1);plaster=material('Estuco',2);adobe=material('Adobe',3);wood=material('Madera',4);tile=material('Teja colonial',5);thatch=material('Palma tejida',6);blue=material('Madera azul',7)
iron=material('Fierro pintado',color=(.055,.065,.062),metal=.55);glass=material('Vidrio oscuro',color=(.10,.19,.22),metal=.35);white=material('Cal',color=(.83,.80,.70));tank=material('Tanque de agua',color=(.04,.05,.055));roofmetal=material('Calamina',color=(.38,.40,.37),metal=.65)
paints=[material('Pintura '+str(i),color=c) for i,c in enumerate([(.65,.32,.18),(.16,.50,.46),(.76,.60,.12),(.51,.28,.39),(.78,.74,.62)])]
def box(name,loc,size,mat,bevel=.015):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.name=name;o.dimensions=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    o.data.materials.append(mat)
    if 'atlas_tile' in mat:
        for face in o.data.polygons:
            axis=max(range(3),key=lambda k:abs(face.normal[k]));axes=[k for k in range(3) if k!=axis]
            if mat['atlas_tile'] in [5,6] and axis==2:axes=[1,0]
            for loop_index in face.loop_indices:
                co=o.data.vertices[o.data.loops[loop_index].vertex_index].co
                o.data.uv_layers.active.data[loop_index].uv=(co[axes[0]]*.5,co[axes[1]]*.5)
    if bevel:
        mod=o.modifiers.new('Cantos reales','BEVEL');mod.width=bevel;mod.segments=2;bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=mod.name)
    return o
def pole(name,a,b,r,mat):
    d=Vector(b)-Vector(a);bpy.ops.mesh.primitive_cylinder_add(vertices=10,radius=r,depth=d.length,location=(Vector(a)+Vector(b))*.5);o=bpy.context.object;o.name=name;o.rotation_euler=d.to_track_quat('Z','Y').to_euler();o.data.materials.append(mat)
    if 'atlas_tile' in mat:
        for uv in o.data.uv_layers.active.data:uv.uv=(uv.uv.x,uv.uv.y*max(1,d.length*.5))
    return o
def window(x,y,z,w=1.2,h=1.25,bars=True,frame=None):
    frame=frame or white
    box('Marco de ventana',(x,y,z),(w+.16,.16,h+.16),frame)
    box('Ventana empotrada',(x,y-.095,z),(w,.035,h),glass,0)
    for v in [-1,0,1]:box('Carpinteria',(x+v*w*.45,y-.13,z),(.035,.035,h),iron,0)
    box('Travesano',(x,y-.13,z),(w,.04,.04),frame,0)
    if bars:
        for t in range(6):box('Reja',(x-w*.45+t*w*.18,y-.20,z),(.022,.025,h),iron,0)
def door(x,y,z,mat=wood,w=1.05,h=2.15):
    box('Dintel',(x,y,z+h*.5),(w+.20,.20,h+.15),cement)
    box('Puerta',(x,y-.12,z+h*.5),(w,.08,h),mat)
    for j in range(3):box('Panel puerta',(x,y-.17,z+.4+j*.65),(w*.72,.025,.42),mat)
    pole('Manija',(x+w*.32,y-.22,z+1),(x+w*.32,y-.22,z+1.16),.025,iron)
def gable(w,d,base,rise,mat):
    for sign in [-1,1]:
        mesh=bpy.data.meshes.new('Testero cerrado');mesh.from_pydata([(-w*.5,sign*d*.5,base),(w*.5,sign*d*.5,base),(0,sign*d*.5,base+rise)],[],[(0,1,2) if sign<0 else (2,1,0)]);mesh.update()
        obj=bpy.data.objects.new('Testero cerrado',mesh);bpy.context.collection.objects.link(obj);obj.data.materials.append(wall)
        layer=mesh.uv_layers.new()
        for loop in mesh.loops:
            co=mesh.vertices[loop.vertex_index].co;layer.data[loop.index].uv=(co.x*.5,co.z*.5)
    for sign in [-1,1]:
        length=math.hypot(w*.5+.5,rise)
        o=box('Faldon de cubierta',(sign*w*.25,0,base+rise*.5),(length,d+1.1,.14),mat,.01);o.rotation_euler.y=sign*math.atan2(rise,w*.5+.5)
    pole('Cumbrera',(0,-d*.5-.6,base+rise+.10),(0,d*.5+.6,base+rise+.1),.09,mat)
def balcony(w,y,z,mat=wood):
    box('Balcón volado',(0,y,z),(w,1.2,.17),cement)
    for x in [-w*.5,w*.5]:pole('Poste balcon',(x,y-.55,z),(x,y-.55,z+1),.05,mat)
    for k in range(int(w/.18)+1):
        x=-w*.5+k*.18
        box('Balaustre tallado',(x,y-.55,z+.48),(.055,.055,.90),mat)
    box('Pasamanos',(0,y-.55,z+1),(w+.15,.10,.10),mat)
def export(key):
    # Join by material: a small number of draw calls when instanced across the map.
    objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
    groups={}
    for o in objects:groups.setdefault(o.data.materials[0].name,[]).append(o)
    for group in groups.values():
        bpy.ops.object.select_all(action='DESELECT')
        for o in group:o.select_set(True)
        bpy.context.view_layer.objects.active=group[0];bpy.ops.object.join()
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=str(OUT/(key+'.glb')),export_format='GLB',use_selection=True,export_yup=True,export_texcoords=True)
    height=max((o.matrix_world@Vector(c)).z for o in bpy.context.scene.objects if o.type=='MESH' for c in o.bound_box)
    print('HOUSE_READY',key,round(height,3),flush=True)
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    return height
catalog=[]
# Distinct regional typologies and lot widths. A district selects compatible buildings.
configs=[]
def add(region,prefix,styles,zones):
    for i,(style,floors,w,d) in enumerate(styles):configs.append((region,prefix+'_%02d'%i,style,floors,w,d,zones,i))
add(0,'costa_barrio',[('brick',1,5.5,7),('brick',2,6.2,7),('brick',3,7.0,7),('paint',2,5.8,7.2),('paint',3,7.2,7),('brick',4,6.4,7.5)],['popular'])
add(0,'costa_calle',[('paint',1,5.8,6.8),('paint',2,6.8,7),('paint',3,7.2,7),('paint',2,8.0,7.5)],['tradicional','residencial'])
add(0,'costa_moderna',[('modern',2,9,9),('modern',1,10,9),('tower',7,10,9),('tower',10,12,10)],['moderna'])
add(0,'costa_rural',[('brick',1,5.6,6.2),('paint',1,7.0,6.4)],['rural'])
add(1,'sierra_centro',[('colonial',2,6.0,7),('arches',2,8.0,7),('colonial',2,7.0,6.8),('colonial',3,8.4,7)],['tradicional'])
add(1,'sierra_popular',[('brick',2,5.8,6.8),('brick',3,6.4,7.2),('adobe',1,6.2,6.0),('paint',2,6.4,7)],['popular'])
add(1,'sierra_rural',[('adobe',1,5.5,5.5),('adobe',1,7.2,6),('adobe',2,6.4,6.6)],['rural'])
add(1,'sierra_residencial',[('colonial',2,8.8,8),('andes_modern',2,9.5,8.5),('andes_modern',2,11,9)],['residencial','moderna'])
add(2,'selva_urbana',[('amazon',1,5.8,7),('amazon',2,6.4,7),('iquitos',1,7.2,7.5),('iquitos',2,8.2,7),('amazon',2,7,7.5)],['popular','tradicional'])
add(2,'selva_residencial',[('amazon_villa',1,9,9),('amazon_villa',2,9.5,8),('amazon_villa',2,11,9),('iquitos',2,8.5,8)],['residencial','moderna'])
add(2,'selva_ribera',[('thatch',1,5.6,5.8),('wood',1,6.4,6.6),('thatch',1,7.4,6),('wood',2,6.6,7.2)],['ribereno','rural'])
palette=[(.65,.25,.15),(.12,.40,.34),(.74,.50,.10),(.50,.22,.35),(.70,.67,.53),(.24,.40,.56),(.58,.38,.21),(.58,.66,.51),(.78,.48,.35),(.72,.62,.46),(.36,.28,.20),(.77,.77,.70)]
paints=[material('Fachada regional '+str(i),color=c) for i,c in enumerate(palette)]
for region,key,style,floors,w,d,zones,variation in configs:
    random.seed(key)
    raised=.75 if style in ['thatch','wood'] else 0
    base=raised+.18;floor=2.5 if raised else 2.7
    wall=brick if style=='brick' else adobe if style=='adobe' else wood if raised else white if style in ['colonial','arches','tower','modern'] else paints[(variation*3+region*4)%len(paints)]
    if raised:
        for x in [-w*.43,0,w*.43]:
            for y in [-d*.43,0,d*.43]:pole('Pilote de madera',(x,y,0),(x,y,base),.13,wood)
        for j in range(7):box('Grada acceso',(1.8,-d*.5-.35-j*.27,base-j*.18), (1.3,.32,.16),wood)
    else:box('Sobrecimiento',(0,0,.14),(w+.15,d+.15,.28),cement)
    for f in range(floors):
        z=base+f*floor
        box('Muros',(0,0,z+floor*.5),(w,d,floor),wall)
        box('Viga entrepiso',(0,0,z+floor),(w+.10,d+.10,.16),cement if style=='brick' else wall)
        for x in [-w*.5,w*.5]:box('Columna',(x,0,z+floor*.5),(.22,d+.07,floor),cement if style=='brick' else wall)
        for x in [-w*.29,w*.29]:window(x,-d*.5-.03,z+1.55,1.35,1.23,style not in ['tower','thatch','wood','adobe'],blue if style in ['colonial','arches'] else wood if style in ['thatch','wood','adobe'] else None)
        for side in [-1,1]:
            for y in [-d*.25,d*.24]:
                o=box('Vidrio lateral',(side*(w*.5+.025),y,z+1.6),(.025,1.15,1.15),glass,0)
        if f==0:door(0,-d*.5-.13,z,iron if style=='brick' else blue if style in ['colonial','arches'] else wood)
        elif style in ['colonial','arches','tower','paint','iquitos','modern','andes_modern','amazon','amazon_villa']:balcony(w*.82,-d*.5-.50,z+.1,blue if style in ['colonial','arches'] else iron if style=='tower' else wood)
    top=base+floors*floor
    if style in ['adobe','colonial','arches','andes_modern']:gable(w,d,top,1.55,tile)
    elif raised:
        gable(w+.5,d+.6,top,1.6,thatch if style=='thatch' else roofmetal)
        if style=='thatch':
            # Layered palm bundles and a ragged eave have real depth rather than a thin roof card.
            angle=math.atan2(1.6,(w+1.5)*.5)
            for sign in [-1,1]:
                for row in range(8):
                    x=sign*(.18+row*(w+1.5)/16)
                    z=top+1.6-abs(x)*math.tan(angle)+.09
                    for j in range(38):
                        y=-(d+1.7)*.5+j*(d+1.7)/37
                        o=box('Haz de palma',(x+random.uniform(-.03,.03),y,z+random.uniform(-.02,.02)),(.65,.22,.07),thatch,0);o.rotation_euler.y=sign*angle
                for j in range(65):
                    y=-(d+1.7)*.5+j*(d+1.7)/64;x=sign*(w+1.5)*.5
                    pole('Fleco de palma',(x,y,top+.10),(x+sign*random.uniform(.05,.18),y,top-random.uniform(.10,.32)),.017,thatch)
        # Porch structure and shady awning; houses are supported through their entire footprint.
        for x in [-w*.44,w*.44]:pole('Pilar veranda',(x,-d*.5-.65,base),(x,-d*.5-.65,top),.09,wood)
        box('Veranda',(0,-d*.5-.5,base),(w,1.2,.16),wood)
        balcony(w,-d*.5-.5,base,wood)
    elif style in ['iquitos','amazon','amazon_villa']:
        gable(w,d,top,.65,roofmetal)
        o=box('Alero tropical',(0,-d*.5-.8,top-.3),(w+1,1.8,.09),roofmetal);o.rotation_euler.x=-.12
        for x in [-w*.44,w*.44]:pole('Pilar galeria',(x,-d*.5-1.35,0),(x,-d*.5-1.35,top-.4),.07,iron)
    else:
        box('Losa de azotea',(0,0,top+.10),(w+.3,d+.3,.20),cement)
        for side in [-1,1]:box('Parapeto',(side*w*.5,0,top+.45),(.16,d,.7),wall)
        if style=='brick':
            for x in [-w*.5,w*.5]:
                for y in [-d*.5,d*.5]:
                    for dx in [-.06,.06]:pole('Fierro de ampliacion',(x+dx,y,top+.2),(x+dx,y,top+1),.012,iron)
            bpy.ops.mesh.primitive_cylinder_add(vertices=24,radius=.57,depth=.95,location=(1.7,1.6,top+.7));bpy.context.object.data.materials.append(tank)
            box('Base del tanque',(1.7,1.6,top+.16),(1.3,1.3,.24),cement)
        elif style=='tower':
            box('Cuarto de maquinas',(0,1.5,top+.85),(3,3,1.5),white)
    if style in ['colonial','arches']:
        for x in [-w*.5,0,w*.5]:box('Pilar de piedra',(x,-d*.5-.25,1.2),(.25,.5,2.4),cement)
        for center in [-w*.25,w*.25]:
            for k in range(14):
                a=math.pi*k/13;b=math.pi*(k+1)/13
                pole('Arco de piedra',(center+math.cos(a)*w*.235,-d*.5-.30,1.65+math.sin(a)*.82),(center+math.cos(b)*w*.235,-d*.5-.30,1.65+math.sin(b)*.82),.11,cement)
    if style in ['modern','andes_modern','amazon_villa']:
        # Set-back upper volume, broad shaded glazing and a sheltered entrance.
        box('Volumen de acceso',(-w*.27,-d*.48,1.35),(w*.38,1.0,2.7),cement)
        box('Vidrio de sala',(w*.22,-d*.51,1.55),(w*.36,.07,1.6),glass)
        box('Marquesina',(0,-d*.5-.65,2.8),(w*.8,1.55,.18),white)
        for j in range(12):box('Liston de sombra',(-w*.38+j*w*.065,-d*.5-.70,2.95),(.08,1.6,.16),wood if region else iron)
    if style in ['amazon','amazon_villa','iquitos']:
        # Ventilated tropical front gallery, contrasting plinth and shutters.
        box('Franja de zocalo',(0,-d*.5-.03,.42),(w,.08,.7),paints[(variation+7)%len(paints)])
        for x in [-w*.40,w*.40]:
            for side in [-1,1]:
                shutter=box('Persiana tropical',(x+side*.74,-d*.5-.16,1.6),(.38,.09,1.25),blue if variation%2 else wood)
                shutter.rotation_euler.z=side*.06
        for j in range(int(w/.34)):
            box('Celosia ventilada',(-w*.5+.2+j*.34,-d*.5-.045,2.42),(.20,.06,.16),white)
    if style=='brick':
        # Partial render, corrugated shop shutter and improvised extensions.
        if variation%2:box('Revoque parcial',(0,-d*.5-.025,.65),(w*.92,.055,1.05),paints[(variation+4)%len(paints)])
        if variation%3==0:
            box('Porton enrollable',(-w*.28,-d*.5-.16,1.05),(1.9,.08,1.95),iron)
            for j in range(18):box('Lama de porton',(-w*.28,-d*.5-.21,.15+j*.10),(1.85,.025,.022),roofmetal,0)
        if region==1:gable(w,d,top+.16,.72,roofmetal)
    if style=='tower':
        box('Planta baja acristalada',(0,-d*.5-.04,1.55),(w*.90,.08,2.2),glass)
        for side in [-1,1]:box('Banda vertical',(side*w*.39,-d*.5-.08,top*.5),(.24,.13,top),cement)
    height=export(key);entry=dict(file='peru/'+key+'.glb',region=region,height=height,yaw=0.0,style=style,zones=zones,frontage=w)
    if raised:entry['supports']=[[x,0,-y] for x in [-w*.43,0,w*.43] for y in [-d*.43,0,d*.43]]
    catalog.append(entry)
(OUT/'catalog.json').write_text(json.dumps(catalog,indent=2))
script=ROOT/'project/scripts/terrain_houses.gd'
content=script.read_text(encoding='utf8');start=content.index('const MODELS := [');end=content.index('\n]',start)+2
entries='const MODELS := [\n'+''.join('\t'+json.dumps(item,ensure_ascii=False)+',\n' for item in catalog)+']'
script.write_text(content[:start]+entries+content[end:],encoding='utf8')
script=ROOT/'project/scripts/terrain_houses.gd'
content=script.read_text(encoding='utf8');start=content.index('const MODELS := [');end=content.index('\n]',start)+2
entries='const MODELS := [\n'+''.join('\t'+json.dumps(item,ensure_ascii=False)+',\n' for item in catalog)+']'
script.write_text(content[:start]+entries+content[end:],encoding='utf8')
