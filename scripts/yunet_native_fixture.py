"""Prepare a translated real photograph for native RGB-to-PWM regression."""
from yunet_integer import *
from yunet_decode_vectors import lut_arrays,candidate
def main():
    net=json.loads((OUT/'network.json').read_text());m,w=load_graph()
    ops,scales,heads,*_=lower(m,w,net['scales'],{o['dst']:[1,o['shape'][2],o['shape'][0],o['shape'][1]] for o in net['operations']})
    a=fixture_images()['lena'];shifted=np.zeros_like(a);shifted[:,32:]=a[:,:128]
    t,_,_=infer(shifted,ops);sig,off,sz=lut_arrays(scales,heads);best=None;score=-1
    for level,stride in enumerate((8,16,32)):
        c=t[heads[f'cls_{stride}']];ob=t[heads[f'obj_{stride}']];b=t[heads[f'bbox_{stride}']]
        for y in range(c.shape[0]):
            for x in range(c.shape[1]):
                valid,s,box=candidate(level,x,y,[c[y,x,0],ob[y,x,0],*b[y,x]],sig,off,sz)
                if valid and s>score:best=box;score=s
    assert best and best[3]>850,(best,score)
    out=ROOT/'reports/yunet_v48';out.mkdir(exist_ok=True,parents=True)
    raw=np.pad(shifted,((0,0),(0,0),(0,1)));np.savetxt(out/'native_shift.hex',raw.reshape(-1),fmt='%02x')
    (out/'native_expected.txt').write_text(' '.join(map(str,[score,*best]))+'\n')
    print('Translated photograph',best,'score product',score)
if __name__=='__main__':main()
