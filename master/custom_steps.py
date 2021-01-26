import os
import xml.etree.ElementTree as Xml
from collections import defaultdict
from pathlib import Path
from typing import Dict, List

from buildbot.process.buildstep import BuildStepFailed, BuildStep, ShellMixin
from buildbot.process.results import SUCCESS, FAILURE
from buildbot.steps.worker import CompositeStepMixin
from twisted.internet import defer

__all__ = ['CleanOldFiles', 'CTest']


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


class CTest(ShellMixin, CompositeStepMixin, BuildStep):
    name = 'ctest'

    def __init__(self, *, build_config, jobs=None, tests=None, exclude_tests=None, labels=None, exclude_labels=None,
                 **kwargs):
        kwargs['command'] = [
            'ctest',
            '--build-config', build_config,
            *(['--parallel', str(jobs)] if jobs else []),
            *(['--tests-regex', '|'.join(tests)] if tests else []),
            *(['--exclude-regex', '|'.join(exclude_tests)] if exclude_tests else []),
            *(['--label-regex', '|'.join(labels)] if labels else []),
            *(['--label-exclude', '|'.join(exclude_labels)] if exclude_labels else []),
            '--output-on-failure',
            '--test-action', 'Test',
            '--no-compress-output'
        ]

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
