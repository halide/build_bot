from copy import deepcopy
from unittest.mock import Mock

import pytest
import pytest_twisted
from buildbot.process.results import CANCELLED, EXCEPTION, FAILURE, RETRY, SKIPPED, SUCCESS, WARNINGS
from github_app_check_push import GitHubAppCheckPush
from twisted.internet import defer


@pytest.fixture
def reporter():
    reporter = GitHubAppCheckPush(token="unused")
    reporter.parent = Mock()
    reporter.context = "buildbot/test"
    reporter.verbose = False
    reporter._get_auth_header = Mock(return_value=defer.succeed({}))
    response = Mock(code=200)
    reporter._http = Mock()
    reporter._http.get.return_value = defer.succeed(
        Mock(json=Mock(return_value=defer.succeed({"check_runs": [{"id": 42, "status": "in_progress"}]})))
    )
    reporter._http.http._do_request.return_value = defer.succeed(response)
    reporter._http.post.return_value = defer.succeed(response)
    return reporter


def make_report(result, *, complete=True, queued=False):
    return {
        "body": "Build done.",
        "builds": [
            {
                "complete": complete,
                "results": result,
                "properties": {},
                "url": f"https://buildbot.example/#/{'buildrequests/1' if queued else 'builders/1/builds/1'}",
                "buildset": {
                    "sourcestamps": [
                        {"project": "halide/Halide", "repository": "", "revision": "abc123"},
                    ],
                },
            },
        ],
    }


@pytest.mark.parametrize(
    ("result", "conclusion"),
    [
        (SUCCESS, "success"),
        (WARNINGS, "success"),
        (SKIPPED, "success"),
        (FAILURE, "failure"),
        (EXCEPTION, "failure"),
        (CANCELLED, "cancelled"),
    ],
)
@pytest_twisted.inlineCallbacks
def test_completed_results(reporter, result, conclusion):
    report = make_report(result)
    original = deepcopy(report)
    yield reporter.sendMessage([report])
    payload = reporter._http.http._do_request.call_args.kwargs["json"]
    assert payload["status"] == "completed"
    assert payload["conclusion"] == conclusion
    assert report == original


@pytest.mark.parametrize(
    ("result", "complete", "queued", "status"),
    [
        (None, False, True, "queued"),
        (None, False, False, "in_progress"),
        (CANCELLED, False, False, "in_progress"),
        (RETRY, True, False, "in_progress"),
    ],
)
@pytest_twisted.inlineCallbacks
def test_pending_reports(reporter, result, complete, queued, status):
    yield reporter.sendMessage([make_report(result, complete=complete, queued=queued)])
    payload = reporter._http.http._do_request.call_args.kwargs["json"]
    assert payload["status"] == status
    assert "conclusion" not in payload


@pytest.mark.parametrize("runs", [[], [{"id": 42, "status": "completed"}]])
@pytest_twisted.inlineCallbacks
def test_cancelled_buildrequest_creates_completed_check(reporter, runs):
    reporter._http.get.return_value = defer.succeed(Mock(json=Mock(return_value=defer.succeed({"check_runs": runs}))))
    yield reporter.sendMessage([make_report(CANCELLED, queued=True)])
    payload = reporter._http.post.call_args.kwargs["json"]
    assert payload["status"] == "completed"
    assert payload["conclusion"] == "cancelled"
    assert payload["head_sha"] == "abc123"
    reporter._http.http._do_request.assert_not_called()


@pytest_twisted.inlineCallbacks
def test_updates_newest_open_check(reporter):
    runs = [
        {"id": 43, "status": "queued"},
        {"id": 44, "status": "completed"},
        {"id": 42, "status": "in_progress"},
    ]
    reporter._http.get.return_value = defer.succeed(Mock(json=Mock(return_value=defer.succeed({"check_runs": runs}))))
    yield reporter.sendMessage([make_report(SUCCESS)])
    assert reporter._http.http._do_request.call_args.args == (
        reporter._http,
        "patch",
        "/repos/halide/Halide/check-runs/43",
    )
    reporter._http.post.assert_not_called()
