"""Contract tests for allowed Corn repair changes; no scene files are written."""
import importlib.util
from pathlib import Path
from unittest.mock import patch
import copy
import unittest
spec = importlib.util.spec_from_file_location('scene_preservation', Path(__file__).resolve().parents[1]/'scripts/verify-scene-preservation.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
class Input:
    def read_bytes(self): return b'unchanged source bytes'
    def __str__(self): return 'fixture.rbxl'
class CornRepairPreservation(unittest.TestCase):
    def setUp(self):
        self.before = {
            'Workspace/CornMap': {'class':'Model','properties':{'AttributesSerialize':['BinaryString','old',[]]}},
            'Workspace/SpawnLocation': {'class':'SpawnLocation','properties':{'Enabled':['bool','true',[]]}},
            'Workspace/CornMap/Props/House': {'class':'Part','properties':{'CFrame':['CoordinateFrame','author_frame',[]]}},
            'Workspace/CornMap/EditorPreview/Corn': {'class':'Model','properties':{'Name':['string','Corn',[]]}},
        }
        self.after = copy.deepcopy(self.before)
        self.after['Workspace/CornMap']['properties']['AttributesSerialize'][1] = 'version2'
        self.after['Workspace/SpawnLocation']['properties']['Enabled'][1] = 'false'
        del self.after['Workspace/CornMap/EditorPreview/Corn']
        self.meta = {'map_attrs':{'corn_project_id':{'type':'string','value':'children_of_corn'},'map_version':{'type':'number','value':'1'}},
            'corners_valid':True,'overview_owned':True,'preview_owned':True,'lower_is_spawn':True,'lower_enabled':True,'lower_below_field':True}
        self.after_meta = copy.deepcopy(self.meta)
        self.after_meta['map_attrs']['map_version']['value'] = '2'
        self.after_meta['lower_enabled'] = False
        self.raw = {'supported':True,'properties':{'Terrain.raw':{'payload_sha256':'exact'}}}
    def compare(self, repair=True, after_raw=None):
        with patch.object(module,'known_dom',side_effect=[(self.before,''),(self.after,'')]), patch.object(module,'corn_metadata',side_effect=[self.meta,self.after_meta]), patch.object(module,'unknown_properties',side_effect=[self.raw,after_raw or self.raw]):
            return module.compare(Input(),Input(),repair)
    def test_explicit_repair_changes_only(self):
        result = self.compare()
        self.assertTrue(result['passed'])
        self.assertEqual(len(result['allowed_changes']),2)
    def test_strict_mode_rejects_same_changes(self):
        self.assertFalse(self.compare(False)['passed'])
    def test_author_house_move_is_not_allowed(self):
        self.after['Workspace/CornMap/Props/House']['properties']['CFrame'][1] = 'changed'
        self.assertFalse(self.compare()['passed'])
    def test_disable_above_map_spawn_is_not_allowed(self):
        self.meta['lower_below_field'] = False
        self.assertFalse(self.compare()['passed'])
    def test_other_root_attributes_are_not_allowed(self):
        self.after_meta['map_attrs']['manual_note'] = {'type':'string','value':'changed'}
        with self.assertRaises(AssertionError): self.compare()
    def test_unknown_terrain_payload_change_is_not_allowed(self):
        raw = copy.deepcopy(self.raw)
        raw['properties']['Terrain.raw']['payload_sha256'] = 'changed'
        self.assertFalse(self.compare(after_raw=raw)['passed'])
if __name__ == '__main__': unittest.main()
