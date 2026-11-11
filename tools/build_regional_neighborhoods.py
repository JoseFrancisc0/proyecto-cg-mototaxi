"""76 reference-led buildings with individually studied houses and closed envelopes."""
from pathlib import Path
import json,math,random
ROOT=Path(__file__).resolve().parent.parent
prefix=(ROOT/'tools/build_peru_architecture.py').read_text(encoding='utf8').split('catalog=[]')[0]
prefix=prefix.replace('co[axes[0]]*.5,co[axes[1]]*.5','co[axes[0]]*mat.get("uv_scale",.5),co[axes[1]]*mat.get("uv_scale",.5)')
exec(prefix,globals())
library=json.loads((OUT/'materials/catalog.json').read_text())
pbr_library={m['id']:m for m in json.loads((OUT/'materials/pbr_catalog.json').read_text())}

def bind_surface_normal(m,source,strength=.45):
    if 'normal_file' not in source:return
    nodes=m.node_tree.nodes;links=m.node_tree.links
    tex=nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(source['normal_file'],check_existing=True);tex.image.colorspace_settings.name='Non-Color'
    normal=nodes.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=strength
    links.new(tex.outputs['Color'],normal.inputs['Color']);links.new(normal.outputs['Normal'],nodes.get('Principled BSDF').inputs['Normal'])

materials={}
for region in ['costa','sierra','selva']:
    materials[region]=[]
    for entry in [m for m in library if m['region']==region]:
        m=bpy.data.materials.new(entry['id']);m.use_nodes=True;m['atlas_tile']=0
        # The API dimensions are millimetres; 2500 means a 2.5 m tile.
        # The previous cm interpretation made individual bricks metre-sized.
        m['uv_scale']=1000/max(400,entry['dimensions_cm'][0]);nodes=m.node_tree.nodes;p=nodes.get('Principled BSDF');p.inputs['Roughness'].default_value=.84
        tex=nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(OUT/'materials'/entry['file']),check_existing=True)
        m.node_tree.links.new(tex.outputs['Color'],p.inputs['Base Color'])
        if entry['id'] in pbr_library:
            maps=pbr_library[entry['id']];m['normal_file']=str(OUT/'materials'/maps['normal'])
            bind_surface_normal(m,m)
            arm=nodes.new('ShaderNodeTexImage');arm.image=bpy.data.images.load(str(OUT/'materials'/maps['arm']),check_existing=True);arm.image.colorspace_settings.name='Non-Color'
            channels=nodes.new('ShaderNodeSeparateColor');m.node_tree.links.new(arm.outputs['Color'],channels.inputs['Color'])
            m.node_tree.links.new(channels.outputs['Green'],p.inputs['Roughness']);m.node_tree.links.new(channels.outputs['Blue'],p.inputs['Metallic'])
        materials[region].append(m)

# Shared structural parts use the same measured library as the facades.
cement=materials['costa'][10]
wood=materials['selva'][0]
def paint(index,region):
    colors=[(.82,.69,.34),(.23,.54,.52),(.75,.40,.28),(.75,.70,.57),(.50,.63,.70),(.77,.78,.72),(.43,.51,.33),(.65,.34,.29)]
    m=material('Pintura mineral '+str(index)+region,color=colors[index%len(colors)])
    # A real plaster microtexture modulates the paint instead of a flat RGB wall.
    source=materials[region][[7,8,9,6][index%4] if region=='costa' else [8,9,0,1][index%4] if region=='sierra' else [10,11,12,14][index%4]]
    tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=next(n.image for n in source.node_tree.nodes if n.type=='TEX_IMAGE')
    mix=m.node_tree.nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=.40;mix.inputs[1].default_value=(*colors[index%len(colors)],1)
    m.node_tree.links.new(tex.outputs['Color'],mix.inputs[2]);m.node_tree.links.new(mix.outputs[0],m.node_tree.nodes.get('Principled BSDF').inputs['Base Color']);m['atlas_tile']=0;m['uv_scale']=.5
    return m
def cornice(w,d,z,mat):
    # Shallow continuous front cornice; no tall, universal side parapets.
    box('Cornisa frontal',(0,-d*.5-.10,z),(w+.18,.30,.14),mat)
def shutter(x,y,z,w,h,mat):
    for side in [-1,1]:
        box('Contraventana',(x+side*w*.59,y-.16,z),(w*.32,.10,h),mat)
        for j in range(7):box('Lama persiana',(x+side*w*.59,y-.22,z-h*.4+j*h*.13),(w*.29,.045,.04),mat,0)
def sheet_roof(w,d,z,rise,mat):
    gable(w,d,z,rise,mat)
    for sign in [-1,1]:
        for k in range(int(d/.24)):
            y=-d*.5+k*.24
            pole('Nervio de calamina',(sign*.05,y,z+rise+.03),(sign*(w*.5+.45),y,z+.03),.017,mat)
def simple_roof(w,d,z,mat):box('Losa lisa',(0,0,z+.07),(w+.10,d+.10,.14),mat)
def arch_front(w,d,z,mat):
    for center in [-w*.26,w*.26]:
        for j in range(16):
            a=math.pi*j/16;b=math.pi*(j+1)/16
            pole('Arco',(center+math.cos(a)*w*.22,-d*.5-.20,z+math.sin(a)*.65),(center+math.cos(b)*w*.22,-d*.5-.20,z+math.sin(b)*.65),.075,mat)
def modern_volume(w,d,top,v,region):
    box('Volumen retranqueado',(-w*.18,d*.15,top+.95),(w*.64,d*.67,1.9),paint(v+2,region))
    box('Ventanal alto',(-w*.18,-d*.19,top+.94),(w*.55,.08,1.45),glass)
    box('Alero en voladizo',(-w*.1,-d*.12,top+1.98),(w*.85,d*.85,.15),white)
    for k in range(9):box('Celosia de acceso',(w*.33,-d*.5-.20,.8+k*.19),(w*.18,.14,.07),wood if region!='costa' else iron)
exec((ROOT/'tools/house_envelope.py').read_text(encoding='utf8'),globals())
exec((ROOT/'tools/house_wall_finishes.py').read_text(encoding='utf8'),globals())
exec((ROOT/'tools/regional_facade_components.py').read_text(encoding='utf8'),globals())
exec((ROOT/'tools/reference_facades.py').read_text(encoding='utf8'),globals())
exec((ROOT/'tools/coastal_reference_buildings.py').read_text(encoding='utf8'),globals())
exec((ROOT/'tools/andes_amazon_reference_buildings.py').read_text(encoding='utf8'),globals())
exec((ROOT/'tools/individual_modern_houses.py').read_text(encoding='utf8'),globals())
exec((ROOT/'tools/individual_andean_houses.py').read_text(encoding='utf8'),globals())
sys.path.insert(0,str(ROOT/'tools'))
from repair_gltf_paint import repair as repair_paint
from share_gltf_textures import share as share_textures
_export=export
house_metadata={}
def export(key):
    global OUT
    count=[2,2,2,1][v] if style=='barrio' else 2 if style=='iquitos' and v==0 else floors
    if style not in ['miraflores','jardin','valle_sagrado','andina_ladera','tarapoto','tropical_actual','casa_moderna','andina_actual']:back_and_corner_elevations(style,v,w,d,base,level,count)
    finishes=graffiti_wall_finish(style,v)
    house_metadata[key]=finalize_house(key,w,d)
    house_metadata[key].update(finishes)
    if raised:
        house_metadata[key]['approach']=[0,.06,d*.5+1.5+.28*math.ceil(base/.18)+.25]
    bpy.context.view_layer.update()
    bottom=min((o.matrix_world@Vector(c)).z for o in bpy.context.scene.objects if o.type=='MESH' for c in o.bound_box)
    if bottom<-.30:raise ValueError(f'{key}: geometry below its foundation ({bottom:.3f} m)')
    # Do not expose an embedded/intermediate GLB to an open Godot editor.
    # Publish only the checked, compact final file in one atomic replacement.
    import os,time
    destination=OUT/(key+'.glb');library_folder=OUT/'shared_textures';original_out=OUT
    staging=ROOT/'tools/.worldgen/house_export';staging.mkdir(parents=True,exist_ok=True)
    try:
        OUT=staging;height=_export(key)
    finally:OUT=original_out
    ready=staging/(key+'.glb')
    repair_paint(ready);share_textures(ready,library_folder)
    for attempt in range(40):
        try:os.replace(ready,destination);break
        except OSError:
            if attempt==39:raise
            time.sleep(.25)
    return height

districts={
0:[('ladera','invasion'),('popular','barrio'),('tradicional','barranco'),('residencial','jardin'),('moderna','miraflores'),('rural','valle'),('residencial','casa_moderna')],
1:[('popular','andina_urbana'),('tradicional','san_blas'),('residencial','valle_sagrado'),('moderna','andina_actual'),('rural','adobe'),('ladera','andina_ladera')],
2:[('popular','pucallpa'),('tradicional','iquitos'),('residencial','tarapoto'),('moderna','tropical_actual'),('rural','comunidad'),('ribereno','belen')]}
names=['costa','sierra','selva'];catalog=[]
requested=set(sys.argv[sys.argv.index('--')+1:]) if '--' in sys.argv else set()
existing={m['file']:m for m in json.loads((OUT/'catalog.json').read_text())} if requested else {}
lime=material('Cal de San Blas',color=(.88,.85,.77));lime['atlas_tile']=0
tex=lime.node_tree.nodes.new('ShaderNodeTexImage');tex.image=next(n.image for n in materials['sierra'][8].node_tree.nodes if n.type=='TEX_IMAGE')
mix=lime.node_tree.nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=.12;mix.inputs[1].default_value=(.88,.85,.77,1)
lime.node_tree.links.new(tex.outputs['Color'],mix.inputs[2]);lime.node_tree.links.new(mix.outputs[0],lime.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
for region,families in districts.items():
    label=names[region];mats=materials[label]
    for family,(zone,style) in enumerate(families):
        for v in range(4):
            key=label+'_'+style+'_'+str(v);random.seed(key)
            if requested and style not in requested:catalog.append(existing['peru/'+key+'.glb']);continue
            w=[5.2,6.1,7.2,8.3][v];d=6.2+v*.45
            if style=='barrio':w=[9.2,5.3,5.7,6.0][v]
            if style=='iquitos' and v==0:w=10.8
            if zone in ['residencial','moderna']:w+=2.5;d+=1
            if style=='miraflores':w=[15.0,18.0,12.0,22.0][v];d=[13.0,13.5,10.0,17.0][v]
            if style=='jardin':w=[7.2,6.4,6.8,6.1][v];d=8.4
            if style=='casa_moderna':w=[9.6,6.4,10.0,16.0][v];d=[10.0,8.0,10.0,12.0][v]
            if style=='andina_actual':w=[8.5,10.0,12.6,10.2][v];d=[8.0,9.0,10.0,10.2][v]
            if style=='valle_sagrado':w=[14.8,13.0,16.0,12.5][v];d=8.1
            if style=='andina_ladera':w=[6.0,7.0,5.5,8.5][v];d=6.6
            if style=='tarapoto':w=[3.6,4.0,4.2,3.4][v];d=6.8
            if style=='tropical_actual':w=[8.6,9.0,10.1,7.6][v];d=[7.0,7.5,8.4,7.1][v]
            floors=1+v%3 if zone in ['popular','tradicional'] else 1+v%2
            if style=='miraflores' and v>1:floors=6+(v-2)*3
            if style in ['adobe','comunidad']:floors=1 if v<3 else 2
            if style=='invasion':floors=[1,2,1,3][v]
            if style=='barranco':floors=[1,2,2,1][v]
            if style=='jardin':floors=[1,2,1,2][v]
            level=3.5 if style=='iquitos' else 2.55 if region==1 else 2.7
            raised=1.5+v*.25 if style=='belen' else .5 if style=='comunidad' else 0
            base=.14+raised
            wall=mats[(family*3+v)%20]
            if zone not in ['rural','ribereno']:wall=paint(v+family*2,label)
            if style in ['san_blas','adobe']:wall=paint(0 if v%2==0 else 3,label) if style=='san_blas' else mats[v%2]
            if style in ['belen','comunidad']:wall=mats[v%5]
            if style=='invasion':wall=mats[v%3] if v%2 else material('Pintura de ladera '+str(v),color=(.12,.37,.39) if v==0 else (.70,.68,.60))
            if style=='barrio':wall=paint([0,1,2,8][v],label)
            if style=='miraflores':wall=paint([8,3,8,8][v],label)
            if style in ['andina_actual','valle_sagrado']:wall=mats[3+v%4]
            if style=='pucallpa' and v==3:wall=mats[13]
            roofmat=mats[10+v%4] if region==1 else mats[5+v%3] if style=='comunidad' else mats[8] if region==2 else mats[14]
            if region==2 and style!='comunidad' and zone not in ['residencial','moderna']:roofmat=mats[8+v%2]
            if style in ['casa_moderna','andina_actual']:
                (modern_individual if style=='casa_moderna' else andean_individual)(v,w,d)
                height=export(key)
                catalog.append(dict(file='peru/'+key+'.glb',region=region,height=height,yaw=0.0,style=style,zones=['residencial','moderna'] if style=='casa_moderna' else ['moderna'],frontage=w,roof='flat',material_ids=[]))
                continue
            if style in ['valle_sagrado','andina_ladera','tarapoto','tropical_actual']:
                builders={'valle_sagrado':huayoccari_reference,'andina_ladera':adobe_street_reference,'tarapoto':tarapoto_reference,'tropical_actual':tropical_gallery_reference}
                builders[style](v,w,d)
                height=export(key)
                catalog.append(dict(file='peru/'+key+'.glb',region=region,height=height,yaw=0.0,style=style,zones=[zone],frontage=w,roof='flat' if style=='tarapoto' else 'pitched',material_ids=[]))
                continue
            if style in ['miraflores','jardin']:
                if style=='miraflores':modern_reference_tower(v,w,d)
                else:quinta_reference(v,w,d)
                height=export(key)
                catalog.append(dict(file='peru/'+key+'.glb',region=region,height=height,yaw=0.0,style=style,zones=[zone],frontage=w,roof='pitched' if style=='jardin' else 'flat',material_ids=[]))
                continue
            if style=='barrio' or (style=='iquitos' and v==0):
                if style=='barrio':coast_reference_shop(v,w,d)
                else:iquitos_reference(w,d)
                height=export(key)
                catalog.append(dict(file='peru/'+key+'.glb',region=region,height=height,yaw=0.0,style=style,zones=[zone],frontage=w,roof='flat',material_ids=[]))
                continue
            if raised:
                for x in [-w*.43,0,w*.43]:
                    for y in [-d*.43,0,d*.43]:pole('Pilote',(x,y,0),(x,y,base),.12,mats[3])
                n=math.ceil(base/.18)
                for j in range(n):
                    h=base*(n-j)/n
                    box('Escalera apoyada',(0,-d*.5-1.64-j*.28,h*.5),(1.25,.285,h),mats[3])
                box('Piso cerrado de galeria',(0,-d*.5-.75,base-.08),(w+.10,1.5,.16),mats[3])
                for x in [-w*.43,w*.43]:pole('Pilote de galeria',(x,-d*.5-1.30,0),(x,-d*.5-1.30,base),.10,mats[3])
                segments=[];front_y=-d*.5-1.5
                for a,b in [((-w*.5,front_y),(-.66,front_y)),((.66,front_y),(w*.5,front_y)),((-w*.5,front_y),(-w*.5,-d*.5)),((w*.5,front_y),(w*.5,-d*.5))]:
                    segments.append(((a[0],a[1],base+1.05),(b[0],b[1],base+1.05),.035))
                    count=max(1,math.ceil((Vector(a)-Vector(b)).length/.12))
                    for k in range(count+1):
                        p=Vector(a).lerp(Vector(b),k/count);segments.append(((p.x,p.y,base+.10),(p.x,p.y,base+1.04),.015))
                rail_segments('Proteccion completa de galeria',segments,joinery[0])
            else:box('Zocalo',(0,0,.13),(w,d,.26),cement if region==0 else mats[5] if region==1 else mats[13])
            for f in range(floors):
                z=base+f*level
                # Modern buildings have stepped massing; hillside homes stay compact.
                floor_w=w*(.76 if zone=='moderna' and f>0 and floors<4 else .90 if style=='jardin' and f>0 else 1)
                floor_wall=mats[9] if style=='valle_sagrado' and f>0 else wall
                if style in ['invasion','barrio'] and f>0:floor_wall=mats[v%3] if v%2 else paint(v+family*2+f+2,label)
                box('Muro principal',(0,0,z+level*.5),(floor_w,d,level),floor_wall)
                if style in ['barrio','andina_urbana','andina_ladera']:
                    concrete=mats[10+v%3] if region==0 else cement
                    for x in [-floor_w*.5,floor_w*.5]:
                        for y in [-d*.5,d*.5]:box('Columna de concreto',(x,y,z+level*.5),(.18,.18,level),concrete)
                    box('Viga',(0,0,z+level),(floor_w+.03,d+.03,.13),cement)
                count=3 if style=='iquitos' else 2 if style=='andina_actual' else 2 if v%2==0 else 3
                for j in range(count):
                    x=(j-(count-1)*.5)*floor_w/(count+.5)
                    if f==0 and count==2:x=(-1 if j==0 else 1)*floor_w*.31
                    if f==0 and count==3 and j==1:continue
                    if style=='barrio' and f==0 and j==0 and v in [1,2]:continue
                    kind=(v+j+f)%7
                    if style in ['barrio','invasion','andina_urbana','andina_ladera']:kind=[0,2,4,0][(v+j+f)%4]
                    if style in ['barranco','iquitos']:kind=[3,1,5,6][(v+j+f)%4]
                    if style=='san_blas':kind=0
                    if zone=='moderna':kind=4 if floors>4 else 0
                    carp=joinery[0] if style=='san_blas' else joinery[(v+j+family)%6] if zone=='tradicional' else joinery[0] if region==2 else joinery[2] if v%2 else iron
                    if style=='invasion':carp=iron;kind=2
                    opening_w=min(1.6,floor_w*.25) if f==0 and count==2 else min(1.35,floor_w/(count+1.6)) if style=='invasion' else floor_w/(count+1.6)
                    if style=='san_blas':opening_w=min(1.15,opening_w)
                    window(x,-d*.5-.035,z+level*.59,opening_w,1.55 if style=='san_blas' else 1.0 if style=='invasion' else 1.75 if style=='iquitos' else 1.1 if style=='adobe' else 1.45 if style=='barranco' else 1.25,zone in ['popular','ladera'],carp,kind)
                if f==0:door(0,-d*.5-.15,z,joinery[4] if style=='san_blas' else iron if zone in ['popular','ladera','moderna'] and region==0 else joinery[(v+family)%6],w=1.0 if v%2==0 else 1.35,h=2.5 if style=='iquitos' else 2.1,kind=(v%2)*3 if zone in ['popular','ladera','moderna'] else (v+family)%5)
                if style=='andina_actual':
                    for x in [-w*.47,w*.47]:box('Marco de madera',(x,-d*.5-.14,z+1.3),(.12,.16,2.6),wood)
                if style=='valle_sagrado' and f==0:
                    box('Porche de piedra',(0,-d*.5-.9,.12),(w*.9,2,.24),mats[4])
                    for x in [-w*.40,w*.40]:box('Pilar de piedra',(x,-d*.5-1.6,1.3),(.34,.34,2.6),mats[3+v%4])
                if f>0 and style in ['barranco','iquitos','tarapoto','belen'] and v!=0:
                    balcony(floor_w*(.88 if style=='belen' else .65),-d*.5-.58,z+.12,joinery[(v+family)%6],v%3)
                if floors>4:
                    box('Banda de cristal',(0,-d*.5-.09,z+1.4),(w*.84,.09,1.8),glass)
                    if v!=2:balcony(w*.76,-d*.5-.58,z+.1,iron,3)
            top=base+floors*level
            if region==1:
                if style=='andina_actual':sheet_roof(w,d,top,.8+v*.14,roofmat)
                else:gable(w,d,top,1.0+v*.18,roofmat)
                box('Basamento de piedra',(0,-d*.5-.05,.42),(w,.12,.75),mats[7] if style=='san_blas' and v==3 else mats[3+v%4])
            elif region==2:
                rise=1.8+v*.18 if style=='comunidad' else .9+v*.16
                sheet_roof(w,d,top,rise,roofmat) if style!='comunidad' else gable(w,d,top,rise,roofmat)
                box('Galeria cubierta',(0,-d*.5-.8,top-.17),(w+1,2.0,.13),roofmat)
                for x in [-w*.44,w*.44]:pole('Pilar de galeria',(x,-d*.5-1.25,base),(x,-d*.5-1.25,top-.15),.07,wood)
                for j in range(int(w/.30)):box('Ventilacion superior',(-w*.5+.15+j*.30,-d*.5-.08,top-.20),(.19,.07,.15),iron,0)
                if style=='iquitos':cornice(w,d,top,white)
            else:
                if style=='invasion':
                    roof=box('Calamina de ampliacion' if v==1 else 'Losa de ladera',(0,0,top+.1),(w+.20,d+.25,.12),roofmat if v==1 else mats[10]);roof.rotation_euler.x=-.03 if v==1 else 0
                    for j in range(4):pole('Liston exterior',(-w*.45+j*w*.3,-d*.5-.06,base),(-w*.45+j*w*.3,-d*.5-.06,top),.035,wood)
                else:simple_roof(w,d,top,cement)
                if style=='barranco':cornice(w,d,top,white)
                if style=='miraflores' and floors<4:modern_volume(w,d,top,v,label)
                if style=='barrio' and v==3:
                    bpy.ops.mesh.primitive_cylinder_add(vertices=16,radius=.52,depth=.8,location=(w*.27,d*.27,top+.4));bpy.context.object.data.materials.append(tank)
            facade_details(style,v,w,d,base,level,floors,label)
            if style=='san_blas':diamond_grilles(w,d,base,level,floors,v)
            if style=='barrio' and v in [1,2]:
                box('Garaje enrollable',(-w*.29,-d*.5-.22,base+1.05),(w*.32,.08,2.05),mats[13])
                for k in range(18):box('Junta de persiana',(-w*.29,-d*.5-.27,base+.10+k*.11),(w*.32,.025,.018),iron,0)
            elif zone=='moderna' and region==0:
                box('Revestimiento de piedra',(w*.40,-d*.5-.12,top*.5),(w*.16,.10,top),mats[16+v%3])
            used={m.name for o in bpy.context.scene.objects if o.type=='MESH' for m in o.data.materials}
            height=export(key)
            entry=dict(file='peru/'+key+'.glb',region=region,height=height,yaw=0.0,style=style,zones=[zone],frontage=w,roof='pitched' if region else 'flat',material_ids=[m['id'] for m in library if m['region']==label and m['id'] in used])
            if raised:entry['supports']=[[x,0,-y] for x in [-w*.43,0,w*.43] for y in [-d*.43,0,d*.43]]+[[x,0,d*.5+1.30] for x in [-w*.43,w*.43]]
            catalog.append(entry)
for entry in catalog:entry.update(house_metadata.get(Path(entry['file']).stem,{}))
(OUT/'catalog.json').write_text(json.dumps(catalog,indent=2),encoding='utf8')
script=ROOT/'project/scripts/terrain_houses.gd';content=script.read_text(encoding='utf8');start=content.index('const MODELS := [');end=content.index('\n]',start)+2
entries='const MODELS := [\n'+''.join('\t'+json.dumps({k:v for k,v in item.items() if k!='material_ids'},ensure_ascii=False)+',\n' for item in catalog)+']'
script.write_text(content[:start]+entries+content[end:],encoding='utf8')
print('REGIONAL_CATALOG',len(catalog),flush=True)
