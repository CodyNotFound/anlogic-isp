"""Generate deterministic full-resolution input for the actual camera sampler test."""
from pathlib import Path
import numpy as np
from deployment import storage_bytes

root=Path(__file__).resolve().parents[2]
out=root/'.agent/build/camera_input'
out.mkdir(parents=True,exist_ok=True)
rng=np.random.default_rng(64090)
bgr=rng.integers(0,256,(720,1280,3),dtype=np.uint8)
bgr[:8,:8]=[0,127,255]
rgb=(bgr[:,:,2].astype(np.uint32)<<16)|(bgr[:,:,1].astype(np.uint32)<<8)|bgr[:,:,0]
np.savetxt(out/'rgb.hex',rgb.reshape(-1),fmt='%06x')
np.savetxt(out/'expected.hex',storage_bytes(bgr),fmt='%02x')
print('Generated full-frame integer sampler fixture')
