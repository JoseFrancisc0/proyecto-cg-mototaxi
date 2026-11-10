import fs from 'node:fs/promises';
const folder=new URL('../project/assets/driver/models/',import.meta.url);
await fs.mkdir(folder,{recursive:true});
for(const [file,url] of [
 ['face_landmarker.task','https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task'],
 ['selfie_multiclass.tflite','https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_multiclass_256x256/float32/1/selfie_multiclass_256x256.tflite'],
 ['pose_landmarker.task','https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task']]){
 const response=await fetch(url);if(!response.ok)throw new Error(`${file}: ${response.status}`);
 const data=Buffer.from(await response.arrayBuffer());await fs.writeFile(new URL(file,folder),data);console.log(file,data.length);
}
