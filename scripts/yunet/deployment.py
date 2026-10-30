"""The production 1280x720 post-ISP camera -> YuNet tensor contract."""
import numpy as np

def camera_canvas(bgr):
    """OpenCV BGR uint8 frame -> 96x160 BGR, exact rounded 8x8 box average.

    Caller must perform crops/photometric/geometric augmentation BEFORE this
    operation. Padding is introduced last and must remain exactly zero.
    This models yunet_rgb_snapshot with WIDTH=1280, HEIGHT=720 only.
    """
    if bgr.shape != (720,1280,3) or bgr.dtype != np.uint8:
        raise ValueError('Expected post-ISP 720x1280x3 uint8 BGR frame')
    sums=bgr.astype(np.uint32).reshape(90,8,160,8,3).sum(axis=(1,3),dtype=np.uint32)
    canvas=np.zeros((96,160,3),dtype=np.uint8)
    canvas[:90]=((sums+32)>>6).astype(np.uint8)
    return canvas

def storage_bytes(bgr):
    canvas=camera_canvas(bgr)
    out=np.zeros((96,160,4),dtype=np.uint8)
    out[:,:,:3]=canvas
    return out.reshape(-1)

def tensor_input(bgr):
    # No division by 255, subtraction of mean, or RGB/BGR reversal.
    return camera_canvas(bgr).transpose(2,0,1)[None].astype(np.float32)
