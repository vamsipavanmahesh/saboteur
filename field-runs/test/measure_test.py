#!/usr/bin/env python3
"""Synthetic command probes, never app findings."""
import json,pathlib,signal,subprocess,sys,tempfile,unittest
SCRIPT=pathlib.Path(__file__).resolve().parents[1]/'script/measure.py'
class Measurement(unittest.TestCase):
 def probe(self,command):
  with tempfile.TemporaryDirectory() as tmp:
   base=pathlib.Path(tmp)/'new';out=base/'measurement.json';log=base/'raw.log'
   p=subprocess.run([sys.executable,str(SCRIPT),'--output',str(out),'--log',str(log),'--kind','verification','--',*command],capture_output=True,text=True)
   return p,json.loads(out.read_text()),log.read_text()
 def test_nonzero(self):
  p,m,log=self.probe([sys.executable,'-c','import sys; print("out");print("err",file=sys.stderr);sys.exit(7)'])
  self.assertEqual(p.returncode,7);self.assertEqual(m['exit_code'],7);self.assertEqual(m['status'],'partly');self.assertIn('out',log);self.assertIn('err',log);self.assertGreater(m['wall_seconds'],0);self.assertGreater(m['peak_rss_kb'],0)
 def test_success(self):
  p,m,_=self.probe([sys.executable,'-c','pass']);self.assertEqual(p.returncode,0);self.assertEqual(m['status'],'done')
 def test_spawn_failure_unknown_memory(self):
  p,m,log=self.probe(['/nonexistent-fixture-command']);self.assertEqual(p.returncode,127);self.assertEqual(m['exit_code'],127);self.assertIsNone(m['peak_rss_kb']);self.assertTrue(log)
 def test_signal(self):
  p,m,_=self.probe([sys.executable,'-c','import os,signal;os.kill(os.getpid(),signal.SIGTERM)']);self.assertEqual(m['exit_code'],-signal.SIGTERM);self.assertEqual(p.returncode,128+signal.SIGTERM)
if __name__=='__main__':unittest.main(verbosity=2)
