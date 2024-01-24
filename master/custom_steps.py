import os
import re
import xml.etree.ElementTree as Xml
from collections import defaultdict
from pathlib import Path
from typing import Dict, List

from buildbot.process.buildstep import BuildStepFailed, BuildStep, ShellMixin
from buildbot.process.results import SUCCESS, FAILURE, WARNINGS
from buildbot.steps.transfer import FileUpload
from buildbot.steps.worker import CompositeStepMixin
from twisted.internet import defer

__all__ = ['CleanOldFiles', 'CTest', 'FileUploadIfNotExist', 'SetPropertiesFromCMakeCache']


class SetPropertiesFromCMakeCache(CompositeStepMixin, BuildStep):
    name = 'set-properties-from-cmake-cache'

    renderables = ['props']

    # Parsing with regex is safe because the CMakeCache.txt format
    # hasn't changed since 2006, according to `git blame`. Caveat:
    # they have backwards compatibility code for parsing entries with
    # quoted names and missing types. We don't bother with that here.
    _cache_re = re.compile(
        r'''
        ^(?!//|\#)    # Ignore comment lines.
        ([^:=]+?)     # Get the variable name,
        (-ADVANCED)?  # which might be marked as advanced,
        :([^=]*)      # and will have a type.
        =(.*)$        # The value extends through the end of the line.
        ''',
        re.VERBOSE)

    def __init__(self, *, props=None, normalize_bools=False, expand_lists=False, **kwargs):
        super().__init__(**kwargs)
        self.props = props or []
        self.normalize_bools = normalize_bools
        self.expand_lists = expand_lists

    @defer.inlineCallbacks
    def run(self):
        if not self.props:
            return SUCCESS

        log = yield self.addLog('props')

        cache = yield self.getFileContentFromWorker(f'{self.workdir}/CMakeCache.txt', abandonOnFailure=True)
        cache = self._parse_cache(cache)

        to_find = set(self.props)
        found = to_find & cache.keys()
        not_found = to_find - cache.keys()

        for key in found:
            log.addStdout(f'{key}={cache[key]}\n')
            self.setProperty(key, cache[key], 'CMakeCache')

        for key in not_found:
            log.addStderr(f'Cache entry not found: {key}\n')
            self.setProperty(key, '', 'CMakeCache')

        yield log.finish()
        return WARNINGS if not_found else SUCCESS

    def _parse_cache(self, cache: str):
        result = {}
        for entry in cache.splitlines():
            match = self._cache_re.match(entry)
            if match:
                key, is_advanced, ty, value = match.groups()
                if ty == 'BOOL' and self.normalize_bools:
                    value = self._normalize_bools(value)
                if self.expand_lists:
                    value = self._expand_lists(value)
                result[key] = value
        return result

    @staticmethod
    def _expand_lists(value: str):
        if ';' in value:
            return value.split(';')
        return value

    @staticmethod
    def _normalize_bools(value: str):
        value = value.upper().strip()
        if value.endswith('-NOTFOUND'):
            return '0'
        if value in {'1', 'ON', 'YES', 'TRUE', 'Y'}:
            return '1'
        if value in {'0', 'OFF', 'NO', 'FALSE', 'N', 'IGNORE', 'NOTFOUND'}:
            return '0'
        raise ValueError(f'Invalid CMake bool "{value}"')


class CleanOldFiles(BuildStep):
    name = 'clean-old'

    def __init__(self, *, groupfn, workdir, keep=1, **kwargs):
        super().__init__(**kwargs)
        self.groupfn = groupfn
        self.workdir = workdir
        self.keep = keep

    @defer.inlineCallbacks
    def run(self):
        stdio = yield self.addLog('stdio')
        status = SUCCESS

        # Group files in workdir together using the supplied function.
        groups: Dict[str, List[Path]] = defaultdict(list)
        for entry in Path(self.workdir).iterdir():
            gid = self.groupfn(entry)
            if gid:
                groups[gid].append(entry)

        # Delete all but the newest self.keep files with the same key.
        for group in groups.values():
            group.sort(key=os.path.getmtime, reverse=True)
            for file in group[self.keep:]:
                try:
                    file.unlink()
                    stdio.addStdout(f'Removed: {file.resolve()}\n')
                except (FileNotFoundError, OSError) as e:
                    stdio.addStderr(f'Could not delete {file.resolve()}: {e}\n')
                    status = FAILURE

        yield stdio.finish()
        return status


# Like FileUpload, but if the dest file already exists,
# just log that to stdio and do nothing. Useful when the
# filename contains (eg) a git commit or SHA that uniquely
# identifies the file version.
class FileUploadIfNotExist(FileUpload):
    name = 'file-upload-if-not-exist'

    @defer.inlineCallbacks
    def run(self):
        masterdest = os.path.expanduser(self.masterdest)
        if os.path.isfile(masterdest) and os.path.getsize(masterdest) > 0:
            stdio = yield self.addLog('stdio')
            stdio.addStdout(f"File {repr(masterdest)} already exists on dest, skipping upload!")
            yield stdio.finish()
            return SUCCESS

        yield from super().run()
        return SUCCESS


class CTest(ShellMixin, CompositeStepMixin, BuildStep):
    name = 'ctest'

    def __init__(self, *, build_config=None, preset=None, jobs=None, tests=None, exclude_tests=None,
                 labels=None, exclude_labels=None, test_dir=None, **kwargs):
        kwargs['command'] = [
            'ctest',
            # Note, jobs may be a renderable, don't explicitly convert to str
            *(['--parallel', jobs] if jobs else []),
            *(['--tests-regex', '|'.join(tests)] if tests else []),
            *(['--exclude-regex', '|'.join(exclude_tests)] if exclude_tests else []),
            *(['--label-regex', '|'.join(labels)] if labels else []),
            *(['--label-exclude', '|'.join(exclude_labels)] if exclude_labels else []),
            *(['--test-dir', test_dir] if test_dir else []),
            '--output-on-failure',
            '--test-action', 'Test',
            '--no-compress-output'
        ]
        assert (build_config is None) ^ (preset is None), "You must pass either build_config or preset, but not both"
        if build_config:
            kwargs['command'] += ['--build-config', build_config]
        if preset:
            kwargs['command'] += ['--preset', preset]

        kwargs = self.setupShellMixin(kwargs)
        super().__init__(**kwargs)

    @defer.inlineCallbacks
    def run(self):
        # Remove any leftover log files (if they exist)
        yield self.runRmdir(f'{self.workdir}/Testing', abandonOnFailure=False)

        # Run CTest
        cmd = yield self.makeRemoteShellCommand()
        yield self.runCommand(cmd)

        # Upload the XML log from the CTest run
        xml_results = yield self.runGlob(f'{self.workdir}/Testing/*/*.xml')
        if len(xml_results) != 1:
            raise BuildStepFailed(f'Expected to find a single XML file. Got: {xml_results}')

        ctest_log = yield self.getFileContentFromWorker(xml_results[0], abandonOnFailure=True)

        # Parse the result, collecting test failures into more convenient logs.
        root = Xml.fromstring(ctest_log)

        for test in root.findall(".//Test[@Status='failed']"):
            log = yield self.addLog(test.findtext('Name'))
            self.write_xml(test,
                           ("./Results/NamedMeasurement[@name='Environment']/Value", log.addHeader),
                           ("./Results/NamedMeasurement[@name='Command Line']/Value", log.addHeader),
                           ("./Results/Measurement/Value", log.addStdout),
                           ("./Results/NamedMeasurement[@name='Fail Reason']/Value", log.addStderr))
            yield log.finish()

        skipped = root.findall(".//Test[@Status='notrun']")
        if skipped:
            log = yield self.addLog('skipped')
            for test in skipped:
                log.addStdout(f'{test.findtext("Name")}\n')
                self.write_xml(test,
                               ("./Results/NamedMeasurement[@name='Environment']/Value", log.addHeader),
                               ("./Results/NamedMeasurement[@name='Command Line']/Value", log.addHeader),
                               ("./Results/Measurement/Value", log.addStdout),
                               indent=2)
                log.addStdout('\n')
            yield log.finish()

        return cmd.results()

    def write_xml(self, test, *sections, indent=0):
        for node, log in sections:
            text = test.findtext(node)
            text = self.clean_text(text, indent=indent)
            log(text)

    @staticmethod
    def clean_text(text, *, indent=0):
        indent = " " * indent
        text = text or ''
        if 'Regex=[' in text:  # clean up annoying CTest output
            text = text.replace('\n]', ']\n')
        text = text.strip()
        text = text.replace('\n', f'\n{indent}')
        text = f'{indent}{text}\n'
        return text
