"""Reference-camera fitting and symmetric projection texturing of actual neural geometry."""
import bpy,sys,math,json
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parent.parent
sys.path[:0]=[str(ROOT/'tools/.reconstruction_runtime'),str(ROOT/'tools/.avatar_runtime')]
import numpy as np,cv2
from scipy.optimize import differential_evolution
from PIL import Image
OUT=ROOT/'project/assets/traffic'
keys=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else ['tico','sedan','coaster','urban_bus']
for key in keys:
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(ROOT/'tools/.worldgen/generated'/(key+'_raw.glb')))
    obj=next(o for o in bpy.context.scene.objects if o.type=='MESH');bpy.context.view_layer.objects.active=obj
    dec=obj.modifiers.new('Superficie optimizada','DECIMATE');dec.ratio=min(1,60000/len(obj.data.polygons));bpy.ops.object.modifier_apply(modifier=dec.name)
    for face in obj.data.polygons:face.use_smooth=True
    vertices=np.array([obj.matrix_world@v.co for v in obj.data.vertices]);ref=np.array(Image.open(OUT/(key+'_reference.png')).convert('RGBA'))
    alpha=ref[:,:,3]>200;ys,xs=np.nonzero(alpha);lo=np.array([xs.min()/ref.shape[1],1-ys.max()/ref.shape[0]]);hi=np.array([xs.max()/ref.shape[1],1-ys.min()/ref.shape[0]])
    target=cv2.resize(alpha[ys.min():ys.max()+1,xs.min():xs.max()+1].astype('uint8'),(192,128))
    sample=vertices[::max(1,len(vertices)//16000)]
    def project(points,angles):
        yaw,el=np.radians(angles);direction=np.array([math.sin(yaw)*math.cos(el),-math.cos(yaw)*math.cos(el),math.sin(el)])
        right=np.cross([0,0,1],direction);right/=np.linalg.norm(right);up=np.cross(direction,right)
        return np.stack([points@right,points@up],axis=1)
    def loss(angles):
        xy=project(sample,angles);mn=xy.min(0);mx=xy.max(0);xy=(xy-mn)/(mx-mn)
        mask=np.zeros((128,192),np.uint8);hull=cv2.convexHull(np.round(xy*[191,-127]+[0,127]).astype('int32'));cv2.fillConvexPoly(mask,hull,1)
        intersection=(mask*target).sum();union=np.maximum(mask,target).sum()
        # Preserve reference aspect as well as silhouette.
        aspect=((mx-mn)[0]/(mx-mn)[1]);actual=(xs.max()-xs.min())/max(1,ys.max()-ys.min())
        return 1-intersection/union+.6*abs(math.log(aspect/actual))
    fit=differential_evolution(loss,[(25,85),(4,32)],seed=41,popsize=8,maxiter=35,tol=.001)
    xy=project(vertices,fit.x);mn=xy.min(0);mx=xy.max(0)
    uv=obj.data.uv_layers.new(name='Foto calibrada')
    mirrored=vertices.copy();mirrored[:,0]=np.abs(mirrored[:,0])
    mapped=(project(mirrored,fit.x)-mn)/(mx-mn)*(hi-lo)+lo
    for loop in obj.data.loops:uv.data[loop.index].uv=mapped[loop.vertex_index]
    if key in ['coaster','urban_bus']:
        # Separate projective charts preserve straight window rows and the frontal destination sign.
        quads={
            'urban_bus':([[24,195],[280,225],[290,574],[24,565]],[[280,225],[758,255],[756,504],[290,574]]),
            'coaster':([[74,160],[352,189],[362,550],[40,535]],[[352,189],[694,221],[702,504],[362,550]])}
        front,side=quads[key];square=np.float32([[0,1],[1,1],[1,0],[0,0]])
        hf=cv2.getPerspectiveTransform(square,np.float32(front));hs=cv2.getPerspectiveTransform(square,np.float32(side))
        minimum=vertices.min(0);extent=vertices.max(0)-minimum
        for face in obj.data.polygons:
            normal=obj.matrix_world.to_3x3()@face.normal;centre=obj.matrix_world@face.center
            is_front=normal.y<-.35 and centre.y<minimum[1]+extent[1]*.16
            for loop_index in face.loop_indices:
                point=vertices[obj.data.loops[loop_index].vertex_index]
                u=(point[0]-minimum[0])/extent[0] if is_front else (point[1]-minimum[1])/extent[1]
                v=(point[2]-minimum[2])/extent[2]
                projected=(hf if is_front else hs)@np.array([u,v,1]);projected=projected[:2]/projected[2]
                uv.data[loop_index].uv=(projected[0]/ref.shape[1],1-projected[1]/ref.shape[0])
    # Extend nearest visible colours outside the silhouette to avoid projection borders.
    rgb=ref[:,:,:3].copy();holes=(~alpha).astype('uint8');rgb=cv2.inpaint(rgb,holes,3,cv2.INPAINT_TELEA)
    texture=OUT/(key+'_albedo.png');Image.fromarray(rgb).save(texture)
    image=bpy.data.images.load(str(texture));image.pack()
    mat=bpy.data.materials.new('Carroceria fotografica');mat.use_nodes=True;p=mat.node_tree.nodes.get('Principled BSDF');p.inputs['Roughness'].default_value=.63;p.inputs['Metallic'].default_value=.12
    tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=image;tex.extension='EXTEND';mat.node_tree.links.new(tex.outputs['Color'],p.inputs['Base Color'])
    rear=bpy.data.materials.new('Pintura posterior');rear.use_nodes=True;rear.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value={'tico':(.86,.62,.03,1),'sedan':(.025,.029,.03,1),'coaster':(.76,.73,.65,1),'urban_bus':(.65,.035,.02,1)}[key]
    obj.data.materials.clear();obj.data.materials.append(mat);obj.data.materials.append(rear)
    ymin,ymax=vertices[:,1].min(),vertices[:,1].max();zmin,zmax=vertices[:,2].min(),vertices[:,2].max()
    for face in obj.data.polygons:
        centre=obj.matrix_world@face.center
        normal=obj.matrix_world.to_3x3()@face.normal
        if (centre.y>ymax-(ymax-ymin)*.08 and normal.y>.3) or (centre.z>zmin+(zmax-zmin)*.88 and normal.z>.65):face.material_index=1
    def detail(name,loc,size,color):
        bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.name=name;o.dimensions=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
        m=bpy.data.materials.get(name) or bpy.data.materials.new(name);m.use_nodes=True;m.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(*color,1);o.data.materials.append(m)
        mod=o.modifiers.new('Cantos','BEVEL');mod.width=.008;mod.segments=2;bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=mod.name)
    width=vertices[:,0].max()-vertices[:,0].min();height=zmax-zmin;length=ymax-ymin
    # Rear glazing, tail lights and plate have their own geometry and materials.
    def rear_surface(x,z):
        close=vertices[(np.abs(vertices[:,0]-x)<width*.08)&(np.abs(vertices[:,2]-z)<height*.045)]
        return float(np.max(close[:,1])) if len(close) else ymax-length*.08
    glazing=bpy.data.materials.new('Vidrio posterior');glazing.use_nodes=True;glazing.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(.04,.09,.11,1);obj.data.materials.append(glazing)
    for face in obj.data.polygons:
        centre=obj.matrix_world@face.center;normal=obj.matrix_world.to_3x3()@face.normal
        if normal.y>.4 and centre.y>ymax-length*.25 and zmin+height*.55<centre.z<zmin+height*.85:face.material_index=2
    if key in ['coaster','urban_bus']:
        roof=bpy.data.materials.new('Cubierta marfil');roof.use_nodes=True;roof.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(.74,.73,.64,1);roof.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.75;obj.data.materials.append(roof)
        for face in obj.data.polygons:
            centre=obj.matrix_world@face.center;normal=obj.matrix_world.to_3x3()@face.normal
            if centre.z>zmin+height*.87 and normal.z>.55:face.material_index=3
    for side in [-1,1]:
        x=side*width*.38;z=zmin+height*.31
        detail('Faros posteriores',(x,rear_surface(x,z)+.012,z),(width*.10,.025,height*.12),(.55,.015,.009))
    z=zmin+height*.21
    detail('Placa posterior',(0,rear_surface(0,z)+.012,z),(width*.23,.025,height*.07),(.70,.71,.62))
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    dimensions={'tico':(1.45,3.35,1.55),'sedan':(1.70,4.50,1.48),'coaster':(2.05,6.80,2.65),'urban_bus':(2.48,9.0,3.10)}[key]
    scale=Vector((dimensions[0]/width,dimensions[1]/length,dimensions[2]/height))
    for item in bpy.context.selected_objects:
        item.location=Vector((item.location.x*scale.x,item.location.y*scale.y,item.location.z*scale.z-zmin*scale.z))
        item.scale=Vector((item.scale.x*scale.x,item.scale.y*scale.y,item.scale.z*scale.z))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(key+'.glb')),export_format='GLB',use_selection=True,export_yup=True)
    (OUT/(key+'_projection.json')).write_text(json.dumps({'angles':fit.x.tolist(),'silhouette_loss':float(fit.fun),'faces':len(obj.data.polygons)}))
    print('TRAFFIC_READY',key,fit.x.tolist(),len(obj.data.polygons),flush=True)
