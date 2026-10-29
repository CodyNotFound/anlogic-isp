"""PyTorch replica of the yunet_n graph in models/yunet/face_detection_yunet_2023mar.onnx.

Parameters are registered under their exact ONNX initializer names so a trained
model can be written back into the original graph without touching topology.
Forward math follows graph.txt node by node: BN-free Conv+Relu blocks,
depthwise convs, 2x nearest upsample, and three stride 8/16/32 FCOS-style
heads (cls / obj-centerness / bbox). The kps branch is carried through for
graph completeness but is neither trained nor consumed by the FPGA decoder.
"""
from pathlib import Path
import onnx
from onnx import numpy_helper
import torch
import torch.nn.functional as F

ROOT = Path(__file__).resolve().parents[2]
ONNX_PATH = ROOT / 'models/yunet/face_detection_yunet_2023mar.onnx'
STRIDES = (8, 16, 32)
VISIBLE_H, PAD_H, W, H = 90, 6, 160, 96

# (weight_name, bias_name, kernel, stride, pad, groups) for every conv in graph order.
# Names double as ParameterDict keys; see graph.txt for the source of truth.
CONVS = [
    ('420', '421', 3, 2, 1, 1),                                              # stem 3->16
    ('backbone.model0.conv2.conv1.weight', None, 1, 1, 0, 1),
    ('423', '424', 3, 1, 1, 16),
    ('backbone.model1.conv1.conv1.weight', None, 1, 1, 0, 1),
    ('426', '427', 3, 1, 1, 16),
    ('backbone.model1.conv2.conv1.weight', None, 1, 1, 0, 1),
    ('429', '430', 3, 1, 1, 32),
    ('backbone.model2.conv1.conv1.weight', None, 1, 1, 0, 1),
    ('432', '433', 3, 1, 1, 32),
    ('backbone.model2.conv2.conv1.weight', None, 1, 1, 0, 1),
    ('435', '436', 3, 1, 1, 64),
    ('backbone.model3.conv1.conv1.weight', None, 1, 1, 0, 1),
    ('438', '439', 3, 1, 1, 64),
    ('backbone.model3.conv2.conv1.weight', None, 1, 1, 0, 1),
    ('441', '442', 3, 1, 1, 64),
    ('backbone.model4.conv1.conv1.weight', None, 1, 1, 0, 1),
    ('444', '445', 3, 1, 1, 64),
    ('backbone.model4.conv2.conv1.weight', None, 1, 1, 0, 1),
    ('447', '448', 3, 1, 1, 64),
    ('backbone.model5.conv1.conv1.weight', None, 1, 1, 0, 1),
    ('450', '451', 3, 1, 1, 64),
    ('backbone.model5.conv2.conv1.weight', None, 1, 1, 0, 1),
    ('453', '454', 3, 1, 1, 64),
    ('neck.lateral_convs.2.conv1.weight', None, 1, 1, 0, 1),
    ('456', '457', 3, 1, 1, 64),
    ('neck.lateral_convs.1.conv1.weight', None, 1, 1, 0, 1),
    ('459', '460', 3, 1, 1, 64),
    ('neck.lateral_convs.0.conv1.weight', None, 1, 1, 0, 1),
    ('462', '463', 3, 1, 1, 64),
    ('bbox_head.multi_level_cls.0.conv1.weight', None, 1, 1, 0, 1),
    ('bbox_head.multi_level_cls.0.conv2.weight', None, 3, 1, 1, 1),
    ('bbox_head.multi_level_cls.1.conv1.weight', None, 1, 1, 0, 1),
    ('bbox_head.multi_level_cls.1.conv2.weight', None, 3, 1, 1, 1),
    ('bbox_head.multi_level_cls.2.conv1.weight', None, 1, 1, 0, 1),
    ('bbox_head.multi_level_cls.2.conv2.weight', None, 3, 1, 1, 1),
    ('bbox_head.multi_level_bbox.0.conv1.weight', None, 1, 1, 0, 1),
    ('bbox_head.multi_level_bbox.0.conv2.weight', None, 3, 1, 1, 4),
    ('bbox_head.multi_level_bbox.1.conv1.weight', None, 1, 1, 0, 1),
    ('bbox_head.multi_level_bbox.1.conv2.weight', None, 3, 1, 1, 4),
    ('bbox_head.multi_level_bbox.2.conv1.weight', None, 1, 1, 0, 1),
    ('bbox_head.multi_level_bbox.2.conv2.weight', None, 3, 1, 1, 4),
    ('bbox_head.multi_level_obj.0.conv1.weight', None, 1, 1, 0, 1),
    ('bbox_head.multi_level_obj.0.conv2.weight', None, 3, 1, 1, 1),
    ('bbox_head.multi_level_obj.1.conv1.weight', None, 1, 1, 0, 1),
    ('bbox_head.multi_level_obj.1.conv2.weight', None, 3, 1, 1, 1),
    ('bbox_head.multi_level_obj.2.conv1.weight', None, 1, 1, 0, 1),
    ('bbox_head.multi_level_obj.2.conv2.weight', None, 3, 1, 1, 1),
    ('bbox_head.multi_level_kps.0.conv1.weight', None, 1, 1, 0, 1),
    ('bbox_head.multi_level_kps.0.conv2.weight', None, 3, 1, 1, 10),
    ('bbox_head.multi_level_kps.1.conv1.weight', None, 1, 1, 0, 1),
    ('bbox_head.multi_level_kps.1.conv2.weight', None, 3, 1, 1, 10),
    ('bbox_head.multi_level_kps.2.conv1.weight', None, 1, 1, 0, 1),
    ('bbox_head.multi_level_kps.2.conv2.weight', None, 3, 1, 1, 10),
]
# conv1 layers without explicit ONNX bias get their bias from the paired name below.
BIAS_BY_WEIGHT = {
    'backbone.model0.conv2.conv1.weight': 'backbone.model0.conv2.conv1.bias',
    'backbone.model1.conv1.conv1.weight': 'backbone.model1.conv1.conv1.bias',
    'backbone.model1.conv2.conv1.weight': 'backbone.model1.conv2.conv1.bias',
    'backbone.model2.conv1.conv1.weight': 'backbone.model2.conv1.conv1.bias',
    'backbone.model2.conv2.conv1.weight': 'backbone.model2.conv2.conv1.bias',
    'backbone.model3.conv1.conv1.weight': 'backbone.model3.conv1.conv1.bias',
    'backbone.model3.conv2.conv1.weight': 'backbone.model3.conv2.conv1.bias',
    'backbone.model4.conv1.conv1.weight': 'backbone.model4.conv1.conv1.bias',
    'backbone.model4.conv2.conv1.weight': 'backbone.model4.conv2.conv1.bias',
    'backbone.model5.conv1.conv1.weight': 'backbone.model5.conv1.conv1.bias',
    'backbone.model5.conv2.conv1.weight': 'backbone.model5.conv2.conv1.bias',
    'neck.lateral_convs.2.conv1.weight': 'neck.lateral_convs.2.conv1.bias',
    'neck.lateral_convs.1.conv1.weight': 'neck.lateral_convs.1.conv1.bias',
    'neck.lateral_convs.0.conv1.weight': 'neck.lateral_convs.0.conv1.bias',
}


def enc(name):
    """ONNX initializer names contain dots; torch forbids dots in parameter keys."""
    return name.replace('.', '@')


def dec(name):
    return name.replace('@', '.')


def bias_name(wname, explicit=None):
    """Every named conv stores its bias as the same stem with .bias (graph.txt)."""
    if explicit is not None:
        return explicit
    if not wname.endswith('.weight'):
        raise KeyError(f'cannot derive bias for {wname}')
    return wname[:-len('.weight')] + '.bias'


class YuNetN(torch.nn.Module):
    def __init__(self):
        super().__init__()
        self.p = torch.nn.ParameterDict()

    def load_onnx(self, path=ONNX_PATH):
        m = onnx.load(str(path))
        for init in m.graph.initializer:
            if init.data_type != onnx.TensorProto.FLOAT:
                continue  # Resize scales / Reshape targets are int constants, not weights
            a = numpy_helper.to_array(init)
            name = enc(init.name)
            if name in self.p:
                continue
            if a.ndim in (1, 4):
                self.p[name] = torch.nn.Parameter(torch.from_numpy(a.copy()))
        missing = self.expected_conv_params() - set(self.p.keys())
        if missing:
            raise KeyError(f'missing initializers: {sorted(missing)[:5]} ...')
        return self

    def expected_conv_params(self):
        names = set()
        for w, b, *_ in CONVS:
            names.add(enc(w))
            names.add(enc(bias_name(w, b)))
        return names

    def conv(self, x, wname):
        w, b, k, s, pad, g = next(c for c in CONVS if c[0] == wname)
        bias = self.p[enc(bias_name(wname, b))]
        return F.conv2d(x, self.p[enc(wname)], bias, stride=s, padding=pad, groups=g)

    def forward(self, x):
        """x: BGR float tensor (N,3,H,W), raw 0..255 scale, no normalization."""
        p = self.p
        c = self.conv
        x = F.relu(c(x, '420'))                                   # s2
        x = F.relu(c(c(x, 'backbone.model0.conv2.conv1.weight'), '423'))
        x = F.max_pool2d(x, 2, 2)                                 # s4
        x = c(x, 'backbone.model1.conv1.conv1.weight')
        x = F.relu(c(x, '426'))
        x = c(x, 'backbone.model1.conv2.conv1.weight')
        x = F.relu(c(x, '429'))                                   # 32ch
        x = c(x, 'backbone.model2.conv1.conv1.weight')
        x = F.relu(c(x, '432'))
        x = c(x, 'backbone.model2.conv2.conv1.weight')
        x = F.relu(c(x, '435'))                                   # 64ch, s4
        x = F.max_pool2d(x, 2, 2)                                 # s8
        x = c(x, 'backbone.model3.conv1.conv1.weight')
        x = F.relu(c(x, '438'))
        f8 = c(x, 'backbone.model3.conv2.conv1.weight')
        f8 = F.relu(c(f8, '441'))                                 # '214', s8
        x = F.max_pool2d(f8, 2, 2)                                # s16
        x = c(x, 'backbone.model4.conv1.conv1.weight')
        x = F.relu(c(x, '444'))
        f16 = c(x, 'backbone.model4.conv2.conv1.weight')
        f16 = F.relu(c(f16, '447'))                               # '223', s16
        x = F.max_pool2d(f16, 2, 2)                               # s32
        x = c(x, 'backbone.model5.conv1.conv1.weight')
        x = F.relu(c(x, '450'))
        f32 = c(x, 'backbone.model5.conv2.conv1.weight')
        f32 = F.relu(c(f32, '453'))                               # '232', s32

        def lateral(f, tag):
            f = c(f, f'neck.lateral_convs.{tag}.conv1.weight')
            return F.relu(c(f, {'0': '462', '1': '459', '2': '456'}[tag]))

        def up(f):
            return F.interpolate(f, scale_factor=2.0, mode='nearest')

        top = lateral(f32, '2')                                   # '236', s32
        mid = lateral(f16 + up(top), '1')                         # '246', s16
        base = lateral(f8 + up(mid), '0')                         # '256', s8

        def head(f, i):
            cls = c(c(f, f'bbox_head.multi_level_cls.{i}.conv1.weight'),
                    f'bbox_head.multi_level_cls.{i}.conv2.weight')
            box = c(c(f, f'bbox_head.multi_level_bbox.{i}.conv1.weight'),
                    f'bbox_head.multi_level_bbox.{i}.conv2.weight')
            obj = c(c(f, f'bbox_head.multi_level_obj.{i}.conv1.weight'),
                    f'bbox_head.multi_level_obj.{i}.conv2.weight')
            kps = c(c(f, f'bbox_head.multi_level_kps.{i}.conv1.weight'),
                    f'bbox_head.multi_level_kps.{i}.conv2.weight')
            return cls, obj, box, kps

        feats = (base, mid, top)                                  # s8, s16, s32
        cls, obj, box, kps = zip(*(head(f, i) for i, f in enumerate(feats)))
        return dict(cls=cls, obj=obj, box=box, kps=kps)


def export_onnx_weights(model, src=ONNX_PATH, dst=None):
    """Replace initializer tensors in the original graph with trained values."""
    m = onnx.load(str(src))
    trained = {dec(k): v.detach().cpu().numpy() for k, v in model.p.items()}
    replaced = 0
    keep = []
    for init in m.graph.initializer:
        if init.name in trained:
            new = numpy_helper.from_array(trained[init.name].astype('float32'), init.name)
            keep.append(new)
            replaced += 1
        else:
            keep.append(init)
    del m.graph.initializer[:]
    m.graph.initializer.extend(keep)
    if replaced != len(trained):
        raise AssertionError(f'replaced {replaced} of {len(trained)} trained tensors')
    if dst is not None:
        onnx.save(m, str(dst))
    return m


def decode_heads(heads, threshold=0.65, iou_threshold=0.3, single=False):
    """Shared Python decode: score=sqrt(sigmoid(cls)*sigmoid(obj)), exp geometry."""
    import numpy as np
    boxes = []
    for level, stride in enumerate(STRIDES):
        cls = torch.sigmoid(heads['cls'][level]).detach().numpy()[0, 0]
        obj = torch.sigmoid(heads['obj'][level]).detach().numpy()[0, 0]
        reg = heads['box'][level].detach().numpy()[0].transpose(1, 2, 0)
        score = np.sqrt(np.clip(cls * obj, 0, 1))
        for y in range(score.shape[0]):
            for x in range(score.shape[1]):
                s = score[y, x]
                if s < threshold:
                    continue
                cx = (x + reg[y, x, 0]) * stride
                cy = (y + reg[y, x, 1]) * stride
                bw = np.exp(np.clip(reg[y, x, 2], -12, 12)) * stride
                bh = np.exp(np.clip(reg[y, x, 3], -12, 12)) * stride
                boxes.append([cx - bw / 2, cy - bh / 2, bw, bh, float(s), stride])
    if single:
        return max(boxes, key=lambda b: b[4]) if boxes else None
    keep = []
    for b in sorted(boxes, key=lambda b: -b[4]):
        if all(_iou(b, k) < iou_threshold for k in keep):
            keep.append(b)
    return keep


def _iou(a, b):
    x = max(0.0, min(a[0] + a[2], b[0] + b[2]) - max(a[0], b[0]))
    y = max(0.0, min(a[1] + a[3], b[1] + b[3]) - max(a[1], b[1]))
    inter = x * y
    return inter / max(1e-12, a[2] * a[3] + b[2] * b[3] - inter)
