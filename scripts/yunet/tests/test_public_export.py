"""Public training/export must not depend on unshipped deployment parameters."""
import hashlib
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import export_fpga
from common import write


class PublicExportTests(unittest.TestCase):
    def test_baseline_works_without_any_deployed_weights_or_deployment_manifest(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            work = root / 'work'
            model = work / 'upstream/yunet.onnx'
            model.parent.mkdir(parents=True)
            model.write_bytes(b'official-model-fixture')
            topology = root / 'rtl/analytics/face_cnn/program.hex'
            topology.parent.mkdir(parents=True)
            topology.write_text('01\n')
            contract = root / 'contract.json'
            write(contract, dict(operations=55, weight_bank_depth=12373))

            def schedule(*args, **kwargs):
                reference = work / 'scheduled_baseline'
                reference.mkdir()
                (reference / 'program.hex').write_text('01\n')
                write(reference / 'schedule_report.json', dict(
                    ops=55, weight_bank_depth=12373, arena_peak_bytes=61440))

            with patch.object(export_fpga, 'ROOT', root), \
                    patch.object(export_fpga, 'CONTRACT', contract), \
                    patch.object(export_fpga, 'MODEL_SHA', hashlib.sha256(model.read_bytes()).hexdigest()), \
                    patch.object(export_fpga.subprocess, 'run', side_effect=schedule):
                self.assertEqual(export_fpga.official_baseline(work), work / 'scheduled_baseline')

    def test_baseline_rejects_nonofficial_model_before_scheduling(self):
        with tempfile.TemporaryDirectory() as temp:
            work = Path(temp)
            model = work / 'upstream/yunet.onnx'
            model.parent.mkdir()
            model.write_bytes(b'not-the-official-model')
            with patch.object(export_fpga.subprocess, 'run') as scheduled:
                with self.assertRaisesRegex(ValueError, 'checksum'):
                    export_fpga.official_baseline(work)
                scheduled.assert_not_called()

    def test_delta_uses_generated_baseline_and_rejects_truncated_candidate(self):
        with tempfile.TemporaryDirectory() as temp:
            reference, candidate = Path(temp) / 'reference', Path(temp) / 'candidate'
            reference.mkdir()
            candidate.mkdir()
            for name in ['bias.hex', 'shift.hex'] + [f'weights{i}.hex' for i in range(4)]:
                (reference / name).write_text('01\n02\n')
                (candidate / name).write_text('01\n02\n')
            self.assertFalse(export_fpga.integer_delta(reference, candidate)['changed'])
            (candidate / 'weights0.hex').write_text('01\n03\n')
            result = export_fpga.integer_delta(reference, candidate)
            self.assertTrue(result['changed'])
            self.assertEqual(result['reference'], 'official_pretrained')
            self.assertEqual(result['entries']['weights0.hex'], 1)
            (candidate / 'bias.hex').write_text('01\n')
            with self.assertRaisesRegex(ValueError, 'layout'):
                export_fpga.integer_delta(reference, candidate)


if __name__ == '__main__':
    unittest.main()
