"""Texture and rig an actual reconstructed clothed mesh. No geometric stand-in body parts."""
import bpy,bmesh,sys,json,math,os
from pathlib import Path
from mathutils import Vector
import numpy as np
ROOT=Path(__file__).resolve().parent.parent
folder=Path(sys.argv[sys.argv.index('--')+1]).resolve()
data=np.load(folder/'surface.npz');vertices=data['vertices'];faces=data['faces']
projection=json.loads((folder/'projection.json').read_text())
# PIFuHD coordinates: X right in photo, Y up, Z toward viewer.
low=float(vertices[:,1].min());high=float(vertices[:,1].max());scale=1.75/(high-low)
geometry=[(float(x)*scale,-float(z)*scale,(float(y)-low)*scale) for x,y,z in vertices]
analysis=json.loads((folder/'analysis.json').read_text()) if (folder/'analysis.json').exists() else {}
hand_regions=[]
if analysis.get('body'):
    for wrist_id,finger_id in [(15,19),(16,20)]:
        region=[]
        for index in [wrist_id,finger_id]:
            x,y=analysis['body'][index][:2]
            rx=((x*projection['width']-projection['left'])/projection['side'])*2-1
            ry=1-((y*projection['height']-projection['top'])/projection['side'])*2
            region.append(Vector((rx*scale,0,(ry-low)*scale)))
        hand_regions.append((region[0],(region[1]-region[0]).normalized()))
budget=int(os.environ.get('PERU_NPC_FACE_BUDGET','95000'))
texture_size=int(os.environ.get('PERU_NPC_TEXTURE_SIZE','4096'))
cache=folder/('textured_body_v5_%d_%d.blend'%(budget,texture_size))
if cache.exists():
    bpy.ops.wm.open_mainfile(filepath=str(cache))
    body=bpy.data.objects['Conductor reconstruido'];mesh=body.data;geometry=[tuple(v.co) for v in mesh.vertices]
else:
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    mesh=bpy.data.meshes.new('Reconstrucción continua de cuerpo y vestimenta');mesh.from_pydata(geometry,[],faces.tolist());mesh.update()
    body=bpy.data.objects.new('Conductor reconstruido',mesh);bpy.context.collection.objects.link(body)
    bpy.context.view_layer.objects.active=body;body.select_set(True)
    # Consistent outward normals, remove only tiny disconnected extraction noise.
    bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
    for polygon in mesh.polygons:polygon.use_smooth=True
    def material(name,color,roughness=.6,photo=False):
        mat=bpy.data.materials.new(name);mat.use_nodes=True;shader=mat.node_tree.nodes.get('Principled BSDF')
        shader.inputs['Base Color'].default_value=(*color,1);shader.inputs['Roughness'].default_value=roughness
        nodes=mat.node_tree.nodes;links=mat.node_tree.links
        node=nodes.new('ShaderNodeTexImage');node.image=bpy.data.images.load(str(folder/'texture_projection.png'),check_existing=True);node.image.pack();node.interpolation='Linear'
        uv_node=nodes.new('ShaderNodeUVMap');uv_node.uv_map='Fotografía';links.new(uv_node.outputs['UV'],node.inputs['Vector'])
        geo=nodes.new('ShaderNodeNewGeometry');xyz=nodes.new('ShaderNodeSeparateXYZ');links.new(geo.outputs['Normal'],xyz.inputs[0])
        factor=nodes.new('ShaderNodeMapRange');factor.clamp=True;factor.inputs['From Min'].default_value=.40;factor.inputs['From Max'].default_value=-.40;links.new(xyz.outputs['Y'],factor.inputs['Value'])
        noise=nodes.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=75 if 'Cabello' in name else 160
        ramp=nodes.new('ShaderNodeMapRange');ramp.inputs['To Min'].default_value=.72;ramp.inputs['To Max'].default_value=1.28;links.new(noise.outputs['Fac'],ramp.inputs['Value'])
        variation=nodes.new('ShaderNodeMixRGB');variation.blend_type='MULTIPLY';variation.inputs[0].default_value=1;variation.inputs[1].default_value=(*color,1);links.new(ramp.outputs['Result'],variation.inputs[2])
        mix=nodes.new('ShaderNodeMixRGB');links.new(variation.outputs[0],mix.inputs[1]);links.new(factor.outputs['Result'],mix.inputs[0]);links.new(node.outputs['Color'],mix.inputs[2])
        emission=nodes.new('ShaderNodeEmission');links.new(mix.outputs[0],emission.inputs['Color']);links.new(emission.outputs[0],nodes.get('Material Output').inputs['Surface'])
        return mat
    front=material('Fotografía frontal · piel y ropa',(.08,.08,.08),.68,True)
    def palette(key,fallback):
        return tuple(v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in analysis.get(key,fallback))
    jacket=material('Prenda posterior',palette('jacket',[.12,.14,.15]),.65)
    pants=material('Pantalón posterior',palette('pants',[.12,.12,.13]),.87)
    hair=material('Cabello',palette('hair',[.20,.14,.10]),.83)
    skin=material('Piel lateral',palette('skin',[.63,.49,.40]),.82)
    for mat in [front,jacket,pants,hair,skin]:mesh.materials.append(mat)
    uv=mesh.uv_layers.new(name='Fotografía')
    for polygon in mesh.polygons:
        center=polygon.center;normal=polygon.normal
        # Actual photographed front/side. Back uses inferred materials, never a second face.
        if center.z>1.54:polygon.material_index=3
        elif center.z>1.48 and abs(center.x)<.07:polygon.material_index=4
        elif center.z<.90:polygon.material_index=2
        else:polygon.material_index=1
        for wrist,axis in hand_regions:
            delta=Vector((center.x-wrist.x,0,center.z-wrist.z))
            if delta.length<.16 and delta.dot(axis)>-.008:polygon.material_index=4
        for loop in polygon.loop_indices:
            original=vertices[mesh.loops[loop].vertex_index]
            uv.data[loop].uv=(float(original[0])*.5+.5,float(original[1])*.5+.5)
    # Bake the smoothly blended front/side/back into one portable PBR albedo atlas.
    atlas=bpy.data.images.new('DriverAlbedo',width=texture_size,height=texture_size,alpha=False)
    atlas.colorspace_settings.name='sRGB'
    for mat in mesh.materials:
        target=mat.node_tree.nodes.new('ShaderNodeTexImage');target.image=atlas;mat.node_tree.nodes.active=target
    mesh.uv_layers.new(name='Atlas')
    mesh.uv_layers.active_index=1
    bpy.context.view_layer.objects.active=body
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.008);bpy.ops.object.mode_set(mode='OBJECT')
    mesh.uv_layers.active_index=1;mesh.uv_layers['Atlas'].active_render=True
    bpy.context.scene.render.engine='CYCLES';bpy.context.scene.cycles.samples=1
    bpy.ops.object.bake(type='EMIT',margin=16,use_clear=True)
    atlas.filepath_raw=str(folder/'albedo.png');atlas.file_format='PNG';atlas.save();atlas.pack()
    final_mat=bpy.data.materials.new('Rostro y vestimenta · atlas reconstruido');final_mat.use_nodes=True
    shader=final_mat.node_tree.nodes.get('Principled BSDF');shader.inputs['Roughness'].default_value=.68
    node=final_mat.node_tree.nodes.new('ShaderNodeTexImage');node.image=atlas
    atlas_uv=final_mat.node_tree.nodes.new('ShaderNodeUVMap');atlas_uv.uv_map='Atlas'
    final_mat.node_tree.links.new(atlas_uv.outputs['UV'],node.inputs['Vector'])
    final_mat.node_tree.links.new(node.outputs['Color'],shader.inputs['Base Color'])
    mesh.materials.clear();mesh.materials.append(final_mat)
    for polygon in mesh.polygons:polygon.material_index=0
    # Optimize before calculating skin weights, avoiding new interpolated joint influences.
    if len(mesh.polygons)>budget:
        decimate=body.modifiers.new('Optimización para juego','DECIMATE');decimate.ratio=budget/len(mesh.polygons);bpy.ops.object.modifier_apply(modifier=decimate.name)
    mesh=body.data;geometry=[tuple(v.co) for v in mesh.vertices]
    # Create anatomical joints at the actual locations detected in the source photograph.
    bpy.ops.wm.save_as_mainfile(filepath=str(cache))
analysis=json.loads((folder/'analysis.json').read_text()) if (folder/'analysis.json').exists() else {}
pose=analysis.get('body',[])
def point(index,fallback):
    if not pose or pose[index][3]<.45:return Vector(fallback)
    x,y=pose[index][:2]
    rawx=((x*projection['width']-projection['left'])/projection['side'])*2-1
    rawy=1-((y*projection['height']-projection['top'])/projection['side'])*2
    return Vector((rawx*scale,0,(rawy-low)*scale))
hip_l=point(23,(.10,0,.90));hip_r=point(24,(-.10,0,.90));hips=(hip_l+hip_r)/2
shoulder_l=point(11,(.21,0,1.40));shoulder_r=point(12,(-.21,0,1.40));shoulders=(shoulder_l+shoulder_r)/2
neck=Vector((shoulders.x,0,shoulders.z+.07));head=Vector((neck.x,0,1.57))
bones=[('Hips',None,hips,hips+Vector((0,0,.12))),('Spine','Hips',hips+Vector((0,0,.12)),Vector((hips.x,0,1.30))),('Chest','Spine',Vector((hips.x,0,1.30)),neck),('Neck','Chest',neck,head),('Head','Neck',head,Vector((head.x,0,1.73)))]
for side,offset,sign in [('Left',0,1),('Right',1,-1)]:
    hip=hip_l if side=='Left' else hip_r;shoulder=shoulder_l if side=='Left' else shoulder_r
    knee=point(25+offset,(sign*.1,0,.5));ankle=point(27+offset,(sign*.1,0,.1));toe=point(31+offset,(sign*.1,-.12,.05));toe.y=-.12
    elbow=point(13+offset,(sign*.43,0,1.16));wrist=point(15+offset,(sign*.60,0,.98));finger=point(19+offset,(sign*.64,0,.91))
    bones.extend([(side+'UpLeg','Hips',hip,knee),(side+'Leg',side+'UpLeg',knee,ankle),(side+'Foot',side+'Leg',ankle,toe),(side+'Arm','Chest',shoulder,elbow),(side+'ForeArm',side+'Arm',elbow,wrist),(side+'Hand',side+'ForeArm',wrist,finger)])
rig_data=bpy.data.armatures.new('DriverRig');rig=bpy.data.objects.new('DriverRig',rig_data);bpy.context.collection.objects.link(rig);bpy.context.view_layer.objects.active=rig
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
for name,parent,start,end in bones:
    bone=rig_data.edit_bones.new(name);bone.head=start;bone.tail=end
    if (Vector(end)-Vector(start)).length<.001:bone.tail=Vector(start)+Vector((0,0,.01))
    if parent:bone.parent=rig_data.edit_bones[parent]
bpy.ops.object.mode_set(mode='OBJECT')
# Smooth, continuous skinning. Restrict each limb to its own anatomical region.
auto_weighted=False
body.select_set(True);rig.select_set(True);bpy.context.view_layer.objects.active=rig
try:
    bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    used={group.name:0 for group in body.vertex_groups}
    unweighted=0
    for vertex in body.data.vertices:
        if not vertex.groups:unweighted+=1
        for influence in vertex.groups:
            if influence.weight>.01:used[body.vertex_groups[influence.group].name]+=1
    auto_weighted=unweighted<len(body.data.vertices)*.01 and all(used.get(name,0)>3 for name,*_ in bones)
    if auto_weighted:
        for vertex in body.data.vertices:
            if sum(g.weight for g in vertex.groups)>.001:continue
            closest=0;distance=1e9
            for i,(_,_,start,end) in enumerate(bones):
                a=Vector(start);axis=Vector(end)-a
                t=max(0,min(1,(vertex.co-a).dot(axis)/max(axis.length_squared,1e-8)))
                d=(vertex.co-a-axis*t).length
                if d<distance:closest=i;distance=d
            body.vertex_groups[bones[closest][0]].add([vertex.index],1,'REPLACE')
    print('AUTOMATIC_SKINNING',auto_weighted,'unweighted',unweighted,used)
except Exception as error:print('Automatic skinning failed:',error)
if not auto_weighted:
    body.vertex_groups.clear()
    points=np.array(geometry,dtype='float32');distances=[]
    for name,parent,start,end in bones:
        a=np.array(start);b=np.array(end);axis=b-a;t=np.clip(((points-a)@axis)/max(np.dot(axis,axis),1e-8),0,1)
        d=np.linalg.norm(points-(a+t[:,None]*axis),axis=1)
        if 'Arm' in name or 'Hand' in name:
            other=points[:,0]* (1 if name.startswith('Left') else -1)<.12;d[other]+=10
        elif 'Leg' in name or 'Foot' in name:
            other=(points[:,0]*(1 if name.startswith('Left') else -1)<0)|(points[:,2]>hips.z+.05);d[other]+=10
        elif name in ['Spine','Chest','Hips']:
            d[np.abs(points[:,0])>.23]+=10
            d[points[:,2]<hips.z-.08]+=10
        elif name in ['Neck','Head']:d[points[:,2]<neck.z-.03]+=10
        distances.append(d)
    distances=np.stack(distances,1);indices=np.argsort(distances,axis=1)[:,:3]
    weights=np.exp(-(np.take_along_axis(distances,indices,1)-distances.min(1)[:,None])*45);weights/=weights.sum(1)[:,None]
    groups=[body.vertex_groups.new(name=name) for name,*_ in bones]
    for vertex in range(len(points)):
        for k in range(3):
            value=float(weights[vertex,k])
            if value>.001:groups[int(indices[vertex,k])].add([vertex],value,'REPLACE')
body.parent=rig
if not any(m.type=='ARMATURE' for m in body.modifiers):
    modifier=body.modifiers.new('Piel articulada','ARMATURE');modifier.object=rig
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=str(folder/'driver.glb'),export_format='GLB',export_animations=False,export_yup=True,export_apply=False)
(folder/'rig.json').write_text(json.dumps({name:[list(start),list(end)] for name,_,start,end in bones}),encoding='utf8')
(folder/'skin_quality.json').write_text(json.dumps(dict(automatic_weights=auto_weighted)),encoding='utf8')
print('RECONSTRUCTED_DRIVER_READY',folder/'driver.glb',len(body.data.polygons))
