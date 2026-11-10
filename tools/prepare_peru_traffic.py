"""Reduce neural surfaces and render orientation views before material projection."""
import bpy,sys,math,json
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parent.parent;OUT=ROOT/'project/assets/traffic'
key=sys.argv[sys.argv.index('--')+1] if '--' in sys.argv else 'tico'
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(ROOT/'tools/.worldgen/generated'/(key+'_raw.glb')))
obj=next(o for o in bpy.context.scene.objects if o.type=='MESH');bpy.context.view_layer.objects.active=obj
mod=obj.modifiers.new('Game surface','DECIMATE');mod.ratio=min(1,65000/len(obj.data.polygons));bpy.ops.object.modifier_apply(modifier=mod.name)
for poly in obj.data.polygons:poly.use_smooth=True
mat=bpy.data.materials.new('Clay');mat.diffuse_color=(.55,.58,.61,1);obj.data.materials.clear();obj.data.materials.append(mat)
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=12
scene.render.resolution_x=640;scene.render.resolution_y=480;scene.render.resolution_percentage=100
scene.world.color=(.3,.3,.3)
for p in [(2,-4,5),(-3,2,4)]:
    bpy.ops.object.light_add(type='AREA',location=p);bpy.context.object.data.energy=350;bpy.context.object.data.shape='DISK';bpy.context.object.data.size=4
bpy.ops.object.camera_add();camera=bpy.context.object;scene.camera=camera;camera.data.type='ORTHO';camera.data.ortho_scale=2.9
for i,(x,y) in enumerate([(3,-4),(-3,-4),(-3,4),(3,4)]):
    camera.location=(x,y,2.2);camera.rotation_euler=(-camera.location).to_track_quat('-Z','Y').to_euler();scene.render.filepath=str(ROOT/'output'/('traffic_%s_clay_%d.png'%(key,i)));bpy.ops.render.render(write_still=True)
bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'tmp'/(key+'_reduced.blend')))
print('REDUCED',key,len(obj.data.polygons),list(obj.dimensions),flush=True)
