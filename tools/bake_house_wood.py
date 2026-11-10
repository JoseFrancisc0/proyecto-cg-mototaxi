"""Bake an original fine-grain joinery material in Blender (no paid service)."""
import bpy
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
target=ROOT/'project/assets/houses/peru/materials/custom/honey_joinery.png';target.parent.mkdir(exist_ok=True)
def linear(v):return ((v+.055)/1.055)**2.4 if v>.04045 else v/12.92
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.mesh.primitive_plane_add(size=2)
obj=bpy.context.object;mat=bpy.data.materials.new('Veta fina original');mat.use_nodes=True;obj.data.materials.append(mat)
nodes=mat.node_tree.nodes;links=mat.node_tree.links;nodes.clear()
coords=nodes.new('ShaderNodeTexCoord');stretch=nodes.new('ShaderNodeVectorMath');stretch.operation='MULTIPLY';stretch.inputs[1].default_value=(2.0,170.0,1)
noise=nodes.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=3;noise.inputs['Detail'].default_value=3
ramp=nodes.new('ShaderNodeValToRGB')
for element,color in zip(ramp.color_ramp.elements,[(.50,.30,.13),(.76,.55,.30)]):element.color=(*[linear(v) for v in color],1)
emit=nodes.new('ShaderNodeEmission');output=nodes.new('ShaderNodeOutputMaterial')
links.new(coords.outputs['UV'],stretch.inputs[0]);links.new(stretch.outputs[0],noise.inputs['Vector']);links.new(noise.outputs['Fac'],ramp.inputs['Fac']);links.new(ramp.outputs['Color'],emit.inputs['Color']);links.new(emit.outputs[0],output.inputs['Surface'])
image=bpy.data.images.new('Honey joinery original',width=1024,height=1024)
tex=nodes.new('ShaderNodeTexImage');tex.image=image;nodes.active=tex
bpy.context.scene.render.engine='CYCLES';bpy.context.scene.cycles.samples=1
bpy.ops.object.bake(type='EMIT');image.filepath_raw=str(target);image.file_format='PNG';image.save()
print('JOINERY_MATERIAL_READY',target)
