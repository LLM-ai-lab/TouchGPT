import argparse
import json
import os
from pathlib import Path
import socket
import struct
import subprocess
import tempfile
import uuid

def run(binary, choice, method, suffix):
    # Keep the UNIX socket path below macOS sun_path's 104-byte limit.
    with tempfile.TemporaryDirectory(prefix='touch-gpt-', dir='/tmp') as scratch:
        root = Path(scratch).resolve()
        (root/'ipc').mkdir(mode=0o700)
        path = root/'ipc'/'ipc.sock'
        with socket.socket(socket.AF_UNIX) as listener:
            listener.bind(str(path))
            path.chmod(0o600)
            listener.listen()
            listener.settimeout(5)
            thread = str(uuid.uuid4())
            test = subprocess.Popen([str(binary),thread,choice],env=dict(os.environ,CODEX_HOME=str(root)))
            try:
                client,_ = listener.accept()
                with client,client.makefile('rb') as stream:
                    client.settimeout(5)
                    def receive():
                        return json.loads(stream.read(struct.unpack('<I',stream.read(4))[0]))
                    def send(m):
                        b=json.dumps(m).encode()
                        client.sendall(struct.pack('<I',len(b))+b)
                    def broadcast(change):
                        send(dict(type='broadcast',method='thread-stream-state-changed',version=11,sourceClientId='owner',
                            params=dict(conversationId=thread,hostId='local',change=change)))
                    hello = receive()
                    assert hello['method']=='initialize'
                    send(dict(type='response',requestId=hello['requestId'],resultType='success',result={'clientId':'companion'}))
                    sub = receive()
                    assert sub['method']=='thread-stream-following-changed' and sub['params']['following']
                    req = dict(id=25,method=method,params=dict(threadId=thread, command='git status',permissions={'fileSystem':{'read':['/tmp']}}))
                    def state(status,requests):
                        turn=dict(turnId='t1',status=status,items=[dict(type='agentMessage',phase='final_answer',text='已验证  这是一条回复')])
                        return dict(id=thread,requests=requests,turnHistory={'history':{'entitiesByKey':{'key':turn}}})
                    broadcast(dict(type='snapshot',revision=1,conversationState=state('inProgress',[])))
                    broadcast(dict(type='patches',baseRevision=1,revision=2,patches=[dict(op='add',path=['requests',0],value=req)]))
                    decision = receive()
                    assert decision['method']==suffix and decision['params']['requestId']==25
                    assert decision['targetClientId']=='owner' and decision['version']==1
                    if method.endswith('permissions/requestApproval'):
                        assert decision['params']['response']=={'scope':'turn','permissions':req['params']['permissions'] if choice=='allow' else {}}
                    else:
                        assert decision['params']['decision']==('accept' if choice=='allow' else 'decline')
                    send(dict(type='response',requestId=decision['requestId'],resultType='success',handledByClientId='owner'))
                    assert receive()['method']=='thread-stream-following-changed'
                    broadcast(dict(type='patches',baseRevision=2,revision=3,patches=[
                        dict(op='remove',path=['requests',0]),
                        dict(op='replace',path=['turnHistory','history','entitiesByKey','key','status'],value='completed')]))
                    assert receive()['method']=='thread-stream-following-changed'
                    broadcast(dict(type='snapshot',revision=3,conversationState=state('completed',[])))
                    broadcast(dict(type='patches',baseRevision=3,revision=4,patches=[
                        dict(op='add',path=['turnHistory','history','entitiesByKey','next'],
                             value=dict(turnId='t2',status='inProgress',items=[]))]))
                    assert test.wait(timeout=5)==0
            finally:
                if test.poll() is None:
                    test.terminate()
                    test.wait(timeout=5)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Test the local desktop bridge using a synthetic socket server.")
    parser.add_argument("binary", type=Path, help="Path to the compiled bridge_test executable")
    binary = parser.parse_args().binary.resolve(strict=True)
    run(binary, 'allow', 'item/commandExecution/requestApproval', 'thread-follower-command-approval-decision')
    run(binary, 'reject', 'item/fileChange/requestApproval', 'thread-follower-file-approval-decision')
    run(binary, 'allow', 'item/permissions/requestApproval', 'thread-follower-permissions-request-approval-response')
    run(binary, 'reject', 'item/permissions/requestApproval', 'thread-follower-permissions-request-approval-response')
