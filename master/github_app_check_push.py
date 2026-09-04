import time

import jwt
import requests
from buildbot.interfaces import IRenderable
from buildbot.reporters.github import GitHubStatusPush
from twisted.internet import defer, threads
from zope.interface import implementer

__all__ = ["AppInstallationToken", "GitHubAppCheckPush"]


@implementer(IRenderable)
class AppInstallationToken:
    """Renders to a GitHub App installation access token, refreshed as needed. Pass an instance
    as GitHubAppCheckPush's `token=`; buildbot re-renders it on every request, so refreshes
    happen transparently.
    """

    def __init__(self, client_id, private_key, installation_id):
        self._client_id = client_id
        self._private_key = private_key
        self._installation_id = installation_id
        self._token = None
        self._expires = 0
        self._lock = defer.DeferredLock()

    async def getRenderingFor(self, _iprops):
        if time.time() > self._expires:
            async with self._lock:
                if time.time() > self._expires:
                    self._token = await threads.deferToThread(self._fetch)
                    self._expires = time.time() + 55 * 60
        return self._token

    def _fetch(self):
        now = int(time.time())
        app_jwt = jwt.encode(
            {"iat": now - 60, "exp": now + 570, "iss": self._client_id},
            self._private_key,
            algorithm="RS256",
        )
        resp = requests.post(
            f"https://api.github.com/app/installations/{self._installation_id}/access_tokens",
            headers={"Authorization": f"Bearer {app_jwt}", "Accept": "application/vnd.github+json"},
            timeout=10,
        )
        resp.raise_for_status()
        return resp.json()["token"]


class GitHubAppCheckPush(GitHubStatusPush):
    """Like GitHubStatusPush, but reports through the Checks API instead of the legacy Statuses
    API, so a build in progress shows GitHub's spinner instead of a static pending dot. Requires
    a GitHub App: pass an AppInstallationToken as `token=` (the Statuses API's PAT-based token
    doesn't work here; only the Checks API used by this class requires App auth).
    """

    @defer.inlineCallbacks
    def _get_auth_header(self, props):
        token = yield props.render(self.token)
        return {"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json"}

    @defer.inlineCallbacks
    def createStatus(
        self, repo_user, repo_name, sha, state, props, target_url=None, context=None, issue=None, description=None
    ):
        headers = yield self._get_auth_header(props)
        base = f"/repos/{repo_user}/{repo_name}/check-runs"
        output = {"title": context, "summary": description or ""}

        if state == "pending":
            payload = {
                "name": context,
                "head_sha": sha,
                "status": "in_progress",
                "details_url": target_url,
                "output": output,
                "external_id": issue,
            }
            return (yield self._http.post(base, json=payload, headers=headers))

        # The check run's id isn't threaded through from the "pending" call above, so look it up
        # by name instead of tracking build-run state; one extra GET, but no persisted state.
        resp = yield self._http.get(
            f"/repos/{repo_user}/{repo_name}/commits/{sha}/check-runs",
            params={"check_name": context},
            headers=headers,
        )
        runs = (yield resp.json())["check_runs"]
        if not runs:
            return None

        # GitHubStatusPush.sendMessage() already collapsed several build results into "error";
        # both "failure" and "error" map to the same GitHub conclusion.
        conclusion = "success" if state == "success" else "failure"
        payload = {
            "status": "completed",
            "conclusion": conclusion,
            "details_url": target_url,
            "output": output,
        }
        # HTTPSession has no patch() wrapper (only get/put/post/delete); the Checks API update
        # endpoint is PATCH-only, so fall through to the generic dispatcher it's built on.
        return (
            yield self._http.http._do_request(
                self._http, "patch", f"{base}/{runs[0]['id']}", json=payload, headers=headers
            )
        )
