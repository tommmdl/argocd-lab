#!/usr/bin/env python3
"""Compare the same deployment with self-heal disabled and enabled."""
import json
import subprocess
import time
import urllib.request
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
def k(*args):
    return subprocess.check_output(['bash', str(ROOT/'notes/k.sh'), *args], text=True)
def obj(*args):
    return json.loads(k(*args, '-o', 'json'))
def app():
    return obj('-n','argocd','get','application','notes')
def wait(predicate, timeout=180):
    end=time.monotonic()+timeout
    while time.monotonic()<end:
        if predicate(): return
        time.sleep(2)
    raise AssertionError('Timed out waiting for reconciliation')
def healthy():
    s=app().get('status',{})
    return s.get('sync',{}).get('status')=='Synced' and s.get('health',{}).get('status')=='Healthy' and s.get('operationState',{}).get('phase')=='Succeeded'
def replicas():
    return obj('-n','notes-lab','get','deployment','notes-api')['spec']['replicas']
def heal(value):
    k('-n','argocd','patch','application','notes','--type=merge','-p',json.dumps({'spec':{'syncPolicy':{'automated':{'selfHeal':value}}}}))
def request(method, path, payload=None):
    data=json.dumps(payload).encode() if payload else None
    with urllib.request.urlopen(urllib.request.Request('http://localhost:8005'+path,data=data,method=method,headers={'Content-Type':'application/json'}),timeout=10) as response:
        body=response.read()
        return json.loads(body) if body else None
results={}
note=None
try:
    wait(healthy,300)
    revision=app()['status']['sync']['revision']
    pvc=obj('-n','notes-lab','get','pvc','data-postgres-alpine-0')['metadata']['uid']
    note=request('POST','/notes',{'title':'Argo CD self-heal verification'})
    heal(False)
    k('-n','notes-lab','scale','deployment/notes-api','--replicas=3')
    wait(lambda: app().get('status',{}).get('sync',{}).get('status')=='OutOfSync')
    start=time.monotonic()
    while time.monotonic()-start<30:
        assert replicas()==3, 'Drift was unexpectedly corrected with self-heal off'
        time.sleep(2)
    results['self_heal_off']={'status':'OutOfSync','replicas':3,'observation_seconds':30}
    heal(True)
    wait(lambda: replicas()==2 and healthy())
    results['self_heal_on']={'status':'Synced','health':'Healthy','replicas':2}
    k('-n','notes-lab','scale','deployment/notes-api','--replicas=3')
    wait(lambda: replicas()==2 and healthy())
    results['second_drift_corrected']=True
    assert obj('-n','notes-lab','get','pvc','data-postgres-alpine-0')['metadata']['uid']==pvc
    assert any(n['id']==note['id'] for n in request('GET','/notes')['notes'])
    results.update(pvc_preserved=True,note_preserved=True,source_revision=revision,argocd_version='v3.5.5',executed_at=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()))
    (ROOT/'evidence').mkdir(exist_ok=True)
    (ROOT/'evidence/notes-self-heal.json').write_text(json.dumps(results,indent=2)+'\n')
    print(json.dumps(results,indent=2))
finally:
    heal(True)
    if note: request('DELETE',f"/notes/{note['id']}")
