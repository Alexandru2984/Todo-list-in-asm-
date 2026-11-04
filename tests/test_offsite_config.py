"""Deployment helper must isolate secrets without modifying the shared config."""
import configparser
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

spec=importlib.util.spec_from_file_location('offsite_config',Path(__file__).resolve().parents[1]/'tools/offsite_config.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)


@unittest.skipIf(os.getuid()==0,'Private target belongs to an unprivileged service')
class OffsiteConfigTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='asm-offsite-config-');self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.source=self.root/'shared';self.dest=self.root/'isolated'
        self.text='[drive]\ntype = drive\ntoken = original-token\n[encrypted]\ntype = crypt\nremote = drive:backups\npassword = fixture-password\npassword2 = fixture-salt\n[unrelated]\ntype = s3\nsecret_access_key = never-copy\n'
        self.source.write_text(self.text);self.source.chmod(0o600)

    def isolate(self):module.isolate(self.source,self.dest,'encrypted')

    def test_only_selected_dependency_and_crypt_are_copied(self):
        self.isolate()
        config=configparser.RawConfigParser();config.read(self.dest)
        self.assertEqual(config.sections(),['drive','encrypted'])
        self.assertNotIn('never-copy',self.dest.read_text())
        self.assertEqual(self.dest.stat().st_mode&0o777,0o600)
        self.assertEqual(self.source.read_text(),self.text)

    def test_idempotent_install_preserves_refreshed_private_token(self):
        self.isolate();updated=self.dest.read_text().replace('original-token','refreshed-token')
        self.dest.write_text(updated);self.isolate()
        self.assertEqual(self.dest.read_text(),updated)
        self.assertEqual(self.source.read_text(),self.text)

    def test_key_change_is_not_silently_applied(self):
        self.isolate();before=self.dest.read_bytes()
        self.source.write_text(self.text.replace('fixture-password','changed-password'))
        with self.assertRaises(ValueError):self.isolate()
        self.assertEqual(self.dest.read_bytes(),before)

    def test_plaintext_disabling_encryption_and_external_secret_files_fail(self):
        for text in [self.text.replace('type = crypt','type = local'),
                     self.text.replace('password2 = fixture-salt','no_data_encryption = true'),
                     self.text.replace('password2 = fixture-salt','filename_encryption = off'),
                     self.text.replace('token = original-token','service_account_file = /private/secret')]:
            self.source.write_text(text)
            with self.assertRaises(ValueError):self.isolate()
            self.assertFalse(self.dest.exists())

    def test_unsafe_source_and_destination_permissions_or_links_fail(self):
        self.source.chmod(0o644)
        with self.assertRaises(ValueError):self.isolate()
        self.source.chmod(0o600);self.dest.symlink_to(self.root/'outside')
        with self.assertRaises(ValueError):self.isolate()
        self.assertFalse((self.root/'outside').exists())
        self.dest.unlink();os.link(self.source,self.dest)
        with self.assertRaises(ValueError):self.isolate()
        self.dest.unlink();self.dest.write_text(self.text);self.dest.chmod(0o600)
        with self.assertRaises(ValueError):self.isolate()
