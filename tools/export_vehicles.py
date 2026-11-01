"""Export user Blender sources with complete replacement wheels.
Usage: blender --background --python tools/export_vehicles.py -- SOURCE_DIR OUTPUT_DIR [MODEL_ID ...]
Original Blender files remain untouched. Wheel positions are normalized Z-up coordinates.
"""
import bpy, bmesh, sys, os, json, math
from mathutils import Vector
wheel_specs=json.load(open(os.path.join(os.path.dirname(__file__),'vehicle_wheels.json'),encoding='utf-8'))
STYLES={
 'neon_thunder':((.12,.85,.025,1),8,.75),
 'faketaxi_drift':((.16,.17,.20,1),6,.85),
 'neon_shadow':((.13,.16,.18,1),6,.55),
 'silver_guardian':((.68,.73,.8,1),10,.95),
 'midnight_camper':((.3,.34,.38,1),16,.65),
 'dusty':((.24,.19,.135,1),5,.15),
}

def material(name,color,metallic=0,roughness=.6):
 m=bpy.data.materials.new(name);m.diffuse_color=color;m.use_nodes=True
 bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=color
 bs.inputs['Metallic'].default_value=metallic;bs.inputs['Roughness'].default_value=roughness
 return m

def add_mesh(name,verts,faces,parent,mat,smooth=False):
 mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.materials.append(mat);mesh.update()
 obj=bpy.data.objects.new(name,mesh);bpy.context.scene.collection.objects.link(obj);obj.parent=parent
 for face in mesh.polygons: face.use_smooth=smooth
 return obj

def lathe(name,profile,parent,mat,segments=64):
 # Surface of revolution around X; closed cross-section gives a complete tire/rim.
 verts=[];faces=[]
 for x,r in profile:
  for i in range(segments):
   angle=math.tau*i/segments;verts.append((x,r*math.cos(angle),r*math.sin(angle)))
 for row in range(len(profile)):
  other=(row+1)%len(profile)
  for i in range(segments):
   j=(i+1)%segments;faces.append((row*segments+i,row*segments+j,other*segments+j,other*segments+i))
 return add_mesh(name,verts,faces,parent,mat,True)

def build_wheel(spec,key,mats):
 c=Vector(spec['center']);r=spec['radius'];width=spec['half_width']*.88
 pivot=bpy.data.objects.new('Wheel'+spec['name']+'Pivot',None);bpy.context.scene.collection.objects.link(pivot);pivot.location=c
 pivot['wheel_radius']=r;pivot['steering_wheel']=spec['name']=='Front'
 spin=bpy.data.objects.new('Wheel'+spec['name']+'Spin',None);bpy.context.scene.collection.objects.link(spin);spin.parent=pivot
 spin['complete_wheel']=True
 rubber,rim,edge=mats
 # Rounded tire with modeled shoulders, closed inner wall, and no source-body fragments.
 profile=[(-width*.72,r*.72),(-width,r*.82),(-width,r*.91),(-width*.65,r*.985),(-width*.25,r),
          (width*.25,r),(width*.65,r*.985),(width,r*.91),(width,r*.82),(width*.72,r*.72)]
 lathe('Tire'+spec['name'],profile,spin,rubber)
 lathe('Rim'+spec['name'],[(-width*.8,r*.71),(-width*.85,r*.79),(width*.85,r*.79),(width*.8,r*.71)],spin,edge)
 # Shallow hub and recessed backing hide old fused geometry inside the new wheel.
 lathe('Hub'+spec['name'],[(-width*.78,r*.03),(-width*.78,r*.22),(width*.78,r*.22),(width*.78,r*.03)],spin,rim,32)
 lathe('Brake'+spec['name'],[(-width*.42,r*.05),(-width*.42,r*.70),(width*.42,r*.70),(width*.42,r*.05)],spin,rubber,48)
 count=STYLES[key][1];verts=[];faces=[]
 for side in (-1,1):
  for i in range(count):
   a=math.tau*i/count;spread=.035 if count>12 else .075
   # Swept spokes retain a visible rotation cue at driving speed.
   pts=[]
   for rad,ang in [(r*.18,a-spread),(r*.74,a+.10-spread),(r*.74,a+.10+spread),(r*.18,a+spread)]:
    pts.append((side*width*.80,rad*math.cos(ang),rad*math.sin(ang)))
   base=len(verts);verts.extend(pts);faces.append(tuple(range(base,base+4)))
 add_mesh('Spokes'+spec['name'],verts,faces,spin,rim)
 # Rubber tread blocks: modest contrast, balanced evenly around the circumference.
 verts=[];faces=[]
 for i in range(40):
  a=math.tau*i/40;da=.019
  base=len(verts)
  for x,ang in [(-width*.55,a-da),(width*.55,a-da),(width*.55,a+da),(-width*.55,a+da)]:
   verts.append((x,r*1.003*math.cos(ang),r*1.003*math.sin(ang)))
  faces.append(tuple(range(base,base+4)))
 add_mesh('Tread'+spec['name'],verts,faces,spin,rubber)
 # A valve on each outer rim gives a second rotation cue without flashing textures.
 for side in (-1,1):
  bpy.ops.mesh.primitive_uv_sphere_add(segments=8,ring_count=4,radius=r*.035,location=(0,0,0))
  valve=bpy.context.object;valve.name='Valve'+spec['name'];valve.parent=spin
  valve.location=(side*width*.87,r*.73,0);valve.data.materials.append(edge)
 print('COMPLETE_WHEEL',key,spec['name'],r,flush=True)

def replace_wheels(meshes,key):
 specs=wheel_specs[key]
 # Remove only wheel-facing geometry. Axles, fenders and bodywork stay stationary.
 # Recessed source parts are occluded by the complete replacement wheel and brake disc.
 for obj in meshes:
  bm=bmesh.new();bm.from_mesh(obj.data);remove=[]
  for face in bm.faces:
   p=face.calc_center_median()
   for spec in specs:
    c=Vector(spec['center']);r=spec['radius'];dx=abs(p.x-c.x)
    radial=math.hypot(p.y-c.y,p.z-c.z)
    if dx<spec['half_width']*1.1 and radial<r*.96 and abs(face.normal.x)>.65:
     remove.append(face);break
  bmesh.ops.delete(bm,geom=remove,context='FACES')
  bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
  bm.to_mesh(obj.data);bm.free();obj.name='Body'
 color,_,metal=STYLES[key]
 rubber=material(key+'_rubber',(.075,.065,.05,1) if key=='dusty' else (.018,.021,.026,1),0,.94 if key=='dusty' else .82)
 rim=material(key+'_rim',color,metal,.68 if key=='dusty' else .28)
 edge=material(key+'_rim_edge',(.32,.25,.17,1) if key=='dusty' else (.42,.47,.52,1),metal,.65 if key=='dusty' else .24)
 for spec in specs: build_wheel(spec,key,(rubber,rim,edge))

source,target,*selected=sys.argv[sys.argv.index('--')+1:]
models=[('neon_thunder','Neon_Thunder_Tuk_Tuk'),('faketaxi_drift','Faketaxi_Drift_Rickshaw'),('neon_shadow','Neon_Shadow_Hauler'),('silver_guardian','Silver_Guardian_Tuk_Tuk'),('midnight_camper','Midnight_Tuk_Tuk_Camper'),('dusty','Dusty_Tuk_Tuk')]
os.makedirs(target,exist_ok=True)
for key,name in models:
 if selected and key not in selected: continue
 bpy.ops.wm.open_mainfile(filepath=os.path.join(source,'Meshy_AI_'+name+'_20261101_texture.blend'))
 for obj in list(bpy.context.scene.objects):
  if obj.type!='MESH': bpy.data.objects.remove(obj,do_unlink=True)
 meshes=list(bpy.context.scene.objects)
 pts=[o.matrix_world@Vector(c) for o in meshes for c in o.bound_box]
 lo=Vector(tuple(min(p[i] for p in pts) for i in range(3)));hi=Vector(tuple(max(p[i] for p in pts) for i in range(3)))
 scale=2.65/(hi.x-lo.x);center=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
 for obj in meshes:
  matrix=obj.matrix_world.copy()
  for vertex in obj.data.vertices:
   p=(matrix@vertex.co-center)*scale;vertex.co=Vector((-p.y,p.x,p.z))
  obj.matrix_world.identity();obj.data.update()
 for image in bpy.data.images:
  if max(image.size)>2048:
   ratio=2048/max(image.size);image.scale(round(image.size[0]*ratio),round(image.size[1]*ratio))
 replace_wheels(meshes,key)
 bpy.ops.export_scene.gltf(filepath=os.path.join(target,key+'.glb'),export_format='GLB',export_yup=True,export_image_format='AUTO',export_cameras=False,export_lights=False,export_animations=False,export_extras=True)
 print('EXPORTED',key,flush=True)
