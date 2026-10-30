"""Critical dataset/download/decoder contracts, not model-accuracy tests."""
import hashlib,http.server,json,sys,tempfile,threading,unittest,zipfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import numpy as np
from deployment import camera_canvas,storage_bytes
from download import fetch,extract
from evaluate import Decoder
from data import annotations,labels

class ContractTests(unittest.TestCase):
    def test_rounded_camera_padding_and_order(self):
        a=np.zeros((720,1280,3),np.uint8);a[0,0,0]=32;a[0,0,1]=31;a[:8,:8,2]=255
        b=camera_canvas(a)
        self.assertEqual(b[0,0].tolist(),[1,0,255]);self.assertFalse(b[90:].any())
        self.assertEqual(storage_bytes(a)[:4].tolist(),[1,0,255,0]);self.assertEqual(storage_bytes(a).size,61440)
        with self.assertRaises(ValueError):camera_canvas(a[:90,:160])

    def test_empty_wider_dummy_and_ignore_regions(self):
        with tempfile.TemporaryDirectory() as temp:
            p=Path(temp)/'annotations.txt';p.write_text('event/a.jpg\n0\n0 0 0 0 0 0 0 0 0 0\nevent/b.jpg\n1\n10 10 20 20 0 0 0 1 0 0\n')
            ann=annotations(p);self.assertEqual(len(ann),2);self.assertFalse(ann['event/a.jpg'])
            valid,ignored=labels(ann['event/b.jpg'],[0,0,160,90]);self.assertFalse(valid);self.assertEqual(len(ignored),1)

    def test_real_decoder_threshold_tie_and_domain(self):
        decoder=Decoder()
        maps={k:[np.full((96//s,160//s,4 if k=='box' else 1),-128 if k!='box' else 0,np.int64) for s in (8,16,32)] for k in ('cls','obj','box')}
        self.assertIsNone(decoder(maps,True))
        for x in (2,3):maps['cls'][0][2,x,0]=0;maps['obj'][0][2,x,0]=127
        value=decoder(maps,True)
        self.assertEqual(value['anchor'],[0,2,2]);self.assertEqual(value['center'],[128,128]);self.assertEqual(value['square'],[96,96,64,64])
        maps['box'][0][2,2,0]=-128
        self.assertEqual(decoder(maps,True)['anchor'],[0,3,2])

    def test_checked_resume_and_server_without_range(self):
        payload=bytes(range(256))*64;expected=hashlib.sha256(payload).hexdigest()
        class Handler(http.server.BaseHTTPRequestHandler):
            support=True
            def do_GET(self):
                offset=int(self.headers.get('Range','bytes=0-').split('=')[1].split('-')[0]) if self.support else 0
                self.send_response(206 if offset else 200)
                if offset:self.send_header('Content-Range',f'bytes {offset}-{len(payload)-1}/{len(payload)}')
                self.send_header('Content-Length',str(len(payload)-offset));self.end_headers();self.wfile.write(payload[offset:])
            def log_message(self,*args):pass
        server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        try:
            with tempfile.TemporaryDirectory() as temp:
                for flag in (True,False):
                    Handler.support=flag;p=Path(temp)/str(flag);p.with_name(p.name+'.part').write_bytes(payload[:333])
                    fetch(f'http://127.0.0.1:{server.server_port}/file',p,expected,len(payload));self.assertEqual(p.read_bytes(),payload)
                p=Path(temp)/'bad';p.write_bytes(b'bad')
                with self.assertRaises(ValueError):fetch('http://unused',p,expected)
        finally:server.shutdown();server.server_close();thread.join()

    def test_stale_rtl_proof_is_not_accepted(self):
        from types import SimpleNamespace
        from common import write,sha,read
        from pipeline import status
        with tempfile.TemporaryDirectory() as temp:
            work=Path(temp);package=work/'fpga';resource=package/'rtl/test.v'
            resource.parent.mkdir(parents=True);resource.write_text('current RTL')
            write(package/'manifest.json',{'rtl/test.v':sha(resource)})
            write(package/'verification/completion.json',dict(status='passed',source_sha256={'rtl/test.v':'old fingerprint'}))
            write(work/'evaluation/report.json',dict(accuracy_accepted=True,non_regression_passed=True,test={'candidate':dict(positive_images=200,negative_images=100)}))
            model=work/'training/candidate.onnx';model.parent.mkdir();model.write_bytes(b'test model')
            write(package/'integer_delta.json',dict(changed=True))
            write(work/'training/result.json',dict(validation_eligible=True))
            status(SimpleNamespace(work=work,smoke=False))
            result=read(package/'status.json')
            self.assertEqual(result['rtl_status'],'pending');self.assertFalse(result['eligible_for_whole_board_build'])

    def test_standalone_verifier_updates_package_without_training_environment(self):
        from verify_rtl import update_package_status
        from common import read,write
        with tempfile.TemporaryDirectory() as temp:
            package=Path(temp)
            write(package/'status.json',dict(accuracy_accepted=True,smoke_only=False,rtl_status='pending'))
            update_package_status(package,'running');self.assertFalse(read(package/'status.json')['eligible_for_whole_board_build'])
            update_package_status(package,'passed');self.assertTrue(read(package/'status.json')['eligible_for_whole_board_build'])
            write(package/'status.json',dict(accuracy_accepted=False,smoke_only=True))
            update_package_status(package,'passed');self.assertFalse(read(package/'status.json')['eligible_for_whole_board_build'])

    def test_interrupted_extraction_resumes_even_when_top_directory_exists(self):
        from download import ensure_extracted
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);archive=root/'data.zip';dest=root/'data';check=dest/'images'
            check.mkdir(parents=True);(check/'partial.jpg').write_bytes(b'partial')
            with zipfile.ZipFile(archive,'w') as z:z.writestr('images/complete.jpg',b'complete')
            marker=root/'extract.json';marker.with_suffix('.started').write_text('interrupted')
            ensure_extracted(archive,dest,check,marker,'expected-sha',trust_existing=True)
            self.assertEqual((check/'complete.jpg').read_bytes(),b'complete')
            self.assertFalse(marker.with_suffix('.started').exists())

    def test_archive_traversal_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            z=Path(temp)/'bad.zip'
            with zipfile.ZipFile(z,'w') as f:f.writestr('../escaped.txt','bad')
            with self.assertRaises(ValueError):extract(z,Path(temp)/'out')
            self.assertFalse((Path(temp)/'escaped.txt').exists())

if __name__=='__main__':unittest.main()
