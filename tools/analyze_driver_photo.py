"""Free/offline face geometry, garment palette and visible-body landmarks. No remote calls."""
import sys, json, traceback
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT/'tools/.avatar_runtime'))
import numpy as np
from PIL import Image, ImageOps
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

photo,folder=map(Path,sys.argv[1:3]);folder.mkdir(parents=True,exist_ok=True)
def status(stage,progress,**kwargs):
    temp=folder/'status.tmp';temp.write_text(json.dumps(dict(stage=stage,progress=progress,**kwargs)),encoding='utf8');temp.replace(folder/'status.json')
try:
    status('Detectando rostro y ropa localmente',.12)
    image=ImageOps.exif_transpose(Image.open(photo)).convert('RGB');image.thumbnail((1600,1600))
    image.save(folder/'photo.png');pixels=np.array(image);h,w=pixels.shape[:2]
    models=ROOT/'project/assets/driver/models'
    source=mp.Image(image_format=mp.ImageFormat.SRGB,data=pixels)
    body=[]
    with vision.PoseLandmarker.create_from_options(vision.PoseLandmarkerOptions(base_options=python.BaseOptions(model_asset_path=str(models/'pose_landmarker.task')),min_pose_detection_confidence=.35,min_pose_presence_confidence=.35)) as pose_detector:
        pose=pose_detector.detect(source)
        if pose.pose_landmarks: body=[[p.x,p.y,p.z,p.visibility] for p in pose.pose_landmarks[0]]
    crop=(0,0,w,h)
    with vision.FaceLandmarker.create_from_options(vision.FaceLandmarkerOptions(base_options=python.BaseOptions(model_asset_path=str(models/'face_landmarker.task')),num_faces=2,min_face_detection_confidence=.4,min_face_presence_confidence=.4)) as detector:
        result=detector.detect(source)
        if not result.face_landmarks and body:
            # A full-body photo makes the face tiny in the detector input. Locate it using pose.
            points=body[:11];xs=[v[0]*w for v in points];ys=[v[1]*h for v in points]
            center_x=(min(xs)+max(xs))/2;center_y=(min(ys)+max(ys))/2
            size=max(max(xs)-min(xs),max(ys)-min(ys),24)*2.8
            crop=(max(0,int(center_x-size/2)),max(0,int(center_y-size/2)),min(w,int(center_x+size/2)),min(h,int(center_y+size/2)))
            region=np.array(image.crop(crop).resize((512,512)))
            result=detector.detect(mp.Image(image_format=mp.ImageFormat.SRGB,data=region))
    if not result.face_landmarks: raise ValueError('No se detectó un rostro. Prueba una foto más nítida o acércalo con el recorte.')
    if len(result.face_landmarks)>1: raise ValueError('Hay varias personas. Recorta la foto para elegir a tu conductor.')
    landmarks=result.face_landmarks[0]
    x0,y0,x1,y1=crop
    face=np.array([[(x0+p.x*(x1-x0))/w,(y0+p.y*(y1-y0))/h,p.z*(x1-x0)/w] for p in landmarks])
    edges=vision.FaceLandmarksConnections.FACE_LANDMARKS_TESSELATION
    neighbors={i:set() for i in range(468)}
    for edge in edges:
        if edge.start<468 and edge.end<468: neighbors[edge.start].add(edge.end);neighbors[edge.end].add(edge.start)
    triangles=[]
    for a in neighbors:
        for b in neighbors[a]:
            if b<=a:continue
            for c in neighbors[a]&neighbors[b]:
                if c>b:triangles.append([a,b,c])
    status('Separando pelo, piel y vestimenta',.3)
    with vision.ImageSegmenter.create_from_options(vision.ImageSegmenterOptions(base_options=python.BaseOptions(model_asset_path=str(models/'selfie_multiclass.tflite')),output_category_mask=True)) as segmenter:
        labels=segmenter.segment(source).category_mask.numpy_view().copy().squeeze()
    Image.fromarray((labels*40).astype('uint8')).save(folder/'segmentation.png')
    def color(mask,fallback):
        p=pixels[mask];return (np.median(p,axis=0)/255).tolist() if len(p)>20 else fallback
    hair=color(labels==1,[.12,.08,.06]);skin=color(labels==3,[.65,.45,.34])
    cx=float((face[234,0]+face[454,0])/2);top=float(face[10,1]);bottom=float(face[152,1]);fw=float(abs(face[454,0]-face[234,0]))
    cloth=(labels==4);yy,xx=np.indices((h,w));left=(xx/w<cx)&cloth;right=(xx/w>=cx)&cloth
    upper=cloth&(yy/h<min(1,bottom+(bottom-top)*1.7))
    jacket=color(upper,[.08,.09,.1]);pants=color(cloth&(yy/h>bottom+(bottom-top)*2),jacket)
    shoulders=[cx-fw*1.5,bottom+(bottom-top)*.35,cx+fw*1.5,bottom+(bottom-top)*.35]
    if body and min(body[11][3],body[12][3])>.4:
        a,b=sorted([body[11],body[12]],key=lambda p:p[0]);shoulders=[a[0],a[1],b[0],b[1]]
    torso_bottom=min(.97,bottom+(bottom-top)*2.7)
    if body and min(body[23][3],body[24][3])>.55 and max(body[23][1],body[24][1])<1:torso_bottom=(body[23][1]+body[24][1])/2
    # Remove hands/skin and background from the clothing projection before making the atlas.
    import cv2
    mask=((labels!=4)*255).astype('uint8')
    garment=cv2.inpaint(pixels,mask,7,cv2.INPAINT_TELEA)
    Image.fromarray(garment).save(folder/'garment.png')
    visible_clothes=bool(np.count_nonzero(upper)>w*h*.01 and bottom+(bottom-top)*.65<.98)
    profile=dict(version=2,method='offline-photo-mesh',face=face.tolist(),triangles=triangles,width=w,height=h,hair=hair,skin=skin,jacket=jacket,pants=pants,shoulders=shoulders,torso_bottom=torso_bottom,body=body,visible_clothes=visible_clothes,face_top=top,face_bottom=bottom,face_width=fw,face_center=cx)
    (folder/'analysis.json').write_text(json.dumps(profile),encoding='utf8')
    status('Rostro y ropa analizados; preparando cuerpo articulado',.48)
except Exception as error:
    status('No se pudo analizar la foto',0,error=str(error),done=True);traceback.print_exc();sys.exit(1)
