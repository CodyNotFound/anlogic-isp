"""Localization-only training must preserve the confidence branches exactly."""
import sys, unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import torch
from train import configure_training,loss_fn
from yunet_torch import YuNetN,ONNX_PATH

class LocalizationTrainingTests(unittest.TestCase):
    def test_update_changes_only_bbox_and_preserves_scores(self):
        torch.set_num_threads(1);torch.manual_seed(12)
        model=YuNetN().load_onnx(ONNX_PATH)
        groups=configure_training(model,3e-5,'localization')
        before={k:v.detach().clone() for k,v in model.p.items()}
        optimizer=torch.optim.AdamW(groups,weight_decay=1e-5)
        x=torch.rand(2,3,96,160)*255
        with torch.no_grad():teacher={k:[v.clone() for v in vs] for k,vs in model(x).items()}
        output=model(x)
        loss=loss_fn(output,teacher,[[[50,25,25,30]],[]],'localization')
        self.assertTrue(torch.isfinite(loss));loss.backward();optimizer.step()
        changed=[k for k,v in model.p.items() if not torch.equal(v,before[k])]
        self.assertTrue(changed)
        self.assertTrue(all('multi_level_bbox' in k for k in changed))
        with torch.no_grad():after=model(x)
        for kind in ('cls','obj'):
            for old,new in zip(teacher[kind],after[kind]):self.assertTrue(torch.equal(old,new))
        self.assertTrue(any(not torch.equal(old,new) for old,new in zip(teacher['box'],after['box'])))
        # Background-only batches must retain a differentiable zero even when
        # no teacher location is confident enough for bbox distillation.
        output=model(x)
        quiet={k:[torch.full_like(v,-100) if k in ('cls','obj') else v.detach() for v in vs] for k,vs in output.items()}
        optimizer.zero_grad(set_to_none=True)
        zero=loss_fn(output,quiet,[[],[]],'localization')
        self.assertTrue(torch.isfinite(zero));self.assertEqual(zero.item(),0)
        zero.backward()

if __name__=='__main__':unittest.main()
