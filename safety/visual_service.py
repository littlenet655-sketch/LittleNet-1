import os,tempfile,subprocess
from .common import env_flag,normalize_signals,timed_call,timeout_seconds

def _runtime_device():
    requested=os.getenv('LITTLENET_DEVICE','auto').lower()
    try:
        import torch
        if requested=='cuda' and torch.cuda.is_available():return 'cuda'
        if requested=='cpu':return 'cpu'
        return 'cuda' if torch.cuda.is_available() else 'cpu'
    except Exception:return 'cpu'
_CLIP=None;_CLIP_PROC=None;_YOLO=None;_NUDE=None;_NSFW=None;_OPENNSFW2=None;_EXTRA_HF=None

def _clip_score_impl(image_path):
    global _CLIP,_CLIP_PROC
    from PIL import Image
    from transformers import CLIPModel,CLIPProcessor
    if _CLIP is None:
        _CLIP=CLIPModel.from_pretrained('openai/clip-vit-base-patch32');device=_runtime_device()
        if device=='cuda':_CLIP=_CLIP.to(device)
        _CLIP.eval();_CLIP_PROC=CLIPProcessor.from_pretrained('openai/clip-vit-base-patch32')
    labels=['normal child-friendly content','nudity or sexually explicit content','physical violence','weapon gun knife dangerous object','smoking drugs or alcohol']
    inp=_CLIP_PROC(text=labels,images=Image.open(image_path).convert('RGB'),return_tensors='pt',padding=True);device=_runtime_device()
    if device=='cuda':inp={k:v.to(device) if hasattr(v,'to') else v for k,v in inp.items()}
    probs=_CLIP(**inp).logits_per_image.softmax(dim=1)[0].detach().cpu().tolist()
    return {'adult':probs[1],'sexual':probs[1],'violence':probs[2],'weapon':probs[3],'general':max(probs[1:])}

def _clip_score(image_path):
    try:return timed_call('clip',lambda:_clip_score_impl(image_path),timeout_seconds('clip',90))
    except Exception:return None

def _nudenet(path):
    global _NUDE
    from nudenet import NudeDetector
    if _NUDE is None:_NUDE=NudeDetector()
    ds=_NUDE.detect(path)
    risky={'FEMALE_BREAST_EXPOSED','FEMALE_GENITALIA_EXPOSED','MALE_GENITALIA_EXPOSED','ANUS_EXPOSED','BUTTOCKS_EXPOSED'}
    return max([float(d.get('score',0)) for d in ds if d.get('class') in risky] or [0])

def _falconsai(path):
    global _NSFW
    from transformers import pipeline
    if _NSFW is None:_NSFW=pipeline('image-classification',model='Falconsai/nsfw_image_detection',device=0 if _runtime_device()=='cuda' else -1)
    rs=_NSFW(path)
    return max([float(x['score']) for x in rs if str(x['label']).lower()=='nsfw'] or [0])

def _opennsfw2(path):
    if not env_flag('LITTLENET_ENABLE_OPENNSFW2'):return None
    import opennsfw2
    return float(opennsfw2.predict_image(path))

def _extra_hf_nsfw(path):
    """Feature-flagged additional image classifier (e.g. LAION-derived NSFW model)."""
    if not env_flag('LITTLENET_ENABLE_EXTRA_NSFW'):return None
    model_id=os.getenv('LITTLENET_EXTRA_NSFW_MODEL','').strip()
    if not model_id:raise RuntimeError('extra_nsfw_model_missing')
    global _EXTRA_HF
    if _EXTRA_HF is None:
        from transformers import pipeline
        _EXTRA_HF=pipeline('image-classification',model=model_id,device=0 if _runtime_device()=='cuda' else -1)
    rows=_EXTRA_HF(path);score=0.0
    for row in rows or []:
        label=str(row.get('label','')).lower()
        if any(k in label for k in ('nsfw','porn','sexual','adult','unsafe')):score=max(score,float(row.get('score',0) or 0))
    return score

def _yolo_scores(path):
    global _YOLO
    from ultralytics import YOLO
    if _YOLO is None:_YOLO=YOLO('yolov8n.pt')
    result=_YOLO(path,verbose=False,device=0 if _runtime_device()=='cuda' else 'cpu')[0]
    defaults={'knife','scissors','gun','pistol','rifle','weapon'}
    custom={x.strip().lower() for x in os.getenv('LITTLENET_DANGEROUS_OBJECTS','').split(',') if x.strip()}
    dangerous=defaults|custom;weapon=0.0;hits=[]
    for b in result.boxes:
        label=str(result.names[int(b.cls[0])]).lower();conf=float(b.conf[0])
        if label in dangerous:weapon=max(weapon,conf);hits.append({'label':label,'score':conf})
    return weapon,hits

def check_image(path):
    from .remote_client import enabled,moderate_file
    if enabled():
        try:return normalize_signals(moderate_file('IMAGE',path),category='IMAGE')
        except Exception:return normalize_signals({'category':'IMAGE','total_safety_failure':True,'errors':['remote_ai_unavailable']},category='IMAGE')
    adult=sexual=violence=weapon=general=0.0;ran=0;errors=[];details={}
    for name,fn in [('nudenet',lambda:_nudenet(path)),('falconsai',lambda:_falconsai(path))]:
        try:
            score=float(timed_call(name,fn,timeout_seconds(name,90)));ran+=1;adult=max(adult,score);sexual=max(sexual,score);details[name]=score
        except Exception as exc:errors.append(name+'_timeout' if 'timeout' in str(exc) else name)
    c=_clip_score(path)
    if c:ran+=1;adult=max(adult,c['adult']);sexual=max(sexual,c.get('sexual',0));violence=max(violence,c['violence']);weapon=max(weapon,c.get('weapon',0));general=max(general,c['general']);details['clip']=c
    else:errors.append('clip')
    try:
        y,h=timed_call('yolo',lambda:_yolo_scores(path),timeout_seconds('yolo',90));ran+=1;weapon=max(weapon,float(y));details['yolo_hits']=h
    except Exception as exc:errors.append('yolo_timeout' if 'timeout' in str(exc) else 'yolo')
    if env_flag('LITTLENET_ENABLE_OPENNSFW2'):
        try:
            s=float(timed_call('opennsfw2',lambda:_opennsfw2(path),timeout_seconds('opennsfw2',90)));ran+=1;adult=max(adult,s);sexual=max(sexual,s);details['opennsfw2']=s
        except Exception as exc:errors.append('opennsfw2_timeout' if 'timeout' in str(exc) else 'opennsfw2')
    if env_flag('LITTLENET_ENABLE_EXTRA_NSFW'):
        try:
            s=float(timed_call('extra_nsfw',lambda:_extra_hf_nsfw(path),timeout_seconds('extra_nsfw',90)));ran+=1;adult=max(adult,s);sexual=max(sexual,s);details['extra_nsfw']=s
        except Exception as exc:errors.append('extra_nsfw_timeout' if 'timeout' in str(exc) else 'extra_nsfw')
    result={'adult_score':adult,'sexual_score':sexual,'violence_score':violence,'weapon_score':weapon,'toxicity_score':0,'general_score':max(general,adult,sexual,violence,weapon),'category':'ADULT' if max(adult,sexual)>=.4 else ('WEAPON' if weapon>=.45 else 'IMAGE'),'total_safety_failure':ran==0,'partial_safety_failure':ran>0 and bool(errors),'errors':errors,'model_signals':details}
    return normalize_signals(result,category='IMAGE')

def video_duration_seconds(path):
    try:
        r=subprocess.run(['ffprobe','-v','error','-show_entries','format=duration','-of','default=noprint_wrappers=1:nokey=1',path],capture_output=True,text=True,timeout=15,check=True);return float((r.stdout or '0').strip() or 0)
    except Exception:
        try:
            import cv2;c=cv2.VideoCapture(path);fps=c.get(cv2.CAP_PROP_FPS) or 0;frames=c.get(cv2.CAP_PROP_FRAME_COUNT) or 0;c.release();return frames/fps if fps else 0
        except Exception:return 0

def _audio_from_video(path):
    fd,out=tempfile.mkstemp(suffix='.wav');os.close(fd)
    try:subprocess.run(['ffmpeg','-y','-loglevel','error','-i',path,'-vn','-ac','1','-ar','16000',out],check=True,timeout=90);return out
    except Exception:
        try:os.unlink(out)
        except OSError:pass
        return None

def _video_frames(path,max_frames):
    import cv2
    cap=cv2.VideoCapture(path);total=int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    idxs=[int(i*max(total-1,0)/max(max_frames-1,1)) for i in range(min(max_frames,max(total,1)))];outs=[]
    for idx in idxs:
        cap.set(cv2.CAP_PROP_POS_FRAMES,idx);good,frame=cap.read()
        if not good:continue
        fd,tmp=tempfile.mkstemp(suffix='.jpg');os.close(fd);cv2.imwrite(tmp,frame)
        try:outs.append(check_image(tmp))
        finally:
            try:os.unlink(tmp)
            except OSError:pass
    cap.release();return outs

def check_video(path,max_frames=6):
    from .remote_client import enabled,moderate_file
    if enabled():
        try:return normalize_signals(moderate_file('VIDEO',path),category='VIDEO')
        except Exception:return normalize_signals({'category':'VIDEO','total_safety_failure':True,'errors':['remote_ai_unavailable']},category='VIDEO')
    try:
        outs=timed_call('video_frames',lambda:_video_frames(path,max_frames),timeout_seconds('video_frames',240))
        if not outs:return normalize_signals({'total_safety_failure':True,'category':'VIDEO','errors':['no_video_frames']},category='VIDEO')
        keys=['adult_score','sexual_score','weapon_score','violence_score','general_score'];out={k:max(float(x.get(k,0)) for x in outs) for k in keys};out['toxicity_score']=0
        out['partial_safety_failure']=any(x.get('partial_safety_failure') for x in outs);out['total_safety_failure']=all(x.get('total_safety_failure') for x in outs);out['errors']=[err for x in outs for err in x.get('errors',[])]
        ap=_audio_from_video(path)
        if ap:
            try:
                from .audio_service import check_audio;a=check_audio(ap)
                for k in ['adult_score','sexual_score','toxicity_score','general_score']:out[k]=max(float(out.get(k,0)),float(a.get(k,0)))
                out['transcript']=a.get('transcript','');out['partial_safety_failure']=out['partial_safety_failure'] or bool(a.get('partial_safety_failure'));out['errors']+=a.get('errors',[])
            finally:
                try:os.unlink(ap)
                except OSError:pass
        else:out['partial_safety_failure']=True;out['errors'].append('ffmpeg_audio_unavailable')
        out['category']='ADULT' if max(out['adult_score'],out['sexual_score'])>=.4 else ('WEAPON' if out['weapon_score']>=.45 else 'VIDEO')
        return normalize_signals(out,category='VIDEO')
    except Exception as exc:return normalize_signals({'total_safety_failure':True,'category':'VIDEO','errors':['video_timeout' if 'timeout' in str(exc) else 'video_processing']},category='VIDEO')
